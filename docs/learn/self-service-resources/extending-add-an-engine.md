# How-to: add a new resource engine

**A platform-engineer how-to** — task-oriented, not teaching. Read the [orientation](orientation.md) first for
the model; this is the recipe for the *producer* side: extending the self-service catalog with a new engine
(say `rds` / relational, or `elasticache` / cache) so developers can then declare it like any other.

**When to use:** a team needs a resource type the catalog doesn't offer yet. Adding it is a deliberate,
reviewable change to the platform — the catalog is a **floor, not a ceiling** (ADR-073), and this is how you
raise it.

**The shape you're implementing:** every engine is a self-contained slot that, given one `resources.<name>`
entry, must produce three things — a **hardened managed resource**, **derived least-privilege IAM** for its
ARN, and an **output coordinate** for the ConfigMap. Get those three right and it composes with everything
else for free.

## The recipe

Each step names the real file. Steps 1–5 are the resource + its governance; 6–8 wire provisioning and
discovery.

1. **Render the resource + hardening + IAM** — `infra/modules/crossplane/charts/environment-api/files/composition.yaml`.
   Add an engine block next to the existing ones (`{{- if eq $rescfg.engine "sqs" }}` at ~L650 is the
   cleanest template). It must:
   - emit the managed resource(s) as **namespaced v2 MRs** (`<svc>.aws.m.upbound.io`) with a **pinned
     deterministic** `crossplane.io/external-name: refplat-<team>-<product>-<stage>-<name>-<hash>` and
     `managementPolicies: ["Observe","Create","Update","LateInitialize"]` (orphan-equivalent — see gotchas);
   - apply the **safety floor** (encryption, deny-non-TLS policy, versioning/PITR as the engine allows) —
     non-overridable, not dev-configurable;
   - append **derived least-privilege IAM** to `$stmts`, scoped to *this resource's ARN only*, split on
     `access` (read vs `readwrite`) — copy the shape of the S3/SQS blocks;
   - collect the **output env var** (e.g. `MYENGINE_ENDPOINT`) for the `<svc>-resources` ConfigMap.
2. **Allow the engine in the Team envelope schema** —
   `infra/modules/crossplane/charts/environment-api/templates/team-crd.yaml` (~L109): add it to the
   `allowedEngines` enum `["s3","sqs","sns","dynamodb"]`. (The `kind` enum in the XRD already covers
   relational/cache/objectstore/stream/keyvalue — only extend it for a genuinely new *class*.)
3. **Allow it in the gitops gate** — `.github/scripts/teams/gate.sh` (L46): add the engine to
   `VALID_ENGINES=" s3 sqs sns dynamodb "`. (The env-claim gate,
   `.github/scripts/gitops-gate/validate-environments.sh`, is already data-driven off the Team's
   `allowedEngines` — no per-engine edit.)
4. **Kyverno needs no per-engine change.** `restrict-environment-envelope` validates a claim's engines
   against the *Team's declared* `allowedEngines` (data-driven), so steps 2–3 are the gate; Kyverno enforces
   whatever the Team opted into at admission.
5. **Scope the provisioner IAM role** — `infra/modules/crossplane/main.tf`. Add a statement (model it on
   `EnvironmentSqsQueues`, ~L727) that lets the **Crossplane provisioner role** create the resource, gated on
   `contains(var.provider_services, "<engine>")` and constrained to `refplat-*` names in-region. This role is
   a high-value target — keep it name-prefixed and least-privilege.
6. **Turn the provider on** — `infra/live/aws/preprod/us-east-1/platform/crossplane/terragrunt.hcl` (L75):
   add the engine to `provider_services = ["ecr","iam","eks","s3","sqs","sns","dynamodb"]` to install
   `provider-aws-<engine>`.
7. **Project it into the catalog** — the Backstage `platform-projection` provider's engine→type map (so the
   resource shows as a `kind: Resource` in the portal, `dependencyOf` the service). Add the new type; the
   projection is otherwise cloud-neutral.
8. **Guard it with tests** — add render-test cases (resource-less claims still render byte-identical; the new
   engine renders its MRs/IAM/output), a gate test in `test-validate-environments.sh`, and Kyverno fixtures.

## Gotchas that *will* bite you (they bit us on S3 → SQS → SNS → DynamoDB)

- **`crossplane render` can't validate provider CRD schemas.** Render tests pass while a real `apply` fails.
  **Before applying, check the provider's actual CRD** for the resource. Concrete surprises we hit: an SNS
  `Topic` has **no `spec.forProvider.name`** (the name is the external-name, like S3/DynamoDB); an SNS topic
  policy **rejects a bare `sns:*`** ("action out of service scope") — enumerate topic-scoped actions.
- **The `.m.upbound.io` family collapses `MaxItems=1` blocks** from TF-style lists into single objects (e.g.
  s3 `versioningConfiguration`, SSE `applyServerSideEncryptionByDefault`, dynamodb `serverSideEncryption`).
  List-form renders fine but admission rejects `expected map, got []`. Some sub-fields *stay* lists
  (s3 SSE `rule`, dynamodb `attribute`) — check the CRD per field.
- **Pin the external-name.** Without `crossplane.io/external-name`, a fresh MR calls Create and collides
  (`QueueAlreadyExists`) instead of adopting — and deterministic names are what make re-declare idempotent.
- **v2 MRs have no `spec.deletionPolicy`** — strict-decode rejects it. Use `managementPolicies` (omit
  `Delete`) for orphan-equivalent, data-safe deletes.
- **Template-only edits need the chartChecksum bump.** The helm provider only re-renders a local chart when a
  *value* changes, so a Composition/CRD/RBAC-only edit silently doesn't apply. The
  `chart_checksum` mechanism (in `crossplane/main.tf`) forces it — confirm your chart is in that loop.
- **The teams gate runs from the trusted base (`main`), not PR head.** A PR that adds `allowedEngines: [new]`
  can't pass its own gate — so the **schema/gate allowance (steps 2–3) must merge to `main` first**, then the
  Team opt-in and the realization. Land it as: (a) gate/CRD allowance, (b) realization + Team opt-in.

## Verify it end-to-end

1. **Offline:** `crossplane render` the composition against a claim using the new engine + the resource-less
   claim (must stay byte-identical); run the gate + Kyverno test suites.
2. **Apply** the crossplane unit to **preprod** (from the main checkout, over Tailscale — never a worktree).
   This is where provider-schema bugs surface.
3. **E2E:** add a `resources.<name>: { kind, engine: <new>, access: readwrite }` to a real env claim → gate
   admits (team opted in) → the MR goes `READY` → the derived RolePolicy carries the new ARN → the
   `<svc>-resources` ConfigMap gains the coordinate → prove real I/O from the workload (the `alpha/conformance`
   selftest is the reference harness). Then verify safety in AWS directly (encryption on, non-TLS denied).

## The bar

This is control-plane plumbing that hands out AWS access, so it gets the control-plane quality bar: derived
IAM (never author-supplied ARNs), negative tests (a claim for the engine can't reach another env's resource),
gate **and** Kyverno both enforcing (defense in depth), and safety proven in AWS — not assumed from the
Composition. A sloppy engine here is a security defect, not a cosmetic one.

## Go deeper

- The model this extends: the [orientation](orientation.md) · the mechanism: the [reference](reference.md).
- The Composition internals: the [Environment API deep dive](../environment-api/deep-dive-composition-rendering.md).
- Why it's shaped this way: [ADR-073](../../adrs/073-self-service-cloud-resources.md) (the extensibility
  section) · authoring Compositions: the `crossplane-composition-authoring` skill.

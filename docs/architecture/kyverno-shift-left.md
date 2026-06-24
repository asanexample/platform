# Pre-merge policy validation (shift-left)

Kyverno admission is the **enforcement** point: non-compliant environment workloads and out-of-envelope
`XEnvironment` claims are rejected when they reach the cluster (see
[ADR-014](../adrs/014-kyverno-as-policy-engine.md) and [the policy catalog](kyverno-policy-catalog.md)).
The problem with enforcement-only is *timing* — a team learns its claim or manifest is non-compliant at
**deploy** time (the ArgoCD sync / admission webhook fails), long after the PR merged. **Shift-left**
moves the *same checks* into **pull-request CI** so the PR goes red before merge: fast feedback, same rules.

It is a **feedback** gate, not a new enforcement gate. Admission stays the source of truth; shift-left
just surfaces the verdict earlier.

> **History.** An earlier per-app composite action (`.github/actions/kyverno-validate`) rendered the
> `policies-chart` and ran the Kyverno CLI against each app's manifests in app-repo CI. It was **removed
> at the v3 cutover** (`gitops/products` + `gitops/environments`, ADR-067): it was coupled to the now-deleted
> `XTenant` claim — it derived the allowed route host from `XTenant` and rendered the v2 per-tenant chart —
> so it could not survive the model change. The dogfood CI job that exercised it (`Kyverno Shift-Left
> (dogfood)` in `.github/workflows/ci.yml`) was retired with it. See the note in `ci.yml` (the
> `kyverno-policy-test` job's trailing comment). The current shift-left is the two mechanisms below.

---

## 1. The gitops Gate — envelope shift-left on the claim (#388)

The primary shift-left is the **gitops Gate** ([`.github/workflows/gitops-gate.yml`](../../.github/workflows/gitops-gate.yml)),
a required status check on `main`. When a PR touches the ADR-067 registry surfaces — the `Product` registry
(`gitops/products/**`) or the `XEnvironment` claims (`gitops/environments/**`) — the gate runs the **same
checks the `restrict-environment-envelope` admission policy (#387) makes**, pre-merge, against the projected
Team + Product. This is the shift-left for the *claim*, which is where the self-service surface now lives.

The Environment validator ([`.github/scripts/gitops-gate/validate-environments.sh`](../../.github/scripts/gitops-gate/validate-environments.sh))
checks each claim as **YAML data** (yq only — nothing from the PR is executed):

1. **Schema + identity** — `kind: XEnvironment`, `apiVersion: platform.refplat.org/v1beta1`, required
   `spec.{team,product,stage}`, and the load-bearing path (`gitops/environments/<team>/<product>/<stage>.yaml`
   must match the spec, since the ApplicationSet derives the namespace/host from it).
2. **Enums** — `stage ∈ {dev,test,uat,staging,prod}`, `tier ∈ {standard,elevated,pci,hipaa}`,
   `isolation.compute ∈` the compute ladder.
3. **The envelope** — `stage` and `tier` must be in the **owning Team's envelope** (`allowedStages` /
   `allowedTiers`, read from the **trusted base** `gitops/teams/<team>.yaml`); `spec.team` must equal the
   Product's owner; `customer` is required iff a per-customer Product at a prod/uat stage (and forbidden
   otherwise).
4. **The IAM deny-set** — every Service's `permissions.aws.policyStatements` is scanned; the sensitive
   service prefixes (`iam`, `sts`, `organizations`, `account`) and a bare `*` action are denied — mirroring
   the admission `policystatements-no-escalation` rule.
5. **Self-service resources (ADR-073)** — each declared resource's `engine` must be in the Team's
   `envelope.resources.allowedEngines` (default-deny), the count ≤ `maxPerEnvironment`, names/kinds/access
   valid, and isolation ≥ the Team's `isolationFloor` — mirroring the `resources-engine-within-envelope` /
   `resources-count-within-cap` admission rules.

The gate also **renders each claim against the Composition** (`crank render`,
[`render-environments.sh`](../../.github/scripts/gitops-gate/render-environments.sh)) to catch claims that are
schema/envelope-valid but break the Environment+Product join at build time. The companion validators cover the
`Product` registry ([`validate-products.sh`](../../.github/scripts/gitops-gate/validate-products.sh)) and the
ADR-071 release records ([`validate-releases.sh`](../../.github/scripts/gitops-gate/validate-releases.sh)).

**CI-gate integrity.** The gate uses `pull_request_target`, so the workflow definition and every script it
calls run from the **protected base branch** — a PR cannot edit the gate that judges it. The PR's registry
files are checked out separately (sparse, credential-free) and read strictly as YAML data. The Team
registry — the envelope authority — is always read from the trusted base.

Beyond validation, this same job arms the auto-merge / deletion-guard / gated-prod lifecycle (ADR-062/068,
issues #377/#501); that machinery is documented in the gate workflow header and
[`tenant-claims-automerge.md`](../runbooks/tenant-claims-automerge.md), not here.

## 2. App-repo manifest checks (overlays + Kyverno CLI)

The *workload* shift-left lives in the **app repo**, not the platform repo. A scaffolded product ships
`k8s/` Kustomize overlays plus a thin-caller CI (ADR-050); the per-stage overlay (`k8s/overlays/<stage>`) is
built and validated in the app's PR CI, so a malformed overlay fails before merge. The image digest is
injected centrally at promotion (ADR-071) — the app's `main` stays protected and delivery-CI-free.

Teams that want admission-policy parity locally can run the **Kyverno CLI** against rendered manifests —
`kyverno apply <policies> --resource <(kubectl kustomize k8s/overlays/<stage>)` — the same binary the
platform CI pins to the cluster chart's appVersion. This is **advisory**, not byte-identical to admission:

- **Image signature verification** (`verifyImages`) can't run at PR time — the image isn't built/cosign-signed
  yet. Admission still enforces it (see [cosign-image-signing.md](cosign-image-signing.md)).
- **Route-host injection** — argocd-apps injects the claim-derived host at deploy; a local render sees the
  app's placeholder, so the hostname allow-list check is only authoritative at admission.
- Anything depending on **live cluster state** (the namespace environment label, domain `Active` status).

So a green local check means "this will likely pass the validate policies"; **admission remains the
authority**, and it is the only thing that enforces signatures and the injected route host.

## What enforces what

| Concern | Pre-merge (shift-left) | Enforced (source of truth) |
|---------|------------------------|----------------------------|
| `XEnvironment` claim schema / enums / path | gitops Gate (`validate-environments.sh`) | the XRD + `restrict-environment-envelope` |
| Stage/tier in Team envelope · team==Product.team · customer rule | gitops Gate | `restrict-environment-envelope` (#387) |
| IAM `policyStatements` deny-set | gitops Gate | `policystatements-no-escalation` |
| Self-service resource engine/count/isolation (ADR-073) | gitops Gate | `resources-*-within-*` |
| Composition build (Environment+Product join) | gitops Gate (`render-environments.sh`) | Crossplane reconcile |
| Workload hardening / requests-limits / probes / ClusterIP | app-repo overlay build (+ optional Kyverno CLI) | Kyverno admission |
| Image signature / SBOM / SLSA attestation | — (image not built at PR time) | `verify-images-product-*` at admission |
| Route hostname allow-list | — (host injected at deploy) | Kyverno admission against the injected host |

## Notes / limitations

- **Advisory, not byte-identical to admission.** Signature verification is skipped pre-merge and the
  namespace label / injected host are not present; treat a green check as "validate-clean", not
  "admission-proven".
- **Kyverno CLI tool pin.** The platform CI pins the Kyverno CLI to the cluster chart's appVersion
  (`1.18.1` for chart `3.8.1`); bump both together. The committed policy-test fixtures live under
  `infra/modules/policy/.kyverno-tests/` and `infra/modules/crossplane/.kyverno-tests/` and are exercised by
  the `kyverno-policy-test` job in `ci.yml`.
- **`@main` semantics.** The gitops Gate always validates against the *current* base policy, so a platform
  policy change surfaces on all open PRs immediately.

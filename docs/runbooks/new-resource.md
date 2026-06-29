# Runbook: New Cloud Resource (Self-Service)

> **On-call scope:** Platform Engineering (the developer flow is self-service; on-call only curates the
> catalog / envelopes)
> **Model:** A dev team self-serves an AWS building block — an **S3 bucket, SQS queue, SNS topic, or
> DynamoDB table** — by declaring it on an existing Service in the Service's `XEnvironment` claim
> ([ADR-073](../adrs/073-self-service-cloud-resources.md), realizing the ADR-067 §7 Service→Resource
> seam). The Crossplane Environment Composition provisions it **safe-by-construction**, derives
> least-privilege IAM onto the Service's Pod-Identity role, and publishes its coordinates into a
> `<svc>-resources` ConfigMap. **No Crossplane/AWS/IaC for the developer** — the cloud-neutral claim is
> the only contract.
>
> **This is BUILT, not just proposed.** Despite any stale "ADR-073 not built" note, the realization
> backbone (Phase A) is implemented: the XRD `resources` block, the per-engine Composition rendering
> (S3/SQS/SNS/DynamoDB) with derived IAM + the `<svc>-resources` ConfigMap, the Team-envelope cap, the
> Backstage **New Resource** scaffolder template, and the gitops Gate shift-left validation all exist.
> Phase B (the conversational agent front door) is the only deferred piece.
>
> **Live configurations / source of truth:**
>
> - `gitops/environments/<team>/<product>/<stage>.yaml` — **the claim**; the resource lives at
>   `spec.services.<svc>.resources.<name>`
> - `gitops/teams/<team>.yaml` — the Team envelope cap (`spec.envelope.resources`)
> - `scaffolder/templates/new-resource/template.yaml` — the Backstage New Resource template
> - `infra/modules/crossplane/charts/environment-api/files/composition.yaml` — the per-engine rendering
>   - IAM derivation + ConfigMap output
> - `infra/modules/crossplane/charts/environment-api/templates/xenvironment-xrd.yaml` — the
>   `resources` schema (`kind`/`engine`/`class`/`isolation`/`access`/`params`)
> - `.github/scripts/gitops-gate/validate-environments.sh` — the gate's shift-left envelope check
>
> **Last reviewed:** 2026-06-28

See [ADR-073](../adrs/073-self-service-cloud-resources.md) for the governance model (the governed-claim
IR: abstraction above the claim, safety below it) and
[environment-onboarding.md](environment-onboarding.md) for the Environment/Service the resource attaches
to.

---

## Table of Contents

1. [What gets provisioned](#what-gets-provisioned)
2. [Prerequisites](#prerequisites)
3. [The developer flow](#the-developer-flow)
4. [Consuming the resource](#consuming-the-resource)
5. [Verification](#verification)
6. [Removing a resource](#removing-a-resource)
7. [Troubleshooting](#troubleshooting)

---

## What gets provisioned

One `resources.<name>` entry on a Service → the Composition renders, **per engine**, the
safe-by-construction managed resources, the derived IAM, and the output ConfigMap. Everything below the
claim is platform-owned and hidden from the developer:

- **Platform-controlled name** — `refplat-<team>-<product>-<stage>-<name>` (truncate+hash to each
  service's length limit). S3 additionally gets a deterministic `account-id`+identity hash suffix
  (globally unique, unpredictable, **stable across re-creates** so a re-declared resource re-adopts its
  orphaned bucket). The developer never names the AWS resource.
- **Safe defaults, non-overridable** — e.g. S3: public access blocked, `DenyInsecureTransport`
  (TLS-only) bucket policy, SSE-S3 encryption, versioning, bucket-owner-enforced. SQS: `DenyInsecure`
  Transport + SSE-SQS. DynamoDB: PITR. Standard-tier uses **service-managed encryption** (no KMS key
  cost/ops); regulated tiers use a per-team CMK (deferred until the first regulated tenant).
- **Least-privilege IAM by *derivation*** — the Composition computes the exact scoped policy for the
  provisioned ARN from the claim's `access` intent and injects it into the **Service's Pod-Identity
  `RolePolicy`** (`Pod-<team>-<product>-<stage>-<svc>`). `read` → consume-only (S3 Get/List; SQS
  Receive/Delete; DynamoDB Get/Query/Scan); `readwrite` → adds the produce/write verbs. **Developers
  never author resource IAM.**
- **Outputs → a `<svc>-resources` ConfigMap** (non-secret, in the environment namespace), one env var
  per resource keyed by the resource name uppercased:
  - S3 → `<NAME>_BUCKET`
  - SQS → `<NAME>_QUEUE_URL`
  - SNS → `<NAME>_TOPIC_ARN`
  - DynamoDB → `<NAME>_TABLE`

  (e.g. an S3 resource named `uploads` → `UPLOADS_BUCKET`.) The scaffolder workload skeleton auto-wires
  `envFrom` (`optional: true`); auth is Pod Identity, so there are **no credentials** in the ConfigMap.
- **`deletionPolicy: Orphan`** by default (mirrors ECR) — removing the resource from the claim deletes
  the managed resource but the AWS resource + data survive; true destruction is an explicit, gated
  action.

---

## Prerequisites

- [ ] The **Service already exists** on the Environment — `resources.<name>` attaches to a declared
      `spec.services.<svc>` (with its `serviceAccount`, the Pod-Identity binding the derived IAM lands
      on). If the Service doesn't exist yet, add it via [environment onboarding](environment-onboarding.md)
      first.
- [ ] The **Team has opted into the engine.** The Team envelope (`gitops/teams/<team>.yaml`) gates
      resources — **default-deny**: if `spec.envelope.resources` is absent/empty, nothing is allowed.
      It carries `spec.envelope.resources` with `allowedEngines` (which engines this team may use,
      e.g. `["s3", "sqs", "sns", "dynamodb"]`), `maxPerEnvironment` (count cap per Environment, e.g.
      `10`), and `isolationFloor` (minimum isolation, e.g. `shared`). Widening the envelope is an
      **admin-only** PR to the Team CR.
- [ ] You belong to the team (the scaffolder verifies membership server-side; a hand-authored PR is
      CODEOWNERS-gated).

---

## The developer flow

### 1. Pick the engine

Choose the cloud-neutral building block your Service needs: **S3** (object storage), **SQS** (queue),
**SNS** (topic), or **DynamoDB** (key-value table). You declare *intent* — `engine` + `access` — not
AWS config.

### 2a. The Backstage **New Resource** template (the common path)

In Backstage, run the **New Resource** scaffolder template and fill in: team, product, stage, the
**Service** to attach to, a short **resource name** (e.g. `uploads`, `jobs` — becomes the env-var
prefix), the **engine**, and the **access** intent (`read` / `readwrite`, default `readwrite`). The
template:

1. verifies your team membership (`platform:verify-team-membership`),
2. fetches the Service's Environment claim,
3. adds `spec.services.<svc>.resources.<name> = { kind, engine, access }` (the `kind` is derived from
   the engine: `objectstore`/`stream`/`keyvalue`), and
4. opens a **gated PR** against the claim.

Crossplane and AWS are fully hidden — you never see raw IaC.

### 2b. Direct claim authoring (power users)

Equivalently, open a PR editing the Service's claim by hand — useful for multi-resource changes. You
see only the thin, cloud-neutral resource block:

```yaml
spec:
  services:
    web:
      serviceAccount: shop-web
      resources:
        uploads: { kind: objectstore, engine: s3, access: readwrite }
        assets:  { kind: objectstore, engine: s3, access: read }
        jobs:    { kind: stream,      engine: sqs, access: readwrite }
        notify:  { kind: stream,      engine: sns, access: readwrite }
        sessions:{ kind: keyvalue,    engine: dynamodb, access: readwrite }
```

### 3. The gated PR

Either path produces the **same governed claim** and passes the **same validation** — the abstraction
above the claim is interchangeable; the safety floor is the claim. The PR is validated:

- **gitops Gate (shift-left)** — `validate-environments.sh` checks each resource's `engine` is in the
  Team's `allowedEngines` (default-deny), the per-Environment count is `≤ maxPerEnvironment`, the name/
  kind/access are valid, and `isolation ≥ isolationFloor`.
- **Kyverno `restrict-environment-envelope` (admission)** — the same rules re-checked at admission, so
  a gate bypass is still caught.

**Merge policy:** non-prod resource PRs from the bot **auto-merge**; **prod** requires a
release-approver. On merge, the per-Product ArgoCD ApplicationSet syncs the updated `XEnvironment` and
the Composition reconciles it.

---

## Consuming the resource

After the resource provisions, its coordinates appear in the `<svc>-resources` ConfigMap. Your
workload reads them as env vars (the scaffolder skeleton auto-wires `envFrom` with `optional: true`);
runtime access is **Pod Identity** — no credentials to wire:

```yaml
# in your Deployment's container
envFrom:
  - configMapRef:
      name: <svc>-resources
      optional: true
```

> **Restart your Service after the resource provisions.** `envFrom` is read at container start, so a
> running pod won't see a newly-added key until it restarts: `kubectl rollout restart deploy/<name> -n
> <team>-<product>-<stage>`.

---

## Verification

```bash
# The resource's managed resources reconciled (S3 example; engine prefixes: s3-/sqs-/sns-/dynamodb-)
kubectl --context preprod get managed | grep <team>-<product>-<stage>

# The output ConfigMap (the coordinates your workload consumes)
kubectl --context preprod get configmap <svc>-resources -n <team>-<product>-<stage> -o yaml
#   → e.g. UPLOADS_BUCKET: refplat-<team>-<product>-<stage>-uploads-<hash>

# The derived IAM landed on the Service's Pod-Identity role (scoped to the resource ARN only)
aws iam list-role-policies --role-name Pod-<team>-<product>-<stage>-<svc> --profile preprod
aws iam get-role-policy --role-name Pod-<team>-<product>-<stage>-<svc> \
  --policy-name <...> --profile preprod        # actions match the access intent, resources = the one ARN

# The AWS resource itself (S3 example)
aws s3api get-bucket-policy --bucket refplat-<team>-<product>-<stage>-<name>-<hash> --profile preprod
```

A workload in another team's namespace cannot reference or access the resource — names are
platform-controlled and ARNs are derived, so cross-team access is structurally prevented (and
negative-tested).

---

## Removing a resource

Remove the `resources.<name>` entry from the claim via PR. On merge the Composition deletes the managed
resource, but with `deletionPolicy: Orphan` the **AWS resource + data survive** — no accidental data
loss. True destruction (deleting the orphaned bucket/queue/table) is an explicit, gated,
decommission-first action, reusing the [environment deprovisioning](environment-deprovisioning.md)
pattern (ADR-062). Orphaned `refplat-*` resources with no owning claim are flagged by a tag-based
audit for cleanup.

---

## Troubleshooting

| Symptom | Cause / fix |
| ------- | ----------- |
| PR fails the gate: `engine '<e>' not in Team envelope.resources.allowedEngines` | The team hasn't opted into that engine (default-deny). Widen `spec.envelope.resources.allowedEngines` in `gitops/teams/<team>.yaml` (admin PR), or pick an allowed engine. |
| PR fails the gate: `… self-service resources exceed … maxPerEnvironment` | The Environment is at its resource count cap. Raise `maxPerEnvironment` (admin envelope PR) or remove an unused resource. |
| PR fails the gate: `isolation 'shared' is below … isolationFloor 'dedicated'` | The team's envelope requires dedicated isolation; set the resource's `isolation: dedicated` (or relax the floor, admin). |
| Resource entry merged but the MRs aren't appearing | Check the `XEnvironment` is `READY` — the Composition only renders resources for a healthy claim: `kubectl --context preprod get xenvironment <name>` then `kubectl describe`. A resource-less Service still renders byte-identically, so a render error usually points at the new entry. |
| Workload doesn't see the new env var | The `<svc>-resources` ConfigMap is read via `envFrom` at container start — **restart the Service** (`kubectl rollout restart`). Confirm the ConfigMap has the key first. |
| MR stuck `Synced=False` with an IAM/create `AccessDenied` | The `crossplane-provisioner-<cluster>` role is missing a verb for the new service — add it under the same name-prefix/permissions-boundary discipline in the `crossplane` module and apply. |

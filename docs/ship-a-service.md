# Ship a Service

The developer's paved road: from *"I have an app idea"* to *"it's running in prod"* — using the Backstage portal,
without touching Terragrunt, ArgoCD, or AWS directly.

> **Who this is for.** Application developers. If you're a new joiner getting set up, start with
> [Onboarding](onboarding.md); if you operate the platform infra, see the [User Guide](user-guide.md). This page
> is *"I'm a dev — ship my service."* Each step says **what you do** vs **what the platform does automatically**,
> and links to the runbook with the detail. The architecture behind it all is the
> [Delivery Pipeline](architecture/delivery-pipeline.md).

---

## Prerequisites

- **Membership in your team's group** (Keycloak / Backstage). The scaffolder verifies it; it gates what you can
  create. → [Identity & SSO](architecture/identity-and-sso.md).
- **Backstage portal access** — the portal is the front door for every step below.
- *(Optional)* **kubectl** for read/debug. The per-team `DeveloperAccess-<team>` role is **not yet provisioned**
  (#364) — until it lands, use `platctl kubeconfig` / PlatformAdmin. You do **not** need kubectl to ship —
  delivery is fully GitOps. → [EKS Cluster Access](runbooks/eks-cluster-access.md).

---

## 1. Create the Product

**You:** open Backstage → **New Product**, pick your team, name the product and its first service.

**The platform:** opens a PR that creates your **app repository** (`<team>-<product>`, seeded with thin-caller
CI and `k8s/` overlays), a **Product registry entry**, and a **dev Environment**. The gitops Gate validates and
**auto-merges** it; Crossplane provisions the dev namespace, quota, scoped ECR, and AWS access.

→ Detail: [Environment Onboarding](runbooks/environment-onboarding.md) ·
architecture: [Platform Domain API](architecture/platform-domain-api.md).

## 2. Push code → signed image → running in dev

**You:** push to your app repo's `main`.

**The platform:** your thin-caller CI invokes the shared supply-chain workflow — **build → push** to your
product-scoped ECR → **cosign sign** → **SBOM** → **SLSA provenance**. The new digest is written to your **dev
Release**, and the delivery ApplicationSet runs it in your dev namespace.

Your `k8s/` overlays must satisfy Kyverno **enforce** mode, or the pod is **rejected at admission**. The
must-haves:

- image from **your** product-scoped ECR (`team-<team>/<product>-<svc>`) at an **explicit, signed digest/tag**
  — never `:latest`;
- **resource requests *and* limits** (cpu + memory) on every container;
- **liveness *and* readiness** probes;
- `Service` type **`ClusterIP`** (ingress is the shared Gateway via `HTTPRoute`);
- `HTTPRoute` hostnames within your Environment's allow-list;
- a **named** ServiceAccount (never `default`) if the workload needs AWS.

The platform auto-injects the hardening bits (`securityContext` drops, `automountServiceAccountToken: false`, the
`team` label) — don't bother setting them. Full list: [Kyverno Policy Catalog](architecture/kyverno-policy-catalog.md)
and CLAUDE.md *"Authoring Policy-Compliant Workloads"*. → CI detail:
[App Supply-Chain Onboarding](runbooks/app-supply-chain-onboarding.md).

## 3. App config & secrets

**You:** for a secret (e.g. `DATABASE_URL`, an API key), store it in **AWS Secrets Manager** and add an
`ExternalSecret` to your environment overlay; the External Secrets Operator syncs it into a Kubernetes `Secret`
your pod mounts. Plain config can be a `ConfigMap` in your overlay.

→ Detail: [Secrets & External Secrets](architecture/secrets-and-external-secrets.md).

> **Heads-up (known gap).** A *declarative, claim-driven* config/secrets paved road
> ([ADR-070](adrs/070-tenant-app-config-and-secrets.md)) is **proposed but not yet built** — for now you
> author the `ExternalSecret` yourself against the platform `aws-secrets-manager` `ClusterSecretStore`.

## 4. PR previews *(partial — heads-up)*

Opening a PR against your app repo **builds + signs a preview image** (so it would pass policy). However,
**ephemeral per-PR preview *environments* are not yet wired** in the current model
([ADR-032](adrs/032-pr-preview-environments.md) is a future enhancement). Don't expect a live preview URL per PR
today.

## 5. Add higher-stage Environments

**You:** Backstage → **New Environment** for each stage you need (`test`, `uat`, `staging`, `prod`).

**The platform:** the same gated registry flow provisions each environment's namespace, quota, ECR, and access.
A stage has no running pod until you **promote** a digest to it (next step).

→ Detail: [Environment Onboarding](runbooks/environment-onboarding.md).

## 6. Promote up the ladder

**You:** Backstage → **Request Promotion** to advance the running digest one stage up (e.g. dev → test). Or rely
on **auto-promotion**: a healthy lower stage automatically advances **up to staging** on a schedule.

**The platform:** opens a Release PR carrying the **same signed digest** (no rebuild); the gitops Gate validates
and auto-merges it (≤ staging); delivery runs it.

→ Detail: [Promote a Release](runbooks/promote-a-release.md) ·
architecture: [Promotion & Release](architecture/promotion-and-release.md).

## 7. Ship to prod (gated)

**You:** request the prod promotion the same way. It will **not** merge until a **release-approver** for your
team/product approves the Release PR (and the approver can't be you).

**The platform:** the gitops Gate holds the PR on a required `gitops Approval` check, fail-closed, until an
authorized approver signs off (two approvers for `pci`/`hipaa`). Then it merges and delivers — the exact artifact
you tested, byte-for-byte.

→ Detail: [Promote a Release](runbooks/promote-a-release.md).

---

## The whole journey, at a glance

| Step | You | Platform (automatic) |
|------|-----|----------------------|
| 1. New Product | portal form | app repo + Product + dev env, auto-merged + provisioned |
| 2. Push code | `git push` | build → sign → SBOM → provenance → dev Release → pod |
| 3. Config/secrets | `ExternalSecret` in overlay | ESO syncs from Secrets Manager |
| 4. PR previews | open a PR | preview image built + signed *(delivery: future)* |
| 5. New Environment | portal form | namespace + quota + ECR + access |
| 6. Promote ≤ staging | Request Promotion / nothing | same digest promoted, auto-merged, delivered |
| 7. Prod | Request Promotion | held for release-approver, then delivered |

## See also

- [Delivery Pipeline](architecture/delivery-pipeline.md) — how the whole machine fits together.
- [Promotion & Release](architecture/promotion-and-release.md) — the ladder + gated-prod mechanics.
- [Promote a Release](runbooks/promote-a-release.md) — the promote/approve runbook.
- [Kyverno Policy Catalog](architecture/kyverno-policy-catalog.md) — what your manifests must satisfy.

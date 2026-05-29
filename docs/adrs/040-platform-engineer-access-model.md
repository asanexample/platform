# ADR-040: Platform Engineer Access Model

**Date:** 2026-05-29

**Status:** Accepted

## Context

ADR-007 created `PlatformAdmin` as the platform engineer's interactive role, but in practice it was
broadly over-privileged: full Kubernetes **cluster-admin** (via an `AmazonEKSClusterAdminPolicy`
access entry), `ssm:StartSession` on **any** instance, and `secretsmanager:GetSecretValue` across an
entire account prefix. That let an engineer hand-mutate any AWS or K8s resource and read every team's
secrets.

We want a clear principle for how platform engineers interact with the platform:

- They should be able to **broadly observe and operate** the platform (AWS + Kubernetes) — inspect
  everything, debug, run sessions, restart/cordon/drain — **without authoring resources by hand**.
- **Resource authoring flows through the delivery pipelines**, which are the enforced source of truth:
  AWS via Terragrunt/`PlatformDeployer`, Kubernetes via ArgoCD (ADR-021).
- True emergencies that must bypass the pipelines use **break-glass** (`OrganizationAccountAccessRole`).

This is a least-privilege posture: the day-to-day human role carries no standing authoring power.

## Decision

Rescope `PlatformAdmin` to **operate/observe, not author**, in both the platform and preprod accounts.

### Kubernetes

The EKS access entry associates the AWS-managed **`AmazonEKSViewPolicy`** (broad read) and maps the
principal to the Kubernetes group **`platform-operators`**. A `platform-operator` ClusterRole (the
`cluster-rbac` module) adds only the verbs View lacks:

- **Debug:** `pods/log`, `pods/exec`, `pods/portforward`
- **Operate:** delete pods, `pods/eviction` (drain), `patch` nodes (cordon/drain), `patch`
  deployments/statefulsets/daemonsets (`kubectl rollout restart`)

No `create`, no other resource types. `PlatformDeployer`, ArgoCD, and break-glass keep cluster-admin.

> **RBAC is not field-level.** Granting `patch` on nodes/workloads (needed for cordon/drain and
> rollout-restart) technically permits arbitrary patches to those objects, not just the intended
> operation. For ArgoCD-managed resources, manual drift is reverted by ArgoCD **self-heal**
> (`prune + selfHeal = true`), so GitOps remains the source of truth. RBAC blocks `create` and writes
> to every other type.

### AWS

- **Broad read:** AWS-managed `ReadOnlyAccess`.
- **Deny** (overrides the managed Allow) on sensitive data/secret exfil: `secretsmanager:GetSecretValue`,
  `kms:Decrypt`, `s3:GetObject*`, `dynamodb` item/query/scan, `ssm:GetParameter*`.
- **Allow** only the non-read actions needed to reach the cluster: `ssm:StartSession` scoped by tag to
  the **bastion** (`Name = <env>-<region_abbv>-ssm-bastion`) + the port-forward document, plus
  own-session management.
- No write to any service; no secret **values**.

Trust is unchanged — only SSO `AdministratorAccess` holders may assume `PlatformAdmin`.

## Consequences

**Positive:**

- Platform engineers can observe and operate the whole platform but cannot author resources by hand;
  GitOps/IaC stay the enforced source of truth.
- No standing access to secret values or bulk data; no AWS write; no K8s cluster-admin.
- Clear separation: author = pipelines (`PlatformDeployer`/ArgoCD), operate = `PlatformAdmin`,
  emergency = break-glass.

**Negative / residual risks:**

- **`pods/exec` is the main residual privilege:** a shell into any pod can read that pod's mounted
  secrets and its IRSA service-account token (→ assume the workload's IAM role). So "no
  `GetSecretValue`" is not absolute while exec is granted. Deliberate trade for debuggability; the
  tighter option is logs + port-forward without exec.
- `ReadOnlyAccess` + Deny is **best-effort, not airtight** — it still allows content reads the Deny
  list doesn't enumerate (`lambda:GetFunction`, ECR image pull, log contents). The airtight-but-narrower
  alternative is `ViewOnlyAccess`.
- Operational tasks that are genuine mutations outside the operate tier (e.g. creating a one-off
  resource) require break-glass.
- Bastion SSM scoping depends on the bastion's `Name` tag being present (ADR-020).

**Adjacent (separate ticket):** `PlatformDeployer` (AdministratorAccess) trust has no SSO-role
condition, so it's more broadly assumable than `PlatformAdmin`; worth tightening on its own.

## Related ADRs

- ADR-007 (IAM role model) — `PlatformAdmin` is defined there; this refines its posture.
- ADR-021 (ArgoCD for GitOps) — the enforcement path for K8s authoring.
- ADR-020 (SSM bastion) — the session path that StartSession is scoped to.
- ADR-037 (CloudTrail audit logging) — break-glass assumption and `pods/exec` are the sensitive paths to audit.
- ADR-039 (per-team developer RBAC) — same group-mapped access-entry mechanism.

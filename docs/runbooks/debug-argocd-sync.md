# Runbook: Debugging ArgoCD Sync

> **Severity:** Medium (delivery stalled — app not converging)
> **On-call scope:** Development Teams (app sync) / Platform Engineering (cluster reachability, RBAC)
> **Related:** [Deploy App to Preprod](deploy-app-preprod.md), [ArgoCD SSO](argocd-sso.md),
> [Crossplane Tenant API](../architecture/crossplane-tenant-api.md),
> [Tenant Onboarding](tenant-onboarding.md)
>
> **Last reviewed:** 2026-06-08

---

"My ArgoCD app is OutOfSync / Unknown / Degraded and won't sync." ArgoCD runs on the **platform** cluster and
delivers to both the platform cluster and the **preprod** cluster cross-account. Most app issues are a bad
manifest or AppProject denial; most platform issues are cross-account reachability or the GitHub token.

The UI is at `https://argocd.aws.refplat.org` (Tailscale). CLI: `argocd login argocd.aws.refplat.org --sso`.

---

## Table of Contents

1. [Read the status first: OutOfSync vs Unknown vs Degraded](#read-the-status-first)
2. [Cross-account / cluster reachability](#cross-account--cluster-reachability)
3. [AppProject / RBAC denials](#appproject--rbac-denials)
4. [ApplicationSet PR-preview generator failures](#applicationset-pr-preview-generator-failures)
5. [selfHeal / prune behavior](#selfheal--prune-behavior)
6. [XTenant claims: ServerSideApply + ignoreDifferences](#xtenant-claims-serversideapply--ignoredifferences)

---

## Read the status first

```bash
argocd app get alpha-demo
argocd app get alpha-demo -o yaml | grep -A 20 conditions
kubectl get application alpha-demo -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
```

Two orthogonal axes — read both:

- **Sync status** = does live match Git? `Synced` / `OutOfSync` / `Unknown`.
  - **`OutOfSync`** — ArgoCD compared Git vs live and they differ. Normal pre-sync, or a self-heal target.
    `argocd app diff alpha-demo` shows exactly what.
  - **`Unknown`** — ArgoCD **cannot compute** the diff. Almost always a `ComparisonError`: the destination
    cluster is unreachable, the repo can't be cloned, or a manifest fails to render. Check `conditions`.
- **Health status** = are the live resources healthy? `Healthy` / `Progressing` / `Degraded` / `Missing`.
  - **`Degraded`** — the resource synced but is unhealthy at runtime (CrashLoopBackOff, failed rollout, an
    HTTPRoute the Gateway rejected). This is **not** a sync problem — debug the workload
    (see [Deploy App to Preprod](deploy-app-preprod.md#debugging-deployments) and, for routes,
    [Debug Ingress & DNS](debug-ingress-and-dns.md)).

```bash
argocd app diff alpha-demo                                   # OutOfSync: what differs
argocd app get alpha-demo -o yaml | grep -A 10 operationState # last sync result + message
argocd app get alpha-demo --refresh                          # re-read Git without syncing
argocd app get alpha-demo --hard-refresh                     # also invalidate the manifest cache
```

---

## Cross-account / cluster reachability

**Symptom:** `Unknown` with a `ComparisonError` like `... i/o timeout` or `the server has asked for the
client to provide credentials`, typically on preprod-destined apps.

**Diagnosis.** ArgoCD reaches preprod via a **cluster Secret** (label
`argocd.argoproj.io/secret-type: cluster`) whose `awsAuthConfig` tells the application-controller to
STS-AssumeRole + fetch an EKS token. These secrets are managed by the `argocd-clusters` unit.

```bash
argocd cluster list                                          # is preprod present + reachable?
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster
kubectl get secret -n argocd <preprod-cluster-secret> -o jsonpath='{.data.config}' | base64 -d | jq .
# confirm awsAuthConfig.clusterName + roleARN look right
kubectl logs -n argocd deploy/argocd-application-controller --tail=80 | grep -i 'comparison\|cluster\|timeout'
```

**Causes and fixes:**

- **Stale preprod API ENI IPs after scale-to-zero/restore.** The most common one: the preprod EKS API ENI
  IPs changed and the `cross-vpc-dns` record went stale, so ArgoCD `i/o timeout`s. Re-apply
  `platform/.../cross-vpc-dns`, then `argocd app get <app> --hard-refresh`
  (see [Tenant Onboarding](tenant-onboarding.md#troubleshooting)).
- **AssumeRole denied.** The application-controller's role can't assume the cluster `roleARN`, or that role
  lacks an EKS access entry. Re-apply `argocd-clusters`; verify the preprod access entry exists.
- **Cluster secret missing.** `argocd-clusters` wasn't applied for that environment — re-apply it.

---

## AppProject / RBAC denials

**Symptom:** `SyncFailed` / sync error mentioning a resource is "not permitted in project" or a destination
mismatch.

**Diagnosis.** Each team has an `AppProject` (named for the team) restricting **source repos**, the
**destination** `(server, namespace)`, and the allowed resource kinds (`namespaceResourceWhitelist`):
ConfigMap, Secret, Service, ServiceAccount, Deployment, StatefulSet, Job, CronJob, HTTPRoute,
ExternalSecret. Anything else is rejected by the project, not by Kyverno.

```bash
argocd proj get alpha
kubectl get appproject alpha -n argocd -o yaml
```

**Causes and fixes:**

- **Disallowed kind** (e.g. a `Role`, `LoadBalancer`-typed Service, a CRD). Remove it from the app manifests
  — tenant manifests are limited to the whitelist (ingress is HTTPRoute on the shared Gateway, not a
  Service of type LoadBalancer).
- **Namespace mismatch.** The manifest's `namespace` must equal the project destination (`team-<team>`). A
  manifest in `default` or another team's namespace is denied.
- **Source repo not in the project.** `sourceRepos` is derived from `teams.hcl`; a new repo URL needs the
  `argocd-apps` unit re-applied.
- **Admission (not project) denial.** If the message is a Kyverno `restrict-*`/`verify-*` policy, it's an
  admission rejection on the destination cluster — see [Deploy App to Preprod](deploy-app-preprod.md#common-issues)
  / [Debug Ingress & DNS](debug-ingress-and-dns.md).

---

## ApplicationSet PR-preview generator failures

**Symptom:** Open PRs don't get preview Applications (`<app>-<team>-pr-<n>`), or the ApplicationSet shows an
error.

**Diagnosis.** Preview apps (`preview = true`) are driven by a per-app `ApplicationSet` whose GitHub
`pullRequest` generator polls every 60s. It needs the GitHub org configured and, for private repos, a token.

```bash
kubectl get applicationset -n argocd | grep preview
kubectl describe applicationset <app>-<team>-preview -n argocd     # generator errors at the bottom
kubectl logs -n argocd deploy/argocd-applicationset-controller --tail=80
```

**Causes and fixes:**

- **Missing/invalid GitHub token (private repos).** The generator reads a token from a Secret in the
  `argocd` namespace (`tokenRef`). Without it, private-repo PRs are silently not discovered. Confirm with
  platform that the token Secret exists for the repo's org.
- **PR labels gate.** Previews can be opt-in via `preview_pr_labels` — only PRs carrying **all** the
  configured labels get an environment (this excludes Dependabot/routine PRs). A PR missing the label(s) is
  intentionally skipped; add the label.
- **`github_org` not set.** If the org is empty, no preview ApplicationSet is created at all
  (`preview_apps` is empty) — a platform/`argocd-apps` config gap.
- **Fork PRs.** Forks can't push to ECR (`id-token: write` blocked), so previews from forks have no image —
  expected.

---

## selfHeal / prune behavior

App Applications sync with `automated { selfHeal = true, prune = true }` and `CreateNamespace=false`.

- **selfHeal** reverts any manual in-cluster edit back to Git. A `kubectl edit`/`kubectl rollout undo` will
  be undone — to change a live resource, change the **Git manifest**. (See
  [Deploy App to Preprod](deploy-app-preprod.md#deployment-rollout).)
- **prune** deletes resources removed from Git. If a resource vanished unexpectedly, it was removed from the
  manifests — check the app repo history.
- **CreateNamespace=false** — ArgoCD does **not** create namespaces; `team-<team>` is owned by the Tenant
  Composition. A `namespace not found` sync error means the `XTenant` isn't `READY`
  (see [Tenant Onboarding](tenant-onboarding.md)).

To pause self-heal for debugging:

```bash
argocd app set alpha-demo --sync-policy none      # stop automated sync (re-enable with --sync-policy automated)
argocd app sync alpha-demo                         # one-shot manual sync
```

---

## XTenant claims: ServerSideApply + ignoreDifferences

The `tenant-claims-preprod` Application (project `platform-tenants`) syncs the cluster-scoped `XTenant`
claim YAMLs from `gitops/tenant-claims/preprod/`. It has its own quirks:

- It syncs with **`ServerSideApply=true`** + `selfHeal` + `prune`, so ArgoCD owns **only the fields it sets**
  (the claim intent). XRD-applied defaults (`resourceQuota`, `complianceTier`, …) and Crossplane's
  `spec.crossplane`/finalizer injections are **not** stripped by self-heal.
- An **`ignoreDifferences`** customization (in the `argocd` unit) keeps the UI `Synced` despite Crossplane
  mutating the live object. If `tenant-claims-preprod` flaps `OutOfSync` on `spec.crossplane`/finalizers, the
  `ignoreDifferences` (or ServerSideApply) wasn't applied — re-apply the `argocd` unit.
- ArgoCD applies as the assumed **`ArgoCD` IAM role**, the platform principal excluded from the S1
  `restrict-tenant-control-plane` Kyverno backstop. An `XTenant` creation denied as a tenant principal means
  the claim was applied by something other than this Application.

```bash
argocd app get tenant-claims-preprod
kubectl get application tenant-claims-preprod -n argocd -o jsonpath='{.spec.ignoreDifferences}' | jq .
kubectl --context preprod get xtenant <team>                 # SYNCED / READY after the app syncs
```

To trace a claim end-to-end after it syncs, see
[Crossplane Tenant API](../architecture/crossplane-tenant-api.md#claim-delivery--lifecycle).

# Runbook: Debugging ArgoCD Sync

> **Severity:** Medium (delivery stalled — app not converging)
> **On-call scope:** Development Teams (app sync) / Platform Engineering (cluster reachability, RBAC)
> **Related:** [Deploy App to Preprod](deploy-app-preprod.md), [ArgoCD SSO](argocd-sso.md),
> [Crossplane Environment API](../architecture/crossplane-environment-api.md),
> [Environment Onboarding](environment-onboarding.md)
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
4. [Per-stage preview hostnames (and the per-PR previews gap)](#per-stage-preview-hostnames)
5. [selfHeal / prune behavior](#selfheal--prune-behavior)
6. [XEnvironment claims: ServerSideApply + ignoreDifferences](#xenvironment-claims-serversideapply--ignoredifferences)

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
  (see [Environment Onboarding](environment-onboarding.md#troubleshooting)).
- **AssumeRole denied.** The application-controller's role can't assume the cluster `roleARN`, or that role
  lacks an EKS access entry. Re-apply `argocd-clusters`; verify the preprod access entry exists.
- **Cluster secret missing.** `argocd-clusters` wasn't applied for that cluster — re-apply it.

---

## AppProject / RBAC denials

**Symptom:** `SyncFailed` / sync error mentioning a resource is "not permitted in project" or a destination
mismatch.

**Diagnosis.** Each **Product** has an `AppProject` named `product-<team>-<product>` (e.g.
`product-alpha-shop`) restricting **source repos**, the **destination** `(server, namespace)`, and the
allowed resource kinds (`namespaceResourceWhitelist`): ConfigMap, Secret, Service, ServiceAccount,
Deployment, StatefulSet, Rollout, AnalysisTemplate, AnalysisRun (the three `argoproj.io` Argo Rollouts
kinds, ADR-056), Job, CronJob, HTTPRoute, ExternalSecret. Anything else is rejected by the project, not
by Kyverno.

```bash
argocd proj get product-alpha-shop
kubectl get appproject product-alpha-shop -n argocd -o yaml
```

**Causes and fixes:**

- **Disallowed kind** (e.g. a `Role`, `LoadBalancer`-typed Service, a CRD). Remove it from the app manifests
  — environment manifests are limited to the whitelist (ingress is HTTPRoute on the shared Gateway, not a
  Service of type LoadBalancer).
- **Namespace mismatch.** The manifest's `namespace` must equal the project destination — the environment
  namespace `<team>-<product>-<stage>` (e.g. `alpha-demo-dev`). A manifest in `default` or another
  environment's namespace is denied.
- **Source repo not in the project.** `sourceRepos` is derived from the **Product** registry
  (`gitops/products/<team>/<product>.yaml`, `spec.repo`); a new repo URL needs the `argocd-apps` unit
  re-applied.
- **Admission (not project) denial.** If the message is a Kyverno `restrict-*`/`verify-*` policy, it's an
  admission rejection on the destination cluster — see [Deploy App to Preprod](deploy-app-preprod.md#common-issues)
  / [Debug Ingress & DNS](debug-ingress-and-dns.md).

---

## Per-stage preview hostnames

**Symptom:** an Environment's `HTTPRoute` hostname isn't the expected
`<product>-<team>-<stage>.<preview_domain>` form.

**Diagnosis.** When the `argocd-apps` unit sets `preview_domain`, the per-Product **delivery**
ApplicationSet rewrites each Environment's `HTTPRoute` hostname to
`<product>-<team>-<stage>.<preview_domain>` via a kustomize patch — a **per-stage host rewrite on the
standard delivery**, applied per Environment that has a Release. If the host is wrong, check that
`preview_domain` is set on the unit and that the Release/Environment resolved the expected `<stage>`.

```bash
kubectl get applicationset -n argocd          # the per-Product delivery ApplicationSets
kubectl logs -n argocd deploy/argocd-applicationset-controller --tail=80
```

> **Per-PR ephemeral preview environments (ADR-032) are NOT implemented** on the v3 delivery model. There
> is **no** `pullRequest` generator, no `<product>-<team>-pr-<n>` Applications, and no `github_org` /
> `preview = true` per-app flag — that entire v2 surface was removed at the v3 cutover (ADR-067/069).
> Re-implementing previews on the Release-keyed model is future work; ADR-032 remains the intended design.
> Don't go looking for a preview ApplicationSet — it doesn't exist.

---

## selfHeal / prune behavior

App Applications sync with `automated { selfHeal = true, prune = true }` and `CreateNamespace=false`.

- **selfHeal** reverts any manual in-cluster edit back to Git. A `kubectl edit`/`kubectl rollout undo` will
  be undone — to change a live resource, change the **Git manifest**. (See
  [Deploy App to Preprod](deploy-app-preprod.md#deployment-rollout).)
- **prune** deletes resources removed from Git. If a resource vanished unexpectedly, it was removed from the
  manifests — check the app repo history.
- **CreateNamespace=false** — ArgoCD does **not** create namespaces; `<team>-<product>-<stage>` is owned by the
  Environment Composition. A `namespace not found` sync error means the `XEnvironment` isn't `READY`
  (see [Environment Onboarding](environment-onboarding.md)).

To pause self-heal for debugging:

```bash
argocd app set alpha-demo --sync-policy none      # stop automated sync (re-enable with --sync-policy automated)
argocd app sync alpha-demo                         # one-shot manual sync
```

---

## XEnvironment claims: ServerSideApply + ignoreDifferences

A **single** registry-sync `Application` named `environments` (project `platform-environments`, ADR-069)
recurses **all** the cluster-scoped `XEnvironment` claim YAMLs under `gitops/environments/` (one app for
every environment, not one app per Product/environment). It has its own quirks:

- It syncs with **`ServerSideApply=true`** + `selfHeal` + `prune`, so ArgoCD owns **only the fields it sets**
  (the claim intent). XRD-applied defaults (`quota`, `tier`, …) and Crossplane's `spec.crossplane`/finalizer
  injections are **not** stripped by self-heal.
- A global **`ignoreDifferences`** resource customization (in the `argocd` unit's argocd-cm —
  `resource.customizations.ignoreDifferences.platform.refplat.org_XEnvironment`, ignoring `spec.crossplane`
  and `/metadata/finalizers`) keeps the UI `Synced` despite Crossplane mutating the live object. This is a
  **cluster-wide** customization, **not** an `Application.spec.ignoreDifferences` field. If the `environments`
  app flaps `OutOfSync` on `spec.crossplane`/finalizers, that customization (or ServerSideApply) wasn't
  applied — re-apply the `argocd` unit.
- ArgoCD applies as the assumed **`ArgoCD` IAM role**, the platform principal excluded from the S1
  `restrict-environment-control-plane` Kyverno backstop. An `XEnvironment` creation denied as an environment
  principal means the claim was applied by something other than this Application.

```bash
argocd app get environments                                          # the single XEnvironment-claims app
# The ignoreDifferences is a GLOBAL argocd-cm customization, not an Application field — inspect the ConfigMap:
kubectl get cm argocd-cm -n argocd -o jsonpath='{.data.resource\.customizations\.ignoreDifferences\.platform\.refplat\.org_XEnvironment}'
kubectl --context preprod get xenvironment <team>-<product>-<stage>  # SYNCED / READY after the app syncs
```

To trace a claim end-to-end after it syncs, see
[Crossplane Environment API](../architecture/crossplane-environment-api.md#claim-delivery--lifecycle).

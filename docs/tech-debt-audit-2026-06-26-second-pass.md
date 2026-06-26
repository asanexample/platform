# Technical Debt Inventory — Second Pass (Live-State / Runtime)

**Date:** 2026-06-26
**Branch:** `fix/root-hcl-provider-pins` (current `main` lineage, post-#769 paydown)
**Scope:** the gaps the [first pass](tech-debt-audit-2026-06-25.md) could not see. The first audit (2026-06-25, epic #769) was **static / repo-only**. This pass targets **live AWS + cluster state**, plus the under-covered static dimensions (DR/backup, secrets lifecycle, policy coverage, resilience/SPOF, cost/FinOps, regulated-tier readiness) and re-examines the first pass's deferred items.

**Method:** Seven parallel adversarial agents — three live-state (AWS orphans/cost, platform-cluster drift, preprod-cluster drift + right-sizing), four static-plus-live (DR/data-layer, secrets-lifecycle + Kyverno-coverage + regulated-tier, resilience/SPOF + coupling, rename-leftovers + deferred-item re-examination). Creds: `AWS_PROFILE=management` (SSO; assumes PlatformDeployer per account) + kubectl over Tailscale. **Every Tier-1/2 headline finding was independently spot-verified** by the orchestrator before filing (the first pass had ≥3 false findings caught only by verification — see its TD-602/TD-007 notes).

> This is an **inventory for later prioritization**, not a change set. Nothing here was fixed. IDs are `TD2-NN` (second-pass handles); first-pass IDs are referenced as `TD-NNN`.

---

## 1. Executive Summary

The **live state is remarkably clean** — far cleaner than a runtime audit usually finds. No orphaned EIPs/ENIs/snapshots/AMIs/unused-SGs, no idle load balancers, no unretained log groups, no stopped instances, every CloudWatch log group has retention, total measurable cost-waste is **under ~$1/mo**. ArgoCD apps are Synced/Healthy, all PolicyReports PASS, certs/ESO/secret-stores all green, SOPS KMS rotation is on, the deployment DAG has **no circular dependencies**, and the cosign-on-hub enforcement (#770) is verified live and **not** blocking legit pods. A first-pass cost claim was **disproven** (TD-208: prod has no NAT gateway, so it costs nothing — see §6).

The debt that exists is **not cruft — it is missing resilience/recovery machinery and a few real runtime faults**, clustered into five themes:

1. **No data backup or recovery story (highest risk).** The Backstage and — critically — **Keycloak** Postgres databases are single-instance, on `reclaimPolicy: Delete` EBS, with **zero backup** (no WAL archiving, no object store, no `ScheduledBackup`). There is no Velero, no EBS DLM snapshot policy, and restore has never been tested. ADR-054 documents the plan but it is entirely unbuilt; the DR doc's "no application data to back up yet" is now **false**.
2. **Static, never-rotated credentials.** **None** of the 23 platform / 3 preprod Secrets Manager secrets have rotation — including 5 GitHub App private keys, a GitHub PAT, Tailscale OAuth, the Cloudflare token, and Keycloak admin passwords.
3. **Resilience gaps the `cost_profile` switch silently misses.** Most SPOFs (single-AZ, single-NAT, single-replica add-ons) are deliberate `cost_profile=dev` tradeoffs with a designed `prod` remediation. But **Keycloak HA and the CNPG DB instance counts are NOT wired to the switch** — they stay single even at `cost_profile=prod`. And **preprod's Kyverno admission controller is single-replica, fail-closed, with no PDB** on the cluster that actually runs tenant workloads.
4. **A few real runtime faults.** Backstage portal is **down** (503 for 10h, can't reconnect to its rescheduled DB, won't self-heal). preprod's `kyverno-platform-policies` Helm release is in `failed` state. Platform node image-fs is at 85% with ImageGC failing. OTel auto-instrumentation was never installed (failed Helm release, no `Instrumentation` CR).
5. **Cost/FinOps & config-creep gaps.** preprod's Kyverno admission controller burns ~1.1–1.2 CPU cores (request 100m, **no CPU limit**), likely forcing a second node that sits at 4% utilization. Tenant/product ECR repos have **no lifecycle policy** → unbounded image accumulation.

Plus the re-confirmed first-pass deferred items (all **still open** on main, none silently fixed): TD-103 (validation 2.9%), TD-105 (8 `null_resource`/`local-exec`), TD-107 (zero `moved` blocks), TD-206 (dead `common_tags`), #118 (80 trivyignore CMK), #680 (EBS-CSI on IRSA), TD-605 (`tenant-api` label leftover).

---

## 2. Tier 1 — Act Soon (verified, real risk now)

### TD2-01 — Backstage + Keycloak Postgres have ZERO backup; single-instance; EBS `reclaimPolicy: Delete` — **HIGH** ✅ verified

The single biggest data-loss risk on the platform. Both CNPG clusters are 1 instance, no backup of any kind, on a `Delete`-reclaim StorageClass.

- **Verified live:** `kubectl get clusters.postgresql.cnpg.io -A` → `backstage-db` (1 inst, `.spec.backup=<none>`), `keycloak-db` (1 inst, `<none>`); `get scheduledbackups,backups -A` → **No resources found**; `gp3` StorageClass `reclaimPolicy=Delete`.
- **Source:** `infra/modules/backstage/main.tf:278-313`, `infra/modules/keycloak/main.tf:138-145` define the `Cluster` CR with `instances`/`storage` only — no `backup`/`barman`/`objectStore` block. `instances=1` hardcoded (`backstage/terragrunt.hcl:151`).
- **Risk:** A lost cluster/PVC/AZ permanently destroys the **Keycloak realm DB** (users, OIDC clients, RBAC — the platform's identity source of truth) and the Backstage catalog. RPO = ∞. CNPG natively supports Barman/S3 continuous backup + PITR; it is simply not configured. *(DR-1)*

### TD2-02 — No rotation on ANY Secrets Manager secret, including high-value long-lived credentials — **HIGH** ✅ verified

- **Verified live:** all preprod secrets return `Rotation: null` (`preprod/tailscale/oauth`, `…/api-key`, `…/slack-webhook`); agent confirmed all 23 platform + 3 preprod the same.
- **Inventory of concern:** GitHub PAT (`platform/github/argocd-pat`), 5 GitHub App private keys (backstage, scaffolder, gha-runner-controller, promote, github-ownership), Tailscale OAuth + API key (both envs), Cloudflare API token, Keycloak admin + seed passwords, OIDC client secrets, Grafana admin, Slack/PagerDuty tokens. Many `LastChanged` = rebuild day (2026-06-14), untouched since.
- **Risk:** Durable standing access if any leaks (PAT → ArgoCD repo access; Tailscale OAuth → tailnet/subnet-router; GitHub Apps → org repo write); blast radius compounds because nothing ever rolls. No rotation policy, no expiry, no rotation runbook. *(TD-S1)*
- **Sub-finding TD2-02b (Med):** `platform/github/argocd-pat` is a PAT where the rest of the platform standardized on GitHub Apps — broader scope, harder to attribute/rotate, and PAT expiry can silently break ArgoCD repo sync.

### TD2-03 — preprod Kyverno admission controller: single replica, fail-closed, no PDB (on the tenant cluster) — **MEDIUM-HIGH** ✅ verified

- **Verified live:** preprod `kyverno-admission-controller` `1/1`, **no kyverno PDB** in preprod (only karpenter/coredns/ebs-csi/metrics-server have PDBs). Webhook `failurePolicy=Fail`. Platform (hub) by contrast runs `3/3` **with** PDB `minAvailable=1`.
- **Risk:** preprod is the Enforce-mode tenant-workload cluster. A single admission pod that is down (node drain, park/unpark, OOM) **fail-closes all matched admission** → no tenant deploy, no ArgoCD sync to environment namespaces — until it restarts. The hardening asymmetry (hub hardened, tenant cluster not) directly compounds the known #665 unpark wedge. Cheap fix: scale to 2–3 + add PDB. *(R4)*

### TD2-04 — preprod Kyverno admission controller burns ~1.1–1.2 CPU cores; request 100m, NO CPU limit — **MEDIUM** ✅ verified

- **Verified live:** `kubectl top -n kyverno` → admission controller **1175m** CPU (agent saw 1107/1096/1210m across samples), steady ~120Mi mem. Resources: `requests cpu=100m`, `limits {memory:384Mi}` — **no CPU limit**.
- **Root cause (agent-attributed):** continuous no-op `UPDATE` admissions on the 3 XEnvironments from Crossplane's reconcile loop, each hitting the `restrict-environment-envelope` validating webhook, logged at `--v=2`. The objects are stable; the churn is reconcile traffic.
- **Cost/risk:** ~55% of a 2-vCPU node consumed at otherwise-idle steady state; the dominant reason a node sits at ~101% CPU (and plausibly why a 2nd node exists — see TD2-13). **Levers:** exclude the crossplane SA from the envelope webhook / fire only on user-driven changes (the Composition already controls envelope contents, ADR-062); lower kyverno log verbosity; set a CPU limit. *(B1)*

### TD2-05 — Backstage portal is DOWN: backend 503 for 10h after DB reschedule, won't self-heal — **MEDIUM** ✅ verified

- **Verified live:** `backstage-7b645bd5b9-69l4r 0/1 Running (10h)`, readiness 503 (×653), liveness 200; `backstage-db-1` only ~2h old (rescheduled on the ~105m-old nodes). Restart count 0 → it will **not** self-heal; the backend can't reconnect to its moved Postgres.
- **Risk:** `backstage.aws.refplat.org` not serving (endpoints not Ready behind the Gateway). Needs a pod restart now; longer-term needs a DB-reconnect/readiness-driven restart so a CNPG failover doesn't strand the backend. *(platform-1)*

---

## 3. Tier 2 — Resilience / DR / Regulated-Tier Readiness

### TD2-06 — Both clusters run entirely in a single AZ (`us-east-1c`), incl. all stateful EBS — **HIGH (by-design, dev profile)**

- **Verified live:** platform 3 nodes + preprod 2 nodes **all `us-east-1c`**. Driven by `cost_profile="dev"` (`common.hcl:58`) → `single_az_nodes=true` (`_base.hcl:62`); `node-groups/terragrunt.hcl:58` both envs.
- **Blast radius:** a us-east-1c outage takes down the entire data plane of both clusters; all EBS-backed StatefulSets (CNPG, Mimir/Loki/Tempo/Prometheus, Keycloak DB) are volume-bound to 1c and unrecoverable until the AZ returns. `cost_profile="prod"` spreads nodes across AZs. Track as **prod-readiness checklist**, not a defect. *(R1)*

### TD2-07 — Keycloak (auth IdP) and CNPG DB instance counts are NOT wired to the `cost_profile` switch — would stay single even at `prod` — **MEDIUM**

- **Evidence:** Keycloak unit passes no `high_availability`/`replica_count` → module default `1` (`keycloak/variables.tf:52-55`); HA additionally needs an Infinispan/JGroups follow-up. Backstage hardcodes `instances=1` (`terragrunt.hcl:151`); both CNPG clusters show PDB `ALLOWED DISRUPTIONS=0`.
- **Why it matters:** these are the one critical control-plane service (Keycloak) and the two stateful DBs the HA switch **silently misses** — flipping `cost_profile=prod` would leave them single-replica. (Operators are NOT locked out if Keycloak dies — kubectl via PlatformAdmin/AWS IAM is independent — but ArgoCD-UI/Backstage/tenant SSO are.) **Verify the `prod` profile path has actually been exercised end-to-end.** *(R2/R3)*

### TD2-08 — EKS control-plane audit logging is OFF on both clusters — **MEDIUM** ✅ verified

- **Verified live:** `aws eks describe-cluster … --query cluster.logging` → `enabled:false` for all of api/audit/authenticator/controllerManager/scheduler, both clusters. Deliberate per-env override ("vended audit/api logs ran ~$700/mo", `eks/terragrunt.hcl:42-45`); module default is all-5-on.
- **Risk:** forensics gap today (no API/audit trail for incident reconstruction — the autonomous triage agent leans on ArgoCD as change-source partly to compensate) and a hard **blocker for any hipaa/pci tier**. Re-enable path exists per-env (cheap to flip when needed). *(TD-R1)*

### TD2-09 — No Velero, no EBS DLM snapshot policy; restore never tested; ADR-054 unbuilt; DR doc stale — **MEDIUM-HIGH**

- **Verified:** `aws dlm get-lifecycle-policies` → `[]`; no `velero` namespace/pods; `velero` appears only in design docs. `docs/runbooks/platform-rebuild-from-scratch.md` states "data loss is expected and acceptable"; `infra/docs/16-disaster-recovery.md` lists CNPG backup/PITR, Velero/snapshots, CRR, RPO/RTO, and DR game-days all as **Planned**; **ADR-054 is Status: Proposed** and unbuilt.
- **Risk:** the "rebuild = DR" story reprovisions **empty** databases (identity + portal state lost on any rebuild). No restore mechanism exists, so no restore drill has ever run. The DR doc's claim "no application data to back up yet" is **false** — Backstage + Keycloak DBs already exist. *(DR-4/DR-5)*

### TD2-10 — State backend DR gaps: bucket no CRR / no Object-Lock / no off-account copy; lock table no PITR / no deletion-protection — **MEDIUM**

- **Verified live (mgmt acct):** state bucket versioning **Enabled** (good), but `get-bucket-replication`/`get-object-lock-configuration` → none; DynamoDB `terraform-locks` `PointInTimeRecovery=DISABLED`, `DeletionProtectionEnabled=false`.
- **Risk:** state is the one asset that cannot be regenerated from code (the DR doc says so). Versioning protects in-place corruption, but a region loss / account compromise / accidental delete = total state loss. The lock-table risk is mostly accidental-delete (it holds only lock metadata). Object Lock + deletion-protection are cheap hardening; CRR + off-account copy are the bigger DR lift (the DR doc lists both as Planned). *(DR-2/DR-3)*

### TD2-11 — Regulated-tier (hipaa/pci) machinery is present but UNTESTED; node EBS uses AWS-managed key not CMK — **MEDIUM (latent)**

- **Evidence:** `require-pod-security-restricted` + `require-ro-rootfs` render only for `complianceTier != standard` (`pod-hardening.yaml:78`), but the offline harness only runs `--set complianceTier=standard` (`.kyverno-tests/run.sh:13`) — these admit/reject paths have **never executed** on a live cluster (both are `standard`). `eks-node-group` sets `ebs{encrypted=true}` with no `kms_key_id` → AWS-managed `aws/ebs` key, not a customer CMK (ties to #118). Karpenter EC2NodeClass encryption unverified.
- **Risk:** the first real regulated environment would be the first time `runAsNonRoot`/`readOnlyRootFilesystem` enforcement runs (unknown breakage, e.g. RO-rootfs crashing images), and CMK-on-volumes wouldn't satisfy a regulated tier. *(TD-R2/TD-R3)*

### TD2-12 (resilience) — Hub-failure blast radius is undocumented; ArgoCD components single-replica with no PDB even in HA mode — **LOW-MEDIUM**

- **Evidence:** platform cluster is the sole host of ArgoCD, the observability hub, the Crossplane control plane, registry-sync, and the triage agent. If it is down, preprod keeps *running* but loses all GitOps reconciliation, telemetry ingestion, environment provisioning, and SSO. No documented hub-failure blast-radius/RTO note was found. Separately, all ArgoCD components are `1/1` with **no PDBs on either cluster**, and the unit's `high_availability` path adds replicas but still declares **no PDB** (`infra/modules/argocd/main.tf:67-89`) — a node drain can evict both HA replicas at once. *(R6/R7)*

---

## 4. Tier 3 — Cost / FinOps & Cluster Hygiene

### TD2-13 — preprod is request-bound, not usage-bound: over-provisioned requests force a 2nd node at 4% utilization — **MEDIUM**

- **Evidence:** node `-29` cpu **requests 1901m (98%)** / usage 101%; node `-32` requests 560m (59%) but **actual usage 45m (4%)**. Top requesters are boilerplate 100m each (alloy, prometheus, the 4 kyverno controllers, metrics-server, coredns). Karpenter can't consolidate because *requests* (not usage) pack `-29` to 98%.
- **Cost:** with TD2-04 (kyverno core-burn) fixed and the boilerplate 100m requests right-sized, the preprod control-plane footprint could plausibly fit on **one** `t4g.large` → ~50% preprod node-cost saving. *(B2)*

### TD2-14 — Tenant/product ECR repos have NO lifecycle policy → unbounded image accumulation — **MEDIUM** ✅ verified

- **Verified live:** `team-platform/triage-copilot-server`, `team-alpha/conformance-web`, `team-alpha/shop-web` → **NO lifecycle policy**; `platform/backstage` → HAS policy. triage-copilot already at 118 images over ~4 days of active pushes.
- **Risk:** every CI merge pushes an image; with no expiry these grow without bound. Current cost trivial (~$0.06/mo) but it's a **systematic gap** — the ECR provisioning path (`infra/modules/aws/ecr` / the Composition's ECR wiring) should attach an `untagged`/`countMoreThan` lifecycle policy the way the platform-owned repos do. Fix once, applies to all future products. *(orphans-2)*

### TD2-15 — Platform node image-filesystem at 85%, ImageGC failing; high redeploy churn — **MEDIUM**

- **Evidence:** event `ImageGCFailed / FreeDiskSpaceFailed: 85% of 19.9 GiB used … freed 0 bytes` on `ip-10-100-2-40`; DiskPressure currently False (borderline). Driven by heavy image churn: `platform-agent-triage-copilot` has **12 ReplicaSets**, `crossplane-agent-api` Helm at **v6**, all within ~17h of active iteration (exceeds default `revisionHistoryLimit`).
- **Risk:** could escalate to ImagePullBackOff / pod eviction if it crosses the GC threshold. Consider a larger ephemeral/image volume and trimming `revisionHistoryLimit` on the agent control plane. *(platform-4/5)*

### TD2-16 — OTel auto-instrumentation never installed (failed Helm release, no `Instrumentation` CR) — **MEDIUM**

- **Evidence:** `sh.helm.release.v1.platform-instrumentation.v1` `status=failed` (only revision, never retried); `kubectl get instrumentations.opentelemetry.io -A` → **No resources found**, while the `opentelemetry-operator` Deployment is 1/1 Ready.
- **Risk:** the SDK auto-instrumentation layer of the observability epic is silently absent on the hub despite the operator running — no `Instrumentation` resource for pods to be injected from. *(platform-2)*

### TD2-17 — Manually-applied `agent-demo/checkout` crashloop fixture on BOTH clusters (not GitOps) — **LOW-MEDIUM** ✅ verified

- **Verified live:** `agent-demo/checkout` `CrashLoopBackOff`, 27 restarts / 10h, on platform **and** preprod; namespace has no team label, **not an ArgoCD Application** (applied by hand, `last-applied-configuration` present). `busybox:1.36` echoing `FATAL … payments-db … connection refused`.
- **Assessment:** almost certainly the deliberate "incident" the triage-copilot agent triages — but it is **cluster drift** (hand-applied, not in git, on the GitOps hub), generates continuous restart/log churn, and leaves **two stale ReplicaSets**. If intentional, move it into git; if leftover, delete. **Confirm intent with owner.** *(platform-3/preprod-A2)*

### TD2-18 — preprod `kyverno-platform-policies` Helm release stuck `failed` (latest 2 revisions) — **MEDIUM**

- **Evidence:** `kyverno-platform-policies` v17=`deployed`, **v18/v19=`failed`** (`Upgrade … failed: no endpoints available for service "kyverno-svc"/"kyverno-cleanup-controller"`). Live policy set is still v17 (admission works) but the release is dirty.
- **Risk:** the next `terragrunt apply` of the policy unit hits a dirty release and will likely need `helm rollback`/`--force`. Root cause is the Kyverno chicken-and-egg during a node-disruption window (webhook had no ready endpoints) — the same fragility as TD2-03. *(preprod-A1)*

### TD2-19 — Minor live cruft (each LOW, ~$0 cost) — **LOW**

One orphaned 5GiB EBS volume (`vol-0b39bed948ed01e83`, a detached `storage-tempo-0` PVC, ~$0.40/mo — the *only* EBS orphan found; the "rebuild EBS-orphan pile" is a non-issue in current state); empty orphaned ECR repo `team-alpha/payments-web` (0 images, no matching push role — expected ECR-Orphan-on-delete cruft, safe to delete after confirming `payments` isn't in-flight); the self-service tenant S3 bucket `refplat-alpha-conformance-dev-blob-*` has **no `AbortIncompleteMultipartUpload` lifecycle** (the self-service-S3 path should attach one by default); platform gateway NLB has 4 empty `k8s-default-ciliumga-*` target groups (free, possible stale listeners). *(orphans 1/3/4/5)*

---

## 5. Tier 4 — Policy Coverage, Re-confirmed Deferred Items, Rename Leftovers

### TD2-20 — Kyverno coverage gaps (the inverse of the first pass) — **MEDIUM / LOW-MED**

- **No admission floor on platform/system namespaces (Med):** `require-requests-limits` and `restrict-image-registries` match only environment namespaces (`platform.refplat.org/team` selector); platform/system namespaces (`argocd`, `backstage`, `crossplane-system`, `kube-system`, …) carry **no PSA `enforce` label** and no Kyverno floor. No policy anywhere guards `hostNetwork`/`hostPath`/`hostPID`/`privileged`/`hostPort` (grep empty) — that protection lives only in PSA baseline, which is unlabeled on platform namespaces. *(TD-K1)*
- **~~Non-supply-chain ClusterPolicies are Audit on both clusters~~ — FALSE FINDING (retracted):** the TD-K5 agent read the *deprecated* top-level `spec.validationFailureAction` (which is `Audit`) and missed the modern per-rule `validate.failureAction`, which is **`Enforce`** on every validation rule. **Verified live:** platform = 19/19 rules `Enforce`, preprod = 22/22 rules `Enforce` (plus the 8 `verify-*` cpols at `spec=Enforce`). In Kyverno 1.18 the per-rule `failureAction` governs and takes precedence over the deprecated field. **The policies ARE enforcing on both clusters — CLAUDE.md is correct.** (Caught by orchestrator spot-verification; this is the kind of deprecated-field misread the discipline note warns about.)
- **NetworkPolicy existence not admission-enforced (Low-Med):** per-env netpols are Composition-provisioned; nothing rejects their deletion → a reconciliation-lag window of unrestricted egress/ingress. *(TD-K2)*
- **RBAC-escalation coverage partial (Low-Med):** `restrict-binding-clusteradmin` + `restrict-wildcard-rbac` cover the worst cases; no policy guards `escalate`/`bind`/`impersonate` verbs or non-wildcard-but-broad `secrets:get` ClusterRoles. *(TD-K4)*

### TD2-21 — First-pass deferred items re-examined — ALL STILL OPEN on main (none silently fixed by #769)

| Item | Verdict | Evidence |
|------|---------|----------|
| TD-103 variable validation | STILL OPEN — **2.9%** (25 `validation{}` / **857** vars; 10 of ~60 modules); ~101 high-value vars (arn/account/cidr/version/region/email) mostly unguarded | repo-wide |
| TD-105 `null_resource`+`local-exec` | STILL OPEN — **6 modules / 8 `null_resource` / 10 `local-exec`**; riskiest = crossplane IAM/ECR **orphan sweeps** (mutate live AWS on destroy) | `crossplane/main.tf:327,409,430`, cilium/observability/backstage/tailscale/keycloak |
| TD-107 `moved{}` blocks | STILL OPEN — **still zero**; renames (#427/#433) were mostly Helm/manifest (lower need), but the practice gap remains | `infra/modules/` |
| TD-206 dead `common_tags` | STILL OPEN — `inputs.common_tags` passed to every module but **no module declares the var**; `locals.common_tags` referenced nowhere | `infra/root.hcl:77,113` |
| #118 CMK deferral | STILL OPEN by design — **80** `.trivyignore.yaml` entries (AWS-0132×9 S3-CMK, AWS-0015×2 CloudTrail-CMK, …); CloudTrail/audit+state S3/SNS/4× observability stores on AWS-managed/SSE-S3 keys | `.trivyignore.yaml` |
| #680 EBS-CSI on IRSA | STILL OPEN — `aws-ebs-csi-driver` uses an `irsa{}` block (not Pod Identity) on **both** clusters; lone IRSA add-on holdout | `…/eks-addons/terragrunt.hcl` platform:68-72, preprod:48-52 |

### TD2-22 — Rename leftovers — **LOW**

- **`tenant-api` label still on 3 Team CRs (confirms TD-605, STILL OPEN):** `gitops/teams/{platform,bravo,alpha}.yaml` carry `app.kubernetes.io/part-of: tenant-api` while every Product/Environment uses `environment-api`. The projected template already uses `environment-api`; only the git-native source files lag. Trivial one-line-each fix. No sibling leftovers found.
- **`app-alpha` ServiceAccount name (PARTIAL):** all three alpha environment claims use `serviceAccount: app-alpha` (`gitops/environments/alpha/*/dev.yaml`) — a stale `app-` prefix as an *in-cluster identifier* (distinct from the legitimately-named GitHub app repos). Consistent, not broken; renaming requires coordinated app-repo manifest changes.
- **Clean:** `ops→platform` fully landed (no residue); `_v1/_v2/_v3`/`XTenant` essentially clean (one dead comment at `cluster-rbac/main.tf:100`); the ~40 `tenant` hits in observability are the legitimate multi-tenant (X-Scope-OrgID) concept, **not** rename residue.

### TD2-23 — preprod ESO deployed but reconciles zero ExternalSecrets — **LOW**

preprod `external-secrets` has 3 healthy pods but `kubectl get externalsecrets -A` returns **zero** — the env-secrets delivery path is unexercised on the cluster that actually runs tenant apps. Not a leak; flags that the path is unproven on preprod. *(TD-S3)*

---

## 6. What's Healthy / Corrections (explicitly checked)

- **Live AWS state is exceptionally clean:** no unused EIPs, no orphaned ENIs/snapshots/AMIs, no unused security groups, no idle load balancers, no stopped instances, **every** CloudWatch log group has retention; total measurable cost-waste **< ~$1/mo**. mgmt account completely clean. NAT (1/active VPC) and the preprod internet-facing NLB are both confirmed **by-design**, not waste.
- **Correction to first-pass TD-208:** the prod account has **only the default VPC** — **zero NAT gateways**, zero EC2/EIP/EBS/ELB. The "prod stub costs NAT for nothing" framing is **false in live state** (cost $0). The only residual is a hygiene item: the AWS default VPC still exists in prod (best practice = delete it).
- **Secrets/cert/ESO health (skeptic's non-findings):** SOPS KMS rotation **enabled** (365d, next 2027-06-10); cert-expiry alerts exist (`CertManagerCertExpiring*` 7d/21d) and all certs Ready (~2026-09, LE auto-renew); ESO-sync-failure alerts exist and all ExternalSecrets are `SecretSynced`; both ClusterSecretStores Valid; **zero PolicyExceptions** on either cluster (no polex sprawl); SOPS file has no placeholder entries; EKS secrets ARE CMK-envelope-encrypted.
- **GitOps/DAG health:** top-level ArgoCD apps Synced/Healthy; all PolicyReports PASS (0 fail) on both clusters; all XEnvironments Synced/Ready; **no circular dependencies** in the platctl-derived DAG (the historical policy↔crossplane near-cycle is fixed); bootstrap chicken-and-egg cases are documented/handled.
- **Kyverno IS enforcing on both clusters (correction to an agent's draft finding):** the modern per-rule `validate.failureAction` is `Enforce` on all validation rules (platform 19/19, preprod 22/22) — the deprecated top-level `spec.validationFailureAction: Audit` is a red herring. CLAUDE.md's "Enforce on preprod and platform" is accurate.
- **cosign-on-hub (#770) verified live:** `verify-images/attestations-product-platform-triage-copilot` are `ADMISSION=true, READY=True`, enforcing, and **not** blocking the running agent (PolicyReport 11 PASS / 0 FAIL).
- **Observability S3 buckets are durable-by-design** (versioning on, only noncurrent-version expiry; app-managed retention) — telemetry loss on rebuild is acceptable by design, not an at-risk gap.

---

## 7. Suggested Prioritization (for later triage)

**Tier 1 — fix soon (verified):** TD2-01 (CNPG/Keycloak backup — *the headline*), TD2-02 (Secrets Manager rotation), TD2-03 (preprod Kyverno HA + PDB), TD2-05 (Backstage portal down — restart now), TD2-18 (clear failed preprod policy release before next apply).

**Tier 2 — resilience/DR/cost (high leverage):** TD2-09 (build *some* backup — Velero or CNPG Barman/PITR; ADR-054), TD2-04+TD2-13 (kyverno core-burn → likely consolidate preprod to one node), TD2-07 (wire Keycloak/CNPG HA to `cost_profile` or document the gap), TD2-10 (state Object-Lock + lock-table deletion-protection — cheap), TD2-14 (ECR lifecycle policy on the provisioning path).

**Tier 3 — hygiene/coverage (opportunistic):** TD2-08 (audit-logging path for regulated tier), TD2-15/16/17 (node disk + OTel Instrumentation + agent-demo drift), TD2-20 (platform-namespace admission floor + NetworkPolicy/RBAC-escalation coverage), TD2-11 (exercise regulated-tier policies in the harness).

**Tier 4 — re-confirmed deferred / leftovers (low risk):** TD2-21 (TD-103/105/107/206, #118, #680), TD2-22 (`tenant-api` label, `app-alpha` SA), TD2-23, TD2-19 (minor cruft).

---

*Generated by a 7-agent parallel live-state audit on 2026-06-26; every Tier-1/2 headline finding orchestrator-verified against live AWS/cluster state before filing. Re-validate against current `main` before acting.*

# Documentation Audit — shared (non-aws/non-observability) module READMEs (28 modules)

Checkout @ origin/main. Clusters parked; verification against repo only. **26 have a README; 2 do NOT.**

## infra/modules/oauth2-proxy/README.md — MISSING

- [SEVERITY: high] No README for a recent, non-trivial module (helm_release oauth2-proxy, an ExternalSecret, generated cookie secret, gateway-Service lookup; 18 variables incl. the non-obvious `oidc_client_secret_sm_key`/`secret_store_name` ExternalSecret wiring and `issuer_host_alias` split-horizon knob; 2 outputs). — **Evidence:** module `.tf` files exist; `README.md` absent. — **Fix:** add a README (Rollouts-UI/no-native-auth usage, `allowed_groups`/`email_domains` gate, SM-key ExternalSecret inputs).

## infra/modules/platform-directory/README.md — MISSING

- [SEVERITY: high] No README for a module provisioning a CNPG database (Cluster + ingress NetworkPolicy, generated DB password, cross-namespace role secret, SM secret+version, destroy-time CNPG finalizer-cleanup `null_resource`; 13 vars, 2 outputs). The `finalizer_clear_script`/`deployer_role_arn` destroy mechanics + `consumer_namespace` cross-namespace secret projection are easy to misuse undocumented. — **Evidence:** module `.tf` exist; `README.md` absent. — **Fix:** add a README.

## infra/modules/argocd/README.md

- [SEVERITY: medium] TF_DOCS Inputs omit `region` (pins regional STS for cross-account managed-cluster auth) and `component_resources`. — **Evidence:** `variables.tf:12,96`. — **Fix:** regenerate terraform-docs.
- [SEVERITY: low] Dex/SAML correctly framed as the dormant legacy toggle; chart 9.5.14 matches. Verified-correct.

## infra/modules/argocd-apps/README.md

- [SEVERITY: high] The ADR-082 platform-agent delivery road (`agents.tf`) is entirely undocumented — the agents registry-sync, the per-agent workload ApplicationSet targeting `hub_cluster_server`, four agent resources. Inputs table also omits `agents` and `hub_cluster_server`. — **Evidence:** `agents.tf:1-201`, `variables.tf:75-90`. — **Fix:** add an "Agent delivery (ADR-082)" section + regenerate.
- [SEVERITY: medium] AppProject whitelist Note stale — omits `ServiceAccount` + the ADR-056 `Rollout`/`AnalysisTemplate`/`AnalysisRun` kinds. — **Evidence:** `delivery.tf:43-58`. — **Fix:** update the kinds list.

## infra/modules/argocd-clusters/README.md — accurate

## infra/modules/argo-rollouts/README.md

- [SEVERITY: low] The web dashboard (`enable_dashboard`, a write-capable no-auth operator UI, + `dashboard_default_namespace`) is silent in prose/Inputs. — **Evidence:** `variables.tf:41-51`, `main.tf:43-55`. Chart 2.41.0 + ADR-056 verified. — **Fix:** add a one-line dashboard note (Tailscale-internal, no built-in auth).

## infra/modules/keycloak/README.md — accurate (chart 7.2.0, image 26.6.3)

## infra/modules/keycloak-config/README.md

- [SEVERITY: medium] Stale source-of-truth: README + the `teams` var description say the Team taxonomy comes from "canonical `infra/live/aws/_teams.hcl`", but `_teams.hcl` is **retired/absent** — the unit reads `gitops/teams/`. — **Evidence:** README `:36,76,114,254`; unit `terragrunt.hcl:47`. — **Fix:** replace `_teams.hcl` with `gitops/teams/` (ADR-061/067).

## infra/modules/policy/README.md

- [SEVERITY: high] Documents a non-existent input `tenant_registry_map` (Inputs table + copy-paste Usage) — no such variable. Copying the Usage yields "Unsupported argument". — **Evidence:** `variables.tf` (absent; only a stale mention in `allowed_registries`'s description `:34`). — **Fix:** remove it (per-env registry scoping is Composition-owned, ADR-046).
- [SEVERITY: high] Documents a non-existent input `migrated_teams` (Inputs + Usage). — **Evidence:** `variables.tf` (absent). — **Fix:** delete the row + Usage line.
- [SEVERITY: medium] Phase-1 table lists `restrict-images-team-<k>` as a deployed ClusterPolicy — no such template (only cluster-wide `restrict-image-registries`). — **Evidence:** `policies-chart/templates/image-registries.yaml`. — **Fix:** drop the row.
- [SEVERITY: medium] Stale source-of-truth: Design says per-env values come "from `teams.hcl`". — **Fix:** replace with the Product registry.
- [SEVERITY: medium] Default drift: `required_workload_labels` documented `["app.kubernetes.io/name","team"]`; actual default `["team"]`. — **Evidence:** `variables.tf:103`. — **Fix:** correct to `["team"]`.
- [SEVERITY: low] Gap: Design claims "Helm-only provider" but module also uses `aws` for the Kyverno ECR-read IAM role + Pod Identity association. — **Evidence:** `main.tf:181-242`.

## infra/modules/github-teams/README.md — accurate (ADR-061/067-correct)

## infra/modules/cluster-rbac/README.md

- [SEVERITY: high] Security-relevant access description is wrong: README says the `platform-operator` ClusterRole grants only listed read/debug verbs and "deliberately grants **no `create`** and **no other resource types**." The actual ClusterRole also grants `create/update/patch` on `pods` + `pods/ephemeralcontainers`, `patch/update/delete` on a broad CR allow-list (karpenter/crossplane/cnpg/platform.refplat.org), and cluster-wide `get/list/watch` on `*/*` (incl. Secrets). — **Evidence:** README `:11-18` vs `main.tf:37-41,84-96,109-113`. — **Fix:** rewrite the verb inventory; drop/qualify "no create".

## infra/modules/falco/README.md — accurate (chart 9.0.0, ADR-045)

## infra/modules/cilium/README.md

- [SEVERITY: medium] `cloud_provider` documented default `"azure"` but code default is `"aws"`. — **Evidence:** README `:137` vs `variables.tf:15`. — **Fix:** regenerate docs.
- [SEVERITY: medium] TF_DOCS Inputs table omits the entire datapath variable surface (`ipam_mode`, `routing_mode`, `tunnel_protocol`, `pod_cidr`, `egress_masquerade_interfaces`, `bpf_masquerade`, …) — the module's headline feature. — **Evidence:** `variables.tf:33-119`. — **Fix:** re-run terraform-docs.
- [SEVERITY: low] `prometheus_service_monitor_enabled` documented (default `true`) but dead — `main.tf` hardcodes `serviceMonitor.enabled = false`. Note refers to retired "Crossplane **Tenant** Composition". `aws >= 5.0` doc vs `~> 6.0`.

## infra/modules/gateway/README.md

- [SEVERITY: low] Requirements/Providers pin `kubernetes >= 2.35.0` but `versions.tf` requires `~> 3.0`. — **Fix:** regenerate docs. (Body matches `main.tf`.)

## infra/modules/gateway-config/README.md

- [SEVERITY: low] Same `kubernetes >= 2.35.0` vs `~> 3.0` drift.

## infra/modules/cloudflare/dns_delegation/README.md

- [SEVERITY: low] TF_DOCS "No requirements" / cloudflare `n/a`, but `versions.tf` requires `terraform >= 1.6.0` + `cloudflare ~> 5.0`.

## infra/modules/tailscale/README.md

- [SEVERITY: medium] Resources table lists two finalizer resources but code has a single `null_resource.crd_finalizer_cleanup`. — **Evidence:** README `:88-89` vs `main.tf:102`. — **Fix:** regenerate.
- [SEVERITY: medium] Inputs table omits real vars `region`, `deployer_role_arn`, `finalizer_clear_script` (destroy-time cleanup depends on them). — **Evidence:** `variables.tf:115-131`. — **Fix:** re-run terraform-docs.
- [SEVERITY: low] `kubernetes >= 2.35.0` vs `~> 3.0` drift.

## infra/modules/tailscale-admin/README.md — accurate (nit: `aws >= 6.0` doc vs `~> 6.0`)

## infra/modules/external-dns/README.md

- [SEVERITY: low] ADR-047 Pod Identity check PASSES. Minor: IAM-policy summary lists only 2 of 4 Route53 actions; `aws >= 5.0` doc vs `~> 6.0`. — **Evidence:** `main.tf:69-77`.

## infra/modules/crossplane/README.md

- [SEVERITY: medium] Silent on the Agent control plane (XAgent/ADR-082) the module now installs — `enable_agent_api`, the `agent-api`/`agent-policies` Helm releases. "Two roles" framing omits the hub's third role. — **Evidence:** `variables.tf:148-159`, `main.tf:267-313`. — **Fix:** document the Agent role + inputs.
- [SEVERITY: medium] "How it fits together" diagram lists 3 Helm releases but the module creates 7. — **Evidence:** `main.tf:91,118,144,183,233,267,297`. — **Fix:** extend the diagram.
- [SEVERITY: low] Calls the XR an "`Environment` claim/XRD"; actual kind is `XEnvironment` (cluster-scoped, no claim type). Tenant→Environment + #647 gap handled correctly.

## infra/modules/backstage/README.md

- [SEVERITY: low] `projection_mode` (ADR-067 catalog-projection toggle) absent from "Key inputs". README attributes split-horizon OIDC-issuer resolution to `host_aliases`, but that's `oidc_gateway_alias_host`. — **Evidence:** `variables.tf:181-212,311-319`.

## infra/modules/cloudnative-pg/README.md — accurate (chart 0.28.2)

## infra/modules/actions-runner-controller/README.md

- [SEVERITY: high] "Scope" says the privileged AWS-creds path "lands **separately**" and the module only "gets runners registered and idle" — but it **now implements the full path**: runner IAM role + inline policy granting `AssumeRole`+`TagSession` into PlatformDeployer (+ cross-account deployers) and TerraformStateAccess, `kms:Decrypt` of the SOPS key, the SA, and the Pod Identity association. Materially understates blast radius. — **Evidence:** README `:19-24` vs `main.tf:91-156`. — **Fix:** rewrite Scope to describe the runner Pod Identity → Deployer/StateAccess/SOPS path.
- [SEVERITY: medium] "Key inputs" omits the now-**required** `deployer_role_arn` and `state_role_arn` (no defaults), plus `additional_deployer_role_arns`, `sops_key_arn_pattern`/`sops_key_alias`, `runner_service_account`. Provisioning from the README's list would fail. — **Evidence:** `variables.tf:113-145`. — **Fix:** add the required inputs.
- [SEVERITY: low] Chart 0.14.2; runbook exists.

## infra/modules/vcluster/README.md

- [SEVERITY: high] TF_DOCS Inputs documents **four variables that don't exist** (`environment` + `region_abbv` listed required, `ingress`, `workload`), and Usage examples pass `environment`/`region_abbv` — OpenTofu rejects them; the documented usage does not plan. — **Evidence:** `variables.tf:1-95` vs README `:13-14,50-52,109-124`. — **Fix:** regenerate terraform-docs + strip phantom args from both Usage blocks.
- [SEVERITY: medium] Stale cross-ref to the retired `tenant` module as the current caller/mode-selector. — **Fix:** drop `tenant` refs; note vcluster is deferred + not wired into the Environment path.
- [SEVERITY: low] Deferred status (ADR-033) correctly flagged.

## infra/modules/cert-manager/README.md

- [SEVERITY: medium] TF_DOCS Inputs table omits `webhook_host_network` (12th var) — load-bearing: toggles webhook hostNetwork + securePort 10260, required on EKS with the Cilium overlay CNI. — **Evidence:** `variables.tf:74-78`, `main.tf:31-34`. — **Fix:** regenerate docs + a Cilium-overlay Note.
- [SEVERITY: low] Pod Identity (ADR-047) correctly described; chart 1.17.1.

## infra/modules/external-secrets/README.md

- [SEVERITY: medium] TF_DOCS Inputs omit `metrics_enabled` (gates metrics Service + ServiceMonitor) and `webhook_host_network` (Cilium-overlay port moves). — **Evidence:** `variables.tf:7-11,97-101`. — **Fix:** regenerate docs.
- [SEVERITY: low] Pod Identity correctly described; chart 0.14.3.

## infra/modules/secret-stores/README.md — accurate (both ClusterSecretStores, Pod Identity)

## infra/modules/pagerduty/README.md — accurate (hand-written, no TF_DOCS drift; ADR-084)

---

## Cross-cutting note

- **Two missing READMEs (high)** — `oauth2-proxy` and `platform-directory`, both recent and non-trivial. (argo-rollouts and pagerduty *do* have READMEs.)
- **Dominant root cause = stale auto-generated `BEGIN_TF_DOCS` blocks.** A repo-wide `terraform-docs` regen clears most medium/low findings: provider-constraint drift (`kubernetes >= 2.35.0` vs `~> 3.0` across cilium/gateway/gateway-config/tailscale; `aws >= 5.0` vs `~> 6.0`), omitted-input gaps (cilium datapath vars, tailscale finalizer vars, cert-manager/external-secrets webhook+metrics, argocd region, actions-runner required vars), cilium `cloud_provider` default, tailscale/vcluster phantom tables.
- **Genuinely dangerous content drift (high), not fixable by regen:** `cluster-rbac` understates the `platform-operator` ClusterRole's real privileges; `actions-runner-controller` understates the full runner→Deployer/StateAccess/SOPS path; `policy` documents two non-existent inputs in copy-paste Usage; `vcluster` Usage passes args that won't plan.
- **The newest delivery feature — ADR-082 agent road — is undocumented in both `argocd-apps` and `crossplane`.** IRSA→Pod Identity + Dex→Keycloak are correctly reflected; remaining stale `teams.hcl`/`_teams.hcl`/"Tenant" refs isolated to cilium, vcluster, policy, keycloak-config. No broken links anywhere.

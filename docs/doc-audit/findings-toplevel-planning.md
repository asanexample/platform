# Documentation Audit — ROADMAP / REQUIREMENTS / root+infra README / infra/docs

Checkout @ origin/main. Clusters parked; verification against repo + closed-issue cross-checks.

## ROADMAP.md

The most drift-prone file; lags reality by ~an entire sprint.

- [SEVERITY: high] **Zero-downtime / graceful-disruption (ADR-085) entirely absent** — no bullet in Now/Next/Shipped. Merged + live both clusters: PDB generation (#837), backfill (#841), topology-spread (#847), Karpenter drain backstop (#838), prod replica-floor flipped **Audit→Enforce** (#844 CLOSED; `a58ff22d`). — **Fix:** add a Reliability/Kubernetes **Shipped** bullet (ADR-085).
- [SEVERITY: high] **Progressive delivery / Argo Rollouts (ADR-056) buried in "Later" (#500) with no Shipped bullet** — largely built + demoed live (module exists; canary/blue-green as-built; metric-gated canary; burn-rate SLO rules; freeze gate; Rollouts UI behind Keycloak SSO). — **Fix:** add a GitOps & Delivery **Shipped** bullet; keep #500 for residual prod-hardening only.
- [SEVERITY: high] **Identity & Access "Phase 1" presented as future ("Later") but has shipped.** #885–#890 all **CLOSED** (People registry, role catalog, IC generator, Keycloak generator from roster, Backstage manage-people templates, auth-strength MFA). — **Fix:** move I&A Phase 1 to **Shipped**; keep only epic #884's remaining (machine-plane/temporary-power) scope forward.
- [SEVERITY: medium] **PagerDuty on-call IaC + owner-routing (ADR-084) and `platform-directory` nowhere in Shipped.** On-call structure merged (#932); directory referenced only obliquely. — **Fix:** add a Shipped bullet (identity-directory + owner-resolution + PagerDuty on-call).
- [SEVERITY: medium] **Keycloak admin-plane hardening (ADR-087) and temporary-power/JIT (ADR-088) unrepresented.** Passkey hardening + bootstrap-admin seal merged (#899/#930/#935/#941); platctl access list/check + break-glass eligibility merged (#943/#945/#946). — **Fix:** add Identity/Security entries (087 Shipped; 088 Now/in-flight).
- [SEVERITY: medium] **Karpenter (ADR-078, #643) in "Now" labeled "Phase 1 (in progress)" — Phase 1 shipped + live both clusters.** — **Fix:** reword "Phase 1 shipped/live; Phase 2 (HPA/KEDA) in flight."
- [SEVERITY: medium] **Reliability & Tech-Debt "Now" lists CLOSED Tier-1 issues as open:** #770/#771/#772/#647 all CLOSED. — **Fix:** mark done; leave epic #769 with remaining tiers.
- [SEVERITY: medium] **#647 cross-referenced as an open regression (line 124) but is CLOSED.** (CLAUDE.md likewise still says "NOT currently provisioned … #647" — corroborates the drift.) — **Fix:** update to "resolved"; re-point to #364.
- [SEVERITY: low] Revision history stops at v1.5 (2026-06-27), predating the above ships.

## REQUIREMENTS.md

- [SEVERITY: low] **Accurate-by-disclaimer.** The legacy banner (3-9) correctly + prominently flags the stale content (multi-cloud Azure/GCP removed, Dex→Keycloak, IRSA→Pod Identity, "Tenant"→Environment). Objectively-wrong body claims (service CIDR `10.241.0.0/16`/DNS `10.241.0.10` line 44 — actual `172.20.0.0/16`, and `10.241` is now preprod's *pod* CIDR; Cilium "AWS ENI IPAM … no VXLAN overlay" line 99 — actual overlay/VXLAN; "38 ADRs" lines 306/431 — actual 88) are all covered by the disclaimer. — **Fix:** none required; optionally tighten the banner to name the CIDR/overlay change. Leave as historical.

## README.md (root)

- [SEVERITY: medium] **"78 ADRs" is wrong (actual 88) and repeated 5×** as a headline deliverable. — **Evidence:** `ls docs/adrs/` → highest `088`, count 88. — **Fix:** replace all "78" with "88" (or a non-numeric phrasing).
- [SEVERITY: medium] **AWS-accounts section points at the wrong/nonexistent secrets file.** Line 223: "Real account IDs live in `infra/live/aws/secrets.hcl`". Per ADR-066 they live in **`secrets.enc.yaml`** (SOPS, committed); `secrets.hcl` is only the bootstrap fallback and not present. — **Fix:** "`infra/live/aws/secrets.enc.yaml` (SOPS-encrypted, committed; ADR-066)."
- [SEVERITY: medium] **Module-by-domain inventory omits four shipped modules** — `argo-rollouts`, `pagerduty`, `platform-directory`, `oauth2-proxy`. — **Fix:** add them.
- [SEVERITY: low] Module-count nits: "~60 reusable modules" undercounts (≈67 leaf); "AWS foundation (21 modules)" enumerates 21 but `aws/` holds 22 (omits `cost-allocation-tags`). — **Fix:** bump counts.
- [SEVERITY: low] Otherwise strong + honest: capability matrix flags match reality; Dex correctly shown retired; Pod-Identity/zero-static-creds correct; overlay not claimed as ENI; "17 observability modules" correct.

## infra/README.md — accurate (AWS-only framing, `/.tool-versions` SSOT, platctl quick-start)

## infra/docs/06-cidr-allocation.md — accurate (overlay/VXLAN, pod CIDRs from 10.240.0.0/14, service 172.20.0.0/16)

## infra/docs/08-kubernetes-network-design.md — accurate (exemplary; overlay, hostNetwork-webhook gotcha, BYOCNI ordering)

## infra/docs/04-multi-cloud-strategy.md

- [SEVERITY: medium] **Stale Cilium datapath for AWS — says ENI/native, contradicting the live config and docs 06/08.** "Cilium Cloud Modes" table reads `AWS | ENI | Native routing | ens+`; lines 36/76 likewise. Live AWS is overlay/VXLAN. — **Evidence:** `network.hcl:5-8`, `cilium/terragrunt.hcl:85-87`. — **Fix:** AWS row → Overlay/VXLAN (ENI remains a configurable non-default datapath).

## infra/docs/17-available-modules.md

- [SEVERITY: medium] **`argocd` module described as "Dex/SAML SSO" — retired.** Line 48. — **Fix:** "Keycloak OIDC SSO (ADR-021/053/059)."
- [SEVERITY: medium] **Catalog materially incomplete for headline capabilities.** Shared table omits `backstage`, `keycloak`, `keycloak-config`, `cloudnative-pg`, `gateway` (base), most of the 17 observability modules, and the new `argo-rollouts`/`pagerduty`/`platform-directory`/`oauth2-proxy`. AWS table omits `karpenter` (ADR-078), `sops-kms`, `cost-allocation-tags`. — **Fix:** add the missing rows.
- [SEVERITY: low] Line 47 "`cloud_provider` selects ENI/overlay" imprecise (datapath selected by `ipam_mode`/`routing_mode`). IRSA refs for external-secrets/argocd may be stale post-ADR-047.

## infra/docs/02-architecture-overview.md

- [SEVERITY: medium] **Stale ArgoCD SSO mechanism.** Line 173: "SSO via Identity Center SAML". Retired → Keycloak OIDC. — **Fix:** "SSO via Keycloak OIDC". (Spot-check the rest of the version table against `_versions.hcl`.)

---

## Cross-cutting note

**ROADMAP.md is the headline problem and lags reality by ~the entire last sprint.** Five merged-and-live capabilities — zero-downtime/ADR-085, progressive-delivery/ADR-056, the I&A Phase-1 registries+generators (#885-890 all closed), PagerDuty/owner-routing ADR-084, Keycloak/temporary-power ADR-087/088 — are either absent from Shipped or parked under Now/Next/Later as if pending. Karpenter Phase 1 is mislabeled "in progress." Because the doc markets itself as "the complete picture" and the system of record alongside Issues, a reader would conclude the platform is ~one epic behind reality. Closed-issue cross-checks (#770/771/772/647/844/885-890) are the fastest objective signal that several "forward" bullets are done.

Secondary theme: **residual pre-overlay and pre-Keycloak staleness in the older infra/docs notes.** Docs 06/08 were modernized to overlay/VXLAN, but **doc 04 still says AWS=ENI** and **docs 02 + 17 still say ArgoCD SSO = Dex/Identity-Center-SAML** — internal contradictions within the same doc set. The two concrete factual errors most likely to mislead an external reader: README's **"78 ADRs"** (actual 88, ×5) and its **`secrets.hcl`** pointer (should be the committed SOPS `secrets.enc.yaml`). REQUIREMENTS.md is the one stale file handled correctly — its legacy banner is accurate and prominent.

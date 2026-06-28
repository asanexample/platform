# Documentation Audit — Report (2026-06-28)

A comprehensive, adversarial **accuracy + completeness** audit of all non-ADR documentation. (The
88 ADRs were audited separately — PR #948.) **Inventory only — no edits to the docs themselves;**
corrections happen in a later pass.

**Surface covered (~190 files, ~32k lines):** the full `docs/` tree (97 non-ADR files — runbooks,
architecture, plans, guides, compliance, archive, examples, top-level), all 67 module READMEs, the
16 house skills + `CLAUDE.md`, `ROADMAP.md` / `REQUIREMENTS.md` / root + `infra` READMEs, and
`infra/docs/`. Plus a dedicated **gap-hunt** diffing shipped features against the docs.

**Method:** every checkable claim verified against the repo (modules, live units, scripts, CI,
`gitops/`, `cmd/`) + `CLAUDE.md`; cheap live checks where the parked clusters allowed (AWS API).
Per-batch findings are in the `findings-*.md` files beside this report.

Severity: **high** (wrong/misleading enough to cause a bad operational decision or a failed
copy-paste), **medium** (stale/inaccurate, lower blast radius), **low** (cosmetic / verified-correct).

---

## The big picture

The docs are, on the whole, **well-written and were largely accurate when written** — link hygiene
is strong (almost no broken cross-links), and several suites are exemplary (the `docs/guides/
zero-downtime/` tutorials, `platform-rebuild-from-scratch.md`, most house skills, the
`infra/docs/06`/`08` network notes). **The problem is currency, not quality:** the platform shipped a
large amount in the last sprint and the docs lag it. Nearly every high-severity finding traces to one
of **six systemic drifts** — fix those and most of the individual findings fall out.

## The six systemic themes (fix these first)

### 1. IRSA → EKS Pod Identity (ADR-047 / #594) — the single most pervasive drift

The platform add-ons (cert-manager, external-dns, external-secrets, ESO/secret-stores, the Kyverno
ECR-read role, Mimir S3, SNS publish, CloudWatch) all migrated **in place** to Pod Identity. Docs
still say "IRSA" and — worse — give **debug steps that look for an `eks.amazonaws.com/role-arn`
annotation that no longer exists**. Hit (high/med): `secrets-and-external-secrets.md`,
`cosign-image-signing.md`, `gateway-and-ingress.md`, `observability-current-state.md`,
`secrets-management.md`, `observability-troubleshooting.md`, `observability-alerts.md`,
`kyverno-break-glass.md`, and the lone module outlier `observability-loki/README.md`. **A single
"IRSA" sweep across `docs/` clears most of these.** (Stale "IRSA" *comments* also linger in a few
modules — `sns-notifications`, `policy`, `observability/variables.tf` — worth the same sweep.)

### 2. The #647 `DeveloperAccess-<team>` gap — documented as if it works

The v3 Composition emits only the in-cluster RoleBinding; the IAM role + EKS access entry are **not
provisioned**. Multiple docs present the full chain as working, with **verification commands that
fail** (`aws eks describe-access-entry … DeveloperAccess-<team>`). Hit (high/med):
`crossplane-environment-api.md`, `preprod-environment-model.md`, `user-guide.md`, `ship-a-service.md`,
`eks-cluster-access.md`, ADR-068 (in the ADR PR), the `iam_roles` README. **Note:** ROADMAP/CLAUDE.md
say #647 is still open, but the issue is **CLOSED** — reconcile the true status before editing.

### 3. v2 → v3 vocabulary / retired source-of-truth

`Tenant`/`XTenant` → `Environment`/`XEnvironment`; `teams.hcl`/`_teams.hcl` → the git-native
`gitops/teams` + `gitops/products` registries; per-team → per-Product (ECR roles, AppProjects,
Kyverno policy names); `gitops/tenant-claims` → `gitops/environments`. Still present-tense in many
docs/READMEs. Worst: a **security gate** in `product-deprovisioning.md`/`gitops-gate-automerge.md`
references the wrong path/label (false "gone" confirmations), and `policy/README.md` documents **two
non-existent inputs** (`tenant_registry_map`, `migrated_teams`) in copy-paste Usage.

### 4. Dex retired → direct Keycloak OIDC … but oauth2-proxy is BACK

Dex is gone (ArgoCD/Backstage/Grafana use Keycloak OIDC directly). Stale "Dex/SAML" claims remain in
`CLAUDE.md`, `keycloak-sso.md`, `infra/docs/02`/`17`, and several spots. **Critically, the inverse
error also exists:** `docs/README.md` and `identity-sso-troubleshooting.md` say *"oauth2-proxy is
retired"* — but it was **re-introduced** as the SSO front for the Argo Rollouts UI (the
`rollouts-sso` unit, issue 919). An operator debugging Rollouts-UI auth is told to ignore the
component doing the auth.

### 5. Recently-flipped/shipped state not propagated

The replica-floor went **Audit → Enforce** on both clusters (#934, yesterday) — stale in `CLAUDE.md`,
the `authoring-k8s-workloads` skill (HIGH — a `<2`-replica prod manifest is now rejected), and
`kyverno-policy-authoring`. **ROADMAP.md lags ~an entire sprint** — five merged-and-live capabilities
(zero-downtime/ADR-085, progressive-delivery/ADR-056, the identity registries #885-890, PagerDuty/
ADR-084, Keycloak+temporary-power ADR-087/088) are absent from Shipped or parked under Now/Next/Later;
Karpenter Phase 1 is mislabeled "in progress." Two house-skill claims (`argocd-app-delivery`) call
**shipped, live** capabilities (the `XEnvironment` ignoreDifferences, the XAgent/ADR-082 control
plane) "not yet built — design intent," which would mis-route an agent into rebuilding them.

### 6. Stale auto-generated `terraform-docs` blocks

Most module-README findings are "code changed, `terraform-docs` not re-run." Highest-impact:
`eks` documents `endpoint_public_access` default `true` (actually `false`, private-only); `networking`
and `vcluster` document **phantom required vars** (`environment`/`region_abbv`/`workload`) that make
**every usage example fail to plan**. Plus omitted inputs (cilium datapath vars, eks-addons gp3 SC,
eks-node-group `single_az`, cert-manager/external-secrets webhook vars, actions-runner required vars)
and provider-constraint drift (`kubernetes >= 2.35.0` vs `~> 3.0`). **A repo-wide `terraform-docs`
regen + a CI check that fails on stale docs fixes this class wholesale.**

## Highest-priority single items (beyond the themes)

- **Two `exempt_roles` / SCP copy-paste hazards (HIGH):** `incident-scp-blocking.md` and `modify-scps.md`
  tell a responder to keep "six" exempt roles incl. a security-audit-**rejected** `*-karpenter-*`
  wildcard — pasting it during an incident broadens an audited control org-wide. The live set is
  **seven** anchored entries, and the Platform OU now carries **three** SCPs (not one) — also wrong in
  `aws-organizations.md` and the auditor-facing `compliance/scp-control-mapping.md`.
- **`cluster-rbac/README.md` understates `platform-operator` privileges (HIGH, security):** claims "no
  create / no other resources"; actually grants pod create + ephemeral-containers + broad CR mutate +
  cluster-wide read incl. Secrets.
- **`actions-runner-controller/README.md` understates blast radius (HIGH):** says the privileged
  AWS-creds path "lands separately"; it's fully built (runner → PlatformDeployer/StateAccess/SOPS).
- **Copy-paste-will-fail commands (HIGH):** `product-deprovisioning.md` (bogus `…/environment` label →
  false "gone"), `rollout-and-gate-operations.md` (double-`-l` same-key → zero pods),
  `transit-gateway-operations.md` (non-existent `transit_subnet_ids` output), `modify-scps.md` (count
  snippet always prints "2").
- **6 of 11 `docs/plans/` are completed/superseded but still read as active** — archive or add dated
  DONE/Superseded banners (`085`, `131`, `adr-071-…`, `v3-implementation-plan`, both `tenant-api-v2-*`).
  `slsa-l3-…-HANDOFF.md` self-says "delete once P4 lands" — P4 landed.

## Top documentation GAPS (undocumented shipped features)

The accuracy fixes above are the bulk of the work; these are the **missing docs** the next pass should
*create* (full detail in `findings-gaps.md`):

1. **Authoring / operating a platform agent (XAgent)** — no skill, no runbook, no architecture doc; the
   `agent-api`/`agent-policies` charts have no README. Flagship live capability, high blast radius.
2. **`oauth2-proxy` + `platform-directory`** — no module READMEs, and absent from every canonical
   inventory (`CLAUDE.md`, `infra/docs/17-available-modules.md`) along with `argo-rollouts`,
   `pagerduty`, `cost-allocation-tags`.
3. **`platctl access` (ADR-088 JIT elevation)** — shipped, absent from the platctl skill + all docs.
4. **Keycloak admin-plane break-glass runbook** (ADR-087 sealed bootstrap-admin) — no recovery doc.
5. **oauth2-proxy reusable-SSO-front how-to** + correcting the "retired" claims (theme 4).
6. **New Resource self-service (ADR-073)** — built (Composition + scaffolder + gate), ADR-only doc.
7. **`manage-people` joiner/leaver runbook**; the people-gate/roles-gate machinery.
8. **`infra/docs/17-available-modules.md`** regenerate (omits the observability stack, Keycloak,
   Backstage, Karpenter, CNPG, OpenCost).
9. **Observability later-phase + day-2 gaps:** per-app SLOs (`app_slos`/ruler), Karpenter operations,
   CloudNative-PG capability + backup/restore, OpenCost/cost (`infra/docs/19` ignores the live tool),
   logs/traces spoke onboarding (the runbook is metrics-only).
10. **Doc-map:** `docs/README.md` indexes only ~14 of ~42 runbooks; add `docs/runbooks/README.md` +
    `docs/architecture/README.md`; link the orphan architecture docs (esp. the
    `identity-and-access-strategy.md` north-star, currently zero inbound links); mark
    `tenant-api-v2.md` superseded.

## Things that are RIGHT (don't touch on the next pass)

- The `docs/guides/zero-downtime/` suite (11 files) — verified accurate end-to-end, incl. the
  replica-floor-Enforce state. The example workloads are admission-safe.
- `platform-rebuild-from-scratch.md`, `mcp-servers.md`, `secret-rotation.md`, `tailscale-vpn.md`,
  `debug-ingress-and-dns.md`, `environment-aws-access-pod-identity.md`, `app-supply-chain-onboarding.md`.
- Most house skills (`apply-and-destroy`, `cluster-access`, `cluster-parking`,
  `crossplane-composition-authoring`, `supply-chain-onboarding`, `skill-self-correction`).
- `REQUIREMENTS.md` (stale body, but the prominent legacy banner handles it correctly).
- `infra/docs/06`/`08`, the `docs/glossary.md` deprecation markers, observability chart-version pins
  (zero drift), the cosign/Pod-Identity-correct observability READMEs.
- **A correctly-documented contradiction to note:** several docs say replica-floor is Audit; the
  runbooks (`rollout-and-gate-operations.md`) and the live units say **Enforce** — the *docs/units are
  right*, and `CLAUDE.md` + project memory are the stale party.

## Surfaced non-doc issues (file separately)

- **Module bug:** the Kyverno `team`-label mutate injects `split(namespace,'-')[1]` = the **product**
  token, not the team, for v3 namespaces (`alpha-demo-dev` → `team: demo`); masked by a v2 test
  fixture. (`policies-chart/templates/mutate-workload-labels.yaml:33`.)
- **CNPG no-backup** is already flagged in `infra/docs/16-disaster-recovery.md` but unaddressed.

## Scope note (live verification)

Clusters are parked, so claims were verified against the **repo/IaC** (the source of truth for what
*should* be deployed). A handful of runtime-only claims (a CM name generated by a chart, the exact
live `beyla-config`) are noted in the findings as needing a live check on the next unpark; none are
load-bearing for the corrections above.

# Portability — Phased Plan with Go/No-Go Gates

**Date:** 2026-07-02
**Companion to:** `hardcoded-values-audit-2026-07-02.md`
**Target:** Bar A (fork-friendly, documented) + Bar B (identity constants are real variables/config, no source edits). **Bar C (one-command portability) is an explicit long-term goal, out of scope here.**

**Consequence of that scope:** Finding 1 (the `platform.refplat.org` API-group domain) is **NOT a build item** — it's decided once at Gate 0 and then either documented-and-guarded (recommended) or deferred to a separate future project. Bar B is reachable without touching it, because the API group never resolves as DNS — an adopter keeps it as an opaque identifier.

**Guiding principles:**

- **Loud-failing first.** Do the refactors whose mistakes surface immediately (DNS/cert/plan diffs) before anything subtle.
- **Value-preserving refactors.** Every extraction must leave the *resolved* config identical — proven by a plan-clean gate, not by eyeball.
- **Guard against regression as you go.** A CI drift-lint flips from warn→enforce per-category as each phase clears it, so de-hardcoded categories can't silently re-hardcode.
- **Each phase is independently shippable** and independently valuable. No phase gates the cheap 80%.

---

## Phase 0 — Decisions & guardrails  ·  *(no code refactors; unblocks everything)*

**Do:**

1. **Decide Finding 1 scope** (the one genuine product decision). Options: **(a) Opaque** — keep `refplat.org` as an arbitrary group identifier, never rename piecemeal *(recommended for Bar A/B)*; **(b) White-label** — defer to a separate, gated project (Phase 4, conditional). Record the decision (a short ADR or a note in `ADOPTING.md`).
2. **Stand up the drift-guard CI lint** in **warn/audit mode** — greps the tree for `refplat.org`, `asanexample`, and the real 12-digit account IDs outside an allowlist (`secrets.enc.yaml`, docs/examples, gitops sample data, `_versions.hcl`). Emits counts, doesn't fail the build yet.
3. **Capture the baseline** — freeze today's grep counts (domain 814/463, org 517, region 530, accounts) as the regression yardstick.

**⛔ GATE 0 (Go/No-Go):**

- Finding 1 decision is **recorded**. → If **opaque**: Phase 4 becomes doc-only. If **white-label**: Phase 4 enters a *separate* backlog, does **not** block Phases 1–3.
- Drift-guard runs green-in-warn-mode on `main`.
- **NO-GO trigger:** if the team can't agree on Finding 1 scope, still proceed to Phases 1–3 (they're independent) — only Phase 4 is blocked.

---

## Phase 1 — DNS / ingress domain (Finding 2)  ·  Difficulty MED–HIGH, risk LOW

**Do:**

1. Add `base_domain` + `dns_subdomain` to `secrets.enc.yaml`; expose via `_base.hcl` as `include.base.locals.base_domain` (+ per-env subdomain: platform→`aws`, preprod→`preprod.aws`).
2. Thread it through the ~32 live units (route53, gateway, external-dns, keycloak(-config), argocd, backstage, observability + spokes, blackbox, rollouts-sso).
3. Replace org-specific module *defaults* (`keycloak` `hostname_url`, `keycloak-config` `oidc_clients` redirect block, `observability` `grafana_hostname`) — make empty-required or derive.
4. Fix the scaffolder Mimir host (`skeleton/k8s/overlays/prod/progressive.yaml`) to template from portal/product config.

**⛔ GATE 1 (Go/No-Go — the key one for this phase):**

- **`terragrunt plan` on platform + preprod shows ZERO resource changes.** A pure value-preserving refactor MUST produce an empty diff (same resolved hostnames). **Any diff = NO-GO** — investigate before merge (a diff means a value changed, i.e. the refactor is wrong).
- Grep for the `aws.refplat.org` literal in `infra/live/**` units → 0 outside allowlist.
- Drift-guard **domain category flips warn→enforce.**

---

## Phase 2 — Account/region CI + scaffolder hygiene (Finding 4) + small extractions (Finding 5)  ·  Difficulty LOW–MED, risk LOW

**Do:**

1. Promote CI `env` literals → repo `vars.*` in the 8 workflows (account ID, `DEPLOYER_ARN`, `ECR_REGISTRY`, `AWS_REGION`, `CLUSTER_NAME`, region-in-`BASE`-path). Pattern already proven by `test-aws.yml`'s `vars.TEST_ROLE_ARN`.
2. **Scaffolder ECR account** → template out of all 5 overlay kustomizations + `rollout.yaml` (highest leverage: touches every future product).
3. `root.hcl` state `region` + `dynamodb_table` → join the `_secrets` map (chicken-and-egg: read pre-`_base`, mirror `state_bucket`). Same for the `state-access` IAM ARN.
4. Small extractions: `pagerduty` `time_zone`, tailscale operator-tag (promote literal side to shared var), tailnet name → SOPS key, `github_org`→existing `org_name` local, branding tags centralized in `common.hcl`, `identity-center` `"josh"` anchor.

**⛔ GATE 2 (Go/No-Go):**

- **Scaffold a throwaway product** → generated manifests contain **no baked account ID / region / Mimir host** (all templated).
- CI green on all touched workflows (a `vars.*` typo fails loud).
- Real account ID grep outside `secrets.enc.yaml` → 0 (excl. allowlisted docs/fixtures).
- Drift-guard **account-ID + region categories flip warn→enforce.**

---

## Phase 3 — GitHub org threading + fork documentation (Finding 3)  ·  Difficulty MEDIUM, risk LOW

**Do:**

1. Thread `org_name` where cheap: the 2 `github-oidc` units, the 38 `curated.yaml` runbook URLs (templatefile the base), bot logins → repo `vars.*`, `github-asanexample-app-creds` secret name.
2. **Document (do NOT variabilize) the inherent fork-time steps:** the Go module-path rewrite (`github.com/<org>/platform`) and the `trusted-ci` reusable-workflow refs (adopter needs their own `trusted-ci` repo + must re-pin the SHAs). CODEOWNERS `@gangster` → adopter's teams.
3. **Write `ADOPTING.md`** — the Bar-A capstone. Captures every identity constant's change-point PLUS the non-repo prerequisites: SOPS/KMS key, `trusted-ci` repo, Cloudflare zone, Tailscale tailnet, Keycloak SAML apps, scaffolder/gate GitHub Apps.

**⛔ GATE 3 (Go/No-Go):**

- `ADOPTING.md` reviewed; a reviewer can trace **every** identity constant (domain, org, region, accounts) to either a documented variable or a documented fork-time step — no orphans.
- Drift-guard **org category flips warn→enforce** (allowlisting the documented fork-time files: `go.mod`, imports, CODEOWNERS).
- **This gate = Bar A + Bar B achieved.**

---

## Phase 4 — API-group re-domaining (Finding 1)  ·  *CONDITIONAL — only if Gate 0 chose white-label*

**Not needed for Bar A/B.** If deferred (recommended): the drift-guard's domain-in-code allowlist documents "these move together"; no further work. If pursued as a separate project:

**Do:** expose `api_group`/`label_domain` through Helm values (charts hardcode it today); add a Go build-time `groupName` const; regenerate CRDs (incl. `platform.refplat.org_*.yaml` base filenames); coordinated change across ~10 Kyverno policies + ~8 RBAC files + the Composition label-writer + PromQL/dashboard labels.

**⛔ GATE 4 (Go/No-Go — strict):**

- A **real preprod (or kind) deploy** proving admission selectors bind AND the operator reconciles under the new group — because partial rename fails *silently*, plan-clean is NOT sufficient here; requires live admission + reconcile verification.
- **NO-GO trigger:** any Kyverno selector or RBAC apiGroup left on the old domain → hard stop (silent-failure hazard).

---

## Phase 5 — Bar C (one-command portability)  ·  LONG-TERM, deferred

Out of scope. Automating the non-repo prerequisites (SOPS key bootstrap, `trusted-ci` fork, Cloudflare/Tailscale/Keycloak/GitHub-App setup). Some resist full automation (SAML/GitHub Apps). Revisit only after Bar B has been validated by a real fork.

---

## The validation gate that spans everything

Until someone runs a **real fork into a throwaway account** (the Test sandbox `157263244316` is a candidate for a partial dry-run), "portable" is a *claim*, not a fact — this stack's private-EKS/Tailscale/SAML wiring makes that the only true test. Recommend scheduling a fork-deploy dry-run after Gate 3 to convert Bar B from claim → verified.

---

## Sequencing summary

| Phase | Delivers | Difficulty | Risk | Gate = |
|-------|----------|-----------|------|--------|
| 0 | Decision + drift-guard (warn) | — | — | Finding-1 scope recorded |
| 1 | DNS domain variabilized | MED–HIGH | LOW | **plan-clean** (zero diff) |
| 2 | CI/scaffolder/account hygiene | LOW–MED | LOW | throwaway scaffold clean + CI green |
| 3 | Org threading + `ADOPTING.md` | MEDIUM | LOW | every constant traceable → **Bar A+B done** |
| 4 | API-group (conditional) | HARD | HIGH | live admission+reconcile verified |
| 5 | Bar C automation | — | — | deferred |

Phases 1–3 are the whole Bar-A/B goal, are mutually independent (any order), and carry low risk. Phase 4 is off the critical path. The single highest-leverage individual task is the **scaffolder ECR de-hardcode** (Phase 2) — it stops the bleed into every future product.

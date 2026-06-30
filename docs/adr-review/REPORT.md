# ADR Adversarial Accuracy Review — Report (2026-06-28)

> **Retained backlog (not an orphan).** The raw per-batch `findings-NNN-NNN.md` files were pruned in
> the docs-housekeeping pass; this synthesis is kept deliberately as the doc-currency backlog. #977
> applied part of it; the remainder is a planned theme-based sweep — **do not delete until burned down.**

**Scope:** all 88 ADRs (`docs/adrs/001`–`088`) + the canonical index (`README.md`).
**Method:** every checkable claim verified against the repo (modules, live units, scripts, CI,
`gitops/`, `cmd/`), `CLAUDE.md`, and cross-ADR consistency. Claims that hinge on "is this actually
running" and can't be settled from a static checkout are flagged **NEEDS LIVE/OWNER VERIFICATION**
below rather than edited. Per-batch findings are in `findings-0NN-0MM.md` alongside this report.

This is **advisory**. The corrections themselves are in the themed commits on this branch; this
file records what was found, what was changed, and what was deliberately left.

## Headline themes

1. **Status lag — decisions shipped, the ADR header didn't move.** Several ADRs written the same day
   they shipped kept `Proposed` while the code (and `CLAUDE.md`) treat them as live/enforced — most
   seriously **ADR-085** (replica-floor now *Enforce*, rejecting prod deploys) and the index rows for
   **056/085**. Fixed: 056, 069, 080, 084, 085, 087 + index.
2. **"Rides the rebuild" claims that already happened in place.** The platform evolved *additively*,
   not via the from-scratch rebuild several ADRs assumed. **ADR-047** said the IRSA→Pod-Identity
   migration waits for the rebuild — #594 did it in place; EBS CSI stays on IRSA for a *technical*
   reason (managed-addon limitation), not timing. Same shape in 051 (Backstage Dex→Keycloak) and 069.
3. **v2→v3 vocabulary/path drift (ADR-067).** `Tenant`/`XTenant`/`teams.hcl`/`gitops/tenant-claims`
   linger in present tense across the tenancy/identity/supply-chain ADRs. Worst: **ADR-062 §3.4** (a
   *security* automerge gate pointed at the retired `gitops/tenant-claims` path) and **ADR-060** (claim
   paths). Fixed with targeted edits + ADR-067 supersession banners.
4. **Module/topology drift.** **ADR-008** described an AWS ENI/native datapath; the platform runs an
   *overlay* (cluster-pool + VXLAN). **ADR-015**'s overlay-CIDR table had the wrong service CIDR
   (collided with preprod's live pod range). The **gateway/gateway-config** split (017/022/029) wasn't
   reflected. **ADR-003/005** predated the security-audit SCP change on the Platform OU.
5. **Self-contradiction / over-claim.** **ADR-065** Decision said ARC deploys "via ArgoCD" — its own
   body, the repo, and `CLAUDE.md` say Terragrunt. **ADR-039** claimed end-to-end per-team developer
   access is provisioned; only the in-cluster RoleBinding is (regression **#647**).
6. **Authoring-artifact contamination.** Stray `</content>`/`</invoke>` tool-call XML at the tail of
   ADR-056/085 and "Generated with Claude Code" footers in 068/069/070/086. Stripped.

## What was corrected (by commit theme)

- Strip leaked tool-call XML + CC footers (056, 068, 069, 070, 085, 086).
- Status reconciliation + index (056, 069, 080, 084, 085, 087, README recategorization).
- Datapath/CIDR/ARC (008, 015, 065).
- SCP-attachment drift on the Platform OU (003, 005).
- Identity-chain over-claims (039, 047, 051).
- `secrets.hcl` → SOPS `secrets.enc.yaml` (001, 002, 004; incl. the stale `root.hcl` snippet).
- gateway / gateway-config module split (017, 022, 029).
- Stale factual one-liners (014, 021, 036, 038, 072, 073, 083).
- Retired-path / vocabulary (028, 031, 040, 046, 048, 050, 053, 059, 060, 062, 068).

## Live verification status

**Verified live 2026-06-28 (AWS API — clusters were parked, so node-group-independent checks only):**

- **ADR-006 — confirmed.** The management state bucket (`tfstate-mgmt-…`) holds 100 state objects but
  **no `state-bootstrap/terraform.tfstate`**, and the unit's backend is `local`. The bootstrap state is
  genuinely local, *not* migrated to S3 — the ADR's migrate-to-S3 narrative is confirmed unfinished
  (correction stands).
- **ADR-010 — confirmed.** `eks describe-cluster` shows **both** platform and preprod at
  `endpointPublicAccess=false` / `endpointPrivateAccess=true`. Preprod is private-only as claimed.

**Still blocked — pending unpark (need kubectl to the private API):** ADR-056 (Rollouts applied + the
alpha-shop prod canary executing), ADR-085 (replica-floor ClusterPolicy = Enforce in etcd), ADR-077
(Beyla DaemonSet + `Instrumentation` CR scheduled), ADR-087 (master-realm passkey enrollment). While
parked, the Tailscale `*-eks-subnet-router` (cluster-hosted) is offline, so the private endpoint is
unreachable from off-cluster.

**External repos (not in this checkout):**

- **ADR-042/050/080:** SLSA-L3 build state, the `trusted-ci` cert identities, and the triage-copilot
  model tiers live in external repos (`asanexample/trusted-ci`, `…/platform-triage-copilot`).
- **ADR-056:** Rollouts *applied* on both clusters + the alpha-shop prod canary proven live (module +
  units + Kyverno are present in-repo; apply-state isn't).
- **ADR-051/061:** upstream Backstage version pin; external Cilium issue # and Cloudflare pricing.
- **ADR-087:** confirm the master `admin` passkey was enrolled before the browser-MFA bind (the live
  unit's inline comment and `enforce_master_browser_mfa = true` look mismatched).

## Deliberately left (low-severity / house convention)

- Append-only ADR bodies whose **status header already declares them superseded** (e.g. 049, 052, 058,
  064, 076) — the bodies legitimately retain historical vocabulary; no edit needed.
- Optional cosmetic notes (e.g. region-scoped split-DNS example in 011, title truncation in the index)
  — recorded in the findings files, not worth churn.

## Suggested follow-ups (engineering, outside this docs PR)

- **#647** — wire the per-team `DeveloperAccess-<team>` IAM role + EKS access entry (ADR-039/068 read
  as shipped until this lands).
- **ADR-083 stragglers** — bound `kubernetes`/`helm` to `~>` in `cluster-rbac`, `observability-k6`,
  `argocd-clusters` to make the ADR's "consistent contract" claim literally true.

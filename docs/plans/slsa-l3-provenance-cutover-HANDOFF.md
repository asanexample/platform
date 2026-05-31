# SLSA L3 provenance cutover — working handoff (updated 2026-05-30 ~18:25 PT)

**Resume:** read this file first. The dual-provenance blocker is being resolved by cutting over to a
SINGLE trusted-ci provenance identity. Most of the rollout is DONE; we're at the verify-and-flip stage.

## TL;DR of the fix (decided + executed)
The app's hand-authored `cosign attest --type slsaprovenance` step was worthless for SLSA L3 and, worse,
produced DUAL provenance (app + trusted-ci) that Kyverno's cosign attestation matching can never pass
(verifiedCount:0). Fix = drop the hand-authored step so **trusted-ci is the sole provenance signer**;
switch the verify-attestations policy's provenance block to the trusted-ci identity (SBOM stays app-signed).

## DONE this session
1. **app-alpha repo** (`asanexample/app-alpha`, local at `/Users/josh/centric/app-alpha`):
   - Remote standardized to `git@github.com:asanexample/app-alpha.git` (was `gangster/...`).
   - Removed hand-authored provenance from `deploy.yml` + `preview.yml`. `deploy.yml` restructured into
     `build → provenance → deploy` jobs (digest pinned only AFTER trusted-ci provenance signed, so ArgoCD
     never sees an image lacking its provenance). `preview.yml`: `build → provenance`.
   - **PR #23 MERGED** (squash) to main. main now at `a9854fe (#23)`, then auto `deploy:` repin commit
     `130cbd9`.
   - Deploy workflow ran green → **new prod image `sha256:d1e942d031ee48981d60f3a29f5951555d9638be6e3ebc70faddb3b1d3a21e71`**.
   - VERIFIED that image: exactly 2 attestations — SBOM signed by `app-alpha/deploy.yml@main` (cosign
     exit 0), provenance signed by `trusted-ci/slsa-provenance.yml` (exit 0), NO app-signed provenance
     (negative test exit 1). This is the clean single-identity state the policy needs.

2. **Platform policy module** (committed `b6d9371` on branch `feat/slsa-l3-p2-kyverno-audit`):
   - Folded L3 into the MAIN policy: `infra/modules/policy/policies-chart/templates/verify-attestations.yaml`
     now renders the slsaprovenance attestor as **trusted-ci** (gated by `githubWorkflowRepository` =
     caller repo) for teams in `attestCallerRepos`; app-signed for others. SBOM always app-signed.
   - Retired `verify-attestations-l3.yaml` + the `enable_l3_provenance_audit` var (removed from main.tf,
     variables.tf, values.yaml). Kept `trusted_ci_subject_regexp` + `attest_caller_repos`.
   - `.kyverno-tests/run.sh` updated; **21/21 tests pass + render-check pass** (alpha=trusted-ci, bravo=app).
   - Live unit `infra/live/aws/preprod/us-east-1/platform/policy/terragrunt.hcl`: `attest_failure_action`
     Enforce→**Audit** for the transition (verify_failure_action stays Enforce); removed
     `enable_l3_provenance_audit`.

3. **Applied the policy** to preprod: `AWS_PROFILE=management terragrunt apply` in the policy unit —
   **"Apply complete! 0 added, 1 changed, 0 destroyed"**, helm upgrade ~1m, `policies_status=deployed`.
   - Confirmed live `clusterpolicy verify-attestations-team-alpha` (context **preprod**) is now
     `validationFailureAction: Audit` and its slsaprovenance block uses the trusted-ci subjectRegExp +
     `githubWorkflowRepository: asanexample/app-alpha`. SBOM block still app (deploy/preview subjects).

## NEXT STEPS (resume here)
1. **(optional sanity, in progress at handoff)** finish confirming the live policy's attestations block
   has provenance=trusted-ci ONLY (no app provenance entry) and SBOM=app. Extract:
   `kubectl --context preprod get clusterpolicy verify-attestations-team-alpha -o jsonpath='{.spec.rules[0].verifyImages[0].attestations}' | python3 -m json.tool`
2. **Trigger ArgoCD sync of app-alpha.** ArgoCD runs on the **platform** cluster
   (`kubectl --context platform`); the app deploys to **preprod** ns `team-alpha`. Either `argocd app sync
   alpha-demo` or kubectl-patch a refresh. ArgoCD should pull image `d1e942d0` (manifest commit `130cbd9`).
3. **Confirm admission + verifiedCount:1.** New pod with `d1e942d0` should be admitted; check the
   PolicyReport in ns team-alpha: `kubectl --context preprod get policyreport -n team-alpha -o yaml | grep -i -A3 verify-attestations`. The OLD failing events were on image `sha256:c57b2a26…` (dual) and
   are expected to clear once `d1e942d0` rolls out.
4. **Flip to Enforce** (ASK USER FIRST): set `attest_failure_action = "Enforce"` in the live
   terragrunt.hcl, `AWS_PROFILE=management terragrunt apply`, then commit that flip.
5. **Commit/push the platform branch** `feat/slsa-l3-p2-kyverno-audit` (currently only local commit
   `b6d9371`) and open a platform PR. Update memory `project_slsa_l3_provenance_cutover` when fully done.

## Environment / gotchas
- ArgoCD = **platform** cluster (`kubectl --context platform`); tenants + cosign verify = **preprod**
  (`kubectl --context preprod`). alpha-demo destination = preprod ns team-alpha.
- AWS: `AWS_PROFILE=management` for terragrunt (PlatformDeployer); `AWS_PROFILE=platform` for ECR/cosign
  (acct 829808296602). SSO session was live this session.
- Policy unit dir: `infra/live/aws/preprod/us-east-1/platform/policy/`. Each apply = helm upgrade ~1-3 min.
- **Permission classifier** denies `terragrunt apply -auto-approve` (blind apply) and `gh pr merge` unless
  pre-authorized — run plain `terragrunt apply` (interactive) or get user OK; user merged #23 manually-ish.
- Tool OUTPUT CHANNEL was flaky all session (empty/delayed results). Run commands ONE AT A TIME; redirect
  to a file and Read it if needed. The underlying git/cluster state was always fine.
- cosign local = v3 (verifies the v2 legacy `.att` fine). `cp` is aliased to prompt — use `/bin/cp -f`.
- Images: OLD/blocked dual = `sha256:c57b2a26…`; NEW good single-provenance = `sha256:d1e942d031ee4898…`.

## Issue #1 (ArgoCD SSO cert rotation) — DONE earlier, do not redo. Follow-up GH issue #137 filed.

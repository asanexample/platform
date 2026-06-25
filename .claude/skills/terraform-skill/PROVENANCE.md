# Provenance — vendored third-party skill

This is a **vendored, pinned** copy of a community Claude Code Agent Skill. It is
third-party content, not authored in this repo. Treat upstream changes as a
supply-chain event: re-audit before bumping the pin.

| Field | Value |
|-------|-------|
| Upstream | https://github.com/antonbabenko/terraform-skill |
| Maintainer | Anton Babenko (terraform-aws-modules, terraform-best-practices.com, AWS Community Hero) |
| Pinned commit | `fdd9dc5fe1391c00c08d0cb57a8e33430fcfc640` (v1.17.1, 2026-06-14) |
| License | Apache-2.0 (see `LICENSE`) |
| Vendored | 2026-06-25 |

## What was vendored

Only the **skill payload** — `SKILL.md` + `references/*.md` — plus the upstream
`LICENSE`. The upstream repo's release tooling (`.github/release/*.js`),
`mcp.json`, `POWER.md`, and CI workflows were **deliberately excluded**: nothing
here executes code, makes network calls, or requests credentials. It is
markdown-only by construction.

## Security audit (2026-06-25)

- Payload is markdown-only — no `.sh`/`.py`/`.js`/binaries in the vendored tree.
- No outbound network calls, no `curl|bash` install path, no credential/token
  requests, no prompt-injection patterns (no "ignore previous instructions",
  `eval`, `base64`, exfiltration). All `secret`/`credential` mentions are
  legitimate best-practice guidance (OIDC over static keys, `write_only` args,
  keep secrets out of state).
- Two upstream `.github/release/*.js` files were reviewed and found benign
  (`fs`/`path` only; one `execSync` runs `git add` in a pre-commit helper) and
  are **not** part of this vendored payload.

## Fit caveat — house skills take precedence

This skill is **generic Terraform/OpenTofu**, not Terragrunt-aware. Where its
advice conflicts with this repo's conventions, the repo's own house skills win:

- It suggests `backend "s3"` blocks and provider blocks in modules — but here
  Terragrunt injects backend/providers and **modules declare none** (see the
  `terraform-style` and `terragrunt-units` house skills).
- It suggests an `environments/ modules/ examples/` layout — this repo uses
  `infra/modules/` + Terragrunt `infra/live/`.

Its high value is the **diagnostic/operational** depth that house skills don't
cover: failure-mode routing (identity churn, blast radius, state corruption),
`count` vs `for_each` identity churn, `moved`/`removed`/`import` blocks, provider
removal, `write_only` secrets, state recovery, and per-feature version floors.

## Re-audit / update procedure

To bump the pin: diff the upstream payload against this copy, re-run the red-flag
scan (network calls, exec, install scripts, injection patterns), confirm the
payload is still markdown-only, then update the commit SHA above.

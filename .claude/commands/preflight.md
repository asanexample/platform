---
description: Run the repo's format/lint/validate checks on your current changes (mirrors CI) and fix any failures
---

# Preflight — format / lint / validate the current changes

Get the working tree green against the checks CI enforces, **before** pushing. Do NOT commit or
push — just find and fix formatting/lint/validation issues in the current changes.

1. **Scope to what changed:** `git diff --name-only origin/main...HEAD` plus uncommitted
   (`git status --short`). Only check file types that actually appear in the diff.
2. **Run the matching check per file type and fix failures:**
   - `*.tf` under `infra/modules/` → `tofu fmt -check -recursive infra/modules/` (fix with
     `tofu fmt infra/modules/`); then for each changed module, `cd` in and
     `tofu init -backend=false -input=false && tofu validate`.
   - `*.hcl` under `infra/live/` → `terragrunt hcl fmt --check` (fix with `terragrunt hcl fmt`).
   - `*.md` → `npx -y markdownlint-cli2 --fix <files>`, then resolve anything it can't auto-fix
     (e.g. **MD040** needs a language on the fence; **MD031** is auto-fixed).
3. **SAST (Semgrep):** if the diff touches anything Semgrep scans — `*.tf`, `.github/**` workflows,
   `*.go`, a `Dockerfile`, or anything that could carry a secret — run `make sast` and fix any
   findings. Note this scan is **full-repo** (not diff-scoped), exactly like the CI gate, so it can
   surface a finding outside your diff; if so, say so rather than papering over it. Needs the
   CI-pinned semgrep (`pipx install semgrep==1.164.0`) — the target prints this if it's missing.
4. **Report** a short summary: what was checked, what got fixed, and anything still failing + why.

This mirrors the CI jobs (OpenTofu Format, OpenTofu Validate, Terragrunt HCL Format, Markdown Lint,
Semgrep) so the PR lands green on the first try. The format-on-edit hook handles most of this
incrementally; this is the explicit full-sweep before you push.

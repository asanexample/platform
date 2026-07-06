---
name: apply-and-destroy
description: >-
  How to safely apply and destroy this platform's OpenTofu + Terragrunt infrastructure —
  the deployment-ordering DAG, the exact (redesigned v1.x) run --all commands, and the
  destroy invocation with its dangerous flags. Use when applying a unit or a whole
  environment, tearing down/rebuilding, or reasoning about deployment order (what must come
  before what). Prefer platctl for full bootstrap/teardown. CRITICAL: get the destroy
  command and the private-EKS endpoint handling right. Consult this ANY time you run a
  `terragrunt plan`/`apply` (or `tofu` equivalent) on this repo — it covers running them so you can
  actually READ the result: capture output to a file instead of piping the only copy through a lossy
  grep, the `AWS_PROFILE=management` requirement (plan/apply assume PlatformDeployer; validate
  doesn't), and the "don't start a second run on the same unit / state-lock held by multiple users"
  trap with long backgrounded applies. Also covers whether a change is already applied by CI on
  merge (the `gitops/teams/**` and `gitops/products/**` apply-on-merge workflows) versus needing a
  manual operator apply — check that BEFORE handing someone a manual apply. NOT for authoring a unit
  (terragrunt-units) or module (terraform-style).
---

# Applying & destroying infrastructure

OpenTofu (`tofu`) + Terragrunt **v1.x** (redesigned CLI). For full-platform operations prefer
**platctl** (DAG-aware, resumable, handles the EKS endpoint unlock/lockdown — see the platctl
skill); use raw `terragrunt run --all` for ad-hoc multi-unit work. Source of truth:
`docs/runbooks/platform-rebuild-from-scratch.md`, CLAUDE.md → Deployment Ordering / Apply-Destroy.

## First check: is this change already applied by CI on merge?

**Not every apply is a manual operator task** — don't reflexively hand someone a `terragrunt apply`
recipe (or plan a manual apply) before checking this. A **limited, specific** set of units already
**apply automatically on merge to `main`**, on the in-VPC `platform-infra` ARC runner (native
private-API reach — **no Tailscale**; AWS via EKS Pod Identity, with `TG_FORCE_DEPLOYER=1`
force-assuming PlatformDeployer since the runner is in-account). If the change touches one of these
paths, the merge *is* the apply — nothing manual to do:

- **`gitops/teams/**`** → `teams-apply.yml` applies the access-model units
  (keycloak-config → argocd → argocd-apps → github-teams). #305 Phase 1 / ADR-053.
- **`gitops/products/**`** → `registry-reconcile.yml` reconciles the per-Product derived units
  (github-oidc → preprod/policy → argocd-apps → github-teams). ADR-071 Gap #2.

Both serialize under the shared `terragrunt-apply` concurrency group (belt-and-suspenders with the
DynamoDB state lock) and apply from the merged SHA. The apply logic lives in
`.github/scripts/{teams,registry}/apply.sh`, **not inline** in the workflow YAML — so a plain
`grep "terragrunt apply" .github/workflows` misses it and makes it *look* like nothing auto-applies.

**This is NOT general apply-on-merge.** It covers only those two derived-unit sets. **Every other
unit — a new module unit like `falco`, or `eks` / `networking` / etc. — is still applied by a
human** (from the main checkout; see the manual flow below and the worktree rule in CLAUDE.md).
Extending apply-on-merge to arbitrary units (general plan-on-PR / apply-on-merge) is the deferred
"…then plan-on-PR/apply-on-merge" half of #305 (ADR-065) — **not built yet**. So: only reach for the
manual apply flow after confirming the change isn't in one of the CI-applied paths above.

## Commands

```bash
# Single unit (from its directory)
terragrunt apply

# Whole environment DAG (topological order) — v1.x form, NOT `run-all`
terragrunt run --all apply

# Destroy (reverse DAG) — flags matter, see below
terragrunt run --all destroy --filter-allow-destroy -- -auto-approve
```

- It is **`terragrunt run --all <cmd>`**, never the legacy `run-all`.
- **`--filter-allow-destroy`** is Terragrunt's guard that *permits* a destroy across the
  filtered DAG (per its `--help`: "Allow destroy runs when using Git-based filters") — it's a
  safety acknowledgement, **not** a protector of critical units. Keep it in the destroy
  invocation (it's the documented form), but don't rely on it to spare anything.
- What actually protects critical state on teardown: the **state backend** (S3 + DynamoDB) lives
  *outside* the teardown trees entirely, and the **SOPS KMS key** (`sops-kms`) carries
  `prevent_destroy = true` — OpenTofu's resource-level lifecycle guard, enforced independently of
  any Terragrunt flag.
- **`--`** separates Terragrunt flags from the `-auto-approve` passed through to OpenTofu.
- Every dependency block has `mock_outputs` + `mock_outputs_allowed_terraform_commands`
  including `destroy`, so reverse-DAG destroy works even when upstream state is already gone.

## Running a plan/apply and actually reading the result

A plan/apply you can't read is worse than useless — you end up guessing whether it worked, or
re-running it and making things worse. Three failure modes bite repeatedly here; all are avoidable.

**Capture to a file, then grep the file — never pipe the only copy through a filter.** Terragrunt
prefixes every line with a timestamped `INFO` log and the real signal (`Plan: N to add, M to
change, K to destroy`, `Apply complete! Resources: ...`, or the actual `Error:`) is a few lines in
a long stream. Piping the live command through `... | grep -E 'Plan:|Apply'` routinely swallows
exactly those lines (wrong pattern, ANSI codes, or buffering) and leaves you with *no* copy to
re-read. Instead redirect everything to a file and inspect that — if your first filter misses, the
full output is still there:

```bash
AWS_PROFILE=management terragrunt plan  -no-color > /tmp/plan.txt  2>&1; grep -iE 'Plan:|No changes|Error' /tmp/plan.txt
AWS_PROFILE=management terragrunt apply -no-color -auto-approve > /tmp/apply.txt 2>&1; tail -20 /tmp/apply.txt
```

`-no-color` keeps ANSI escapes from corrupting your grep. On a change you believe is additive,
**`0 to destroy`** in the plan is the signal it's safe.

**Long applies get backgrounded — wait for them; do NOT start a second run on the same unit.** An
apply that upgrades a big helm release (observability, crossplane) exceeds the foreground limit and
is moved to the background; its summary lands in the task output file when the completion
notification arrives. If you start a *second* `plan`/`apply` on that unit while the first is still
running, OpenTofu's DynamoDB state lock rejects it — `Error acquiring the state lock ... held by
multiple users` — and now you can't tell whether the first one succeeded. So: one run per unit at a
time. Read the backgrounded run's output file (`grep 'Apply complete\|Error'`) before doing anything
else with that unit. A genuinely **stale** lock (no apply is actually running — confirm via the task
notifications and `ps aux | grep terragrunt`) is cleared with `terragrunt force-unlock <LOCK_ID>`
(the ID is printed in the error) — never force-unlock while an apply might still be live, or you risk
corrupting state.

**`AWS_PROFILE=management` is required for plan/apply, not for validate.** The providers assume
`PlatformDeployer` (root.hcl), so `plan`/`apply` need `AWS_PROFILE=management` — without it you get
`Cannot assume IAM Role ... 403`. `terragrunt validate` works *without* it (it only needs the
state-backend role), which is the trap: a green `validate` does **not** mean your creds are right for
the apply.

## Preferred: platctl for full bootstrap/teardown

```bash
make build-platctl
./bin/platctl bootstrap --dry-run     # preview
./bin/platctl bootstrap               # apply full DAG (parallel waves, lockdown phase)
./bin/platctl teardown                # unlock → teardown_args → reverse-DAG destroy
```

platctl adds what raw `run --all` can't: manual-prereq checks, per-unit hooks (finalizer
cleanup, force-destroy args), the EKS public-endpoint unlock/lockdown, and `--resume`.

## Deployment ordering (the DAG)

Key constraints (full picture in CLAUDE.md → Deployment Ordering, verified against unit deps):

```text
iam-roles ┐
          ├─► eks ─► cilium ─► node-groups ─► eks-addons
networking┘                         └─► karpenter
          (BYOCNI: Cilium MUST precede node groups; eks-addons/coredns need CNI+nodes)

then, on the cluster:
  gateway (early, no app deps) ─► keycloak ─► keycloak-config ─► argocd ─► argocd-clusters ─► argocd-apps
  policy ─► crossplane (policies match its CRDs, so policy first)
  cert-manager / external-dns / external-secrets / secret-stores / cloudnative-pg / backstage / tailscale / cross-vpc-dns
```

## Private-EKS caveat (don't enable the public endpoint)

Routine **operator** apply/maintenance reaches the **private** API over Tailscale (see the
cluster-access skill). The in-VPC `platform-infra` CI runners (the apply-on-merge workflows above)
reach it **natively — no Tailscale**. The public endpoint is toggled **only** during a full
from-scratch teardown/rebuild — because Tailscale itself is destroyed — and **platctl** does that
automatically (unlock before destroy, lockdown after). Never enable it by hand for ordinary ops.

## References

- `docs/runbooks/platform-rebuild-from-scratch.md` — the end-to-end procedure
- CLAUDE.md → Deployment Ordering (AWS) / Apply / Destroy
- Related skills: **platctl**, **cluster-access**, **terragrunt-units**

---
name: apply-and-destroy
description: >-
  How to safely apply and destroy this platform's OpenTofu + Terragrunt infrastructure —
  the deployment-ordering DAG, the exact (redesigned v1.x) run --all commands, and the
  destroy invocation with its dangerous flags. Use when applying a unit or a whole
  environment, tearing down/rebuilding, or reasoning about deployment order (what must come
  before what). Prefer platctl for full bootstrap/teardown. CRITICAL: get the destroy
  command and the private-EKS endpoint handling right. NOT for authoring a unit (terragrunt-units)
  or module (terraform-style).
---

# Applying & destroying infrastructure

OpenTofu (`tofu`) + Terragrunt **v1.x** (redesigned CLI). For full-platform operations prefer
**platctl** (DAG-aware, resumable, handles the EKS endpoint unlock/lockdown — see the platctl
skill); use raw `terragrunt run --all` for ad-hoc multi-unit work. Source of truth:
`docs/runbooks/platform-rebuild-from-scratch.md`, CLAUDE.md → Deployment Ordering / Apply-Destroy.

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

Routine apply/maintenance reaches the **private** API over Tailscale (see the cluster-access
skill). The public endpoint is toggled **only** during a full from-scratch teardown/rebuild —
because Tailscale itself is destroyed — and **platctl** does that automatically (unlock before
destroy, lockdown after). Never enable it by hand for ordinary ops.

## References

- `docs/runbooks/platform-rebuild-from-scratch.md` — the end-to-end procedure
- CLAUDE.md → Deployment Ordering (AWS) / Apply / Destroy
- Related skills: **platctl**, **cluster-access**, **terragrunt-units**

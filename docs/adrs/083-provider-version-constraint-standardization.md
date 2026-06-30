# ADR-083: Provider Version-Constraint Standardization

**Date:** 2026-06-26

**Status:** Accepted

## Context

Provider version constraints across the shared OpenTofu modules (`infra/modules/**`) had drifted
into three problems (surfaced by the 2026-06-25 tech-debt audit, findings TD-002 / TD-101):

1. **Fragmented constraints for the same provider.** AWS appeared as `>= 5.0` (15 modules),
   `>= 6.0` (3), and `~> 6.0` (6). Kubernetes spanned `>= 2.0`, `>= 2.10.0`, `>= 2.35.0`, and
   `>= 3.0`. Helm had a `>= 2.0` outlier (falco) against `>= 3.0` elsewhere.
2. **Unbounded `>=` constraints.** ~38 modules pinned providers with a bare lower bound and **no
   upper bound**, so a `tofu init -upgrade` could silently pull the next *major* (a breaking
   provider release) with no signal.
3. **18 `aws/*` modules shipped no `versions.tf` at all** — core, high-blast-radius modules (`eks`,
   `networking`, `iam_roles`, `organizations`, `s3`, `state_bootstrap`, …) inheriting whatever the
   consuming unit resolved, with zero stated provider contract.

We probed what the floating constraints actually resolve to today (`tofu init -upgrade` against the
OpenTofu registry):

| Provider | Floating floor in use | Resolves to (2026-06-26) |
|----------|-----------------------|--------------------------|
| `hashicorp/aws` | `>= 5.0` | **6.52.0** |
| `hashicorp/helm` | `>= 3.0` | **3.2.0** |
| `hashicorp/kubernetes` | `>= 2.35.0` | **3.2.0** |
| `hashicorp/tls` | (implicit) | 4.3.0 |
| `cloudflare/cloudflare` | (implicit) | 5.21.1 |

The **kubernetes** result is the load-bearing finding: the provider's **3.x is released**, and the
existing floating floor (`>= 2.35.0`, no upper bound) **already resolves to 3.2.0** on any fresh
init. So the cluster modules are *already on the kubernetes provider 3.x line* — the constraint
just doesn't say so. (The audit's first instinct, `~> 2.35`, would have been wrong: it would
*downgrade* kubernetes to 2.x and likely break, since 3.0 had breaking changes.)

## Decision

Every shared module declares a `versions.tf`, and the core providers are bounded to the **current
resolved major** with `~>` (allow minor/patch within the major; require a deliberate PR to cross a
major):

| Provider | Source | Constraint |
|----------|--------|------------|
| aws | `hashicorp/aws` | `~> 6.0` |
| kubernetes | `hashicorp/kubernetes` | `~> 3.0` |
| helm | `hashicorp/helm` | `~> 3.0` |
| tls | `hashicorp/tls` | `~> 4.0` |
| cloudflare | `cloudflare/cloudflare` | `~> 5.0` |

`required_version = ">= 1.6.0"` (the established floor). A module declares only the providers it
actually uses. Dependabot's `terraform` ecosystem maintains within-major bumps and raises the next
major as a reviewable PR.

This is **behaviour-neutral** against today's resolution: every currently-resolved version
(aws 6.52, helm 3.2, kubernetes 3.2, tls 4.3, cloudflare 5.21) satisfies its new `~>` bound, so no
provider is up- or down-graded by this change — it only adds the missing upper bound (the
breaking-major guard) and the missing `versions.tf` files. Verified with `tofu validate` on the
representative modules under the new majors (`aws/eks`, `aws/networking`, `cloudflare/dns_delegation`,
`argocd` — all valid, confirming the module code is compatible with kubernetes 3.x and cloudflare 5.x).

## Consequences

- A future provider **major** (aws 7.x, kubernetes 4.x, …) no longer auto-qualifies on
  `init -upgrade`; it requires bumping the `~>` bound in a PR — surfaced by Dependabot, reviewed,
  and validated before adoption.
- Nearly all shared modules now state a consistent, honest provider contract (a handful predating this ADR still float `kubernetes`/`helm` with an unbounded `>=` — `cluster-rbac`, `observability-k6`, `argocd-clusters` — tracked for follow-up); modules validate
  standalone (and in the CI `OpenTofu Validate` job) against a known major.

### Out of scope (follow-ups)

- **Unit-level floors in `root.hcl`.** The generated unit `versions.tf` still floats helm
  (`>= 3.0`) and kubernetes (`>= 2.35.0`). These should be bounded the same way, but `root.hcl` is
  maximal blast radius and there is an unexplained wrinkle to resolve first: it pins
  `aws = "6.47.0"` (exact) yet units lock `6.52.0` — i.e. the exact pin is not binding as written.
  Tracked separately so it gets its own careful change.
- **The implicit kubernetes 2.x → 3.x provider upgrade** is already in flight via the floating
  floor (any fresh init resolves 3.2.0). This ADR documents/bounds it but does not force a re-apply;
  units pick up 3.x on their next normal apply and should be spot-checked then.

Implements TD-002 / TD-101 (from the 2026-06-25 tech-debt audit). See ADR-016 (OpenTofu).

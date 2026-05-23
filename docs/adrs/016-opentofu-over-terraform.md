# ADR-016: OpenTofu over HashiCorp Terraform

**Date:** 2026-05-23

**Status:** Accepted

## Context

The platform needs an infrastructure-as-code execution engine to provision and manage cloud
resources across AWS, Azure, and GCP. HashiCorp Terraform has been the industry standard for
multi-cloud IaC since 2014, but in August 2023 HashiCorp changed Terraform's license from the
Mozilla Public License 2.0 (MPL-2.0) to the Business Source License 1.1 (BSL-1.1).

The BSL license restricts competitive use of Terraform — specifically, it prohibits offering
Terraform as a hosted or embedded service that competes with HashiCorp's commercial products.
While this doesn't directly affect end-user infrastructure provisioning today, it creates several
concerns:

1. **License ambiguity.** The definition of "competitive use" is determined by HashiCorp. As the
   platform matures toward a managed service offering, the boundary between internal tooling and
   competitive product becomes less clear.

2. **Ecosystem fragmentation.** The BSL change prompted a community fork (OpenTofu) under the
   Linux Foundation. The Terraform ecosystem is now split between two runtimes, and providers,
   modules, and tooling must be evaluated for compatibility with both.

3. **Vendor leverage.** A single-vendor-controlled license can change again. Building a platform
   on BSL-licensed software accepts ongoing license risk with no community governance recourse.

### Alternatives Considered

**1. Continue with HashiCorp Terraform (BSL).** No migration effort. Access to HashiCorp's
commercial ecosystem (Terraform Cloud, Sentinel). However, BSL license risk remains, and the
platform cannot be offered as a managed service without legal review. The team would need to track
license changes and potentially migrate later under time pressure.

**2. Pulumi.** General-purpose IaC using real programming languages (TypeScript, Python, Go).
More expressive than HCL for complex logic. However, it would require rewriting the entire module
library and Terragrunt configuration hierarchy — Pulumi has no Terragrunt equivalent. The team's
expertise is in HCL, not Pulumi's SDK model. Significant migration cost for no immediate
capability gain.

**3. OpenTofu (chosen).** Community fork of Terraform maintained by the Linux Foundation under the
MPL-2.0 license. Drop-in compatible with Terraform 1.6.x — existing HCL modules, providers, and
state files work without modification. Terragrunt supports OpenTofu via `terraform_binary = "tofu"`.
The OpenTofu registry mirrors most Terraform providers.

## Decision

Use OpenTofu as the IaC execution engine. The switch is configured globally in `infra/root.hcl`:

```hcl
terraform_binary = "tofu"
```

### Compatibility

OpenTofu 1.6+ is a drop-in replacement for Terraform 1.6.x:

- All existing HCL modules work without modification
- Provider lock files use `registry.opentofu.org` but resolve the same provider binaries
- State file format is identical — no state migration required
- Terragrunt's `terraform_binary` setting is the only configuration change needed

### Provider Registry

Providers are sourced from the OpenTofu registry (`registry.opentofu.org`), which mirrors the
HashiCorp registry for all major providers (AWS, Azure, GCP, Helm, Kubernetes, Cloudflare,
Tailscale). Lock files reference the OpenTofu registry:

```hcl
provider "registry.opentofu.org/hashicorp/aws" {
  version = "6.0.0"
}
```

### CI Integration

The CI pipeline (`ci.yml`) runs `tofu fmt`, `tofu validate`, and `tofu init` — not `terraform`.
The pre-commit hook (`.githooks/pre-commit`) also uses `tofu fmt`.

## Consequences

**Positive:**

- MPL-2.0 license with Linux Foundation governance — no vendor-controlled license risk
- Zero migration cost from Terraform — existing modules, state, and workflows are unchanged
- Terragrunt, Terratest, and all tooling work identically
- Community-driven development with transparent governance
- No restrictions on how the platform can be offered or commercialized

**Negative:**

- OpenTofu lags behind Terraform on some features (e.g., Terraform 1.7+ features like `removed`
  blocks were added to OpenTofu on a different timeline)
- HashiCorp commercial tools (Terraform Cloud, Sentinel) are not available — but the platform
  doesn't use them
- Some documentation and community resources reference "Terraform" — engineers must mentally
  translate
- Provider compatibility is occasionally behind the Terraform registry for niche providers

**Risks:**

- If OpenTofu development stalls or the Linux Foundation reduces investment, the platform would
  need to evaluate alternatives. Mitigated by the fact that OpenTofu has broad industry backing
  and active development.
- A future Terraform feature that OpenTofu doesn't implement could be needed. Mitigated by the
  current feature set being sufficient for the platform's needs, and OpenTofu tracking Terraform
  features closely.

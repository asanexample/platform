# ADR-005: Organizational Unit Hierarchy Design

**Date:** 2025-05-15

**Status:** Accepted

## Context

AWS Organizations uses Organizational Units (OUs) to group accounts for policy application and
administrative delegation. The OU hierarchy is the backbone of a multi-account governance strategy:
it determines how Service Control Policies (SCPs) are inherited, how administrative boundaries are
drawn, and how the organization can scale.

### Current OU Structure

The module deploys the following OU hierarchy:

```text
Root (Organization Root)   [management account sits here, in no OU]
  |
  +-- Platform
  |     +-- platform account
  |     +-- test account        (Terratest sandbox — see "Test account placement" below)
  |
  +-- Workloads
        |
        +-- Preprod
        |     +-- preprod account
        |
        +-- Prod
        |     +-- prod account
        |
        +-- Regulated           (no accounts yet — reserved for future HIPAA/PCI workloads)
```

### Design Principles at Play

1. **Separation of concerns.** Shared infrastructure (networking, identity, security tooling) has
   different governance needs than application workloads. Mixing them in a single OU means SCPs
   must be permissive enough for both, weakening controls.

2. **Environment isolation.** Pre-production, production, and regulated environments have different
   risk profiles, compliance requirements, and operational procedures. Separate OUs allow
   environment-specific policies.

3. **SCP inheritance as a feature.** SCPs attached to parent OUs are inherited by all children.
   This creates a layered security model where foundational controls are applied broadly and
   additional restrictions are applied narrowly.

4. **AWS Well-Architected Framework alignment.** The AWS multi-account strategy recommends
   separating Platform/Infrastructure accounts from Workload accounts, and segmenting workloads
   by environment and compliance tier.

### Constraints

- **5 SCPs per target** (hard AWS limit). The hierarchy must be designed so that no target
  accumulates more than 5 directly attached SCPs.
- **5 levels of OU nesting** (hard AWS limit). The hierarchy must not exceed 5 levels below the
  root.
- **OU operations are slow.** Creating, moving, and deleting OUs requires API calls that can take
  seconds to propagate. The hierarchy should be stable and infrequently modified.
- **Account moves are disruptive.** Moving an account between OUs changes its effective SCP set
  immediately, which can break running workloads if the new OU has more restrictive policies.

### Forces

- Flat hierarchies are simpler but provide fewer policy attachment points.
- Deep hierarchies provide more granularity but increase complexity and risk hitting nesting limits.
- The hierarchy must accommodate both current needs (4 member accounts: platform, test, preprod,
  prod) and future growth (potentially dozens of accounts across multiple environments).

## Decision

### Two-Branch Root Structure: Platform + Workloads

The root of the organization has two top-level OUs:

**Platform OU** -- Contains accounts that provide shared infrastructure services consumed by
workload accounts. Examples:

- Networking hub (Transit Gateway, VPN, Direct Connect)
- Shared security services (Security Hub delegated admin, GuardDuty admin)
- CI/CD infrastructure
- DNS management
- Centralized logging

**Workloads OU** -- Contains accounts that run application workloads. This OU is further subdivided
by environment.

This separation ensures that:

- Platform accounts can have more permissive networking policies (they manage VPCs, peering,
  transit gateways) without exposing those permissions to workload accounts.
- Workload accounts can have stricter data protection policies (tagging requirements, IAM user
  restrictions) without impeding platform operations.
- The `protect-data-and-network` SCP is attached to both Platform and Workloads OUs, but future
  policies can differ between them.

### Workloads Sub-OUs: Preprod, Prod, Regulated

The Workloads OU has three child OUs representing environment tiers:

**Preprod** -- Development, staging, and testing accounts. These accounts may have:

- Relaxed cost controls
- Shorter data retention
- More permissive IAM policies for experimentation
- Access to non-production data only

**Prod** -- Production accounts running customer-facing workloads. These accounts should have:

- Stricter change management controls
- Longer data retention
- Full audit logging
- No direct IAM user access (federation only, enforced by inherited `restrict-iam-users` SCP)

**Regulated** -- Accounts subject to specific compliance frameworks (HIPAA, PCI-DSS, FedRAMP).
These accounts will have:

- The `hipaa-eligible-services` SCP when HIPAA workloads are present
- Additional data residency controls
- Enhanced logging and monitoring
- Restricted service catalog

### SCP Inheritance Model

SCPs flow down the hierarchy through inheritance:

```text
Root
  SCPs: baseline-guardrails, protect-security-services, enforce-encryption, deny-regions
  |
  +-- Platform
  |     Inherited: [all 4 root SCPs]
  |     Direct: protect-data-and-network, require-tagging, restrict-iam-users
  |     Effective: 7 SCPs (4 inherited + 3 direct)
  |
  +-- Workloads
        Inherited: [all 4 root SCPs]
        Direct: protect-data-and-network, require-tagging, restrict-iam-users
        Effective: 7 SCPs (4 inherited + 3 direct)
        |
        +-- Preprod
        |     Inherited: [all 4 root SCPs + 3 Workloads SCPs]
        |     Direct: (none currently)
        |     Effective: 7 SCPs, 5 direct slots available
        |
        +-- Prod
        |     Inherited: [all 4 root SCPs + 3 Workloads SCPs]
        |     Direct: (none currently)
        |     Effective: 7 SCPs, 5 direct slots available
        |
        +-- Regulated
              Inherited: [all 4 root SCPs + 3 Workloads SCPs]
              Direct: (none currently, HIPAA SCP planned)
              Effective: 7 SCPs, 5 direct slots available
```

**Key insight:** Inherited SCPs do not count against the 5-SCP-per-target limit. Only directly
attached SCPs count. This means:

- Root: 4 direct, 1 slot remaining.
- Platform: 3 direct, 2 slots remaining.
- Workloads: 3 direct, 2 slots remaining.
- Preprod/Prod/Regulated: 0 direct, **5 slots remaining each**.

The child OUs under Workloads have their full 5-slot budget available for environment-specific
policies while still inheriting all 7 parent-level controls.

### Room for Growth

The hierarchy is designed to accommodate foreseeable expansion:

| Scenario | How It Fits |
|----------|-------------|
| Add a Sandbox OU for experimentation | New child under Workloads (or root-level). 5 direct slots available. |
| Add HIPAA SCP to Regulated | Attach to Regulated OU. Uses 1 of 5 available direct slots. |
| Add a Security OU for security tooling | New root-level OU alongside Platform and Workloads. |
| Add per-environment region restrictions | Attach to Preprod/Prod OUs. Uses available direct slots. |
| Add a Suspended OU for decommissioned accounts | New root-level OU with a "deny all" SCP. |
| Split Prod into Prod-US and Prod-EU | New child OUs under Prod. Inherit all Prod SCPs. |

The two-level nesting (Root -> Workloads -> Preprod/Prod/Regulated) uses only 2 of the 5 allowed
nesting levels, leaving 3 levels for future subdivision.

### OU-Level Attachment, Not Account-Level

SCPs are attached to OUs, never to individual accounts:

- **Consistency.** All accounts in an OU have identical policy boundaries. There are no
  "special" accounts with unique SCP exceptions within an OU.
- **Auditability.** To understand an account's effective SCPs, an auditor only needs to know
  which OU it belongs to and trace the hierarchy upward.
- **Scalability.** Adding a new account to an OU automatically inherits all OU policies. No
  per-account SCP configuration is needed.
- **Budget preservation.** Account-level SCP attachments consume the account's 5-SCP budget.
  By keeping all attachments at the OU level, accounts retain their full 5-SCP budget for any
  future per-account policies that may be needed in exceptional circumstances.

### Management Account Placement

The management account (<MGMT_ACCOUNT_ID>) is not placed in any OU. It sits at the organization root
by default. This is an AWS best practice because:

- SCPs do not apply to the management account (AWS restriction).
- The management account should have minimal workloads.
- Placing it in an OU could create confusion about which policies apply.

### Test Account Placement

The **Test** account (the Terratest sandbox) sits in the **Platform** OU, not Workloads/Preprod. With
the post-audit attachments, the Platform OU now carries the **same** SCPs as Workloads
(`protect-data-and-network`, `require-tagging`, `restrict-iam-users`), so the Test account inherits
them too — it is **not** placed there to dodge those controls. What unblocks the create-and-destroy
sandbox is role-level exemption, not OU placement: the Terratest CI role (`github-actions-terratest`)
and `PlatformDeployer` are in the org's `exempt_roles`, so their applies aren't blocked by
`require-tagging` / `DenyTeamTagTampering`. Its IaC runs via `PlatformDeployer` like every other
account (see [ADR-040](040-platform-engineer-access-model.md) and the test-sandbox runbook).

## Consequences

### Positive

- **Clear governance boundaries.** The Platform/Workloads split creates an intuitive division
  between "infrastructure that serves other accounts" and "accounts that run business workloads."
- **Scalable SCP application.** The inheritance model means new accounts automatically inherit all
  appropriate controls by virtue of their OU placement. No per-account SCP management is required.
- **Environment isolation.** Preprod, Prod, and Regulated OUs allow environment-specific policies
  to be applied without affecting other environments. The Regulated OU is specifically designed for
  the HIPAA SCP.
- **Budget headroom.** Every leaf OU (Preprod, Prod, Regulated) has 5 free SCP slots. This is
  sufficient for foreseeable requirements without hierarchy restructuring.
- **Shallow nesting.** At 2 levels deep (Root -> Workloads -> Env), the hierarchy is easy to
  understand and visualize. It stays well below the 5-level AWS limit.
- **AWS Well-Architected alignment.** The structure follows AWS's recommended multi-account
  patterns, which simplifies conversations with AWS solutions architects and auditors.

### Negative

- **Platform OU is a catch-all.** Currently there is no sub-OU structure under Platform. As the
  number of platform accounts grows (networking, security, logging, CI/CD), a flat OU may become
  difficult to manage. Mitigation: sub-OUs can be added later without disrupting existing accounts.
- **No dedicated Sandbox OU.** The Test (Terratest sandbox) account lives in the Platform OU and now
  inherits the same SCPs as the most-privileged account; the sandbox is unblocked by exempting its CI
  role, not by OU placement (see "Test Account Placement"). That covers the CI-sandbox case; a dedicated
  root-level Sandbox OU — where the tagging/IAM SCPs could be deliberately *omitted* rather than
  role-exempted — may still be worth adding if interactive experimentation accounts proliferate.
- **Regulated OU is unused.** The Regulated OU exists but has no accounts yet and the HIPAA SCP is
  not enabled. This is forward-looking design, but empty OUs add visual noise.
- **OU renames are state-breaking.** The `for_each` key for OUs is the OU name (e.g.,
  `"Workloads/Preprod"`). Renaming an OU requires a state move operation, not a simple name change.

### Risks

- **OU sprawl.** As the organization grows, the temptation to create highly specific OUs (per-team,
  per-application) must be resisted. Each OU is a policy attachment point and management surface.
  Mitigation: require ADR approval for new OU creation.
- **Account OU migration.** Moving an account between OUs (e.g., from Preprod to Prod) changes its
  effective SCPs immediately. If the new OU is more restrictive, running workloads may break.
  Mitigation: test SCP changes against the target account's workloads before migration.
- **Inheritance opacity.** Engineers working on a specific account may not realize that SCPs
  from three levels up (Root -> Workloads -> Preprod) are affecting their permissions. This can
  lead to confusing permission denied errors. Mitigation: document the effective SCP set for each
  OU in runbooks.

### What This Enables

- **Regulated workload onboarding.** When HIPAA workloads are ready, enabling them is a matter of
  setting `enable_hipaa_scp = true` and attaching the policy to the Regulated OU. No structural
  changes needed.
- **Per-environment policies.** Prod can get stricter change-management SCPs (e.g., deny
  `iam:CreateRole` outside of CI/CD) without affecting Preprod experimentation.
- **Account vending.** New accounts can be added by adding an entry to the `accounts` map with
  the appropriate OU assignment. The OU hierarchy handles all policy application automatically.
- **Compliance reporting.** Auditors can be shown the OU hierarchy and SCP attachments as a
  complete picture of preventive controls, without needing to examine individual accounts.

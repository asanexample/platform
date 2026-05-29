# ADR-039: Per-Team Developer RBAC

**Date:** 2026-05-29

**Status:** Accepted

## Context

ADR-007 introduced a `DeveloperAccess` IAM role for "namespace-scoped kubectl." In practice the
preprod implementation had a single shared role that:

1. Was granted `AmazonEKSEditPolicy` scoped to the **union of every team's namespace** (so a
   developer authorized into one team's namespace was authorized into all of them), and
2. Was assumable by **any** SSO PowerUser/Admin, with no developer→team partitioning.

Separately, the `Developers` SSO group was assigned **PowerUserAccess** on the preprod account,
granting full AWS data-plane access (read *and* write to every team's Secrets Manager, EKS, EC2,
etc.) — which bypasses Kubernetes namespace isolation entirely via the AWS API.

Net effect: there was no real isolation of one team from another, at either the Kubernetes RBAC
layer or the AWS layer. As the platform onboards multiple teams (ADR-027, ADR-031), we need
developer access that is genuinely scoped to a team's own namespace and AWS footprint.

### Alternatives Considered

**1. Per-team access entries with an AWS-managed policy (namespace scope).** Keep using
`AmazonEKSEditPolicy` but create one access entry per team scoped to that team's namespace. Minimal
effort (no RBAC to author), but the authorization lives in the EKS control plane (not inspectable as
in-cluster RBAC), and the managed policy is all-or-nothing — it cannot be tightened (e.g. to exclude
Secrets) and does not generalize to non-EKS clusters or vClusters.

**2. Group-mapped access entries + cluster-managed RBAC (chosen — "Bridge B").** Map each team's IAM
principal to a Kubernetes **group** via an EKS access entry, and bind that group to a namespace-scoped
`RoleBinding` we own. The RBAC is real, inspectable, GitOps-versioned, customizable per compliance
tier, and the group→RoleBinding model is portable to any Kubernetes (including future vClusters).
Costs a small `eks` module change and a per-namespace RoleBinding.

## Decision

Adopt per-team developer isolation built from `teams.hcl` as the single source of truth:

- **One IAM role per team** — `DeveloperAccess-<team>` (preprod), generated in the `iam-roles` unit.
  Its trust condition restricts assumption to that team's own SSO permission set (`Dev-<team>`), so a
  developer can assume only their own team's role.
- **One SSO permission set + group per team** — `Dev-<team>` / `Developers-<team>` (mgmt
  identity-center unit), assigned on the preprod account. The broad `Developers → PowerUserAccess`
  assignment is removed.
- **One EKS access entry per team** — maps `DeveloperAccess-<team>` to the Kubernetes group
  `team-<team>:developers` (no AWS-managed access policy). Requires the `eks` module to support
  group-mapped entries (optional `policy_arn`, new `kubernetes_groups`).
- **One RoleBinding per namespace** — the `tenant` module binds group `team-<team>:developers` to a
  `tenant-developer` ClusterRole in the team's namespace.

### Identity flow

```text
SSO group Developers-<team>
  -> Dev-<team> permission set on Preprod        (identity-center, mgmt)
  -> AWSReservedSSO_Dev-<team>_* session role
  -> assumes DeveloperAccess-<team>              (iam-roles, preprod; trust restricts to that set)
  -> EKS access entry maps it to group team-<team>:developers   (eks unit, preprod)
  -> RoleBinding binds that group -> ClusterRole tenant-developer in ns team-<team>   (tenant module)
  -> authorized to edit only in team-<team>
```

### tenant-developer ClusterRole

Initialized as an aggregate of the built-in `edit` role (via the `aggregate-to-edit` label) under a
name we control. Developers therefore **can** read/write Secrets in their own namespace today; the
named ClusterRole is the single place to tighten this (e.g. exclude Secrets) for a future compliance
tier without touching every RoleBinding. (Note: RBAC alone cannot fully hide Secrets — a developer
who can exec/run pods can read any Secret a pod mounts.)

### AWS access posture

- **Preprod:** the `Dev-<team>` permission set grants account-wide **`ReadOnlyAccess`** (broad
  metadata read; `ReadOnlyAccess` excludes value retrieval like `secretsmanager:GetSecretValue`) plus
  `sts:AssumeRole` into the team's role, **plus a per-team ABAC `Deny`** (#62) that blocks acting on
  any resource tagged with another team (`aws:ResourceTag/Team` ∉ {own team, `platform`}) — so a dev
  can't pull another team's ECR images, etc. Backed by the `Team` tag (#61) and a tag-integrity SCP
  that prevents forging the tag. AWS ABAC only covers actions that support `aws:ResourceTag`, so broad
  `Describe`/`List` metadata read remains account-wide. No data-plane write.
- **Prod (not yet deployed):** same deny-other-teams model; whether to drop account-wide read entirely
  is bounded by the same ABAC limits — tracked as a prod-posture follow-up.

## Consequences

**Positive:**

- A developer can edit only their own team's namespace, and can assume only their own team's role.
- Developers have no AWS data-plane write and no cross-team write; preprod read is read-only.
- RBAC is inspectable (`kubectl get rolebinding -n team-<team>`) and versioned in Git.
- The model is generated from `teams.hcl`, so onboarding a team is largely a one-line change there
  (plus the manual SSO permission-set/group entries in the mgmt identity-center unit).

**Negative:**

- More IAM roles, SSO permission sets, and access entries to manage (one set per team).
- The mgmt identity-center entries are hand-maintained and must track `teams.hcl`.
- The Kubernetes group-name convention (`team-<team>:developers`) is duplicated between the `eks`
  unit and the `tenant` module and must stay in sync.

**Related hardening (so the RBAC cannot be bypassed):** Pod Security Admission on tenant namespaces
(prevents privileged/hostPath pods escaping to the node) and IMDS hardening (prevents pods from
stealing node-role credentials). See ADR-027 and ADR-014.

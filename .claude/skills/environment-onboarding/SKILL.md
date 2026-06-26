---
name: environment-onboarding
description: >-
  How to provision a new Product and/or Environment on this platform via the git-native
  registries and the Crossplane XEnvironment claim. Use when onboarding a new product, adding
  an environment/stage (dev/test/uat/staging/prod), wiring a service's AWS access
  (policyStatements), or deprovisioning. Covers the three registries (Team, Product,
  XEnvironment claim), the gated PR flow, the per-service spec, the policyStatements deny-set,
  and the reversible-suspend vs hard-delete teardown. Use it whenever a task touches
  gitops/teams, gitops/products, or gitops/environments. NOT for authoring the app's k8s
  manifests (authoring-k8s-workloads) or its CI (supply-chain-onboarding).
---

# Environment onboarding

Environments are provisioned by the **Crossplane `XEnvironment` claim** — the sole provisioner
(ADR-067). Ownership and intent live in three git-native registries that `policy`,
`argocd-apps`, and `github-oidc` derive from. Source of truth:
`docs/runbooks/environment-onboarding.md`, `docs/architecture/crossplane-environment-api.md`,
and the real files under `gitops/`.

## The three registries

| Registry | Path | Declares |
|---|---|---|
| **Team** | `gitops/teams/<team>.yaml` | `ssoGroup`, `roles.releaseApprover`, and the **envelope** (`allowedTiers`/`allowedStages`/`allowedLocations`, `quotaCap`, `maxDedicatedIsolation`, self-service `resources`) that caps everything the team can claim; plus an optional `slack.channel` for incident routing (ADR-084 — the triage agent posts the team's incidents there) |
| **Product** | `gitops/products/<team>/<product>.yaml` | `team`, `repo` (the app GitHub repo — drives ECR scope, signing subject, delivery), `tenancy` (`pooled`/`per-customer`), `defaultIsolation`, `domains` |
| **XEnvironment claim** | `gitops/environments/<team>/<product>/<stage>[-<customer>].yaml` | one complete environment — the actual provisioning request (below) |

```yaml
# gitops/environments/<team>/<product>/<stage>.yaml — the claim
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata:
  name: alpha-shop-dev
spec:
  team: alpha            # must own the product; envelope authority
  product: shop
  stage: dev             # ∈ Team.envelope.allowedStages
  tier: standard         # ∈ Team.envelope.allowedTiers (default standard)
  services:
    web:
      serviceAccount: app-alpha          # named SA (Pod Identity binds creds here)
      # image: omitted until first CI build sets the @sha256 digest
      # permissions: { aws: { policyStatements: [...] } }   # optional AWS access
  # domains: [...]        # optional vanity hostnames (unioned with the implicit one)
  # quota: {...}          # optional; capped by Team.envelope.quotaCap
  # lifecycle: { phase: active }   # active | suspended | decommissioning
```

The computed namespace is `<team>-<product>-<stage>` (or `…-<customer>-<stage>` for per-customer).

## Onboarding flow

1. **Prereqs:** the **Team** CR and **Product** CR must already exist; Crossplane control plane healthy.
2. **Author the claim** file `gitops/environments/<team>/<product>/<stage>.yaml` (one `XEnvironment` per file). Set `team`/`product`/`stage`/`tier` and each `services.<svc>.serviceAccount`.
3. **Open a PR.** It's gated by `CODEOWNERS` (the team path) + the **gitops Gate** (`validate-environments.sh`): shape/hygiene, Team-exists, envelope dry-run (`restrict-environment-envelope`), schema + composition-render, the IAM deny-set, and aggregate per-team quota. On merge the Gate may auto-merge.
4. **Provisioning is automatic:** ArgoCD syncs the claim to the preprod cluster; the Crossplane Composition reconciles it (namespace, ResourceQuota/LimitRange, NetworkPolicies, RoleBinding, per-namespace `restrict-images`/`restrict-route-hostnames`, the per-service Pod-Identity IAM role + association, and the ECR repo in the platform account).
5. **Apply the derived delivery units** (operator, `AWS_PROFILE=management terragrunt apply`, once per Product): `policy` (the cosign verify policies), `argocd-apps` (the per-Product ApplicationSet), `github-oidc` (the app-CI ECR-push role). These read the registries via `fileset`+`yamldecode`.

## AWS access — `policyStatements` and the deny-set

Per-service AWS access is declared in the claim, not `teams.hcl`:

```yaml
services:
  web:
    serviceAccount: app-alpha
    permissions:
      aws:
        policyStatements:
          - sid: ReadTeamBucket
            actions: ["s3:GetObject", "s3:ListBucket"]
            resources: ["arn:aws:s3:::team-alpha-*", "arn:aws:s3:::team-alpha-*/*"]
```

These are **deny-set validated** (ADR-062 §4) at CI + admission
(`restrict-environment-envelope/policystatements-no-escalation`): actions in **`iam`, `sts`,
`organizations`, `account`** and bare `*` / `*:*` wildcards are **denied**, and the minted Pod
role is boundary-capped at runtime. (Resource scoping like `s3:*` on `*` is allowed for now.)

## Deprovisioning (two-step, ADR-062)

- **Decommission (reversible):** set `spec.lifecycle.phase: decommissioning` — the Composition
  zeroes the ResourceQuota; namespace/IAM/ECR/policies are retained. Flip back to `active` to
  restore. **Reviewer-merged** — the gate excludes decommission from auto-merge (draining
  workloads warrants a human merge, even though it's reversible). Backstage has a Deprovision
  template.
- **Purge (gated):** removing the claim file deletes the XEnvironment → cascades the namespace +
  AWS resources. Allowed **only if** the claim is already `decommissioning` on base, requires
  admin/maintainer approval (release-approver too for prod), and **never auto-merges**. ECR is
  retained (`deletionPolicy: Orphan`); in-namespace PVCs are deleted — back up first.
  See `docs/runbooks/environment-deprovisioning.md`.

## References

- `docs/runbooks/environment-onboarding.md`, `docs/runbooks/environment-deprovisioning.md`
- `docs/architecture/crossplane-environment-api.md`
- Real examples: `gitops/teams/alpha.yaml`, `gitops/products/alpha/shop.yaml`, `gitops/environments/alpha/shop/dev.yaml`
- Related skills: **supply-chain-onboarding** (the app CI), **authoring-k8s-workloads** (the manifests)
- **Equip a team for incident routing** (the optional `slack.channel`) — the triage agent's `docs/owner-routing-setup.md` (asanexample/platform-triage-copilot, ADR-084): create the channel, invite the bot, add the block, PR.

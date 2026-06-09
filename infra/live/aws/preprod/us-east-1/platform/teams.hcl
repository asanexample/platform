# Team definitions for the preprod environment.
#
# Each team gets a namespace (team-<name>), resource quotas, network policies,
# and one ArgoCD Application per app entry. Teams with preview-enabled apps
# also get an ApplicationSet for PR preview environments.
#
# Fields:
#   mode      - Isolation mode: "namespace" (default) or "vcluster" (deferred, ADR-033)
#   apps      - Map of app deployments managed by ArgoCD
#     repo_url  - Git repo containing the app's Kubernetes manifests
#     repo_path - Path within the repo to the manifest directory
#     preview   - Whether to create an ApplicationSet for PR preview deployments
#   aws       - Optional: per-team AWS access via EKS Pod Identity (ADR-041)
#     service_account - the named ServiceAccount the app's pods run as (association binds to it)
#     s3              - map of bucket name -> { bucket_account, access (read|readwrite), prefix }

locals {
  teams = {
    alpha = {
      mode = "namespace"
      # Migrated to a Tenant claim (BACK stack P3, #174): its tenant INFRA (namespace, RBAC, Pod-team role +
      # association, ECR repo, per-team restrict-* policies, DeveloperAccess + access entry) is now owned by
      # the Composition via tenant-claims/alpha. This entry stays only so app delivery (argocd-apps) and the
      # platform-owned supply-chain policies (verify-images/attestations, policy unit) keep working; the
      # `migrated` flag withdraws alpha from every Terragrunt infra loop below.
      migrated = true
      apps = {
        demo = {
          repo_url  = "https://github.com/asanexample/app-alpha"
          repo_path = "k8s/preprod"
          preview   = true
        }
      }
      # Per-team AWS access via EKS Pod Identity (ADR-041). The platform binds the role to exactly this
      # (namespace, service_account); the app manifest MUST set spec.serviceAccountName to it.
      # s3 keys are SUFFIXES — the full bucket name is built as `asanexample-team-<team>-<suffix>`, so a
      # team structurally cannot name (or be granted) another team's bucket (isolation by construction).
      aws = {
        service_account = "app-alpha"
        s3 = {
          "data" = { access = "read", prefix = "" } # -> asanexample-team-alpha-data
        }
      }
    }
    bravo = {
      mode = "namespace"
      # Migrated to a Tenant claim (BACK stack P3, #174) — see alpha above. app delivery + Dev-bravo SSO stay.
      migrated = true
      apps = {
        demo = {
          repo_url  = "https://github.com/asanexample/app-bravo"
          repo_path = "k8s/preprod"
          preview   = false
        }
      }
      # bravo's role/bucket/association are provisioned (for the cross-team isolation test) even though
      # app-bravo isn't deployed yet; the association is inert until a pod runs as this SA.
      aws = {
        service_account = "app-bravo"
        s3 = {
          "data" = { access = "read", prefix = "" } # -> asanexample-team-bravo-data
        }
      }
    }
  }

  # All tenant infra (namespace, RBAC, Pod-team role + association, ECR, per-team restrict-* policies,
  # DeveloperAccess + access entry) is provisioned by the Crossplane Tenant Composition (BACK stack P3,
  # #174) for `migrated` teams. This file now only feeds APP DELIVERY (argocd-apps reads `teams`/`apps`)
  # and the platform-owned SUPPLY-CHAIN policies (policy unit reads `teams` for verify-images/attestations).
  # The old namespace_teams/aws_teams infra loops are gone with the tenant/pod-identity/s3-shared units.
  migrated_teams = [for k, v in local.teams : k if try(v.migrated, false)]
}

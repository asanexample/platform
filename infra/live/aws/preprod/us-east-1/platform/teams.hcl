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
      # Hostnames this team's Gateway-API routes may claim (Kyverno hostname guard, ADR-029).
      hostnames = ["demo.preprod.aws.refplat.org"]
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
      mode      = "namespace"
      hostnames = ["demo-bravo.preprod.aws.refplat.org"]
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

  namespace_teams = { for k, v in local.teams : k => v if v.mode == "namespace" }
  vcluster_teams  = { for k, v in local.teams : k => v if v.mode == "vcluster" }
  # Teams that declare AWS access (Pod Identity role + association + bucket grants).
  aws_teams = { for k, v in local.teams : k => v if try(v.aws, null) != null }
}

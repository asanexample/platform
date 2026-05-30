include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.github_oidc
}

dependency "ecr" {
  config_path = "../ecr"

  mock_outputs = {
    repository_arns = {
      "team-alpha/demo" = "arn:aws:ecr:us-east-1:000000000000:repository/team-alpha/demo"
      "team-bravo/demo" = "arn:aws:ecr:us-east-1:000000000000:repository/team-bravo/demo"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

locals {
  # Team -> GitHub app repo. Hand-maintained alongside the ecr `repositories` list
  # in this account (see tenant-onboarding runbook). Each team gets its own ECR
  # push role that can push ONLY to its own team-<team>/* repos.
  teams = {
    alpha = { github_repo = "app-alpha" }
    bravo = { github_repo = "app-bravo" }
  }
}

inputs = {
  create     = true
  github_org = "asanexample"

  # One push role per team: trusts only that team's repo (OIDC sub) and can push
  # only to that team's ECR repos. Generated for teams that have ≥1 ECR repo.
  # Merged with the shared isolated-provenance signer role below.
  roles = merge({ for team, cfg in local.teams :
    "github-actions-ecr-push-${team}" => {
      repos    = [cfg.github_repo]
      branches = ["main"]         # push on merge to main
      events   = ["pull_request"] # and PR preview builds
      tags     = { Team = team }  # per-team attribution / ABAC (#61)

      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid      = "ECRAuth"
            Effect   = "Allow"
            Action   = ["ecr:GetAuthorizationToken"]
            Resource = "*"
          },
          {
            Sid    = "ECRPush"
            Effect = "Allow"
            Action = [
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage",
              "ecr:PutImage",
              "ecr:InitiateLayerUpload",
              "ecr:UploadLayerPart",
              "ecr:CompleteLayerUpload",
            ]
            # Only this team's repositories (team-<team>/*).
            Resource = [
              for k, arn in dependency.ecr.outputs.repository_arns : arn
              if startswith(k, "team-${team}/")
            ]
          },
        ]
      })
    }
    if length([for k, _ in dependency.ecr.outputs.repository_arns : k if startswith(k, "team-${team}/")]) > 0
    },
    {
      # Isolated SLSA build-provenance signer (#108/#131, ADR-042). Assumed ONLY while the
      # asanexample/trusted-ci reusable workflow runs — scoped by the OIDC `job_workflow_ref`
      # claim, because for a reusable workflow the `sub` claim reflects the CALLING app repo and
      # so can't identify the signer. It reads image manifests and pushes cosign provenance
      # attestations across ALL team repos; this shared signer is safe because per-team isolation
      # stays anchored on the per-team cosign SIGNATURE (unchanged), and P2's Kyverno policy
      # verifies the caller via the cert's github-workflow-repository extension. Wildcard ref: the
      # workflow PATH is the unforgeable gate, so we avoid an IAM apply on every trusted-ci release.
      "trusted-ci-provenance" = {
        job_workflow_refs = ["trusted-ci/.github/workflows/slsa-provenance.yml@*"]
        tags              = { Purpose = "slsa-provenance" }

        inline_policy = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              Sid      = "ECRAuth"
              Effect   = "Allow"
              Action   = ["ecr:GetAuthorizationToken"]
              Resource = "*"
            },
            {
              Sid    = "ECRReadAndAttest"
              Effect = "Allow"
              # Read the image manifest (to resolve the attestation subject) and push the
              # cosign `.att` attestation. Same action set as the per-team push role, but
              # across every team repo since one signer serves all teams.
              Action = [
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
              ]
              # All team repos (team-*/*).
              Resource = [
                for k, arn in dependency.ecr.outputs.repository_arns : arn
                if startswith(k, "team-")
              ]
            },
          ]
        })
      }
    }
  )

  tags = include.base.locals.tags
}

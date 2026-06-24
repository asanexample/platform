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

inputs = {
  create     = true
  github_org = "asanexample"

  roles = {
    "github-actions-terratest" = {
      repos = ["platform"]
      # The Terratest workflow (.github/workflows/test-aws.yml) runs on workflow_dispatch + schedule
      # (both need repo write to trigger), NOT on PR/push — so feat/* is only reachable by a maintainer
      # dispatching a run on a feature branch (to test module changes pre-merge). The deny-overlay below
      # caps the blast radius of any such run. (Ideal hardening: gate the OIDC sub on a reviewer-protected
      # GitHub `environment:terratest` — tracked as a follow-up; needs repo settings.)
      branches = ["main", "refs/heads/feat/*"]
      # AdministratorAccess (Terratest creates/destroys real sandbox AWS resources) bounded by an explicit
      # Deny overlay: even a poisoned run cannot create durable IAM users/keys/federation (persistence),
      # touch the organization/account, or disable audit/detection — closing the "any feat/* run = unbounded
      # admin in the Test account" finding while leaving normal sandbox provisioning intact.
      role_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Sid    = "DenyPersistenceEscalationAndGuardrailDisable"
          Effect = "Deny"
          Action = [
            "iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile",
            "iam:CreateServiceSpecificCredential", "iam:UploadSSHPublicKey",
            "iam:CreateSAMLProvider", "iam:CreateOpenIDConnectProvider",
            "organizations:*", "account:*",
            "cloudtrail:StopLogging", "cloudtrail:DeleteTrail",
            "guardduty:DeleteDetector", "guardduty:UpdateDetector",
            "config:StopConfigurationRecorder", "config:DeleteConfigurationRecorder",
          ]
          Resource = "*"
        }]
      })
      max_session_duration = 3600 # 1 hour — sufficient for Terratest runs
    }
  }

  tags = include.base.locals.tags
}

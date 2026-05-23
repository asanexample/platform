include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.tailscale_admin
}

# Override versions.tf to add the tailscale provider
generate "versions_override" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.6.0"
      required_providers {
        tailscale = {
          source  = "tailscale/tailscale"
          version = "~> 0.29"
        }
        aws = {
          source  = "hashicorp/aws"
          version = "6.45.0"
        }
      }
    }
  EOF
}

# Tailscale provider — authenticates via API key from Secrets Manager
generate "provider_tailscale" {
  path      = "provider_tailscale.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    data "aws_secretsmanager_secret_version" "tailscale_api_key" {
      secret_id = "platform/tailscale/api-key"
    }

    provider "tailscale" {
      api_key = data.aws_secretsmanager_secret_version.tailscale_api_key.secret_string
      tailnet = "taild3190d.ts.net"
    }
  EOF
}

inputs = {
  create = true

  acl_policy = <<-HUJSON
    {
      "tagOwners": {
        "tag:k8s-operator": ["autogroup:admin"],
        "tag:k8s":          ["tag:k8s-operator"]
      },
      "grants": [
        {"src": ["*"], "dst": ["*"], "ip": ["*"]}
      ],
      "autoApprovers": {
        "routes": {
          "10.100.0.0/16": ["tag:k8s-operator", "tag:k8s"]
        }
      },
      "ssh": [
        {
          "action": "check",
          "src":    ["autogroup:member"],
          "dst":    ["autogroup:self"],
          "users":  ["autogroup:nonroot", "root"]
        }
      ]
    }
  HUJSON

  create_oauth_client      = true
  oauth_client_tags        = ["tag:k8s-operator"]
  oauth_client_description = "K8s Operator managed by Terraform"

  secrets_manager_name = "platform/tailscale/oauth"

  tags = include.base.locals.tags
}

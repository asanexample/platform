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
  if_exists = "overwrite"
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
          version = "6.47.0"
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

# Replicate Tailscale secrets to preprod account for the preprod tailscale unit
generate "preprod_secrets" {
  path      = "preprod-secrets.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      alias  = "preprod"
      region = "us-east-1"

      assume_role {
        role_arn = "arn:aws:iam::${include.base.locals.account_ids["preprod"]}:role/PlatformDeployer" # Preprod account
      }
    }

    resource "aws_secretsmanager_secret" "preprod_oauth" {
      provider = aws.preprod

      name                    = "preprod/tailscale/oauth"
      recovery_window_in_days = 7
    }

    resource "aws_secretsmanager_secret_version" "preprod_oauth" {
      provider = aws.preprod

      secret_id = aws_secretsmanager_secret.preprod_oauth.id
      secret_string = jsonencode({
        clientId     = tailscale_oauth_client.k8s_operator[0].id
        clientSecret = tailscale_oauth_client.k8s_operator[0].key
      })
    }

    resource "aws_secretsmanager_secret" "preprod_api_key" {
      provider = aws.preprod

      name                    = "preprod/tailscale/api-key"
      recovery_window_in_days = 7
    }

    resource "aws_secretsmanager_secret_version" "preprod_api_key" {
      provider = aws.preprod

      secret_id     = aws_secretsmanager_secret.preprod_api_key.id
      secret_string = data.aws_secretsmanager_secret_version.tailscale_api_key.secret_string
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
      // Auto-approve VPC subnet routes so they don't need manual admin approval
      "autoApprovers": {
        "routes": {
          "10.100.0.0/16": ["tag:k8s-operator", "tag:k8s"], // Platform VPC
          "10.101.0.0/16": ["tag:k8s-operator", "tag:k8s"]  // Preprod VPC
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

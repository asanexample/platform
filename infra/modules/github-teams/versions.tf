terraform {
  required_version = ">= 1.11"

  required_providers {
    # GitHub org-team ownership of app repos (ADR-072 Flavor A). The maintained provider (successor to
    # hashicorp/github). Configured by the live unit's generate block (App credentials from Secrets Manager).
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

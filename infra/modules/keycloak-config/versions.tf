terraform {
  required_version = ">= 1.11"

  required_providers {
    # The app-facing realm/broker/clients/mappers (ADR-053). Official provider (successor to mrparkers/keycloak).
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.7"
    }
    # Not used by this module's resources, but the unit injects a data.aws_secretsmanager_secret_version (the
    # Keycloak admin credential) via a generate block, and this versions.tf is the one Terragrunt uses.
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

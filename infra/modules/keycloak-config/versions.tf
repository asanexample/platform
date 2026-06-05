terraform {
  required_version = ">= 1.11"

  required_providers {
    # The app-facing realm/broker/clients/mappers (ADR-053). Official provider (successor to mrparkers/keycloak).
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.7"
    }
    # Per-app OIDC client secrets are generated + stored in Secrets Manager (and the unit injects the admin
    # credential data source via a generate block, using this versions.tf).
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

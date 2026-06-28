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
      version = "~> 6.0"
      # aws.preprod: a second account's Secrets Manager, to REPLICATE selected shared client secrets there so a
      # spoke cluster's ESO can read them locally (var.replicate_client_secrets_to_preprod). The unit supplies it.
      configuration_aliases = [aws.preprod]
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

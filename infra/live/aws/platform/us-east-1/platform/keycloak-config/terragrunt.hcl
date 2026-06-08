include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.keycloak_config

  # In-cluster configuration path (ADR-059). keycloak-config configures Keycloak via a kubectl port-forward to the
  # ClusterIP (the provider points at localhost:18080 below), NOT the Tailscale-fronted gateway — so the deployer
  # does not need the tailnet to deploy, and keycloak-config no longer depends on the gateway/cert/NLB/DNS. The
  # port-forward reaches the cluster the same way Terragrunt does (aws eks + the deployer role); the EKS API is
  # public during bootstrap (SSM/eks-tunnel.sh for a private day-2 cluster). start_pf also waits for Keycloak to
  # serve over the forward (deterministic readiness — Keycloak itself is gated by helm_wait on the keycloak unit).
  # NOT on destroy: teardown drops the keycloak_* resources from state first (platctl state_purge hook), since
  # Keycloak's database — and thus the whole realm — is destroyed wholesale in the next wave, so there's nothing
  # to delete over the forward. Port-forwarding on destroy only adds a dependency on a schedulable Keycloak pod,
  # which fails ("pod is not running, Current status=Pending") under teardown node pressure.
  before_hook "start_pf" {
    commands = ["apply", "plan"]
    execute = [
      "bash", "${get_repo_root()}/scripts/kc-portforward.sh", "up",
      dependency.eks.outputs.cluster_id,
      include.base.locals.region,
      include.base.locals.deployer_role_arn,
      dependency.keycloak.outputs.namespace,
      dependency.keycloak.outputs.service_name,
      "${dependency.keycloak.outputs.service_port}",
      "18080",
    ]
  }

  after_hook "stop_pf" {
    commands     = ["apply", "plan"]
    run_on_error = true
    execute      = ["bash", "${get_repo_root()}/scripts/kc-portforward.sh", "down", dependency.eks.outputs.cluster_id, "18080"]
  }
}

# Canonical Team registry (single source of truth, ADR-053) — read directly (not via _base.hcl, to keep the
# blast radius to this unit + the crossplane unit). Drives the Keycloak groups + developer-access roles.
locals {
  teams = read_terragrunt_config(find_in_parent_folders("aws/_teams.hcl")).locals.teams
}

# Configures the running Keycloak (deployed by the keycloak unit) via the keycloak/keycloak provider — B2,
# ADR-053. The provider talks to the LIVE admin API over an in-cluster port-forward (see the start_pf hook), so
# this unit is not CI-plan-tested; apply is rebuild-gated (needs Keycloak serving + cluster API access).
dependency "keycloak" {
  config_path = "../keycloak"

  mock_outputs = {
    namespace    = "keycloak"
    service_name = "keycloak"
    service_port = 80
    issuer       = "https://keycloak.aws.refplat.org"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Needed for the port-forward (cluster name); region + deployer role come from include.base.locals.
dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id = "mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The keycloak provider authenticates as the bootstrap admin (admin-cli password grant); creds are in Secrets
# Manager (platform/keycloak/admin), created by the keycloak module. (Hardening follow-up: a dedicated
# terraform service-account client with client_credentials.) The aws provider comes from root.hcl.
generate "keycloak_provider" {
  path      = "keycloak-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    data "aws_secretsmanager_secret_version" "kc_admin" {
      secret_id = "platform/keycloak/admin"
    }

    locals {
      kc_admin = jsondecode(data.aws_secretsmanager_secret_version.kc_admin.secret_string)
    }

    # Connect via the localhost port-forward (the start_pf hook), NOT the gateway hostname — keeps the deploy path
    # off Tailscale (ADR-059). The realm/SP config still uses the canonical issuer via the keycloak_url input.
    provider "keycloak" {
      url       = "http://localhost:18080"
      client_id = "admin-cli"
      username  = local.kc_admin.username
      password  = local.kc_admin.password
      realm     = "master"
      # Defer login to first use instead of authenticating at provider-configure time. On teardown the
      # keycloak_* resources are dropped from state first (platctl state_purge) and the port-forward no longer
      # runs, so nothing uses this provider — without this it would still try an initial login to a gone
      # Keycloak ("failed to perform initial login") and fail the destroy. Apply is unaffected: it logs in
      # when the first realm resource is created.
      initial_login = false
    }
  EOF
}

inputs = {
  create = true

  keycloak_url = dependency.keycloak.outputs.issuer

  # Identity source = Keycloak itself (the IdP of record — ADR-053/059 default). `upstream` is omitted (null), so
  # nothing brokers up to an external IdP; identity + membership live in this realm via `users` below. To federate
  # a corporate IdP later (Okta/Entra/Google over OIDC, or AWS IdC over SAML) set `upstream = { … }` here and drop
  # the seed users — NOTHING downstream changes (apps, claims, access model). Presets: docs/runbooks/keycloak-upstream-idp.md.

  # Seed users (membership source in standalone mode). Each is placed in its realm group(s), so the
  # group→role→claim flow is live immediately. Passwords are temporary (must-change on first login) and generated
  # into Secrets Manager at platform/keycloak/seed-user/<username> — read them with `platctl` / the AWS console.
  users = {
    "admin" = {
      email      = "admin@${split("@", include.base.locals.admin_email)[1]}"
      first_name = "Platform"
      last_name  = "Admin"
      groups     = ["platform-admins"]
    }
    "dev-alpha" = {
      email      = "dev-alpha@${split("@", include.base.locals.admin_email)[1]}"
      first_name = "Dev"
      last_name  = "Alpha"
      groups     = ["alpha"]
    }
    "dev-bravo" = {
      email      = "dev-bravo@${split("@", include.base.locals.admin_email)[1]}"
      first_name = "Dev"
      last_name  = "Bravo"
      groups     = ["bravo"]
    }
  }

  # Per-app OIDC clients use the module defaults (ArgoCD/Backstage/oauth2-proxy). Secrets are tagged for SM.
  tags = include.base.locals.tags

  # Public PKCE client for the ArgoCD CLI (no secret — B3, ADR-059): the CLI can't safely hold the confidential
  # `argocd` client's secret, so it uses this. argocd-cm sets oidc.config.cliClientID = argocd-cli.
  public_clients = {
    "argocd-cli" = {
      name          = "ArgoCD CLI"
      redirect_uris = ["http://localhost:8085/auth/callback"]
    }
  }

  # Team taxonomy — one Keycloak group per Team + the developer-access roles, from the canonical registry.
  # platform_groups defaults to { platform-admins } in the module (the non-team admin group ArgoCD maps to org-admin).
  teams = local.teams
}

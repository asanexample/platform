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

# Canonical Team registry — the git-native Team CRs (ADR-063), the same YAMLs ArgoCD syncs to the cluster.
# Each gitops/teams/<team>.yaml is a Team CR; key by metadata.name and expose spec ({ ssoGroup, envelope }),
# which is exactly what the keycloak-config module consumes (groups + envelope→developer-access roles).
# Reads from git, not _teams.hcl (retired) — git is now the single source of truth for Team identity.
locals {
  teams_dir = "${get_repo_root()}/gitops/teams"
  teams = { for f in fileset(local.teams_dir, "*.yaml") :
    yamldecode(file("${local.teams_dir}/${f}")).metadata.name => {
      # Extract ONLY the fields the module consumes — a fixed shape, so a Team-spec field that some teams have and
      # others don't (e.g. platform's platformTrust, ADR-081) can't make the map's element types inconsistent.
      ssoGroup = yamldecode(file("${local.teams_dir}/${f}")).spec.ssoGroup
      envelope = yamldecode(file("${local.teams_dir}/${f}")).spec.envelope
    }
  }

  # Realm users GENERATED from the roster (identity strategy §2.4/§2.6, #889) — the OTHER half of the single
  # source of truth: one Person in gitops/people (#886), joined with the role catalog (gitops/roles, #887), feeds
  # both AWS console access (#888) and app access (here), so people are declared ONCE. Keyed by the Keycloak
  # anchor (spec.person — the realm username); placed in the realm groups its STANDING grants map to: a team grant
  # → the team's group (the keycloak module makes one group per Team); a platform grant → the role's keycloak
  # group (e.g. access-admin → platform-admins). on-demand grants are eligibility, not standing app access (§2.3),
  # so they don't add a group. No PII in git — email is derived from the anchor + the org domain; display names
  # are synthetic (the real identity lives in the ADR-084 directory).
  people_dir = "${get_repo_root()}/gitops/people"
  roles_dir  = "${get_repo_root()}/gitops/roles"
  people = { for f in fileset(local.people_dir, "*.yaml") :
    yamldecode(file("${local.people_dir}/${f}")).metadata.name => yamldecode(file("${local.people_dir}/${f}")).spec
  }
  roles = { for f in fileset(local.roles_dir, "*.yaml") :
    yamldecode(file("${local.roles_dir}/${f}")).metadata.name => yamldecode(file("${local.roles_dir}/${f}")).spec
  }
  kc_domain = split("@", include.base.locals.admin_email)[1]
  gen_users = {
    for pname, p in local.people : p.person => {
      email      = "${p.person}@${local.kc_domain}"
      first_name = title(split("-", pname)[0])
      last_name  = length(split("-", pname)) > 1 ? title(split("-", pname)[1]) : "User"
      groups = distinct(flatten([
        for g in p.grants : (
          try(g.activation, "") == "on-demand" || try(local.roles[g.role].mode, "standing") != "standing" ? [] :
          try(g.team, "") != "" ? [g.team] :
          try(local.roles[g.role].keycloak.group, "") != "" ? [local.roles[g.role].keycloak.group] : []
        )
      ]))
    }
  }
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
  # a corporate IdP later (Okta/Entra/Google over OIDC, or AWS IdC over SAML) set `upstream = { … }` here — the
  # roster still says WHO, but membership then flows from the upstream group claim. Presets: docs/runbooks/keycloak-upstream-idp.md.

  # Realm users GENERATED from the roster (gitops/people × the role catalog, #889) — no longer hand-maintained
  # here, so a person is declared ONCE (the roster) and feeds both AWS (#888) and apps. Each is placed in its
  # realm group(s), so the group→role→claim flow is live immediately. Passwords are temporary (must-change on
  # first login) and generated into Secrets Manager at platform/keycloak/seed-user/<username>. See local.gen_users.
  users = local.gen_users

  # Per-app OIDC clients use the module defaults (ArgoCD + Backstage, both direct OIDC). Secrets are tagged for SM.
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

  # ADR-084 Phase 1: broker GitHub + Slack as linkable IdPs + the directory-sync service account (reads the IdP
  # app secrets from platform/keycloak/{github,slack}-idp; publishes the directory-sync secret for the agent).
  enable_account_linking = true

  # Auth strength (#885, identity strategy §3.1). Keycloak is the IdP of record here, so the factor lives in this
  # realm: a browser flow requires a phishing-resistant passkey (WebAuthn passwordless) for ALL workforce — no OTP
  # anywhere — plus self-service password reset OFF, brute-force defenses, and login/admin event logging (module
  # defaults). Recovery is a backup passkey or admin re-provision.
  #
  # TWO-APPLY, NO-LOCKOUT ROLLOUT (Keycloak is Tier-0):
  #   apply-1 (now): enforce_browser_mfa = false — the flow + force-enroll action + realm hardening are created,
  #     but the built-in browser flow stays live. Then enroll a passkey (+ a backup) on `admin` via the Account
  #     Console over the gateway, and verify it logs in.
  #   apply-2: flip enforce_browser_mfa = true to BIND the new flow. Enrolled users log in by passkey; new users
  #     are force-enrolled. Break-glass if a flow misbehaves: revert to false + re-apply (admin-cli direct-grant
  #     is independent of any browser flow). Master-realm admin hardening is tracked separately in #899.
  enforce_browser_mfa = false
}

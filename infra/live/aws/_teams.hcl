# Canonical Team registry — the single source of truth for Team identity + envelope (ADR-049 / ADR-053).
#
# One source, multiple consumers (read directly via read_terragrunt_config — see the consuming units):
#   - the `crossplane` unit  → projects the envelope subset as Team CRs (Kyverno restrict-tenant-envelope)
#   - the `keycloak-config` unit → generates one Keycloak group per Team + the developer-access roles
#
# Keys are camelCase so this map feeds the crossplane-teams chart values verbatim
# (infra/modules/crossplane/charts/teams/values.yaml). The interim teams.hcl still carries app-delivery
# (repos/hostnames/apps) for policy + argocd-apps; fully subsuming it is a rebuild cleanup.
#
# Per team:
#   ssoGroup     required  the Identity Center group (membership linkage; group MEMBERSHIP is not yet wired)
#   displayName  optional  canonical-only (Backstage); not projected to the cluster or Keycloak
#   envelope     required
#     allowedTiers        required  [] (standard|elevated|pci|hipaa)
#     allowedEnvironments required  [] (preprod|prod)
#     allowedLocations    optional  [] (default ["*"])
#     quotaCap            optional  { cpu, memory, pods }
#     maxDedicatedZones   optional  int (default 0)
locals {
  teams = {
    alpha = {
      ssoGroup    = "Dev-alpha"
      displayName = "Team Alpha"
      envelope = {
        allowedTiers        = ["standard"]
        allowedEnvironments = ["preprod"]
        allowedLocations    = ["*"]
        quotaCap            = { cpu = "8", memory = "16Gi", pods = 40 }
        maxDedicatedZones   = 0
      }
    }
    bravo = {
      ssoGroup    = "Dev-bravo"
      displayName = "Team Bravo"
      envelope = {
        allowedTiers        = ["standard"]
        allowedEnvironments = ["preprod"]
        allowedLocations    = ["*"]
        quotaCap            = { cpu = "8", memory = "16Gi", pods = 40 }
        maxDedicatedZones   = 0
      }
    }
  }
}

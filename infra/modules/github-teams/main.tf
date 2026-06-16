# ---------------------------------------------------------------------------
# GitHub org-Team ownership (ADR-072 Flavor A)
# ---------------------------------------------------------------------------
# Native, auditable write-access for app repos, layered BESIDE — never replacing — the supply-chain identity.
# Org-team membership is NOT in the Actions OIDC token, so it can never carry the cosign/Kyverno team identity
# (that still anchors on the repo name + the per-Product IAM role, ADR-050/069). These resources only manage
# human ownership. Teams + grants are derived from the git registries (gitops/teams, gitops/products) at the
# live unit, so a team is materialised in GitHub on Team-CR convergence — the same lifecycle moment as its
# Keycloak group (keycloak-config), not imperatively at scaffold time.

resource "github_team" "this" {
  for_each = var.create ? var.teams : {}

  # GitHub derives the slug from the name; our team names are slug-safe (^[a-z][a-z0-9]{1,15}$), so name == slug.
  name        = each.key
  description = coalesce(each.value.description, "${each.key} — app-repo ownership (platform-managed, ADR-072).")
  privacy     = each.value.privacy
}

resource "github_team_repository" "this" {
  for_each = var.create ? var.repo_grants : {}

  # Reference the managed team (not a bare slug) so the team is created before its grant and a registry entry
  # for an unknown team fails loudly at plan instead of granting nothing.
  team_id    = github_team.this[each.value.team].id
  repository = each.value.repo
  permission = each.value.permission
}

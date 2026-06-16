# github-teams

GitHub org **Team ownership** of app repos (ADR-072 Flavor A) — the native, auditable human write-access layer,
layered **beside** (never replacing) the supply-chain identity.

> **Not a security anchor.** Org-team membership is **not** in the GitHub Actions OIDC token, so it can never
> carry the cosign / Kyverno team identity. The unspoofable supply-chain team is still the **repo name**
> (`<team>-<product>`, first segment) + the per-Product IAM OIDC role (`infra/modules/aws/github_oidc`,
> ADR-069). This module is ownership only.

## What it does

- `github_team` per team — created from the **Team registry** (`gitops/teams/`).
- `github_team_repository` (`push`) per Product — its owning team gets write access to its `<team>-<product>`
  repo, derived from the **Product registry** (`gitops/products/`).

Both maps are derived at the live unit (`fileset`+`yamldecode`), so a team is materialised in GitHub on
**Team-CR convergence** — the same lifecycle moment as its Keycloak group — not imperatively at scaffold time.

## Provider credential

Configured by the live unit via a `generate` block: the `integrations/github` provider authenticates as a
dedicated **GitHub App** (`app_auth`) with `Members: write` + `Administration: write`, installed org-wide. The
App's `app_id` / `installation_id` / `pem` live in Secrets Manager (`platform/github-ownership/app`). One-time
manual prereq: `docs/runbooks/github-ownership-app.md`.

## Usage

```hcl
module "github_teams" {
  source = "../../modules/github-teams"

  teams = {
    alpha = {}
    bravo = {}
  }
  repo_grants = {
    # keyed by repo name (<team>-<product>, org-unique)
    "alpha-shop" = { team = "alpha", repo = "alpha-shop" } # push by default
  }
}
```

---
name: backstage-portal
description: >-
  How to configure and operate the Backstage developer portal from THIS infra repo —
  the `backstage` module + its live unit. Use when enabling/configuring a Backstage
  plugin (Kubernetes, ArgoCD), wiring Keycloak OIDC auth, the catalog projection
  (Team→Group, Product→System, Environment), the scaffolder GitHub Apps, the
  database mode, or bumping the portal image; and when debugging catalog visibility,
  a plugin 401, or SSO. Covers the appConfig/env-injection config flow, the
  read-only vs write GitHub Apps, the projection_mode flag, and the gotchas
  (ArgoCD-token revocation, K8s cluster-name match, inline config schema). NOT for
  the Backstage APP source (the separate asanexample/backstage repo: image, custom
  plugins, frontend) — only what's controllable from infra here. NOT for Keycloak
  realm setup (`keycloak-config`).
---

# Backstage developer portal (infra side)

Backstage runs as a **read-only, Tailscale-internal** portal on the platform cluster at
`backstage.aws.refplat.org`. The portal **app** (image, custom plugins, frontend) is a
**separate repo, `asanexample/backstage`** — this skill is only what the infra repo
controls: the Helm module, its config, secrets, plugins, and the scaffolder templates.
Decision record: ADR-051; UX roadmap: ADR-064.

Module: `infra/modules/backstage/`. Live unit:
`infra/live/aws/platform/us-east-1/platform/backstage/terragrunt.hcl`. It deploys the
official chart with the custom `platform/backstage` image (cosign-signed by the app
repo's CI), Postgres (in-cluster CloudNativePG dev / RDS prod), EKS Pod Identity for the
Kubernetes plugin, secrets from Secrets Manager via ExternalSecret, and a Cilium Gateway
HTTPRoute (not a K8s Ingress).

## Config flow — image base + Terraform env-injection

The image ships `app-config.production.yaml` with the full shape (plugins, catalog, auth,
integrations) and **env-var placeholders** (`${AUTH_SESSION_SECRET}`, `${ARGOCD_AUTH_TOKEN}`,
GitHub App creds). The module's `appConfig` values render a ConfigMap + inject the env;
the chart appends `--config`. So **feature toggles and cluster/instance lists are unit
variables — no image rebuild needed**; only new *code* or a new config *schema* requires
an app-repo change.

> **Inline-schema gotcha**: Backstage has **no external schema files** — config schema is
> inline JSON in the image's `package.json` (`configSchema`). A config key with no schema
> is **silently ignored** (feature looks "broken", no error). So you can't just add a
> brand-new config section here and inject it; use env-var substitution against the
> image's existing shape (what the module already does), or ship the schema in the app repo.

## Auth — direct Keycloak OIDC (Dex + oauth2-proxy retired)

Backstage authenticates **directly** against Keycloak (no proxy): `oidc` sign-in
provider, confidential client `backstage` (secret synced from `platform/keycloak/backstage-oidc`),
issuer `…/realms/platform`, with a `groups` claim driving ownership/RBAC. Keycloak
brokers upstream IdPs invisibly (ADR-059). The Keycloak client itself is created by
`keycloak-config`, not here. Optional split-horizon `oidc_gateway_alias_host` pins the
Keycloak host to the gateway ClusterIP (avoids internal-NLB hairpin) — resolved
dynamically, never hardcode the IP.

## Catalog = projection of git (not a cluster scrape)

The `platform-projection` backend plugin (in the app repo) reads **this** repo's
registries via the read-only GitHub App and projects entities:

| Git source | Entity |
|---|---|
| `gitops/teams/<team>.yaml` | Group |
| `gitops/products/<team>/<product>.yaml` | System |
| `gitops/environments/<team>/<product>/<stage>.yaml` | Environment (custom kind, v3) |
| app repo `catalog-info.yaml` | Component (via GitHub discovery) |
| Crossplane-composed AWS resources | Resource (via K8s plugin) |

`projection_mode = "v3"` selects the current model (the live unit sets `"v3"`; the module
**defaults to `""`** = the image default, v2 legacy). Flipping it needs **no image
rebuild** — the code is dormant in the image. `catalog.rules: [Component, Location]` keeps
app repos from self-registering Groups/Systems.

## Plugins & GitHub Apps

Enable via unit feature flags:

- **Kubernetes** (`enable_kubernetes_plugin`): provide `kubernetes_clusters` — the
  `name` **must be the real EKS cluster name** (e.g. `platform-use1-eks`); it's the EKS
  token's `x-k8s-aws-id`, a mismatch 401s. Cross-account workload clusters take an
  `assume_role`. `skipMetricsLookup: true` (read-only policy can't reach metrics.k8s.io).
- **ArgoCD** (`enable_argocd_plugin`): provide `argocd_instances` with `url` (in-cluster
  backend) + `frontend_url` (browser links); token synced from `platform/argocd/backstage-token`.
- **GitHub discovery** (`enable_github_discovery`): read-only App `platform/backstage/github-app`.
- **Scaffolder** (`enable_scaffolder`): write App `platform/backstage/scaffolder-github-app`,
  scoped to `asanexample/platform` only (Contents+PRs read/write, no admin/merge).

**Keep the two GitHub Apps' installations disjoint** (a runbook convention — nothing in
the module enforces it) — read-only on app repos, write on the platform repo; overlapping
installs shadow credentials and scaffolder PRs fail. Scaffolder templates live **here**:
`scaffolder/templates/` — the provisioning set `new-{environment,product,team,resource}/`,
the teardown set `deprovision-{environment,product}/`, the person-lifecycle set
`{onboard,offboard}-person/` (back the `gitops/people/` registry, ADR-084/088), plus
`request-promotion/` and `hello-world/`.

## Change config / deploy

Edit the unit, then (private API → over Tailscale, ADR-010):

```bash
AWS_PROFILE=management terragrunt apply \
  --working-dir infra/live/aws/platform/us-east-1/platform/backstage
kubectl --context platform -n backstage get pods -l app.kubernetes.io/name=backstage
```

Common edits: `image_tag` (SHA from `asanexample/backstage`), `enable_*` flags,
`kubernetes_clusters`, `argocd_instances`, `database.mode`, `projection_mode`.

## Minimal example — enable the ArgoCD plugin

```hcl
enable_argocd_plugin = true
argocd_instances = [{
  name         = "platform"
  url          = "http://argocd-server.argocd.svc"
  frontend_url = "https://argocd.aws.refplat.org"
}]
```

Ensure the token secret exists, apply, and verify the ExternalSecret syncs:
`kubectl --context platform -n backstage get externalsecret backstage-argocd-token`
(`SecretSynced=True`). Components with an `argocd/app-selector` annotation then show
sync/health.

## Gotchas

- **ArgoCD card 401 after an apply**: a Helm 3-way merge can drop the minted token id
  from `argocd-cm`; re-mint and update Secrets Manager (`docs/runbooks/backstage-argocd.md`).
- **K8s plugin cluster name** must equal the EKS cluster name (above), else 401.
- **Inline config schema** — see the gotcha above; missing schema fails silently.
- **Scaffolder RBAC (#197)** gates runs to the requester's own team via a permission
  policy + the CI gate (both load-bearing) — `docs/runbooks/backstage-scaffolder-github-app.md`.
- The portal is **read-only by design**; it provisions only via scaffolder PRs into git,
  never by writing to clusters directly.

## References

- ADRs: 051 (portal), 062 (self-service provisioning gates), 064 (provisioning
  visibility), 067 (domain model / entity names), 063 (Team CR), 059 (IdP brokering)
- `docs/architecture/identity-and-sso.md`, `docs/architecture/crossplane-environment-api.md`
- `docs/runbooks/backstage-{github-app,scaffolder-github-app,argocd}.md`
- `infra/modules/backstage/`, `scaffolder/templates/`

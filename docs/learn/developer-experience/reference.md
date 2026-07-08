# Learn: Developer Experience — reference

Look-up, not a lesson. Build the model in the [orientation](orientation.md) first. Verified against code +
ADRs + live (Backstage running on the hub). No account IDs, emails, or secret values appear here (the
`backstage` module's `image_registry` default embeds the platform account ID — omitted; secret *paths* are
fine).

## The model — the BACK stack

**B**ackstage (the form / the view) → **A**rgoCD (delivery) → **C**rossplane (control plane) → **K**ubernetes
(ADR-046). The control plane was built **first**; Backstage is a *thin portal over reconciled APIs*, never an
imperative pipeline. Developer states **intent** → scaffolder opens a **PR to the git registries** → GitOps
(Gate → ArgoCD registry-sync → Crossplane) reconciles it. Developer names *what*; the platform **derives** the
security-sensitive rest (IAM, ECR, namespace, Kyverno scope). **The portal never writes directly — every
change is a PR.**

## Backstage — the portal ([ADR-051](../../adrs/051-backstage-developer-portal.md), Phase 2 live)

- **App vs infra split (hold this):** the **app** (image, custom plugins, the Cost tab, the inline config
  schema) is a *separate repo* (`asanexample/backstage`), CI-built + cosign-signed to ECR. **This** repo
  controls only the *deployment*. "Grepped the module, found nothing" = wrong repo.
- **Module** (`infra/modules/backstage`): a `helm_release` of the official chart running *our* signed image —
  deployed via **Terragrunt, not GitOps** (the portal shouldn't depend on the ArgoCD it observes). Roll a new
  build = bump `image_tag` (an app-repo commit SHA) + `terragrunt apply`. Deploys: the Helm release (`:7007`,
  ClusterIP, ingress via the **Cilium Gateway** HTTPRoute, Tailscale-internal at
  `backstage.aws.refplat.org`); an in-cluster **CNPG** Postgres (`backstage-db-1`, DB-per-plugin →
  `CREATEDB` managed role; Barman S3 backups; `database.mode="rds"` is a planned toggle); **ExternalSecrets**
  (OIDC secret ← `platform/keycloak/backstage-oidc`, GitHub Apps, ArgoCD token, audit DSN); an **EKS Pod
  Identity** *viewer* role.
- **Config model:** the image ships `app-config.production.yaml` with `${ENV}` placeholders; its config
  *schema* is **inline JSON in the image's `package.json`** (`configSchema`). The module renders an
  `appConfig` ConfigMap + env vars. **Feature toggles are unit variables (no rebuild) — but a config key with
  no schema is silently ignored** (feature looks broken, no error). You substitute against the image's shape;
  you can't invent a new config section from the infra side.
- **Catalog = projection of git, not a cluster scrape:** a backend entity provider reads the git registries
  via the **read-only** GitHub App (`projection_mode="v3"`): `gitops/teams/*` → **Group**,
  `gitops/products/*` → **System**, `gitops/environments/*` (XEnvironment) → **Environment** (custom kind).
  *(Separately — not the git projection: an app-repo `catalog-info.yaml` → **Component** via GitHub discovery;
  Crossplane MRs show on an Environment's K8s tab via the Kubernetes plugin, using cluster creds.)*
  `catalog.rules:[Component,
  Location]` blocks app repos from self-registering Groups/Systems (no ownership spoofing). Git is the source
  of truth → no privileged cluster access, no drift.
- **Auth = direct Keycloak OIDC** (Dex + oauth2-proxy **retired**; ADR-051 amendment, ADR-053/059 supersede
  the ADR-052 Dex broker). Confidential client `backstage`, issuer `…/realms/platform`, `groups` claim →
  ownership/RBAC; a TF-generated `AUTH_SESSION_SECRET` signs the session cookie. **Gotcha:** the OIDC issuer
  host is pinned via a pod `hostAlias` to the gateway ClusterIP (looked up per-apply) so token exchange hits
  Envoy directly, not the flaky NLB hairpin. **RBAC** (#197): permission framework gates template runs to the
  requester's team; team members run the non-privileged templates, while `new-team`/offboarding are admin-gated server-side.
- **Plugins — all read-only, scoped** (never cluster-admin): **Kubernetes** (Pod-Identity viewer role,
  `AmazonEKSViewPolicy` — *excludes* Secrets; assumes a cross-account read-only role for **preprod**; cluster
  `name` must be the *real* EKS name or the token 401s; `skipMetricsLookup:true`; surfaces Crossplane MRs on
  workload clusters only). **ArgoCD** (Roadie plugin, read-only `role:readonly` token; `argocd/app-selector`
  annotation). **Cost tab** (ADR-091 A3, platform#1051 — **built**; plugin in the *app image*, infra side =
  **one line** `query_consumer_namespaces=["backstage"]` in the `mimir` unit; renders spend ÷ the team's
  `Team.spec.envelope.budget`; ADR-091's "Remaining" prose (line 127) is **stale** — ADR-092 already treats
  the tab as existing). **Audit/My-Access**
  (borrow history; the one *write* capability — `backstage-activators` create-only on `Activation`).
- **Auth-recovery gotcha:** single CNPG instance → after a `keycloak-db` blip the openid-client caches a
  failed discovery (SSO 503) → `kubectl rollout restart deploy/backstage`.

## The scaffolder — golden paths ([ADR-046](../../adrs/046-back-stack-for-developer-self-service.md)/062, live)

Templates in `scaffolder/templates/` (registered via `location.yaml`, CODEOWNERS-protected). Each
`kind: Template` (`scaffolder.backstage.io/v1beta3`).

| Template | Does | Lands PR at | Gate |
| --- | --- | --- | --- |
| **new-product** | app repo from starter + Product entry + first `dev` env | new repo + `gitops/products/…` + `…/environments/…/dev.yaml` | reviewer |
| **new-environment** | an Environment (Product × Stage) | `gitops/environments/<team>/<product>/<stage>.yaml` | reviewer |
| **new-resource** | self-service S3/SQS/SNS/DynamoDB (ADR-073) | edits the env claim's `services.<svc>.resources` | **auto** — env-claim edit; the prod gate keys on prod *Releases*, not env claims |
| **request-promotion** | dev→…→prod ladder (#377); same digest up | `gitops/releases/<team>/<product>/<stem>.yaml` | ≤staging **auto** / **prod gated** |
| **new-team** | `Team` CR (envelope) | `gitops/teams/<name>.yaml` | admin, never auto |
| **onboard/offboard-person** | `Person` object / delete it | `gitops/people/<name>.yaml` | People Gate |
| **deprovision-environment/-product** | reversible `lifecycle.phase`; purge=delete | edits/deletes claims | reviewer / admin purge |
| **hello-world** | smoke test (`debug:log`, no PR) | — | n/a |

- **Engine:** `parameters` (JSON-schema form; `ui:field` widgets like `EntityPicker`, custom `ProductPicker`)
  → ordered `steps` (actions) → `output.links` (the PR URL). Templating: `${{ parameters.x }}` /
  `${{ steps.id.output.y }}`, **Nunjucks** filters + `{% if %}`.
- **Actions:** *standard* — `fetch:template` (render a `skeleton/`), `fetch:plain:file`, `publish:github`
  (create the app repo), **`publish:github:pull-request`** (the PR-to-registry action, standard not custom),
  `debug:log`. *Custom `platform:*`* (backend plugins in the app image, for what the additive publish can't
  do): `verify-team-membership` (server-side authz spine, on every team-scoped template),
  `resolve-release-digest`, `add-service-resource`, `set-lifecycle-phase`, `offboard-person` (delete),
  `deprovision-product` (fan-out delete).
- **Traced (new-product):** form (team/product/service/language/deployStrategy) → verify-team-membership →
  fetch shared + language skeletons → `publish:github` (new repo) → fetch `platform-skeleton` → PR adds
  `Product` (`spec.repo`, `tenancy`, `domains:[]`) + first `XEnvironment` (**image omitted** = first-deploy;
  the ApplicationSet skips the pair until a signed digest exists). On merge → registry-sync → Crossplane.

## Self-service with guardrails

- **Schema constrains the ask** — you can only pick a stage in your envelope, an engine in `allowedEngines`, a
  product your team owns. Illegal requests are inexpressible.
- **PR by blast radius** — ≤-staging promotion of a signed digest / non-prod resource **auto-merge**; envelope
  grants + drains **reviewer-merged**; prod promotion (release-approver, author≠approver) + product purge +
  offboard **named approval**.
- **Derive-not-specify** (ADR-069): name intent → platform derives ECR `team-<team>/<product>-<svc>`, namespace
  `<team>-<product>-<stage>`, Kyverno scope, OIDC role, and least-privilege **IAM** (deny-set-validated,
  ADR-073). One truth (`argocd-apps`/`policy`/`github-oidc` all read the `Product`), no drift.
- **Four authz layers:** portal permission policy → server-side `verify-team-membership` → gitops **Gate**
  (schema + envelope shift-left: team-matches-product, stage/tier/quota-in-envelope + Composition render) →
  **Kyverno** re-enforces at admission.

## Status ledger

- **Live:** Backstage Phase 2 (`backstage.aws.refplat.org`, direct Keycloak OIDC, catalog projection v3,
  K8s/ArgoCD/Cost plugins); scaffolder **enabled** (team members self-serve non-privileged templates; `new-team`/offboard admin-gated); new-product/new-environment/new-resource/
  request-promotion proven e2e (ADR-062 Phase 3 #278–285; `alpha/shop` 2026-06-14).
- **Known gaps (template headers):** `new-product` repo-creation 403s (scaffolder GitHub App not org-wide yet);
  gitops-Gate **auto-merge not armed** (a reviewer merges low-risk cases); no scaffolder template for `XAgent`
  (hand-authored). *(The gate's decommission-first / purge-completeness guard IS landed + armed — only a
  template's own header prose still reads future-tense.)*
- **Designed / not wired:** **TechDocs** serving `docs/learn/` in-portal (#938 — plugin present, not wired;
  why these docs use absolute source links); RDS database mode.

## Gotchas (quick)

- **Cost tab / a plugin "isn't in the module"** — it's in the *app repo* image; infra side is one line
  elsewhere.
- **Config key silently ignored** — no matching schema in the image; substitute the existing shape.
- **SSO 503** — single CNPG blip → cached failed discovery → `rollout restart deploy/backstage`.
- **`new-product` repo-creation 403** — GitHub App not org-wide; the registry PR still opens.
- **Catalog lag** — entities project from *merged* git, not open PRs.

## Go deeper

Deep dives: [the Backstage portal](deep-dive-the-backstage-portal.md) ·
[the scaffolder golden paths](deep-dive-the-scaffolder-golden-paths.md). Skill: `backstage-portal`. ADRs:
[046](../../adrs/046-back-stack-for-developer-self-service.md) ·
[051](../../adrs/051-backstage-developer-portal.md) · 062 · 069 · 073. Related:
[domain model](../domain-model/orientation.md) · [Environment API](../environment-api/orientation.md) ·
[Delivery](../delivery/orientation.md) · [Onboarding a Product](../products/orientation.md). External:
[Backstage](https://backstage.io/docs/overview/what-is-backstage) ·
[Software Templates](https://backstage.io/docs/features/software-templates/) ·
[Software Catalog](https://backstage.io/docs/features/software-catalog/).

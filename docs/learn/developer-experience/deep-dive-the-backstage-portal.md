# Learn: Developer Experience — the Backstage portal (deep dive)

> Assumes the [Developer Experience orientation](orientation.md) — the paved road (*intent in, a PR out,
> reconciled infra*), the **BACK stack**, and the storefront-over-a-warehouse frame. This dive stays on **Stop 1**:
> the single pane of glass. We open the module, trace the config, and get the one thing everyone gets wrong —
> *which repo owns what* — nailed down.
>
> **Already fluent in Backstage + our deploy?** The terse lookup lives in the
> [`backstage-portal` house skill](../../../.claude/skills/backstage-portal/SKILL.md) and the module
> [README](https://github.com/asanexample/platform/blob/main/infra/modules/backstage/README.md).

## The idea: build the control plane first, then a thin window onto it

The platform underneath a developer is deliberately deep — [Crossplane](https://docs.crossplane.io/) provisions
environments, [ArgoCD](https://argo-cd.readthedocs.io/) delivers apps, [Kyverno](https://kyverno.io/) enforces
admission, Keycloak does identity, the LGTM+P stack does observability. Each is the *right* tool, each with its
own CLI, CRD, and mental model. A developer who must learn *all five* to ship one service has, in effect, **no
platform**. So the platform grows a **single place** to see what teams, products, apps, and infrastructure exist,
who owns them, and their state. That's the **B** in the **BACK stack** (Backstage → ArgoCD →
Crossplane → Kubernetes, [ADR-046](../../adrs/046-back-stack-for-developer-self-service.md)), and its adoption
is [ADR-051](../../adrs/051-backstage-developer-portal.md).

> **The metaphor for this dive: an airport control tower.** The tower is *one vantage point* over the whole
> operation — the planes, the trucks, the runways (Crossplane, ArgoCD, Kyverno). Controllers see everything and
> coordinate, but they are **never on the tarmac** turning bolts. **Where it breaks:** a real tower issues
> binding clearances by radio — it *acts*. Backstage does not. It can *see* the tarmac and *place an order* (a
> PR), but it holds no wrench and pushes no plane. That constraint is the whole design, and it's why
> [ADR-046](../../adrs/046-back-stack-for-developer-self-service.md) built the **control plane first** and
> explicitly **rejected** a portal that fires imperative pipelines (alternative #3: "the *C* is the point").
> The storefront-over-a-warehouse from the orientation is the *ordering* half of the same rule; the tower is the
> *seeing* half.

Everything below is a consequence of "thin window, control plane first."

## The confusion that costs everyone an hour: two repos, one portal

**The single most common wrong turn** is grepping this infra repo for a portal feature and finding nothing. That's
because there are *two* repos:

- **The Backstage *app*** — `asanexample/backstage` — is its own repo: the image, the custom plugins, the Cost
  tab, the frontend, and the config *schema*. Its CI builds the app and **cosign-signs + SBOMs** the image to the
  platform ECR (`platform/backstage`), like any first-party workload.
- **This infra repo** controls only the **deployment** — the Helm module and its config. The module is
  [`infra/modules/backstage`](https://github.com/asanexample/platform/blob/main/infra/modules/backstage/main.tf)
  (`main.tf`, `variables.tf`, `README.md`), driven by the live unit
  [`.../platform/backstage/terragrunt.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/platform/us-east-1/platform/backstage/terragrunt.hcl).

So "I grepped the `backstage` module and the Cost tab isn't there" is the wrong-place error: the plugin ships in
the *app image*; the infra side is often a single line in a *different* unit (we'll see it below).
**Rolling a new portal build** is therefore an *image bump*: point `image_tag` at a new `asanexample/backstage`
commit SHA and `terragrunt apply` — no GitOps drift-correction, because…

## …Backstage is deployed by Terragrunt, *not* GitOps — on purpose

Backstage is **platform infrastructure**, like ArgoCD or cert-manager — not a tenant app. So the module is a
Terragrunt `helm_release` of the official `backstage/backstage` chart running *our* signed image, like every
other platform add-on. The reason is a bootstrapping cycle you must not create: **the portal
observes ArgoCD, so it must not depend on the very ArgoCD it observes.** Put Backstage in the GitOps loop and a
cold start deadlocks — ArgoCD can't come up cleanly while the thing watching it is waiting on ArgoCD. Terragrunt
breaks the cycle ([ADR-051](../../adrs/051-backstage-developer-portal.md), "Deploy via Terragrunt, not GitOps").

What the module actually stands up, from `main.tf`:

- **The Helm release** — port `7007`,
  [`ClusterIP`](https://kubernetes.io/docs/concepts/services-networking/service/). Ingress is the **Cilium
  Gateway** via an `HTTPRoute` (`gateway.networking.k8s.io`), **not** a Kubernetes `Ingress`; it's
  Tailscale-internal only, at `backstage.aws.refplat.org`. The chart's bundled bitnami Postgres is disabled — we
  bring our own.
- **An in-cluster Postgres** — a [CloudNativePG](https://cloudnative-pg.io/documentation/current/) `Cluster`
  (`backstage-db`, one instance → the pod `backstage-db-1`). Backstage creates **a database *per plugin*** at
  startup, so its app role needs `CREATEDB`; superuser access is off, so the module grants it declaratively via a
  CNPG **managed role** rather than an imperative `ALTER ROLE`. Backups are Barman Cloud → S3
  ([#1119](https://github.com/asanexample/platform/issues/1119)). `database.mode = "rds"` is the *planned* prod
  toggle; dev runs CNPG in-cluster today.
- **Five ExternalSecrets** projecting one credential each from AWS Secrets Manager *by path* — the OIDC client
  secret (`platform/keycloak/backstage-oidc`), the read-only GitHub App, the scaffolder write App, the ArgoCD
  read-only token, and the audit-DB DSN.
- **An EKS Pod Identity *reader* role** — the pod's AWS identity, granted via a
  [Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) association, **not** an
  IRSA ServiceAccount annotation ([ADR-047](../../adrs/047-pod-identity-as-aws-identity-standard.md)).

Live, that's exactly two pods and the route:

```text
$ AWS_PROFILE=platform kubectl --context platform -n backstage get pods,httproute
NAME                             READY   STATUS    RESTARTS   AGE
pod/backstage-795f85f797-27rbd   1/1     Running   0          …
pod/backstage-db-1               2/2     Running   0          …

NAME                                          HOSTNAMES                       AGE
httproute.…/backstage                         ["backstage.aws.refplat.org"]   …
httproute.…/backstage-redirect                ["backstage.aws.refplat.org"]   …
```

## The config model — and the trap inside it

Here's the mechanism that governs *what you can and can't change from infra*. The image ships
`app-config.production.yaml` with the full shape — plugins, catalog, auth — using `${ENV}` placeholders. Crucially,
**the config *schema* is inline JSON in the image's `package.json`** (`configSchema`) — there are no external
schema files. The module renders an **`appConfig` ConfigMap** (an extra `--config` layer the chart appends to the
chain) and injects env vars for the placeholders.

The good consequence: **feature toggles and cluster/instance lists are *unit variables*** — flip
`enable_argocd_plugin`, add a cluster to `kubernetes_clusters`, set `projection_mode` — all with **no image
rebuild**. The module composes four such `appConfig` layers (OIDC session, Kubernetes, ArgoCD, projection mode)
and merges them.

The trap: **a config key with no matching schema is *silently ignored*.** No error, no warning — the feature just
looks broken. You cannot invent a brand-new config *section* from the infra side; you can only substitute against
the shape the image already declares, or ship the new schema in the app repo first. When a knob you added "does
nothing," this is almost always why.

## The catalog is a *projection of git* — not a cluster scrape

This is the key design decision, and it's what keeps the tower honest. The Software Catalog is **not** built by
scraping the cluster. A custom backend **entity provider** (`platform-projection`, which lives in the *app* repo)
reads *this* repo's git-native registries through the **read-only GitHub App** — **no AWS, no cluster
credential** — and projects three kinds:

| Git source | Catalog entity |
| --- | --- |
| `gitops/teams/<team>.yaml` (`Team`) | **Group** |
| `gitops/products/<team>/<product>.yaml` (`Product`) | **System** |
| `gitops/environments/<team>/<product>/<stage>.yaml` (`XEnvironment` claim) | **Environment** (custom kind) |

*Two other mechanisms fill in the rest of the graph — **not** the credential-free git projection above:*
an app repo's `catalog-info.yaml` becomes a **Component** via **GitHub discovery**, and the **Kubernetes
plugin** surfaces Crossplane-composed AWS resources (S3/SQS/SNS/DynamoDB) on an Environment's Kubernetes
*tab* — and *that* one **does** use cluster/AWS credentials (on the cross-account workload clusters).

So the browse experience is a **direct rendering of the [domain model](../domain-model/orientation.md)** —
Team → Product → Service → Environment ([ADR-067](../../adrs/067-idp-domain-model.md)). Why projection over
scrape? Because **git is the source of truth**: the catalog stays correct with no privileged cluster access and
*cannot drift* from what's declared. A guardrail rides along — `catalog.rules: [Component, Location]` — so an app
repo can register a `Component` but **not** spoof a `Group` or `System` (no ownership forgery).

The live registries today: teams **alpha / bravo / platform**, their products (alpha's `shop`, `checkout`,
`conformance`; bravo's `widgets`; platform's `triage-copilot`), and their environments. The projection runs in
**`projection_mode = "v3"`** — set as a *unit flag*, not baked into the image (the v3 code already ships dormant;
`v2 → v3` needed **no rebuild**).

## Auth: direct Keycloak OIDC — and a superseded-decision trap

**Read the ADR body carefully here, because most of it is wrong on purpose.** [ADR-051](../../adrs/051-backstage-developer-portal.md)'s
Decision section describes Identity-Center → **Dex** (SAML→OIDC) with an oauth2-proxy session-cookie workaround
([#202](https://github.com/asanexample/platform/issues/202)). **That is all retired.** The ADR carries a
**2026-06-27 amendment** saying so: Dex and the oauth2-proxy are removed
([ADR-053/059](../../adrs/053-identity-and-cross-system-authorization-strategy.md) supersede the ADR-052 broker).
This is the "secondary sources are leads, not proof" rule from the [mold](../_mold.md) made concrete — the ADR's
own header amendment overrides its own body.

**What is actually live:** Backstage authenticates **directly** against Keycloak — the `oidc` sign-in provider, a
confidential `backstage` client, issuer on the `platform` realm at `keycloak.aws.refplat.org`, with the **groups
claim** driving ownership and RBAC. Keycloak brokers any upstream IdP invisibly
([ADR-059](../../adrs/059-identity-topology-pluggable-idp-seam.md)). Two secrets make it work: the client secret, synced
from `platform/keycloak/backstage-oidc` (created by the `keycloak-config` unit) into `OIDC_CLIENT_SECRET`; and a
Terraform-generated `AUTH_SESSION_SECRET` that signs the session cookie — the OAuth handshake stores state in a
cookie, so the provider errors with *"authentication requires session support"* without it. Because Backstage now
authenticates **every request itself**, the pod needs **no ingress NetworkPolicy** and the old oauth2-proxy `:7007`
lockdown is gone — the gateway routes straight to it.

One sharp edge worth understanding — the **split-horizon host alias.** The OIDC issuer host
(`keycloak.aws.refplat.org`) is pinned via a pod `hostAlias` to the **gateway's ClusterIP**, so the backend's
token exchange hits the gateway Envoy directly instead of the flaky internal-NLB hairpin — while TLS still
validates the wildcard cert. The ClusterIP is **looked up dynamically** from the gateway Service on every apply
(a `data.kubernetes_service_v1` read), *never hardcoded* — so it self-heals if the Service is recreated.

RBAC ([#197](https://github.com/asanexample/platform/issues/197)): the permission framework plus a permission
policy gates each run to the requester's own team. Team members can run the **non-privileged** templates
(new-environment / new-resource / request-promotion / new-product); **privileged** ones (`new-team`,
offboarding) set `requireAdmin` and are admin-gated server-side. *(A live unit comment still reads
"admin-only" — the per-template gating the template headers encode supersedes it; the deployed permission
policy in the app image is the final arbiter.)*

## The plugins — read-only, scoped, never cluster-admin

Every live plugin is a *window*, granted the narrowest credential that shows the view. Four surfaces:

**Kubernetes plugin** — live workload/health. It uses the pod's EKS Pod Identity **reader** role
(`AmazonEKSViewPolicy`, which **excludes Secrets** on the platform cluster) and *assumes* a cross-account
read-only `Backstage` role to reach **preprod**. Two edges the module documents in comments:

- **(a)** the cluster `name` **must be the real EKS cluster name** (`platform-use1-eks` / `preprod-use1-eks`),
  because Backstage's AWS auth sends it as the EKS token's `x-k8s-aws-id` — a *display* name like `"preprod"`
  yields a token for the wrong cluster and the API returns **401**.
- **(b)** `skipMetricsLookup: true`, because the view policy can't reach `metrics.k8s.io` and the optional
  pod-metrics call would spuriously 403.

It also surfaces Crossplane-composed AWS resources (S3/SQS/SNS/DynamoDB) on an Environment's Kubernetes tab — but
**only on the cross-account *workload* clusters**, because the platform cluster doesn't run the environment-API
CRDs, so a global `customResources` query 403s there (authz denies the unserved group). Scoped per-cluster to the
`assume_role` clusters, exactly for that reason.

**ArgoCD plugin** (Roadie) — reads the self-hosted ArgoCD over the *in-cluster* HTTP API with a read-only token
(account `backstage`, `role:readonly`), synced from `platform/argocd/backstage-token`. Components link via an
`argocd/app-selector` annotation; `frontend_url` gives working "open in ArgoCD" links (the backend URL is
unreachable from a browser). **Gotcha:** a Helm 3-way merge can drop the token id from `argocd-cm` after an apply
→ the card 401s → re-mint (runbook `backstage-argocd.md`).

**Cost tab** ([ADR-091](../../adrs/091-cost-guardrails.md) A3) — **the canonical check-the-right-code
case.** The plugin **ships in the app image**, so grepping the infra `backstage` module finds *nothing*. The
entire infra side is **one line in a different unit** — the `mimir` unit:

```hcl
# ADR-091 A3: admit Backstage's Cost tab to query the Mimir gateway directly (the ns default-denies ingress).
query_consumer_namespaces = ["backstage"]
```

That admits the `backstage` namespace to query the hub Mimir gateway (the `observability` namespace default-denies
ingress). The tab renders spend against the budget the team declared in `Team.spec.envelope.budget`. ADR-091 is
**Accepted / built + live** — though ADR-091's *"Remaining"* prose still lists the Cost tab, which is
stale (ADR-092 already treats it as existing).

**Audit / My-Access view** ([ADR-088](../../adrs/088-temporary-power-activation.md)) — reads *borrow history* from
the ADR-084 `platform-directory` Postgres via `AUDIT_DB_DSN`, and drives the temporary-power **Activate-Power**
flow. This is the **one exception** to the otherwise read-only posture: the `backstage` ServiceAccount is bound
(via a `backstage-activators` group, create-only on `Activation` objects) with a single narrow **write**
capability. Everything else the pod can do is a read.

## The honest status — live vs designed

- **Live** (verified on the platform cluster this session): Backstage Phase 2.0–2.4 at
  `backstage.aws.refplat.org`, Tailscale-internal behind the Cilium Gateway `HTTPRoute`, pod `Running`; **direct
  Keycloak OIDC** (Dex + oauth2-proxy retired); catalog **projection v3**; Kubernetes / ArgoCD / Cost plugins +
  the audit view enabled; CNPG-backed single instance (`backstage-db-1`) with S3 Barman backups. The
  **Scaffolder** is `enable_scaffolder = true` (BACK Phase 3), with ten templates in-repo under
  [`scaffolder/templates/`](https://github.com/asanexample/platform/tree/main/scaffolder/templates) — note ADR-051's
  Decision still frames the Scaffolder as "Phase 3 / read-only until then," which *predates* enablement.
- **Designed / not wired:** **TechDocs** — the plugin exists in the image (the backend even reserves a `techdocs/`
  working dir) **but** serving *this* learning corpus through it is a separate open effort
  ([#938](https://github.com/asanexample/platform/issues/938)), **not built**. It's why these docs use absolute,
  `main`-pinned source links: they survive the eventual move into TechDocs. Also: **RDS database mode** is a
  planned follow-up (dev runs CNPG today).

## Gotchas that teach

- **"I added a config key in the module and the feature does nothing."** A config key with no matching schema in
  the image is **silently ignored**. You substitute against the image's existing shape; you can't invent a config
  section from infra. Ship the schema in the app repo first.
- **"The Cost tab / a plugin isn't in the backstage module."** Right — it's in the *app* image. The infra side is
  usually one line in a *different* unit (Cost = the `mimir` unit's `query_consumer_namespaces`). Two repos.
- **"Backstage sign-in 503s."** The backing Postgres is a **single CNPG instance**; after a keycloak-db blip the
  `openid-client` can cache a *failed* discovery and wedge → `kubectl rollout restart deploy/backstage`. Keep this
  one resident — single-instance auth DBs are fragile.
- **"The Kubernetes plugin 401s on a cluster."** The cluster `name` must be the **real EKS cluster name**
  (`platform-use1-eks` / `preprod-use1-eks`) — it's the EKS token's `x-k8s-aws-id`. A display name silently
  targets the wrong cluster.
- **"The ADR says Dex / oauth2-proxy."** The **body** does; the **2026-06-27 amendment** retires it. Read ADR
  headers/amendments *before* the body — this is the mold's "secondary sources are leads, not proof" in one page.

## Go deeper

- **ADRs (source of truth):** [ADR-046 BACK stack](../../adrs/046-back-stack-for-developer-self-service.md) ·
  [ADR-051 Backstage-as-portal](../../adrs/051-backstage-developer-portal.md) (**read the amendment first**) ·
  [ADR-048 federated Crossplane](../../adrs/048-federated-per-cluster-crossplane.md) ·
  [ADR-067 domain model](../../adrs/067-idp-domain-model.md) ·
  [ADR-088 temporary access](../../adrs/088-temporary-power-activation.md) ·
  [ADR-091 cost visibility](../../adrs/091-cost-guardrails.md).
- **The code:**
  [`infra/modules/backstage/main.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/backstage/main.tf) ·
  [`variables.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/backstage/variables.tf) ·
  the [live unit](https://github.com/asanexample/platform/blob/main/infra/live/aws/platform/us-east-1/platform/backstage/terragrunt.hcl) ·
  the [`mimir` unit](https://github.com/asanexample/platform/blob/main/infra/live/aws/platform/us-east-1/platform/mimir/terragrunt.hcl)
  (the Cost-tab one-liner) · the [`gitops/` registries](https://github.com/asanexample/platform/tree/main/gitops).
- **The house skill:** [`backstage-portal`](../../../.claude/skills/backstage-portal/SKILL.md) — the operator
  lookup for enabling a plugin, wiring auth, or bumping the image.
- **Substrate docs** (curl-verified): [What is Backstage](https://backstage.io/docs/overview/what-is-backstage)
  (~5 min) · [Software Catalog external integrations](https://backstage.io/docs/features/software-catalog/external-integrations)
  (projection-style providers; ~10 min) · [Backstage OAuth](https://backstage.io/docs/auth/oauth)
  (the session-support requirement; ~5 min) ·
  [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) ·
  [CloudNativePG](https://cloudnative-pg.io/documentation/current/) ·
  [Roadie ArgoCD plugin](https://roadie.io/backstage/plugins/argo-cd/).
- **Next door:** the [scaffolder deep dive](deep-dive-the-scaffolder-golden-paths.md) covers Stop 2 (the golden
  paths); the [domain model](../domain-model/orientation.md) is the vocabulary this catalog renders.

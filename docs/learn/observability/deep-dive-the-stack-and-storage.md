# Learn: Observability — the stack & storage (deep dive)

> Assumes the [Observability orientation](orientation.md) — the four signals, the "platform observes
> you for free" idea, and the LGTM+P names. This deep dive opens up **Stop 3**: the five backends, where
> the bytes actually live, how one Grafana fronts them all, and the one subtle thing (tenancy) that is *not*
> what it looks like. Already fluent in Mimir/Loki/Tempo? The terse per-module facts are in the
> [Reference](reference.md); this is the teaching pass.

The orientation gave you a one-line promise: *"stored together in one correlated stack on the platform's own
storage."* That sentence hides five separate databases, a bucket per signal, an SSO login, a tenancy model
that's really a network-security model in disguise, and a hub-and-spoke shape that lets a second cluster ship
its telemetry home. This doc walks all of it — and, because per-team isolation is the domain's subtlest
claim, it draws a sharp line between what's live-and-carrying-data (metrics + logs isolation, plus
grant-based cross-team sharing) and what's deferred (per-team traces + profiles isolation).

## The one idea for this doc

> **Every signal is stored the same way: a purpose-built open-source database keeping a *small hot buffer*
> on a local disk and flushing the *durable truth* to its own S3 bucket — and all five are fronted by one
> Grafana. The database is disposable; S3 is the source of truth.**

That single shape repeats five times with small variations, so once you understand *one* store you
understand them all. Let's anchor on Mimir (metrics), then show the others as variations on the theme.

## The five backends, and what each one holds

The stack is **LGTM+P** — and each letter is a separate database, pinned to a specific chart version in the
repo's single source of truth, [`infra/live/aws/_versions.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/_versions.hcl):

| Signal | Store | Helm chart (pin) | What it stores | Its S3 bucket |
| --- | --- | --- | --- | --- |
| the view | **Grafana** | `kube-prometheus-stack` **87.5.0** | nothing durable — dashboards/datasources as code | (its SQLite state is on a small PVC) |
| metrics | **Mimir** | `mimir-distributed` **6.0.6** | TSDB **blocks** (compacted time-series) | `…-mimir-blocks-…` |
| logs | **Loki** | `loki` **7.0.0** | log **chunks** + TSDB index | `…-loki-chunks-…` |
| traces | **Tempo** | `tempo-distributed` **2.25.5** | trace **blocks** | `…-tempo-traces-…` |
| profiles | **Pyroscope** | `pyroscope` **2.1.0** | profile blocks (flame-graph data) | `…-pyroscope-profiles-…` |

Grafana rides inside the `kube-prometheus-stack` bundle (which also brings Prometheus, Alertmanager,
node-exporter, kube-state-metrics). Mimir, Loki, Tempo, and Pyroscope are each their own Terragrunt unit and
their own module (`observability-mimir`, `-loki`, `-tempo`, `-pyroscope`). On the live hub they show up
exactly as you'd guess — the microservices fan out for Mimir and Tempo, single-binary for Loki and Pyroscope:

```text
$ kubectl -n observability get pods            # platform (hub), abridged
mimir-compactor-0                 1/1  Running
mimir-distributor-…               1/1  Running
mimir-gateway-…                   1/1  Running
mimir-ingester-0                  1/1  Running
mimir-querier-…                   1/1  Running
mimir-query-frontend-…            1/1  Running
mimir-query-scheduler-…           1/1  Running
mimir-store-gateway-0             1/1  Running
loki-0                            2/2  Running
loki-gateway-…                    1/1  Running
tempo-distributor-…               1/1  Running
tempo-ingester-0                  1/1  Running
tempo-metrics-generator-…         1/1  Running
pyroscope-0                       1/1  Running
kube-prometheus-stack-grafana-0   3/3  Running
```

> **Quick check:** if `mimir-ingester-0` crashes and its PVC is wiped, how much metric history do you lose?
> *A few minutes* — only the un-flushed working set. Everything already compacted to blocks is safe on S3.
> The store is cattle; S3 is the herd.

## Storage: a small gp3 hot buffer, a big cheap S3 tail

Take Mimir as the template. Its
[`observability-mimir` module](https://github.com/asanexample/platform/blob/main/infra/modules/observability-mimir/main.tf)
gives the stateful components — `ingester`, `store-gateway`, `compactor` — a **gp3 PersistentVolume** each
(10Gi / 10Gi / 20Gi). That's the *working set*: the ingester's in-memory-plus-WAL window before a block is
cut, the store-gateway's local cache of block indexes, the compactor's scratch space. It is deliberately
tiny, because it is not where the data *lives*.

Where the data lives is **S3**. Mimir's `blocks_storage` points at a dedicated bucket (`bucket_prefix =
"<cluster>-mimir-blocks-"`); Loki chunks, Tempo traces, and Pyroscope profiles each get their own
cluster-scoped bucket the same way. One bucket per signal, per cluster — so a blast radius, a lifecycle
policy, or an IAM scope is always about exactly one thing. This is the *owning-the-generator* choice from the
orientation made concrete: the durable tier is object storage you already pay pennies for, not a metered
vendor.

### SSE-S3, spelled out on every write — and why

Here's a gotcha that will bite anyone who copies half of it. Every store's S3 config carries an explicit
line — Mimir's reads `sse = { type = "SSE-S3" }`, and Loki/Tempo/Pyroscope say the same. You might assume the
bucket's *default* encryption (also set, AES256) makes this redundant. It doesn't, and the reason is an **org
Service Control Policy**: `enforce-encryption` (`DenyUnencryptedS3Uploads`) rejects any `PutObject` whose
**request** omits the `x-amz-server-side-encryption` header. Default bucket encryption encrypts the object at
rest but does *not* add that header to the request — so without the explicit client-side `sse`, every write
is denied by the SCP and the store silently fails to persist. Belt (default encryption) *and* suspenders
(explicit request header), because the SCP checks the suspenders.

The choice of **SSE-S3 (AES256)** over SSE-KMS is also deliberate: AES256 needs no per-object KMS call and,
crucially, needs **no KMS IAM permission** on the store's role. An SSE-KMS bucket would force every store to
carry `kms:GenerateDataKey*`/`Decrypt` or its writes would `AccessDenied` — extra permission surface and
per-object cost on a high-churn store, for no benefit here.

### The auth: Pod Identity, no IRSA, no keys

How does the ingester get credentials to write that bucket? **[EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)**
([ADR-047](../../adrs/047-pod-identity-as-aws-identity-standard.md)), the platform's standard AWS-identity
mechanism. In the module you'll see the ServiceAccount created with `annotations = {}` — *pointedly* empty,
because the old IRSA way stamped an `eks.amazonaws.com/role-arn` annotation there. Instead an
`aws_eks_pod_identity_association` binds the tuple `(namespace, service-account) → IAM role`, and the role
trusts the service principal `pods.eks.amazonaws.com` (with `sts:AssumeRole` + `sts:TagSession`). The AWS SDK
inside the pod picks the credentials up from the container-credentials chain — no static keys, no OIDC
provider wiring, no annotation. The role's policy is scoped to exactly that one bucket
(`s3:GetObject`/`PutObject`/`DeleteObject` on `<bucket>/*`, `ListBucket` on the bucket) and — because AES256 —
carries **no KMS statement at all**.

## The metrics twist: Prometheus scrapes, Mimir keeps

Metrics have one extra move the other three signals don't, and it's the heart of
[ADR-044](../../adrs/044-mimir-durable-multi-tenant-metrics.md). **Prometheus is still the scraper** — it
pulls `/metrics` off every target — but it keeps only **~15 days** of local TSDB (the module's
`prometheus_retention` default) and **`remote_write`s every sample to Mimir**, which holds the long tail on
S3. So Grafana's **default datasource is Mimir, not Prometheus**: the module provisions the Mimir datasource
with `isDefault = true`, and Prometheus stays selectable for recent/local queries. Lose Prometheus and you
lose nothing but the last few minutes of scrape buffer — the truth is in Mimir/S3. It's **additive**: no
migration, Prometheus just grew a remote write.

**Why Mimir and not Thanos?** Both are OSS, object-store-backed, and mature — ADR-044 calls it defensible
either way. The deciding factor was **tenancy**. Mimir's multi-tenancy is *first-class*: a single
`X-Scope-OrgID` header names the tenant on both read and write, over one horizontally-scaled ingest path.
Thanos bolts tenancy on via a sidecar-per-Prometheus plus store-gateway federation — more moving parts to
glue for a hub, and multi-tenancy expressed through external labels rather than a native header. Since the
whole point here is *centralized writes with a clean per-tenant spine* (the spokes and, later, per-team), the
native model won. Amazon Managed Prometheus was rejected for the same reason as the SaaS options — per-sample
ingest + per-query billing, coarser IAM-shaped workspaces, AWS-only.

Mimir runs in its **classic microservices architecture** — distributor → ingester over gRPC — with
**replication factor 1** on the reference cluster. That RF1 is not an accident you should "fix": with a
single ingester the RF *must* be 1 or writes are rejected. The chart's newer default is a Kafka-based
ingest-storage path; the module explicitly turns that off (`ingest_storage.enabled = false`, `kafka.enabled =
false`) to keep the reference cluster lean. One toggle, `high_availability`, flips the whole stack up to
**RF3**, zone-aware replication, and the memcached caches when a cluster has the capacity to warrant it.

> **Quick check:** you set `high_availability = true` but leave a single ingester replica. What breaks?
> Writes get rejected — RF3 needs three ingesters to place three copies. HA is all-or-nothing; the toggle
> scales replicas *and* RF together for exactly this reason.

## Grafana: the one remote for five TVs

The orientation called Grafana the "central nurses' station." Mechanically it's a **universal TV remote** —
one device, and every store is a channel you flip to without learning five different remotes. That works
because **datasources are code**. Each store's module emits a ConfigMap labelled `grafana_datasource = 1`; a
sidecar in the Grafana pod watches for that label and provisions the datasource live. No datasource is ever
clicked into existence in the UI.

The naming is deliberate and worth internalizing, because it's how tenancy surfaces to a human. Every
datasource is named `"<Store> (<tenant>)"`:

- `Mimir (platform)` — the hub's own metrics (the default datasource, `uid = mimir`).
- `Mimir (preprod)` — a read-only view of the preprod spoke's metrics.
- `Mimir (all clusters)` — a *federated* datasource whose header is `platform|preprod`, so one panel spans
  both clusters (Mimir's `tenant_federation` splits the `|`-joined header across tenants on read).
- `Mimir (my team)` — the per-team lane through the read proxy (see the honest-status section).

Loki, Tempo, and Pyroscope follow the identical `(tenant)` scheme. And the datasources are wired to each
other for the **correlation jump** the orientation promised: the Mimir datasource carries
`exemplarTraceIdDestinations` pointing `mimir → tempo` (click a latency exemplar, land on the trace), and the
Loki datasource carries a `derivedFields` regex that turns a `trace_id` in a log line into a link to the same
Tempo trace. (The jumps themselves are the [collection & correlation](reference.md) story; here just note
that the *plumbing* is datasource config, provisioned as code.)

### Locked down, and SSO'd

Grafana is the only part of this stack a human logs into, so it's hardened in the
[`observability` module](https://github.com/asanexample/platform/blob/main/infra/modules/observability/main.tf):
anonymous access off, sign-up off, `viewers_can_edit` off, secure + `strict`-samesite cookies, CSP on. It's
reachable **Tailscale-only** — an internal-scheme NLB behind the Cilium Gateway, never a public endpoint
(same private-by-default posture as the EKS API).

Login is **Keycloak OIDC** (a `generic_oauth` block; the client secret is synced by External Secrets and
injected as an env var, never written into `grafana.ini` or state). Authorization is a one-line JMESPath over
the token's `groups` claim:

```text
contains(groups[*], 'platform-admins') && 'Admin' || 'Viewer'
```

So a member of `platform-admins` gets Grafana **Admin**; every other authenticated user gets **Viewer**. Note
the ceiling this sets up: everyone-a-Viewer means everyone can *see every dashboard and every cluster's data*.
That's fine for a platform team, and it's exactly the gap the per-team read isolation was built to close —
which brings us to tenancy.

## Tenancy: the apartment number is not a key

This is the subtle part, and the most important security fact in the whole stack. Every store has
multi-tenancy enabled (`multitenancy_enabled` on Mimir/Pyroscope, `auth_enabled = true` on Loki), and every
read and write carries an **`X-Scope-OrgID`** header naming a tenant. It is tempting to read "auth_enabled"
and think the header authenticates the caller. **It does not.**

> **`X-Scope-OrgID` is a *trust* header, not authentication** — it's the **apartment number written on a
> piece of mail.** The store delivers to whatever apartment the envelope names; it never checks whether the
> sender was allowed to write that number. **Where the metaphor breaks:** unlike a real building, there's no
> doorman at the store reading IDs. So if a tenant workload could *reach* Mimir, it could scribble any
> apartment number and read or write any tenant's data.

That means the real isolation boundary is **not the header — it's the network** ([ADR-044](../../adrs/044-mimir-durable-multi-tenant-metrics.md)
names this the single most important operational invariant). Two rules enforce it:

1. The **`observability` namespace is default-deny ingress.** No pod outside it can open a connection in.
2. The **stores are `ClusterIP` only — never on the Gateway.** Verified live: `mimir-gateway`,
   `loki-gateway`, `tempo-*`, `pyroscope`, and the proxies all report `TYPE: ClusterIP`. There is no route
   from the internet, and no route from a tenant namespace, to a store.

The one thing that *is* allowed in is the Cilium Gateway's Envoy — and even that needs a special rule,
because Envoy connects with Cilium's reserved **`ingress` identity (8)**, which a *standard* Kubernetes
NetworkPolicy `from:` clause can't express. So the module admits it with a `CiliumNetworkPolicy`
(`fromEntities: ["ingress"]`, e.g. `allow-grafana-from-gateway`) — the same Gateway-identity gotcha you'll
meet all over this platform.

The **cluster tenants are live and carrying data.** Querying the hub's Mimir gateway directly:

```text
tenant=platform   distinct_metric_names=4274
tenant=preprod    distinct_metric_names=1670
```

`platform` is the hub's own metrics; `preprod` is the spoke's, shipped home — which is the next piece.

## Hub and spoke: one door that stamps the tenant

The `platform` cluster is the **hub** — it runs *both* the collectors and all five backends. `preprod` is a
**spoke**: it runs lightweight collectors only, and ships its signals to the hub. The orientation's metaphor
holds — the hub is a *regional mail-sorting facility*; the spoke is a *neighborhood post office* that bundles
its outgoing mail and trucks it to the hub over the **Transit Gateway** (the private inter-VPC backbone).

The clever bit is the door the spoke ships *through*. For each spoke tenant, the Mimir module renders an
**HTTPRoute** on the shared Cilium Gateway whose every rule force-stamps the tenant — so a spoke can only ever
touch its *own* tenant, read or write:

- **Force-*sets* `X-Scope-OrgID`** to the mapped tenant with a `RequestHeaderModifier`, *overwriting* any
  value the client sent — on **every** rule of the route.
- **Always matches the push path** (`/api/v1/push`), and — only for tenants opted into `query_tenants` — the
  Mimir read path (`/prometheus`) too. On the live hub the `preprod` spoke has `query_tenants = ["preprod"]`,
  so it reads its *own* metrics back from the hub; because the header is force-set, that read still can't
  reach any other tenant's data.

That overwrite is the anti-spoof guard: since the edge stamps the tenant, **a spoke physically cannot touch
another tenant's data** — it can only ever land in its own. Authentication of the spoke itself is
network isolation (the internal NLB is reachable only across the VPC/TGW); mTLS is a documented hardening
follow-up, not yet in place.

## Honest status: write-split and read-isolation are both live

The orientation flagged per-team isolation as the place to be careful; here's the precise version, because a
trust artifact that over- *or* under-sells is worse than one with an honest gap.

**Per-team *write* split — LIVE, with real data.** Both environments set `enable_per_team_tenants = true`.
The mechanism is `cortex-tenant` (chart **0.8.1**, running with 2 replicas on the hub): Prometheus/Alloy
remote-write through it instead of straight to Mimir, and a two-step relabel derives a `route_tenant` label
from the pod's **namespace** — unconditionally `platform` first (so a pod can't spoof it), then overridden to
the team for environment namespaces matching `<team>-<product>-<stage>`. cortex-tenant reads that label, sets
`X-Scope-OrgID` per-series, and *strips* the label so it's never stored. The result is verifiable — the hub's
Mimir has genuinely separate per-team tenants carrying data:

```text
tenant=alpha   distinct_metric_names=136
tenant=bravo   distinct_metric_names=118
```

Those are real, isolated `alpha` and `bravo` tenants — the write split is not a diagram, it's running.

**Per-team *read* isolation — LIVE and fail-closed, for metrics *and* logs.** Two read proxies enforce it: the
[`observability-tenant-proxy`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-tenant-proxy/main.tf)
in front of Mimir and its `loki-tenant-proxy` sibling in front of Loki (each 2 replicas). Each verifies the
Grafana-forwarded OIDC token against the Keycloak JWKS, maps the caller's `groups` to a tenant scope (admin
group → all tenants; **unknown or empty → deny**), overwrites `X-Scope-OrgID`, and reverse-proxies to its
store. They provision the `Mimir (my team)` / `Loki (my team)` datasources. Genuinely **fail-closed** — no
valid token, no data — with the *enforcement* **proven live (2026-07-07)**: identity maps to exactly one tenant
and unknown callers are denied, for metrics *and* logs. (The platform hub runs no team workloads, so its own
metrics are the `platform` tenant; the real per-team tenants are populated by the **preprod spoke's dual-write**
— preprod, where the team apps run, ships each namespace's series into its own tenant, additive to `preprod`.)
*(Per-team **traces (Tempo)** and **profiles (Pyroscope)** isolation is deliberately deferred — metrics + logs
are the two live data-plane signals.)*

**Cross-team read sharing is an `AccessGrant`** ([ADR-068](../../adrs/068-product-scoped-and-cross-team-access-model.md);
claims in `gitops/grants/`). A team grants another read access to its signals, and the read proxy derives that
grant into a **federated** read — the caller queries its own tenant **∪** its granted tenants, e.g. `bravo`
reading `alpha`'s `shop` becomes `X-Scope-OrgID: alpha|bravo` (Mimir's `tenant_federation` splitting the `|`
on read), still fail-closed for anything ungranted. And because OSS Grafana has **no per-team dashboard RBAC**,
this grant *is* the data-and-dashboard sharing mechanism — there is no other lane to share a tenant's signals
across the team boundary. Alongside it, the namespace-filtered overview dashboards remain each team's everyday
*default* self-view. Say it plainly: real per-team read isolation and real grant-based sharing, for metrics and
logs — with traces/profiles still to come.

## Why self-host all of this at all?

The whole doc is downstream of one decision ([ADR-043](../../adrs/043-self-hosted-observability-stack.md)):
run the stack yourself instead of shipping everything to Datadog or Grafana Cloud. The trade, stated bluntly
in the ADR, is *"we operate it."* Three reasons it's worth that:

- **Cost.** A SaaS observability bill is a **metered utility** — the meter spins per host and per series, and
  at platform scale (many teams × many services × high cardinality) that meter becomes the *dominant*
  platform cost. Self-hosting is *owning the generator*: you pay compute you already run plus pennies of S3.
- **Residency.** The telemetry never leaves your AWS account — it sits in your own buckets under your own IAM.
- **Portability.** Dashboards, alerts, and datasources are code in the repo; the stack is OSS and moves across
  clouds. No vendor lock-in on the thing you stare at during every incident.

The modules keep a `metrics_backend`-style seam open, so if the ops burden ever outweighs the win on a given
cluster, switching to managed is a config change, not a rewrite.

## Gotchas that teach

- **Default bucket encryption is not enough — send `sse` explicitly.** The `enforce-encryption` SCP checks the
  *request header*, which bucket defaults don't add. Every store spells out `sse = { type = "SSE-S3" }`; omit
  it and writes silently `AccessDenied` at the SCP.
- **SSE-S3 over SSE-KMS is a permissions decision.** AES256 means the store's IAM role needs **zero KMS
  actions**. Switch a bucket to SSE-KMS and every store starts failing writes until you add
  `kms:GenerateDataKey*`/`Decrypt`.
- **The empty ServiceAccount annotation is intentional.** `annotations = {}` is the *tell* that this is Pod
  Identity, not IRSA — the association binds `(ns, SA) → role` out-of-band. Don't "helpfully" add an
  `eks.amazonaws.com/role-arn` back; on an environment namespace Kyverno would reject it anyway.
- **RF must match replica count.** RF1 with one ingester is correct; flipping `high_availability` scales
  replicas *and* RF together. A lone ingester at RF3 rejects every write.
- **`X-Scope-OrgID` isolates nothing on its own.** Isolation is the default-deny namespace + ClusterIP-only
  stores. A single over-broad NetworkPolicy or one store accidentally exposed on the Gateway would collapse
  the entire tenancy model — which is why ADR-044 calls the network boundary *the* invariant.
- **The Gateway needs a `CiliumNetworkPolicy`, not a NetworkPolicy.** Envoy's reserved `ingress` identity (8)
  is invisible to a standard `from:` clause. Every store that admits Gateway traffic uses `fromEntities:
  ["ingress"]`.
- **Grafana Viewer-for-everyone is by design — per-team reads are fenced *below* Grafana.** Grafana itself has
  no per-team RBAC (every authenticated non-admin is a Viewer). The per-team boundary is enforced at the
  fail-closed **tenant-proxies** (Mimir + Loki, live): the `(my team)` datasources show a caller only its own
  tenant ∪ any `AccessGrant`-ed tenants. The namespace-filtered overview dashboards are the convenient default
  view on top of that.

## Go deeper

- **ADRs (source of truth):** [ADR-043](../../adrs/043-self-hosted-observability-stack.md) (self-hosted
  stack), [ADR-044](../../adrs/044-mimir-durable-multi-tenant-metrics.md) (Mimir + the tenancy invariant),
  [ADR-047](../../adrs/047-pod-identity-as-aws-identity-standard.md) (Pod Identity). As-built:
  [observability-current-state](../../architecture/observability-current-state.md).
- **Module code:**
  [`observability`](https://github.com/asanexample/platform/blob/main/infra/modules/observability/main.tf) (Grafana + Prometheus + Alertmanager),
  [`observability-mimir`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-mimir/main.tf),
  [`observability-loki`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-loki/main.tf),
  [`observability-tempo`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-tempo/main.tf),
  [`observability-pyroscope`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-pyroscope/main.tf),
  [`observability-cortex-tenant`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-cortex-tenant/main.tf),
  [`observability-tenant-proxy`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-tenant-proxy/main.tf).
- **Upstream docs** (all newer than our pins, but the concepts are stable):
  [Grafana Mimir](https://grafana.com/docs/mimir/latest/) ·
  [Mimir architecture](https://grafana.com/docs/mimir/latest/get-started/about-grafana-mimir-architecture/) (~15 min — the microservices/RF model above) ·
  [Mimir authentication & multi-tenancy](https://grafana.com/docs/mimir/latest/manage/secure/authentication-and-authorization/) (~10 min — the `X-Scope-OrgID` trust-header behaviour, first-hand) ·
  [Loki](https://grafana.com/docs/loki/latest/) · [Tempo](https://grafana.com/docs/tempo/latest/) ·
  [Pyroscope](https://grafana.com/docs/pyroscope/latest/) ·
  [cortex-tenant](https://github.com/blind-oracle/cortex-tenant) (the per-team write-split proxy) ·
  [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) (~10 min).
- **Back to the map:** the [Observability orientation](orientation.md) and the [Reference](reference.md).

# Learn: Observability — correlation & the team experience (deep dive)

Two ideas share this file because they're both the *consuming* side of observability — what an
engineer does with the stack once the signals are flowing. First, correlation: the machinery that
turns five stores into one investigation. Second, the per-team experience, where the subtle
build-vs-live nuance lives.

---

## Part 1 — correlation: the detective's case-file hyperlinks

Correlation works like a detective's case file where every clue hyperlinks to the next. The vitals
blip links to the ECG strip, which links to the lab result, which links to the tissue sample —
four stores, one click each, no re-typing a query into a different tool. That's the whole payoff of
running one Grafana over five backends instead of five vendor consoles.

Those hyperlinks aren't a Grafana feature you turn on — they're config you write into each
datasource. Grafana correlation is a set of directed links: on *this* datasource, a value shaped
like *that* opens *this other* datasource. The platform wires four of them. Here's the 4-click
investigation, and the exact wiring behind each click.

### Click 1: a RED spike → the exact trace (metric → trace, via exemplars)

You're staring at a latency panel. A p99 spike. On most stacks that's a dead end — the metric is an
*aggregate*, it averaged away the one slow request you care about. The fix is an **exemplar**: alongside
the aggregated histogram, the metric store keeps a handful of *sample* data points, each tagged with the
**trace ID** of one real request that landed in that bucket. The spike carries clickable dots.

Two halves make this real. The **producer** is Tempo's metrics-generator — it derives the RED
span-metrics from traces and stamps each exemplar with a `traceID` label. The **consumer** is the Mimir
datasource, told where that trace ID can be opened. From
[`observability-mimir/main.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-mimir/main.tf):

```hcl
exemplarTraceIdDestinations = [{
  name          = "traceID"                        # the exemplar label the generator emits (camelCase)
  datasourceUid = replace(ds.uid, "mimir", "tempo")
}]
```

That `replace(ds.uid, "mimir", "tempo")` is what makes the correlation web scale to any number of
tenants. Datasource UIDs follow a **convention** — `mimir`, `mimir-preprod`, `mimir-all` — and every
jump is a *string swap*, not a hard-coded target. The `platform` tenant's Mimir links to the `platform`
tenant's Tempo (`mimir`→`tempo`); the `preprod` tenant's Mimir links to `preprod`'s Tempo
(`mimir-preprod`→`tempo-preprod`); neither line of config names the other. The wiring is a *rule*, not a
table. (Exemplar storage is opt-in on Mimir — `max_global_exemplars_per_user` — because by default Mimir
keeps zero.)

### Click 2: that trace → its logs (trace → logs, `tracesToLogsV2`)

You clicked the dot; now you're looking at a trace waterfall, and one span is fat. You want the log lines
that span emitted. The Tempo datasource carries a `tracesToLogsV2` link, from
[`observability-tempo/main.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-tempo/main.tf):

```hcl
tempo_traces_to_logs = {
  datasourceUid      = var.loki_datasource_uid
  spanStartTimeShift = "-1h"
  spanEndTimeShift   = "1h"
  filterByTraceID    = true
  tags               = [{ key = "service.name", value = "service_name" }]
}
```

Each field earns its place:

- `filterByTraceID = true` — the Loki query it opens is scoped to *this trace's* ID, not "all logs from
  that service." You land on the exact request's log lines.
- `spanStartTimeShift`/`spanEndTimeShift = -1h / 1h` — Grafana widens the log search window an hour each
  side of the span. Without the pad: a span timestamped by the app and a log line timestamped by the
  node's clock never match to the millisecond, so a zero-width window would silently return nothing. The
  pad trades a little query cost for a link that actually resolves.
- `tags` — how a span *attribute* becomes a *log label*: the span's `service.name` maps to Loki's
  `service_name`. The same name-alignment trick returns in Click 3.

### Click 2b: and back again (logs → trace, Loki derived field)

The case-file hyperlinks run *both* directions. If you started in the logs — grepping an error, no trace
in hand — a `trace_id` in the log line is itself clickable back to the trace. That's a Loki **derived
field**. It used to be a regex that scraped raw log text; since [ADR-100](../../adrs/100-observability-instrumentation-and-otlp-convention.md)
it matches on **Loki structured metadata** instead — first-class and robust, not a text scan. From
[`observability-loki/main.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-loki/main.tf):

```hcl
loki_derived_fields = [{
  name          = "trace_id"
  matcherType   = "label"     # matches structured metadata, not the log line's text
  matcherRegex  = "trace_id"  # the FIELD NAME now, not a pattern
  url           = "$${__value.raw}"
  datasourceUid = "tempo-all"
}]
```

The `trace_id` value has to *get into* structured metadata before this can match anything — that's
`observability-alloy`'s per-team pipeline, which promotes `trace_id`/`span_id` out of the JSON log body
into Loki structured metadata for SDK'd apps. So this jump only resolves for **SDK-instrumented services**
(alpha-shop, alpha-checkout — see [collection & instrumentation](deep-dive-collection-and-instrumentation.md)):
Beyla doesn't stamp a `trace_id` into an app's own log lines, so a Beyla-only workload has no field to
promote and the derived field never lights up for it — you still get metric→trace and trace→logs
(`tracesToLogsV2`) for those, just not the reverse jump. Metric→trace→logs→trace is a *loop* for the
workloads that opted into L1, a one-way street otherwise.

### Click 3: that span → its flame graph (trace → profile, `tracesToProfilesV2`)

The span is slow *inside the process* — not waiting on a downstream call, just burning CPU. You want to
know *which function*. The Tempo datasource links to Pyroscope:

```hcl
tracesToProfilesV2 = {
  datasourceUid = replace(ds.uid, "tempo", "pyroscope")
  profileTypeId = "process_cpu:cpu:nanoseconds:cpu:nanoseconds"
  tags          = [{ key = "service.name", value = "service_name" }]
}
```

Same `replace` convention (`tempo`→`pyroscope`), same `service.name`→`service_name` tag mapping. And here
is the subtle thing that makes this jump possible at all: the trace and the profile have to agree on the
service's name, and nobody set that name by hand. Beyla labels a trace's `service.name` from the
workload's `app.kubernetes.io/name` label (falling back to namespace); the eBPF profiler (an Alloy
`pyroscope.ebpf` DaemonSet) labels each profile's `service_name` the *same* way. Two independent zero-code
agents, watching the same process from the kernel, arrive at the same identity — by deliberate convention,
not coincidence. Break that alignment (rename one label source) and the trace→flame-graph link silently
opens an empty profile. It's the single most fragile seam in the correlation web, and the only one with no
config that names both sides — it's an *agreement*.

> Honest scope: this link resolves for any traced service that actually **burns CPU**. The platform's
> trivial echo demo apps don't burn enough to flame-graph under light load — so the jump is wired and
> correct, but you need a real workload (or load) to see a populated graph. Wiring live; interesting data
> is workload-dependent.

### The overlays: service graph + deploy annotations

Two more pieces aren't "clicks" but frame the whole investigation.

The **service graph** answers "which hop" *before* you open a single trace. Tempo's metrics-generator
also emits `traces_service_graph_*` metrics (request counts and latencies *between* services), and the
Tempo datasource's `serviceMap = { datasourceUid = replace(ds.uid, "tempo", "mimir") }` tells Grafana to
render them as a node graph — `user → acme-shop-web → …`. Same swap convention, pointed back at Mimir
because the graph *is* metrics.

**Deploy annotations** answer "…and it got slow *because of what?*" The APM dashboard
([`dashboards/platform-apm.json`](https://github.com/asanexample/platform/blob/main/infra/modules/observability/dashboards/platform-apm.json))
carries a dashboard-level annotation query:

```json
"expr": "changes(kube_deployment_metadata_generation[2m]) > 0",
"name": "Deploys",
"tagKeys": "namespace,deployment"
```

Every deploy draws a vertical line across the time series. So "latency spiked at 03:00" sits directly
under "…because of the 02:58 deploy of `shop-web`" — the metric blip and its likely cause on one axis.
(`kube_deployment_metadata_generation` bumps on every spec change; `changes() > 0` marks the moment.)

---

## Part 2 — the per-team experience

Correlation is what an *engineer mid-incident* does. The other consuming question is quieter and more
political: when a team opens Grafana, what do they see, and can they see *only* their own stuff?

There are **two separate efforts** here — a *default view* and a *hard boundary* — and conflating them
is the mistake to avoid.

### Effort 1 (the soft need, LIVE and actually used): per-team overview dashboards

What a team actually needs day-to-day isn't a security boundary — it's a *default view*: "show me my
services' health without me building a dashboard." The platform delivers that the simple way, with one
dashboard per team, auto-generated from the team registry.

The mechanism is deliberately unclever. There's **one template**,
[`dashboards/team-overview.json.tmpl`](https://github.com/asanexample/platform/blob/main/infra/modules/observability/dashboards/team-overview.json.tmpl),
with a literal `__TEAM__` placeholder everywhere a team name goes. The observability module renders it
once per team ([`observability/main.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/observability/main.tf)):

```hcl
resource "kubernetes_config_map_v1" "team_dashboards" {
  for_each = local.create ? toset(var.team_overview_teams) : toset([])
  metadata {
    name        = "obs-dashboard-team-overview-${each.value}"
    labels      = merge(local.k8s_labels, { grafana_dashboard = "1" })
    annotations = { grafana_folder = "Teams" }
  }
  data = {
    "team-overview-${each.value}.json" = replace(
      file("${path.module}/dashboards/team-overview.json.tmpl"), "__TEAM__", each.value)
  }
}
```

And the team list is **registry-derived** — not a hand-maintained variable. The observability unit reads
it straight off the `gitops/teams/` directory
([`…/platform/observability/terragrunt.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/platform/us-east-1/platform/observability/terragrunt.hcl)):

```hcl
team_overview_teams = [for f in fileset("${get_repo_root()}/gitops/teams", "*.yaml") : trimsuffix(basename(f), ".yaml")]
```

Add a `Team` to the registry and they get an overview dashboard on the next apply. No dashboard authoring,
ever. Live today, one per registered team:

```text
$ kubectl --context platform -n observability get cm | grep team-overview
obs-dashboard-team-overview-acme        1   …
obs-dashboard-team-overview-globex      1   …
obs-dashboard-team-overview-platform    1   …
```

Those three match the three files in `gitops/teams/` (`acme`, `globex`, `platform`) exactly — the
`fileset` in action.

What's *on* the dashboard, and where the numbers come from — it's a RED + USE view scoped to the team:

- **Pre-filtered by namespace.** Every panel query carries `namespace=~"__TEAM__-.*"` — the platform's
  environment-namespace convention (`<team>-<product>-<stage>`, e.g. `acme-demo-dev`) means a single
  regex captures *all* of a team's environments and nothing else.
- **RED**, from Beyla — request rate and 5xx ratio per environment off
  `http_server_request_duration_seconds_count` (the same zero-code Beyla metric the SLOs use;
  exemplars ride the metrics-generator's span-metrics, per Click 1).
- **USE**, from cAdvisor/kube-state-metrics — CPU (`container_cpu_usage_seconds_total`), memory
  (`container_memory_working_set_bytes`), running pods, restarts.
- **Cost**, from OpenCost — an estimated `$/mo` panel (`container_cpu_allocation × node_cpu_hourly_cost`,
  plus the memory equivalent, × 730h).

Crucially, it **queries the federated `Mimir (all clusters)` datasource** (uid `mimir-all`), not a
per-team-isolated one — the template's default datasource is literally `"Mimir (all clusters)"`.

> **This filter is a *default view*, not a boundary.** `namespace=~"acme-.*"` is baked into the panels,
> but nothing *stops* an `acme` engineer from editing the query to `globex-.*` — the dashboard reads the
> all-clusters datasource, which can see every tenant. It's the convenient lane, not a wall. That
> distinction is the whole point of Effort 2.

### Effort 2 — the hard boundary the platform built, then pulled

The *harder* goal — making `acme` genuinely **unable** to query `globex`'s data — is P13 (#590), and it has an
honest arc: the write side landed and stayed; the read side was built, shipped, then **retired**. What's live
is the **write-split into real per-team tenants** — `cortex-tenant` splits each environment namespace's series
into its own Mimir tenant (Loki the same for logs), so `acme` and `globex` are real, separate tenants, not one
bucket with a label. What was *designed* on the read side (from the `observability-tenant-proxy` README):

```text
user → Grafana ──(query + OIDC token, oauthPassThru)──▶ tenant-proxy ──(X-Scope-OrgID=<team>)──▶ Mimir
```

— would verify the Grafana-forwarded Keycloak token, map the `groups` claim to a tenant, *overwrite*
`X-Scope-OrgID` with the caller's own team, and deny anything unauthenticated (fail-closed: no valid token, no
data), surfacing as a `Mimir (my team)` datasource. It was built and shipped — then **retired**
([#1269](https://github.com/asanexample/platform/issues/1269)): OSS Grafana's `oauthPassThru` can't reliably
forward the SSO token to a downstream proxy, so the proxy fail-closed on `no_token` and *every dashboard went
blank for admins*. The modules stay in the repo but inert (`read_proxy_url = ""`), re-enableable if Grafana's
token forwarding is ever fixed. The write-split, though, is genuinely running:

```text
$ kubectl --context platform -n observability get pods | grep cortex
cortex-tenant-…   1/1   Running
cortex-tenant-…   1/1   Running
```

So what isolates a team's *reads* today, with the proxy gone? The **soft model** — which was the actual need:

1. **Real per-team tenants underneath (write-side, live).** The `cortex-tenant` write-split gives each team its
   own Mimir/Loki tenant. The platform **hub** runs no environment namespaces, so its own metrics are the
   `platform` tenant; the real per-team tenants (`acme`, `globex`, …) are populated by the **preprod spoke's
   dual-write** — preprod, where the team apps run, ships each namespace's series into its own tenant (additive
   to `preprod`). So the *separation of the data* is real and live end-to-end.
2. **Soft read scoping on top (Grafana-side, live).** Each team reads through a `Mimir (<team>)` / `Loki
   (<team>)` datasource pinned to its tenant, and per-team isolation is enforced by **Grafana dashboard-folder
   permissions** plus the **namespace-filtered per-team overview dashboards** (#1157) — an organizational
   boundary, not a fail-closed data gate. Cross-team *sharing* is soft too: share the dashboard or grant folder
   access. (The `AccessGrant` model — [ADR-068](../../adrs/068-product-scoped-and-cross-team-access-model.md),
   `gitops/grants/` — still governs cross-team access in general, but its enforcement as a *fail-closed
   observability read-federation* (`X-Scope-OrgID: acme|globex`) went with the retired proxy.) Per-team
   **traces**/**profiles** read scoping is a follow-up.

An architectural footnote worth keeping: the write-split was flipped **hub-first** — the [platform
`env.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/platform/env.hcl) says so:

```hcl
enable_per_team_tenants = true # …HUB flip first: hub metrics still resolve to the `platform`
# tenant (no env namespaces here), proving the path before the spoke.
```

The re-tenant splits metrics by *environment namespace* → team, and the **hub cluster has no environment
namespaces** (tenant workloads run on **preprod**, the spoke), so the hub's *own* metrics still resolve to the
`platform` tenant. The genuinely per-team `acme`/`globex` tenants are fed from the preprod path — now live and
carrying data. That's exactly why the write-split is *proven*, not merely *plumbed*: real per-team data flows
through the part that separates it.

### Net for a team, today

Open **your Team Overview dashboard** for a namespace-filtered RED/USE/cost view of your environments — the
convenient default self-view, driven off the team registry. Underneath it, per-team separation is **soft**:
your writes land in a real separate tenant, but your reads are scoped by Grafana folder permissions, not a
fail-closed gate — the hard read-proxy was built and then **retired** (#1269) as unreliable in OSS Grafana.
That's the honest, current picture: real per-team *data* separation, soft per-team *read* scoping, with
traces/profiles read scoping still deferred.

---

## Dashboards-as-code — the substrate under both parts

Both the correlation dashboards and the team-overview dashboards ride the same delivery mechanism. Grafana
dashboards here are **[ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/),
not clicked-in-the-UI JSON**: a `kubernetes_config_map_v1` holding the dashboard JSON, labeled
`grafana_dashboard = "1"`. A **sidecar** container in the Grafana pod watches for that label
in the observability namespace (`searchNamespace` = the module's namespace) and loads any it finds within
seconds — so a dashboard ConfigMap must live in that namespace to be discovered, and a dashboard is a
reviewed, version-controlled file in `infra/modules/observability/dashboards/`, not tribal knowledge that
vanishes when someone edits it in the browser and forgets to export. (The team-overview ConfigMaps also set `annotations = { grafana_folder
= "Teams" }`, which the sidecar reads to file them in Grafana's *Teams* folder.)

**Vendored dashboards are pinned to an exact grafana.com revision** — downloaded and committed, never
imported-by-ID live — so an upstream dashboard change goes through PR review like any other code, rather
than silently reshaping your panels. Same discipline as pinning a chart version.

---

## Gotchas that teach

- **The correlation web is a naming convention, not a wiring diagram.** Every jump is
  `replace(uid, "mimir", "tempo")`-style string surgery over a UID naming scheme (`mimir` / `mimir-preprod`
  / `mimir-all`). Elegant — it scales to N tenants with zero per-target config — but it means a datasource
  named off-convention silently links nowhere. The convention *is* the contract.
- **The one link with no config on both sides is the fragile one.** trace→profile works only because
  Beyla's `service.name` and the eBPF profiler's `service_name` independently derive from
  `app.kubernetes.io/name`. No file declares "these two must match." Rename one label source and the jump
  opens an empty flame graph with no error. Agreements are harder to keep than declarations.
- **Time-shifts on trace→logs aren't sloppiness — they're clock-skew insurance.** `±1h` around a span
  looks huge until you remember app-stamped span times and node-stamped log times never agree exactly; a
  zero-width window returns nothing and reads as "correlation is broken."
- **"Namespace-filtered" ≠ "isolated" — and neither is a hard boundary anymore.** The Team Overview filter is
  a baked-in default over the *all-clusters* datasource — convenience, not a boundary. The real separation is
  the **write-split** (each team's data in its own tenant); read scoping on top is **soft** (Grafana
  dashboard-folder permissions + the per-tenant datasources), not a fail-closed gate — the hard read-proxy was
  built and then **retired** (#1269) as unreliable. So don't read the filter, or the soft read scoping, as a
  security control.
- **A flag being `true` is a claim about *intent*, not *effect*.** `enable_per_team_tenants` was flipped
  hub-first, but the hub has no environment namespaces (tenants run on the preprod spoke), so the hub's *own*
  metrics still resolve to the `platform` tenant. The genuinely per-team `acme`/`globex` tenants are fed from
  the preprod path — now live and carrying data, which is what makes the write-split *proven*. Verify per-team
  data separation against where the data actually lands, not just the flag.
- **A team appears the instant it's in the registry.** `team_overview_teams` is a `fileset` over
  `gitops/teams/*.yaml`, so onboarding a `Team` yields its overview dashboard on the next apply — and,
  conversely, a dashboard with no matching registry file can't exist. Registry is the source of truth for
  the view, too.

## Go deeper

- **Source of truth — architecture:** [`docs/architecture/observability-current-state.md`](../../architecture/observability-current-state.md)
  — the APM-correlation section (P6), the federated-datasource section (#626), and the multi-tenancy
  security-boundary note.
- **Related learn modules:** [The stack & storage](deep-dive-the-stack-and-storage.md) (the
  `X-Scope-OrgID` tenancy model the proxy enforces) · [Collection & instrumentation](deep-dive-collection-and-instrumentation.md)
  (why Beyla and the eBPF profiler agree on `service.name`) · [SLOs, alerting & cost](deep-dive-slos-alerting-and-cost.md)
  (the same Beyla RED metrics feed the SLOs and the team dashboards).
- **Code:** [`observability-mimir`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-mimir/main.tf)
  (exemplar destinations) · [`observability-tempo`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-tempo/main.tf)
  (`tracesToLogsV2` / `tracesToProfilesV2` / `serviceMap`) · [`observability-loki`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-loki/main.tf)
  (the `trace_id` derived field) · [`observability-tenant-proxy`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-tenant-proxy/README.md)
  (P13 read isolation — built, then retired #1269) · [`team-overview.json.tmpl`](https://github.com/asanexample/platform/blob/main/infra/modules/observability/dashboards/team-overview.json.tmpl).
- **House skill:** `observability-authoring` — the dashboards-as-code ConfigMap pattern and the vendored-
  revision-pinning rule, for when you add one.
- **External (verified, current Grafana):**
  [Configure the Tempo datasource](https://grafana.com/docs/grafana/latest/datasources/tempo/configure-tempo-data-source/)
  (the traces-to-logs / traces-to-profiles / service-graph options, ~10 min) ·
  [Introduction to exemplars](https://grafana.com/docs/grafana/latest/fundamentals/exemplars/)
  (what an exemplar is and the metric→trace link, ~5 min) ·
  [Tempo metrics-generator](https://grafana.com/docs/tempo/latest/metrics-generator/)
  (span-metrics + service-graph, the *producer* side of Click 1 & the service graph, ~10 min).

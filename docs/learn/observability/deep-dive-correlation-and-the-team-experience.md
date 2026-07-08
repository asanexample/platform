# Learn: Observability — correlation & the team experience (deep dive)

> Assumes the [observability orientation](orientation.md) — the four signals, LGTM+P, Beyla, the
> hub-and-spoke stores, and that one Grafana fronts them all. This deep dive opens two things the
> orientation only gestured at: **how the "jump" between signals is actually wired** (Stop 4), and
> **what a *team* really sees today** — including the one honest caveat the orientation flagged and
> refused to oversell (Stop 5's per-team isolation).
>
> Already fluent in Grafana datasource correlation? The [reference](reference.md) is the terse lookup;
> skip to the [per-team section](#part-2--the-per-team-experience) for the part that's specific here.

Two separate ideas share this file because they're the *consuming* side of observability — what an
engineer does with the stack once the signals are flowing. First: correlation, the machinery that turns
five stores into one investigation. Second: the per-team experience, where the subtle build-vs-live
nuance lives.

---

## Part 1 — correlation: the detective's case-file hyperlinks

Recall the orientation's metaphor: **a detective's case file where every clue hyperlinks to the next.**
The vitals blip links to the ECG strip, which links to the lab result, which links to the tissue sample —
four stores, one click each, no re-typing a query into a different tool. That's the whole payoff of
running one Grafana over five backends instead of five vendor consoles.

The thing worth understanding is that **those hyperlinks aren't a Grafana feature you turn on — they're
config you write into each datasource.** Grafana correlation is a set of directed links: "on *this*
datasource, a value shaped like *that* opens *this other* datasource." The platform wires four of them.
Let's walk the 4-click investigation from the orientation and, at each click, look at the exact wiring
that makes it work.

### Click 1: a RED spike → the exact trace (metric → trace, via exemplars)

You're staring at a latency panel. A p99 spike. On most stacks that's a dead end — the metric is an
*aggregate*, it averaged away the one slow request you care about. The fix is an **exemplar**: alongside
the aggregated histogram, the metric store keeps a handful of *sample* data points, each tagged with the
**trace ID** of one real request that landed in that bucket. The spike carries clickable dots.

Two halves make this real. The **producer** is Tempo's metrics-generator — it derives the RED
span-metrics from traces and stamps each exemplar with a `traceID` label (the orientation's Stop 4). The
**consumer** is the Mimir datasource, told where that trace ID can be opened. From
[`observability-mimir/main.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-mimir/main.tf):

```hcl
exemplarTraceIdDestinations = [{
  name          = "traceID"                        # the exemplar label the generator emits (camelCase)
  datasourceUid = replace(ds.uid, "mimir", "tempo")
}]
```

That `replace(ds.uid, "mimir", "tempo")` is the small, elegant idea that makes the whole correlation web
scale to any number of tenants. Datasource UIDs are named by a **convention** — `mimir`, `mimir-preprod`,
`mimir-all` — and every jump is expressed as a *string swap*, not a hard-coded target. So the `platform`
tenant's Mimir links to the `platform` tenant's Tempo (`mimir`→`tempo`), the `preprod` tenant's Mimir
links to `preprod`'s Tempo (`mimir-preprod`→`tempo-preprod`), and neither line of config names the other
explicitly. The wiring is a *rule*, not a table. (Exemplar storage itself is opt-in on Mimir —
`max_global_exemplars_per_user` — because by default Mimir keeps zero.)

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

Read the fields, because each one is a lesson in how these jumps actually behave:

- `filterByTraceID = true` — the Loki query it opens is scoped to *this trace's* ID, not "all logs from
  that service." You land on the exact request's log lines.
- `spanStartTimeShift`/`spanEndTimeShift = -1h / 1h` — Grafana widens the log search window an hour each
  side of the span. **Why-it-breaks-if-you-don't:** a span timestamped by the app and a log line
  timestamped by the node's clock never match to the millisecond; a zero-width window would silently
  return nothing. The pad trades a little query cost for a link that actually resolves.
- `tags` — how a span *attribute* becomes a *log label*: the span's `service.name` maps to Loki's
  `service_name`. This is the same name-alignment trick that shows up again in Click 4; hold onto it.

### Click 2b: and back again (logs → trace, Loki derived field)

The case-file hyperlinks run *both* directions. If you started in the logs — grepping an error, no trace
in hand — a `trace_id` in the log line is itself clickable back to the trace. That's a Loki **derived
field**, a regex that extracts a value from raw log text and turns it into a link. From
[`observability-loki/main.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-loki/main.tf):

```hcl
loki_derived_fields = [{
  name          = "trace_id"
  matcherRegex  = "trace_?[iI][dD]\"?[:=]\\s*\"?([0-9a-fA-F]+)"
  url           = "$${__value.raw}"
  datasourceUid = "tempo"
}]
```

The forgiving regex (`trace_?[iI][dD]`, optional quotes, `:` or `=`) is deliberate: it catches
`traceId=…`, `"trace_id": "…"`, `trace-id = …` and other shapes apps emit, because the platform doesn't
control every app's log format. Metric→trace→logs→trace is a *loop*, not a one-way street.

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
is the subtle thing that makes this jump *possible at all*, the detail the orientation flagged: **the
trace and the profile have to agree on the service's name, and nobody set that name by hand.** Beyla
labels a trace's `service.name` from the workload's `app.kubernetes.io/name` label (falling back to
namespace); the eBPF profiler (an Alloy `pyroscope.ebpf` DaemonSet) labels each profile's `service_name`
the *same* way. Two completely independent zero-code agents, watching the same process from the kernel,
arrive at the same identity — **by deliberate convention, not coincidence.** Break that alignment (rename
one label source) and the trace→flame-graph link silently opens an empty profile. It's the single most
fragile seam in the correlation web, and it's the one with no config that names both sides — it's an
*agreement*.

> Honest scope: this link resolves for any traced service that actually **burns CPU**. The platform's
> trivial echo demo apps don't burn enough to flame-graph under light load — so the jump is wired and
> correct, but you need a real workload (or load) to see a populated graph. Wiring live; interesting data
> is workload-dependent.

### The overlays: service graph + deploy annotations

Two more pieces aren't "clicks" but frame the whole investigation.

The **service graph** answers "which hop" *before* you open a single trace. Tempo's metrics-generator
also emits `traces_service_graph_*` metrics (request counts and latencies *between* services), and the
Tempo datasource's `serviceMap = { datasourceUid = replace(ds.uid, "tempo", "mimir") }` tells Grafana to
render them as a node graph — `user → alpha-shop-web → …`. Same swap convention, pointed back at Mimir
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

### Quick check

Close this section. Why does `exemplarTraceIdDestinations` use `replace(ds.uid, "mimir", "tempo")`
instead of just hard-coding `"tempo"`? And what single, un-configured thing has to be true for the
trace→profile jump to land on a non-empty flame graph?

*(Because the wiring is a per-tenant **rule**: `mimir`→`tempo`, `mimir-preprod`→`tempo-preprod`, minted
by naming convention so it scales without a lookup table. And: Beyla's trace `service.name` must equal the
eBPF profiler's `service_name` — both derived from `app.kubernetes.io/name` — an agreement no config file
names on both sides.)*

---

## Part 2 — the per-team experience

Correlation is what an *engineer mid-incident* does. The other consuming question is quieter and more
political: **when a team opens Grafana, what do they see, and can they see *only* their own stuff?**

This is where the orientation drew its one careful line, and it's worth getting exactly right — because
there are **two separate efforts** here — a *default view* and a *hard boundary* — and conflating them is
the mistake the docs exist to prevent.

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

Add a `Team` to the registry → they get an overview dashboard on the next apply. No dashboard authoring,
ever. Live today, one per registered team:

```text
$ kubectl --context platform -n observability get cm | grep team-overview
obs-dashboard-team-overview-alpha       1   …
obs-dashboard-team-overview-bravo       1   …
obs-dashboard-team-overview-platform    1   …
```

Those three match the three files in `gitops/teams/` (`alpha`, `bravo`, `platform`) exactly — the
`fileset` in action.

**What's *on* the dashboard**, and where the numbers come from — it's a RED + USE view scoped to the
team:

- **Pre-filtered by namespace.** Every panel query carries `namespace=~"__TEAM__-.*"` — the platform's
  environment-namespace convention (`<team>-<product>-<stage>`, e.g. `alpha-demo-dev`) means a single
  regex captures *all* of a team's environments and nothing else.
- **RED**, from Beyla — request rate and 5xx ratio per environment off
  `http_server_request_duration_seconds_count` (the same zero-code Beyla metric the SLOs use;
  exemplars ride the metrics-generator's span-metrics, per Click 1).
- **USE**, from cAdvisor/kube-state-metrics — CPU (`container_cpu_usage_seconds_total`), memory
  (`container_memory_working_set_bytes`), running pods, restarts.
- **Cost**, from OpenCost — an estimated `$/mo` panel (`container_cpu_allocation × node_cpu_hourly_cost`,
  plus the memory equivalent, × 730h).

Crucially, it **queries the federated `Mimir (all clusters)` datasource** (uid `mimir-all`), not a
per-team-isolated one — the template's default datasource is literally `"Mimir (all clusters)"`. Which
brings us to the honest part.

> **This filter is a *default view*, not a boundary.** `namespace=~"alpha-.*"` is baked into the panels,
> but nothing *stops* an `alpha` engineer from editing the query to `bravo-.*` — the dashboard reads the
> all-clusters datasource, which can see every tenant. It's the convenient lane, not a wall. That
> distinction is the whole point of Effort 2.

### Effort 2 (the hard boundary, LIVE + PROVEN): P13 per-team read isolation + AccessGrant sharing

The *harder* thing — the one that makes `alpha` **unable** to query `bravo`'s data unless `bravo` has
granted it — is P13 (#590): a pair of fail-closed **tenant-proxies** (one for Mimir, one for Loki). This is
the mechanism the orientation's honest-status paragraph points at, and it's now **live and proven** for both
metrics and logs — worth seeing exactly how it fences, and how a team opts to *share*.

The design (from [`observability-tenant-proxy/README.md`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-tenant-proxy/README.md)):

```text
user → Grafana ──(query + OIDC token, oauthPassThru)──▶ tenant-proxy ──(X-Scope-OrgID=<team>)──▶ Mimir
```

The proxy verifies the Grafana-forwarded Keycloak token against the realm JWKS, maps the `groups` claim
to a tenant scope (`platform-admins` → all tenants; **unknown/empty → deny**), *overwrites*
`X-Scope-OrgID` with the caller's own team, and reverse-proxies to Mimir. It's **fail-closed**: no valid
token, no data. It surfaces as a `Mimir (my team)` datasource users pick. The **same shape runs in front of
Loki** (`loki-tenant-proxy`), fencing logs the identical way behind a `Loki (my team)` datasource — so the
boundary covers both live data-plane signals. And it's genuinely running — two replicas, alongside the
`cortex-tenant` write-side that splits each team's metrics into its own Mimir tenant in the first place:

```text
$ kubectl --context platform -n observability get pods | grep -E 'tenant-proxy|cortex'
cortex-tenant-…   1/1   Running
cortex-tenant-…   1/1   Running
tenant-proxy-…    1/1   Running
tenant-proxy-…    1/1   Running
```

So who's it isolating, and how does a team *share*? Two things make this real rather than a diagram:

1. **The write-split produces per-team tenants, and the proxy fences by identity — fail-closed.** The
   `cortex-tenant` write-side is configured to split each environment namespace's series into its own Mimir
   tenant (Loki does the same for logs), and the proxy maps SSO identity → that team's `X-Scope-OrgID` and
   overwrites it — so a caller can only reach its own tenant (unknown/empty identity → **deny**). The platform
   **hub** runs no environment namespaces, so its own metrics are the `platform` tenant; the real per-team
   tenants (`alpha`, `bravo`, …) are populated by the **preprod spoke's dual-write** — preprod, where the team
   apps run, ships each namespace's series into its own Mimir tenant (additive to the `preprod` tenant), and
   Loki does the same for logs. So the enforcement is **live end-to-end** — identity-scoped, fail-closed, for
   metrics *and* logs — proven 2026-07-07. (Per-team **traces** (Tempo) and **profiles** (Pyroscope) isolation
   is deferred — metrics + logs are the two live signals.)
2. **Cross-team sharing is an explicit grant, not an open door.** Because the proxy is fail-closed, `bravo`
   *can't* see `alpha`'s signals by default. Sharing is a deliberate act: an **`AccessGrant`**
   ([ADR-068](../../adrs/068-product-scoped-and-cross-team-access-model.md); claims in `gitops/grants/`, e.g.
   `bravo-reads-alpha-shop`) in which `alpha` grants `bravo` read access to its `shop` product. The proxy
   derives that grant into a **federated** read — `bravo`'s queries become `X-Scope-OrgID: alpha|bravo`, i.e.
   its own tenant **∪** its grants — still fail-closed for anything ungranted. And because OSS Grafana has
   **no per-team dashboard RBAC**, that grant *is* the data-and-dashboard sharing mechanism: there's no other
   lane to hand another team your signals.

An architectural footnote worth keeping: the write-split was flipped **hub-first** — the [platform
`env.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/platform/env.hcl) says so:

```hcl
enable_per_team_tenants = true # …HUB flip first: hub metrics still resolve to the `platform`
# tenant (no env namespaces here), proving the path before the spoke.
```

The re-tenant splits metrics by *environment namespace* → team, and the **hub cluster has no environment
namespaces** (tenant workloads run on **preprod**, the spoke), so the hub's *own* metrics still resolve to the
`platform` tenant. The genuinely per-team `alpha`/`bravo` tenants are fed from the preprod path — which is now
live and carrying data. That's exactly why the isolation is *proven*, not merely *plumbed*: there is real
per-team data flowing through the part that isolates.

### Net for a team, today

Open **your Team Overview dashboard** for a namespace-filtered RED/USE/cost view of your environments — the
convenient default self-view, driven off the team registry. Underneath it, the **hard read-isolation is live
and fail-closed** for metrics and logs: through the `(my team)` lane you see only your team's signals, and you
see another team's only if they've handed you an **`AccessGrant`**. That's the honest, current picture — real
per-team isolation and real grant-based sharing (metrics + logs), with traces/profiles still deferred.

### Quick check

A teammate says "our Grafana is multi-tenant — `alpha` literally can't see `bravo`'s metrics." True or
false — and does it depend on *which datasource* they open?

*(Both — it depends on the lane. Through the **`(my team)` lane** (the fail-closed tenant-proxies, live) it's
**true**: `alpha` sees only `alpha`'s metrics and logs, and `bravo`'s only if `alpha` has granted it (an
`AccessGrant`). But the **default Team Overview dashboard** rides the **all-clusters** datasource — a
namespace-*filtered convenience*, editable to show anyone's data — so on *that* lane it's **false**. The
isolation is real and live; it's the dashboard's default datasource, not the proxy, that's the open one.)*

---

## Dashboards-as-code — the substrate under both parts

Both the correlation dashboards and the team-overview dashboards ride the same delivery mechanism, worth
naming once. Grafana dashboards here are **[ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/),
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
- **"Namespace-filtered" ≠ "isolated."** The Team Overview filter is a baked-in default over the
  *all-clusters* datasource — convenience, not a boundary. The actual boundary is a *different* mechanism: the
  fail-closed tenant-proxies (Mimir + Loki, **live**), whose `(my team)` lane fences a caller to its own tenant
  ∪ any `AccessGrant`-ed tenants. Reading the *filter* as the security control is the exact misconception this
  module exists to prevent.
- **A flag being `true` is a claim about *intent*, not *effect*.** `enable_per_team_tenants` was flipped
  hub-first, but the hub has no environment namespaces (tenants run on the preprod spoke), so the hub's *own*
  metrics still resolve to the `platform` tenant. The genuinely per-team `alpha`/`bravo` tenants are fed from
  the preprod path — now live and carrying data, which is what makes the isolation *proven*. Verify per-team
  isolation against where the data actually lands, not just the flag.
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
  (P13 read isolation) · [`team-overview.json.tmpl`](https://github.com/asanexample/platform/blob/main/infra/modules/observability/dashboards/team-overview.json.tmpl).
- **House skill:** `observability-authoring` — the dashboards-as-code ConfigMap pattern and the vendored-
  revision-pinning rule, for when you add one.
- **External (verified, current Grafana):**
  [Configure the Tempo datasource](https://grafana.com/docs/grafana/latest/datasources/tempo/configure-tempo-data-source/)
  (the traces-to-logs / traces-to-profiles / service-graph options, ~10 min) ·
  [Introduction to exemplars](https://grafana.com/docs/grafana/latest/fundamentals/exemplars/)
  (what an exemplar is and the metric→trace link, ~5 min) ·
  [Tempo metrics-generator](https://grafana.com/docs/tempo/latest/metrics-generator/)
  (span-metrics + service-graph, the *producer* side of Click 1 & the service graph, ~10 min).

locals {
  create  = var.create
  sa_name = var.helm_release_name

  # Sanitize tags for K8s label compliance (RFC 1123), matching the observability module.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  # ---- Mimir helm values (mimir-distributed, minimal single-replica unless high_availability) ----
  helm_values = {
    # Deterministic resource names: <name>-gateway, <name>-distributor, … and the SA = <name>.
    nameOverride     = var.helm_release_name
    fullnameOverride = var.helm_release_name

    serviceAccount = {
      create = true
      name   = local.sa_name
      # Pod Identity (ADR-047) — no IRSA annotation; the association below binds (ns, SA) -> role.
      annotations = {}
    }

    # We use S3 — do NOT deploy the chart's bundled demo MinIO.
    minio = { enabled = false }

    # Let the hub Prometheus scrape Mimir's own metrics (health + remote-write lag + object store).
    # clusterLabel overrides the chart's default `cluster` label (which is the Mimir release name, "mimir",
    # and pollutes the real cluster dimension — #630) with the actual cluster, matching Prometheus
    # externalLabels.cluster so Mimir's self-metrics are attributed to the cluster they run on.
    metaMonitoring = {
      serviceMonitor = { enabled = true, clusterLabel = var.cluster_label != "" ? var.cluster_label : var.cluster_name }
    }

    mimir = {
      structuredConfig = {
        # X-Scope-OrgID required on read+write. NOTE: this is a trust header, not auth — in-cluster
        # isolation rests on the observability ns default-deny NetworkPolicy (tenant pods can't reach us).
        multitenancy_enabled = true

        # Read-path tenant federation (#626): a query with `X-Scope-OrgID: a|b` spans both tenants, which is
        # what lets one Grafana panel cover multiple clusters. Write isolation is unaffected (the Gateway edge
        # still force-stamps a single tenant per spoke). Only enabled alongside the federated datasource.
        tenant_federation = { enabled = var.enable_federated_datasource }

        common = {
          storage = {
            backend = "s3"
            s3 = {
              region   = var.aws_region
              endpoint = "s3.${var.aws_region}.amazonaws.com"
              # Pod Identity: access_key_id/secret_access_key intentionally omitted -> AWS SDK container-credentials chain.
              # The org `enforce-encryption` SCP denies s3:PutObject without an explicit SSE header — bucket
              # default encryption alone isn't enough. Send SSE-S3 on every write (mirrors Loki/Tempo).
              sse = { type = "SSE-S3" }
            }
          }
        }

        blocks_storage = {
          backend = "s3"
          s3      = { bucket_name = try(aws_s3_bucket.blocks[0].bucket, "") }
        }

        # Ruler (P4, gated on var.enable_ruler) — evaluates alerting rules against EACH tenant's metrics
        # (incl. the spokes' remote-written data) and sends fired alerts to the hub Alertmanager, which fans
        # critical alerts to the triage agent (ADR-082). Without it, only the hub Prometheus's locally-scraped
        # metrics produce alerts, so a preprod failure never reaches the agent. Rules are loaded per-tenant into
        # ruler_storage (the blocks bucket, `ruler/` prefix) via mimirtool/the ruler API (the (B) rules-sync).
        ruler_storage = var.enable_ruler ? {
          backend        = "s3"
          s3             = { bucket_name = try(aws_s3_bucket.blocks[0].bucket, "") }
          storage_prefix = "ruler"
        } : null
        ruler = var.enable_ruler ? {
          alertmanager_url = var.ruler_alertmanager_url
        } : null

        # Classic write path (distributor -> ingester gRPC push). The chart's base config defaults to
        # the Kafka-based ingest-storage architecture (ingest_storage.enabled: true +
        # push_grpc_method_enabled: false); override both to OFF so no Kafka is needed. Kafka itself is
        # disabled in the helm values below. (Ingest-storage is an HA/scale option for later.)
        ingest_storage = { enabled = false }
        ingester = {
          push_grpc_method_enabled = true
          # Single ingester => replication_factor must be 1 or writes are rejected.
          ring = { replication_factor = var.high_availability ? 3 : 1 }
        }

        limits = {
          max_global_series_per_user        = var.max_global_series_per_user
          ingestion_rate                    = var.ingestion_rate
          ingestion_burst_size              = var.ingestion_burst_size
          compactor_blocks_retention_period = var.blocks_retention
          # Beyla (P7) stamps a rich set of k8s attributes (namespace/deployment/pod/service/…) per series —
          # ~35+, over Mimir's default of 30, so its RED metrics get discarded (max_label_names_per_series).
          # Raise it to admit label-rich auto-instrumentation series. Bounded, so cardinality stays sane.
          max_label_names_per_series = var.max_label_names_per_series
          # Store exemplars (default 0 = off) so span-metric/RED samples keep their trace_id — the APM
          # metric→trace link (P6).
          max_global_exemplars_per_user = var.max_global_exemplars_per_user

          # OTLP -> Prometheus naming convergence (ADR-100). Tenant app-SDK metrics arrive via OTLP ingest; by
          # DEFAULT Mimir keeps raw OTLP names (no unit suffix) + only synthesises job/instance. Translate on
          # ingest so OTLP metrics are INDISTINGUISHABLE from Beyla/kube-state remote-write — one convention, so
          # a single dashboard / SLO / canary / alert query works regardless of delivery path (the root cause of
          # the alpha-shop dashboard+canary+SLO breakage). Only affects OTLP-ingested series; remote-write is
          # untouched. Extra labels stay within the raised max_label_names_per_series.
          #
          # ⚠️ Field names + value TYPES verified against the RUNNING Mimir 3.0.4 `/config` (NOT guessed — an
          # earlier guess `otel_promote_resource_attributes = [list]` crashlooped every component):
          #  - the key is `promote_otel_resource_attributes` (promote_otel, not otel_promote), and its value is a
          #    CSV STRING (a YAML list is rejected — /config renders the default as "" not []).
          otel_metric_suffixes_enabled              = true # http_server_request_duration -> ..._seconds (+ _total)
          otel_keep_identifying_resource_attributes = true # -> service_name / service_namespace / service_instance_id
          # service.name/service.namespace promoted explicitly — they're the identifying attrs used for job/instance,
          # and keep_identifying alone did NOT surface them as labels in 3.0.4, so promote them to get
          # service_name/service_namespace exactly like Beyla/remote-write (full convention parity). CSV string.
          promote_otel_resource_attributes = "service.name,service.namespace,k8s.namespace.name,k8s.pod.name,k8s.deployment.name,k8s.node.name"
        }
      }
    }

    # Classic architecture — no Kafka (ingest_storage disabled in structuredConfig above).
    kafka = { enabled = false }

    # Single entry point (nginx) for push + query.
    gateway = { enabled = true, replicas = var.high_availability ? 2 : 1 }

    # --- Write/read path ---
    distributor    = { replicas = var.high_availability ? 3 : 1 }
    querier        = { replicas = var.high_availability ? 2 : 1 }
    query_frontend = { replicas = var.high_availability ? 2 : 1 }
    # The query-scheduler is required: the chart's base config wires the querier's frontend_worker +
    # query-frontend to scheduler-headless and does NOT reconfigure for scheduler-less mode, so disabling
    # it breaks the read path (DNS failures). Keep it on (single replica when not HA).
    query_scheduler = { enabled = true, replicas = var.high_availability ? 2 : 1 }

    # Karpenter must not voluntarily disrupt (consolidate/drift/expire) the nodes Mimir's PVC-backed
    # StatefulSets (ingester / store-gateway / compactor) run on. The chart renders <component>.podAnnotations
    # onto each component's StatefulSet pod template (covers all zone-aware replicas when HA).
    ingester = {
      replicas             = var.high_availability ? 3 : 1
      zoneAwareReplication = { enabled = var.high_availability }
      persistentVolume     = { enabled = true, storageClass = var.storage_class, size = "10Gi" }
      podAnnotations       = { "karpenter.sh/do-not-disrupt" = "true" }
    }
    store_gateway = {
      replicas             = var.high_availability ? 3 : 1
      zoneAwareReplication = { enabled = var.high_availability }
      persistentVolume     = { enabled = true, storageClass = var.storage_class, size = "10Gi" }
      podAnnotations       = { "karpenter.sh/do-not-disrupt" = "true" }
    }
    compactor = {
      replicas         = 1
      persistentVolume = { enabled = true, storageClass = var.storage_class, size = "20Gi" }
      podAnnotations   = { "karpenter.sh/do-not-disrupt" = "true" }
    }

    # --- ruler gated on var.enable_ruler (P4); alertmanager stays off (we route to the kube-prometheus one) ---
    ruler              = { enabled = var.enable_ruler, replicas = 1 }
    alertmanager       = { enabled = false }
    overrides_exporter = { enabled = var.high_availability }
    rollout_operator   = { enabled = var.high_availability }
    "chunks-cache"     = { enabled = var.high_availability }
    "index-cache"      = { enabled = var.high_availability }
    "metadata-cache"   = { enabled = var.high_availability }
    "results-cache"    = { enabled = var.high_availability }
  }

  # ---- Grafana datasources (auto-loaded by the observability Grafana sidecar) ----
  # One per tenant: the hub's own `default_tenant_id` (optionally default) + one read-only `Mimir (<tenant>)`
  # per spoke tenant (P10) + (optionally) a federated `Mimir (all clusters)` spanning every tenant (#626).
  # All query the same in-cluster gateway; only the X-Scope-OrgID header differs.
  all_tenants = concat([var.default_tenant_id], var.extra_tenant_datasources)

  # P13 enforcement (#590): when read_proxy_url is set, every datasource points at the tenant-proxy with
  # oauthPassThru (the caller's SSO identity decides the scope) instead of the gateway with a fixed tenant
  # header. We then render ONLY the default (`mimir`) + federated (`mimir-all`) uids — dashboards reference
  # those and nothing else — and DROP the per-cluster `extra_tenant_datasources`, which would otherwise be
  # un-proxied datasources a user could pick to bypass isolation (the proxy federates for admins anyway).
  proxy_enforced = var.read_proxy_url != ""

  # The default datasource keeps its stable uid "mimir" (referenced by dashboards) but its DISPLAY name is
  # suffixed with the tenant — so the picker reads `Mimir (platform)` / `Mimir (preprod)` / `Mimir (all
  # clusters)` consistently, instead of a bare `Mimir` for the hub.
  datasource_tenants = concat(
    [{ name = "Mimir (${var.default_tenant_id})", uid = "mimir", tenant = var.default_tenant_id, is_default = var.datasource_is_default }],
    local.proxy_enforced ? [] : [for t in var.extra_tenant_datasources : { name = "Mimir (${t})", uid = "mimir-${t}", tenant = t, is_default = false }],
    var.enable_federated_datasource ? [{ name = "Mimir (all clusters)", uid = "mimir-all", tenant = join("|", local.all_tenants), is_default = false }] : [],
  )

  # Admin all-tenants direct datasource (#1269). When the proxy is enforced, every normal datasource depends on
  # Grafana forwarding the caller's OIDC token to the proxy (X-Id-Token). That path is fragile (Grafana-side
  # oauthPassThru id-token forwarding); when it breaks, admins lose all metrics. This is a break-glass datasource
  # for platform-admins: it points STRAIGHT at the gateway with a static federated X-Scope-OrgID over the full
  # tenant set (incl. per-team tenants the cluster-based `all_tenants` doesn't list), bypassing the proxy.
  # Deliberately un-proxied — it re-widens the metrics bypass, so it's opt-in (enable_admin_all_datasource) and
  # only meaningful with tenant_federation on. Falls back to all_tenants if no explicit set is given.
  admin_all_tenants = length(var.admin_all_datasource_tenants) > 0 ? var.admin_all_datasource_tenants : local.all_tenants
  admin_all_datasources = (local.proxy_enforced && var.enable_admin_all_datasource && var.enable_federated_datasource) ? [{
    name      = "Mimir (admin — all tenants)"
    type      = "prometheus"
    uid       = "mimir-admin-all"
    access    = "proxy"
    url       = "http://${var.helm_release_name}-gateway.${var.namespace}.svc/prometheus"
    isDefault = false
    jsonData = {
      timeInterval    = "30s"
      httpMethod      = "POST"
      httpHeaderName1 = "X-Scope-OrgID"
    }
    secureJsonData = { httpHeaderValue1 = join("|", local.admin_all_tenants) }
  }] : []

  grafana_datasource = {
    apiVersion = 1
    # Prune datasources removed over time (idempotent — a no-op once each is gone). Grafana provisioning keys on
    # name, so a removed datasource must be listed here or it lingers in the DB:
    #  - "Mimir": renamed to "Mimir (platform)" (same uid) — without deleting the old name the new one collides.
    #  - "Mimir (admin — all tenants)": the #1270 break-glass datasource, retired with the read-proxy (#1269) now
    #    that the direct "Mimir (all clusters)" federates the full tenant set.
    #  - "P13 Spike Echo (TEMPORARY - delete me)": a leftover prometheus datasource from an early P13 spike whose
    #    source CM was deleted, leaving it as an orphaned read-only entry the Grafana API refuses to delete —
    #    deleteDatasources is the only way to prune it.
    deleteDatasources = [
      { name = "Mimir", orgId = 1 },
      { name = "Mimir (admin — all tenants)", orgId = 1 },
      { name = "P13 Spike Echo (TEMPORARY - delete me)", orgId = 1 },
    ]
    datasources = concat([for ds in local.datasource_tenants : {
      name   = ds.name
      type   = "prometheus"
      uid    = ds.uid
      access = "proxy"
      # Enforced: query through the tenant-proxy (identity-scoped). Unenforced: straight to the gateway.
      url       = local.proxy_enforced ? var.read_proxy_url : "http://${var.helm_release_name}-gateway.${var.namespace}.svc/prometheus"
      isDefault = ds.is_default
      # exemplarTraceIdDestinations links an exemplar's trace_id to the matching Tempo tenant datasource
      # (mimir->tempo, mimir-preprod->tempo-preprod, …) — click a latency spike → open the trace (P6).
      jsonData = merge(
        {
          timeInterval = "30s"
          exemplarTraceIdDestinations = [{
            name          = "traceID" # the exemplar label the Tempo metrics-generator emits (camelCase)
            datasourceUid = replace(ds.uid, "mimir", "tempo")
          }]
        },
        # Enforced: forward the user's OIDC token to the proxy (X-Id-Token) and POST; the proxy stamps the
        # scoped X-Scope-OrgID. Unenforced: stamp the fixed per-tenant header ourselves.
        local.proxy_enforced
        ? { oauthPassThru = true, httpMethod = "POST" }
        : { httpHeaderName1 = "X-Scope-OrgID" }
      )
      # No baked-in tenant header when the proxy is the authority — the caller's identity decides scope.
      secureJsonData = local.proxy_enforced ? {} : { httpHeaderValue1 = ds.tenant }
    }], local.admin_all_datasources)
  }

  # Spoke ingest edge is created only when tenants are declared (and the store itself is enabled).
  spoke_ingest_create = local.create && length(var.spoke_ingest.tenants) > 0
}

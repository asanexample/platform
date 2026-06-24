locals {
  create  = var.create
  sa_name = var.helm_release_name

  # Sanitize tags for K8s label compliance (RFC 1123), matching the loki/mimir modules.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  traces_bucket = try(aws_s3_bucket.traces[0].bucket, "")

  # ---- Tempo helm values (grafana-community/tempo-distributed) ----
  # ONE chart, sized by high_availability — same spirit as Loki's SingleBinary<->SimpleScalable toggle:
  # dev runs every component at 1 replica (RF1, caches off) so dev exercises the real prod architecture
  # scaled down; HA flips to RF3 + zone-aware + multi-replica + caches. Chart sourced from
  # grafana-community/helm-charts (the standalone Tempo charts moved there Jan 2026 — a repo move, NOT an
  # operator pivot; app v2.10.7). OTLP ingests on the distributor (4317/4318); query API on 3200.
  helm_values = {
    fullnameOverride = var.helm_release_name

    # Multi-tenant (#628): each cluster is a tenant via X-Scope-OrgID, like Loki/Mimir. The hub OTel collector
    # stamps `default_tenant_id`; spokes are stamped at the Gateway edge. Required on read+write once on.
    multitenancyEnabled = true

    serviceAccount = {
      create = true
      name   = local.sa_name
      # Pod Identity (ADR-047) — NO IRSA annotation; the association below binds (ns, SA) -> role.
      annotations = {}
    }

    reportingEnabled = false # no usage phone-home

    # S3 trace backend. The client sends x-amz-server-side-encryption (sse=SSE-S3) to satisfy the org
    # "enforce-encryption" SCP — bucket default encryption alone doesn't add the header (same as Loki).
    storage = {
      trace = {
        backend = "s3"
        s3 = {
          bucket   = local.traces_bucket
          endpoint = "s3.${var.aws_region}.amazonaws.com"
          region   = var.aws_region
          sse      = { type = "SSE-S3" }
        }
      }
    }

    # Enable OTLP receivers (chart default is OFF) — the OTel collector pushes OTLP to the distributor.
    traces = {
      otlp = {
        grpc = { enabled = true }
        http = { enabled = true }
      }
    }

    # Sizing follows cost_profile via high_availability.
    ingester = {
      replicas             = var.high_availability ? 3 : 1
      config               = { replication_factor = var.high_availability ? 3 : 1 }
      zoneAwareReplication = { enabled = var.high_availability } # needs 3 zones
      persistence          = { enabled = true, storageClass = var.storage_class, size = "5Gi" }
      # Karpenter must not voluntarily disrupt (consolidate/drift/expire) the node the ingester runs on —
      # it's the only PVC-backed StatefulSet in tempo-distributed (holds un-flushed trace blocks). The chart
      # renders ingester.podAnnotations onto the ingester StatefulSet's pod template.
      podAnnotations = { "karpenter.sh/do-not-disrupt" = "true" }
    }
    distributor   = { replicas = var.high_availability ? 2 : 1 }
    querier       = { replicas = var.high_availability ? 2 : 1 }
    queryFrontend = { replicas = var.high_availability ? 2 : 1 }
    compactor = {
      replicas = 1
      config   = { compaction = { block_retention = var.retention_period } }
    }

    # Metrics-generator (P6 / APM): derive RED span-metrics + a service graph from traces and remote_write
    # them to Mimir per-tenant (X-Scope-OrgID preserved via remote_write_add_org_id_header, default true).
    # Deployment + emptyDir WAL in dev (a restart loses a few min of un-flushed metrics — fine for reference).
    metricsGenerator = {
      enabled = var.enable_metrics_generator
      config = {
        storage = {
          remote_write = [{ url = var.mimir_remote_write_url }]
        }
        registry = { external_labels = { source = "tempo" } }
        # local-blocks keeps recent traces in the generator so TraceQL *metrics* queries (rate/quantile over
        # spans) work — this is what powers Grafana's Traces Drilldown. flush_to_storage makes them queryable
        # over longer ranges from S3 too.
        processor = {
          local_blocks = { flush_to_storage = true }
        }
      }
    }

    # Enable the generator's processors for all tenants (empty = generate nothing when disabled). local-blocks
    # is required by Grafana Traces Drilldown (TraceQL metrics); service-graphs/span-metrics feed Mimir.
    overrides = {
      defaults = {
        metrics_generator = { processors = var.enable_metrics_generator ? ["service-graphs", "span-metrics", "local-blocks"] : [] }
      }
    }
    memcached = { enabled = var.high_availability }
    cache = var.high_availability ? {
      caches = [{
        memcached = { host = "${var.helm_release_name}-memcached", service = "memcached-client", consistent_hash = true, timeout = "500ms" }
        roles     = ["parquet-footer", "bloom", "frontend-search"]
      }]
    } : { caches = [] }
    gateway = { enabled = false }

    # Self-monitoring: ServiceMonitors for the Tempo components so Prometheus scrapes their metrics
    # (P4 store alerts). Just the ServiceMonitors — no bundled rules/agent.
    metaMonitoring = {
      serviceMonitor = { enabled = true }
    }
  }

  # ---- Grafana datasources (auto-loaded by the observability Grafana sidecar) ----
  # The hub's own `default_tenant_id` + one `Tempo (<tenant>)` per spoke (#628) + (optionally) a federated
  # `Tempo (all clusters)` spanning every tenant. All query the same frontend; only the X-Scope-OrgID differs.
  all_tenants = concat([var.default_tenant_id], var.extra_tenant_datasources)

  datasource_tenants = concat(
    [{ name = "Tempo (${var.default_tenant_id})", uid = "tempo", tenant = var.default_tenant_id }],
    [for t in var.extra_tenant_datasources : { name = "Tempo (${t})", uid = "tempo-${t}", tenant = t }],
    var.enable_federated_datasource ? [{ name = "Tempo (all clusters)", uid = "tempo-all", tenant = join("|", local.all_tenants) }] : [],
  )

  # Trace -> logs: jump from a span to its pod's logs in Loki (pairs with the Loki derivedField trace_id ->
  # tempo). Applied on every Tempo datasource.
  tempo_traces_to_logs = {
    datasourceUid      = var.loki_datasource_uid
    spanStartTimeShift = "-1h"
    spanEndTimeShift   = "1h"
    filterByTraceID    = true
    tags               = [{ key = "service.name", value = "service_name" }]
  }

  grafana_datasource = {
    apiVersion = 1
    # Rename migration (bare "Tempo" -> "Tempo (platform)", same uid): delete the old name first so provisioning
    # doesn't collide on uid and 500 the reload. Idempotent. See the mimir module for the full rationale.
    deleteDatasources = [{ name = "Tempo", orgId = 1 }]
    datasources = [for ds in local.datasource_tenants : {
      name   = ds.name
      type   = "tempo"
      uid    = ds.uid
      access = "proxy"
      url    = "http://${var.helm_release_name}-query-frontend.${var.namespace}.svc:3200"
      # serviceMap points at the matching Mimir tenant datasource so Grafana renders the node graph from the
      # generator's `traces_service_graph_*` metrics (tempo->mimir, tempo-preprod->mimir-preprod, …).
      # tracesToProfilesV2 (P8b) links a span -> its CPU flame graph in the matching Pyroscope tenant datasource
      # (tempo->pyroscope), matching the span's service.name to the profile's service_name label.
      jsonData = merge({
        httpHeaderName1 = "X-Scope-OrgID"
        tracesToLogsV2  = local.tempo_traces_to_logs
        serviceMap      = { datasourceUid = replace(ds.uid, "tempo", "mimir") }
        }, var.enable_traces_to_profiles ? {
        tracesToProfilesV2 = {
          datasourceUid = replace(ds.uid, "tempo", "pyroscope")
          profileTypeId = "process_cpu:cpu:nanoseconds:cpu:nanoseconds"
          tags          = [{ key = "service.name", value = "service_name" }]
        }
      } : {})
      secureJsonData = { httpHeaderValue1 = ds.tenant }
    }]
  }

  spoke_ingest_create = local.create && length(var.spoke_ingest.tenants) > 0
}

# ---------------------------------------------------------------------------
# S3 — Tempo trace storage (SSE-S3/AES256, mirrors observability-loki)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "traces" {
  count = local.create ? 1 : 0

  bucket_prefix = "${var.cluster_name}-tempo-traces-"
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "traces" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.traces[0].id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "traces" {
  count = local.create ? 1 : 0

  bucket                  = aws_s3_bucket.traces[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "traces" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.traces[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "traces" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.traces[0].id
  versioning_configuration { status = "Enabled" }
}

# Tempo's compactor manages trace lifecycle (block_retention); versioning exists for the security baseline.
resource "aws_s3_bucket_lifecycle_configuration" "traces" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.traces[0].id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

# ---------------------------------------------------------------------------
# EKS Pod Identity — IAM role for the Tempo ServiceAccount (S3 trace access)
# (ADR-047 standard; trust pods.eks.amazonaws.com — no OIDC/IRSA.)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "tempo_trust" {
  count = local.create ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "tempo" {
  count = local.create ? 1 : 0

  name_prefix        = "${var.cluster_name}-tempo-"
  assume_role_policy = data.aws_iam_policy_document.tempo_trust[0].json
  tags               = var.tags
}

# AES256 bucket => no KMS statement needed. Scoped to the traces bucket only.
resource "aws_iam_role_policy" "tempo_s3" {
  count = local.create ? 1 : 0

  name = "traces-storage"
  role = aws_iam_role.tempo[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.traces[0].arn]
      },
      {
        Sid      = "ObjectRW"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.traces[0].arn}/*"]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "tempo" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.sa_name
  role_arn        = aws_iam_role.tempo[0].arn
  tags            = var.tags
}

# ---------------------------------------------------------------------------
# Helm release — grafana-community/tempo-distributed
# ---------------------------------------------------------------------------

resource "helm_release" "tempo" {
  count = local.create ? 1 : 0

  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false # the observability module owns the namespace (PSA label)
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true

  values = [yamlencode(local.helm_values)]

  depends_on = [
    aws_iam_role_policy.tempo_s3,
    aws_eks_pod_identity_association.tempo,
  ]
}

# ---------------------------------------------------------------------------
# Grafana datasource (sidecar-discovered ConfigMap in the observability namespace)
# ---------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "grafana_datasource" {
  count = local.create ? 1 : 0

  metadata {
    name      = "${var.helm_release_name}-grafana-datasource"
    namespace = var.namespace
    labels    = merge(local.k8s_labels, { grafana_datasource = "1" })
  }

  data = {
    "tempo-datasource.yaml" = yamlencode(local.grafana_datasource)
  }
}

# ---------------------------------------------------------------------------
# Cross-cluster spoke TRACE ingest edge (#628) — Gateway-API-native, no proxy. Mirrors the Loki/Mimir edges:
# a write-only HTTPRoute on the shared Cilium Gateway that FORCE-SETS X-Scope-OrgID to the mapped tenant and
# routes only the OTLP/HTTP trace path to the Tempo distributor. Auth = network isolation.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "spoke_ingest_route" {
  for_each = local.spoke_ingest_create ? var.spoke_ingest.tenants : {}

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "${var.helm_release_name}-spoke-${each.key}"
      namespace = var.namespace
    }
    spec = {
      parentRefs = [{
        name        = var.spoke_ingest.gateway_name
        namespace   = var.spoke_ingest.gateway_namespace
        sectionName = "https"
      }]
      hostnames = ["${each.key}-traces.${var.spoke_ingest.domain}"]
      rules = [{
        # Write-only: only the OTLP/HTTP trace push path is routed; query APIs are not exposed cross-cluster.
        matches = [{ path = { type = "PathPrefix", value = "/v1/traces" } }]
        filters = [{
          type                  = "RequestHeaderModifier"
          requestHeaderModifier = { set = [{ name = "X-Scope-OrgID", value = each.value }] }
        }]
        backendRefs = [{
          name = "${var.helm_release_name}-distributor"
          port = 4318 # OTLP/HTTP on the Tempo distributor
        }]
      }]
    }
  }
}

# Admit the Cilium Gateway Envoy (reserved `ingress` identity) to the Tempo distributor past the
# observability ns default-deny (the documented gotcha — a standard NetworkPolicy `from:` can't match it).
resource "kubernetes_manifest" "spoke_ingest_from_gateway" {
  count = local.spoke_ingest_create ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "${var.helm_release_name}-spoke-ingest-from-gateway"
      namespace = var.namespace
    }
    spec = {
      endpointSelector = {
        matchLabels = {
          "app.kubernetes.io/name"      = var.helm_release_name
          "app.kubernetes.io/component" = "distributor"
        }
      }
      ingress = [{ fromEntities = ["ingress"] }]
    }
  }
}

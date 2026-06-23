locals {
  create      = var.create
  create_irsa = local.create && var.oidc_provider_arn != ""
  sa_name     = var.helm_release_name

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
      annotations = local.create_irsa ? {
        "eks.amazonaws.com/role-arn" = aws_iam_role.mimir[0].arn
      } : {}
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
              # IRSA: access_key_id/secret_access_key intentionally omitted -> AWS SDK web-identity chain.
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

    ingester = {
      replicas             = var.high_availability ? 3 : 1
      zoneAwareReplication = { enabled = var.high_availability }
      persistentVolume     = { enabled = true, storageClass = var.storage_class, size = "10Gi" }
    }
    store_gateway = {
      replicas             = var.high_availability ? 3 : 1
      zoneAwareReplication = { enabled = var.high_availability }
      persistentVolume     = { enabled = true, storageClass = var.storage_class, size = "10Gi" }
    }
    compactor = {
      replicas         = 1
      persistentVolume = { enabled = true, storageClass = var.storage_class, size = "20Gi" }
    }

    # --- Disabled in P2 (ruler/alertmanager -> P4; the rest are HA-only) ---
    ruler              = { enabled = false }
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

  # The default datasource keeps its stable uid "mimir" (referenced by dashboards) but its DISPLAY name is
  # suffixed with the tenant — so the picker reads `Mimir (platform)` / `Mimir (preprod)` / `Mimir (all
  # clusters)` consistently, instead of a bare `Mimir` for the hub.
  datasource_tenants = concat(
    [{ name = "Mimir (${var.default_tenant_id})", uid = "mimir", tenant = var.default_tenant_id, is_default = var.datasource_is_default }],
    [for t in var.extra_tenant_datasources : { name = "Mimir (${t})", uid = "mimir-${t}", tenant = t, is_default = false }],
    var.enable_federated_datasource ? [{ name = "Mimir (all clusters)", uid = "mimir-all", tenant = join("|", local.all_tenants), is_default = false }] : [],
  )

  grafana_datasource = {
    apiVersion = 1
    # Rename migration: the default datasource was bare "Mimir"; it's now "Mimir (platform)" (same uid). Grafana
    # provisioning keys on name, so without deleting the old name first the new one collides on uid and 500s
    # the whole reload. Idempotent — a no-op once the old name is gone.
    deleteDatasources = [{ name = "Mimir", orgId = 1 }]
    datasources = [for ds in local.datasource_tenants : {
      name      = ds.name
      type      = "prometheus"
      uid       = ds.uid
      access    = "proxy"
      url       = "http://${var.helm_release_name}-gateway.${var.namespace}.svc/prometheus"
      isDefault = ds.is_default
      # exemplarTraceIdDestinations links an exemplar's trace_id to the matching Tempo tenant datasource
      # (mimir->tempo, mimir-preprod->tempo-preprod, …) — click a latency spike → open the trace (P6).
      jsonData = {
        httpHeaderName1 = "X-Scope-OrgID"
        timeInterval    = "30s"
        exemplarTraceIdDestinations = [{
          name          = "traceID" # the exemplar label the Tempo metrics-generator emits (camelCase)
          datasourceUid = replace(ds.uid, "mimir", "tempo")
        }]
      }
      secureJsonData = { httpHeaderValue1 = ds.tenant }
    }]
  }

  # Spoke ingest edge is created only when tenants are declared (and the store itself is enabled).
  spoke_ingest_create = local.create && length(var.spoke_ingest.tenants) > 0
}

# ---------------------------------------------------------------------------
# S3 — Mimir blocks storage (SSE-S3/AES256, mirrors infra/modules/aws/s3)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "blocks" {
  count = local.create ? 1 : 0

  bucket_prefix = "${var.cluster_name}-mimir-blocks-"
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "blocks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.blocks[0].id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "blocks" {
  count = local.create ? 1 : 0

  bucket                  = aws_s3_bucket.blocks[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "blocks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.blocks[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "blocks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.blocks[0].id
  versioning_configuration { status = "Enabled" }
}

# Mimir's compactor manages object lifecycle; versioning exists only to satisfy the security baseline.
# Expire noncurrent versions fast + abort dangling multipart uploads so the bucket doesn't grow unbounded.
resource "aws_s3_bucket_lifecycle_configuration" "blocks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.blocks[0].id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

# ---------------------------------------------------------------------------
# IRSA — IAM role for the Mimir ServiceAccount (S3 blocks access)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "mimir_trust" {
  count = local.create_irsa ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${local.sa_name}"]
    }
  }
}

resource "aws_iam_role" "mimir" {
  count = local.create_irsa ? 1 : 0

  name_prefix        = "${var.cluster_name}-mimir-"
  assume_role_policy = data.aws_iam_policy_document.mimir_trust[0].json
  tags               = var.tags
}

# AES256 bucket => no KMS statement needed (unlike an SSE-KMS bucket, which would require
# kms:GenerateDataKey*/Decrypt or writes fail with AccessDenied). Scoped to the blocks bucket only.
resource "aws_iam_role_policy" "mimir_s3" {
  count = local.create_irsa ? 1 : 0

  name = "blocks-storage"
  role = aws_iam_role.mimir[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.blocks[0].arn]
      },
      {
        Sid      = "ObjectRW"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.blocks[0].arn}/*"]
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Helm release — mimir-distributed
# ---------------------------------------------------------------------------

resource "helm_release" "mimir" {
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

  depends_on = [aws_iam_role_policy.mimir_s3]
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
    "mimir-datasource.yaml" = yamlencode(local.grafana_datasource)
  }
}

# ---------------------------------------------------------------------------
# Cross-cluster spoke ingest edge (P10) — Gateway-API-native, no proxy.
# Per spoke: a write-only HTTPRoute on the shared Cilium Gateway that FORCE-SETS X-Scope-OrgID to the
# mapped tenant (overwriting any client value — so a spoke can't spoof another tenant, the ADR-044 guard)
# and routes only /api/v1/push (no query path is exposed cross-cluster). The header-overwrite + path-match
# are native Gateway API filters — same idiom the repo already uses for HTTP→HTTPS redirects. Auth is
# network isolation (the internal NLB reachable only over the VPC/TGW); mTLS is the P10.x hardening follow-up.
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
      hostnames = ["${each.key}-mimir.${var.spoke_ingest.domain}"]
      rules = [{
        # Write-only: only the remote_write push path is routed; everything else (incl. /prometheus) 404s.
        matches = [{ path = { type = "PathPrefix", value = "/api/v1/push" } }]
        # Overwrite the tenant from the authenticated route (the hostname), ignoring any client header.
        filters = [{
          type = "RequestHeaderModifier"
          requestHeaderModifier = {
            set = [{ name = "X-Scope-OrgID", value = each.value }]
          }
        }]
        backendRefs = [{
          name = "${var.helm_release_name}-gateway"
          port = 80
        }]
      }]
    }
  }
}

# The Gateway's Envoy connects with the reserved Cilium `ingress` identity (8), which a STANDARD k8s
# NetworkPolicy `from:` can't match — so admit it to the Mimir gateway via a CiliumNetworkPolicy
# (the repo's documented Gateway gotcha; mirrors `allow-grafana-from-gateway` in the observability module).
# Ports omitted: the gateway pod's nginx targetPort isn't worth hardcoding — the `ingress` entity is the
# trusted Envoy, and the default-deny + this single allow already scope who reaches the gateway pods.
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
          "app.kubernetes.io/component" = "gateway"
        }
      }
      ingress = [{ fromEntities = ["ingress"] }]
    }
  }
}

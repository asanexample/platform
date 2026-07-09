locals {
  create  = var.create
  sa_name = var.helm_release_name

  # Sanitize tags for K8s label compliance (RFC 1123), matching the observability + mimir modules.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  chunks_bucket = try(aws_s3_bucket.chunks[0].bucket, "")

  # ---- Loki helm values (grafana/loki; SingleBinary single-replica unless high_availability) ----
  helm_values = {
    # Deterministic resource names: <name>-gateway, <name>-read, … and the SA = <name>.
    nameOverride     = var.helm_release_name
    fullnameOverride = var.helm_release_name

    serviceAccount = {
      create = true
      name   = local.sa_name
      # Pod Identity (ADR-047) — NO IRSA `eks.amazonaws.com/role-arn` annotation. The
      # aws_eks_pod_identity_association below binds (ns, SA) -> role; creds arrive via the agent.
      annotations = {}
    }

    # We use S3 — do NOT deploy the chart's bundled demo MinIO.
    minio = { enabled = false }

    # SingleBinary (reference) ↔ SimpleScalable RF3 (HA), driven by one toggle.
    deploymentMode = var.high_availability ? "SimpleScalable" : "SingleBinary"

    loki = {
      # X-Scope-OrgID required on read+write. NOTE: a trust header, not auth — in-cluster isolation
      # rests on the observability ns default-deny NetworkPolicy (tenant pods can't reach us).
      auth_enabled = true

      commonConfig = {
        replication_factor = var.high_availability ? 3 : 1
      }

      # tsdb + schema v13 is mandatory on modern Loki (the chart errors without a schemaConfig).
      schemaConfig = {
        configs = [{
          from         = "2024-04-01"
          store        = "tsdb"
          object_store = "s3"
          schema       = "v13"
          index        = { prefix = "loki_index_", period = "24h" }
        }]
      }

      storage = {
        type = "s3"
        bucketNames = {
          chunks = local.chunks_bucket
          ruler  = local.chunks_bucket
          admin  = local.chunks_bucket
        }
        # No static creds — Pod Identity injects via the AWS SDK credential chain.
        # SSE: the org SCP "enforce-encryption" (DenyUnencryptedS3Uploads) denies any PutObject whose
        # request omits the x-amz-server-side-encryption header — the bucket's *default* encryption does
        # not add that header. So the client must send it. SSE-S3 (AES256) matches the bucket.
        s3 = {
          region = var.aws_region
          sse    = { type = "SSE-S3" }
        }
      }

      # Per-tenant limits double as the noisy-neighbor security control.
      limits_config = {
        retention_period            = var.retention_period
        ingestion_rate_mb           = var.ingestion_rate_mb
        ingestion_burst_size_mb     = var.ingestion_burst_size_mb
        max_global_streams_per_user = var.max_global_streams_per_user
        reject_old_samples          = true
        reject_old_samples_max_age  = "168h"
      }

      compactor = {
        retention_enabled    = true
        delete_request_store = "s3"
      }
    }

    # Karpenter must not voluntarily disrupt (consolidate/drift/expire) the nodes Loki's stateful pods run
    # on (PVC-backed local index/WAL). The chart renders <component>.podAnnotations onto each component's
    # StatefulSet pod template. SingleBinary (dev) is one StatefulSet; SimpleScalable (HA) makes write +
    # backend StatefulSets (read is a stateless Deployment) — annotate all the stateful tiers so the right
    # object is covered in either deployment mode.

    # SingleBinary path (reference): one replica with a PVC. Zeroed when HA.
    singleBinary = {
      replicas       = var.high_availability ? 0 : 1
      persistence    = { enabled = true, storageClass = var.storage_class, size = "10Gi" }
      podAnnotations = { "karpenter.sh/do-not-disrupt" = "true" }
    }

    # SimpleScalable path (HA only): read/write/backend tiers, zeroed in single-binary mode.
    read    = { replicas = var.high_availability ? 3 : 0 }
    write   = { replicas = var.high_availability ? 3 : 0, podAnnotations = { "karpenter.sh/do-not-disrupt" = "true" } }
    backend = { replicas = var.high_availability ? 3 : 0, podAnnotations = { "karpenter.sh/do-not-disrupt" = "true" } }

    # Single push/query entry point (nginx gateway).
    gateway = { enabled = true, replicas = var.high_availability ? 2 : 1 }

    # Trim the reference footprint: memcached caches + canary + helm tests off unless HA.
    chunksCache  = { enabled = var.high_availability }
    resultsCache = { enabled = var.high_availability }
    lokiCanary   = { enabled = false }
    test         = { enabled = false }

    # Self-monitoring: scrape Loki's own metrics into Prometheus (P4 store alerts). ServiceMonitor only —
    # not the chart's bundled rules/dashboards/agent (we author curated rules + manage dashboards).
    monitoring = {
      # The chart hardcodes a relabeling that sets `cluster=loki` on Loki's self-metrics, polluting the real
      # cluster dimension (#630). Loki has no clusterLabel knob, so drop the label post-scrape — Prometheus
      # externalLabels.cluster then attributes them to the actual cluster.
      serviceMonitor = {
        enabled           = true
        metricRelabelings = [{ action = "labeldrop", regex = "cluster" }]
      }
      selfMonitoring = { enabled = false }
      rules          = { enabled = false }
      dashboards     = { enabled = false }
    }
  }

  # ---- Grafana datasources (auto-loaded by the observability Grafana sidecar) ----
  # The hub's own `default_tenant_id` + one `Loki (<tenant>)` per spoke (#627) + (optionally) a federated
  # `Loki (all clusters)` spanning every tenant (#626/#629). All query the same gateway; only the header differs.
  all_tenants = concat([var.default_tenant_id], var.extra_tenant_datasources)

  # P13 enforcement (#590): identical to the mimir module — when read_proxy_url is set, datasources point at
  # the loki-tenant-proxy with oauthPassThru (SSO identity decides scope) and the per-cluster bypass
  # datasources are dropped, leaving only `loki` + `loki-all` (both proxy-fronted).
  proxy_enforced = var.read_proxy_url != ""

  datasource_tenants = concat(
    [{ name = "Loki (${var.default_tenant_id})", uid = "loki", tenant = var.default_tenant_id }],
    local.proxy_enforced ? [] : [for t in var.extra_tenant_datasources : { name = "Loki (${t})", uid = "loki-${t}", tenant = t }],
    var.enable_federated_datasource ? [{ name = "Loki (all clusters)", uid = "loki-all", tenant = join("|", local.all_tenants) }] : [],
  )

  # A trace_id in a log line links straight to the Tempo trace (log → trace). Points at the CROSS-CLUSTER
  # Tempo datasource (tempo-all, X-Scope-OrgID `platform|preprod`) not the single-cluster `tempo`: a log can
  # come from any cluster and its trace lands in that cluster's Tempo tenant, so the link must span tenants
  # (Tempo tenant-federation honours the `a|b` OrgID — verified). Without this a preprod app's log links to
  # the platform tenant and the trace is "not found".
  loki_derived_fields = [{
    name          = "trace_id"
    matcherRegex  = "trace_?[iI][dD]\"?[:=]\\s*\"?([0-9a-fA-F]+)"
    url           = "$${__value.raw}"
    datasourceUid = "tempo-all"
  }]

  grafana_datasource = {
    apiVersion = 1
    # Rename migration (bare "Loki" -> "Loki (platform)", same uid): delete the old name first so provisioning
    # doesn't collide on uid and 500 the reload. Idempotent. See the mimir module for the full rationale.
    deleteDatasources = [{ name = "Loki", orgId = 1 }]
    datasources = [for ds in local.datasource_tenants : {
      name   = ds.name
      type   = "loki"
      uid    = ds.uid
      access = "proxy"
      url    = local.proxy_enforced ? var.read_proxy_url : "http://${var.helm_release_name}-gateway.${var.namespace}.svc"
      jsonData = merge(
        { derivedFields = local.loki_derived_fields },
        local.proxy_enforced ? { oauthPassThru = true } : { httpHeaderName1 = "X-Scope-OrgID" },
      )
      secureJsonData = local.proxy_enforced ? {} : { httpHeaderValue1 = ds.tenant }
    }]
  }

  spoke_ingest_create = local.create && length(var.spoke_ingest.tenants) > 0
}

# ---------------------------------------------------------------------------
# S3 — Loki chunks storage (SSE-S3/AES256, mirrors observability-mimir)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "chunks" {
  count = local.create ? 1 : 0

  bucket_prefix = "${var.cluster_name}-loki-chunks-"
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "chunks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.chunks[0].id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "chunks" {
  count = local.create ? 1 : 0

  bucket                  = aws_s3_bucket.chunks[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "chunks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.chunks[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "chunks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.chunks[0].id
  versioning_configuration { status = "Enabled" }
}

# Loki's compactor manages object lifecycle (retention); versioning exists only for the security baseline.
resource "aws_s3_bucket_lifecycle_configuration" "chunks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.chunks[0].id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

# ---------------------------------------------------------------------------
# EKS Pod Identity — IAM role for the Loki ServiceAccount (S3 chunks access)
# (ADR-047 standard; trust pods.eks.amazonaws.com — no OIDC/IRSA.)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "loki_trust" {
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

resource "aws_iam_role" "loki" {
  count = local.create ? 1 : 0

  name_prefix        = "${var.cluster_name}-loki-"
  assume_role_policy = data.aws_iam_policy_document.loki_trust[0].json
  tags               = var.tags
}

# AES256 bucket => no KMS statement needed. Scoped to the chunks bucket only.
resource "aws_iam_role_policy" "loki_s3" {
  count = local.create ? 1 : 0

  name = "chunks-storage"
  role = aws_iam_role.loki[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.chunks[0].arn]
      },
      {
        Sid      = "ObjectRW"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.chunks[0].arn}/*"]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "loki" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.sa_name
  role_arn        = aws_iam_role.loki[0].arn
  tags            = var.tags
}

# ---------------------------------------------------------------------------
# Helm release — grafana/loki
# ---------------------------------------------------------------------------

resource "helm_release" "loki" {
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
    aws_iam_role_policy.loki_s3,
    aws_eks_pod_identity_association.loki,
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
    "loki-datasource.yaml" = yamlencode(local.grafana_datasource)
  }
}

# ---------------------------------------------------------------------------
# Cross-cluster spoke LOG ingest edge (#627) — Gateway-API-native, no proxy. Mirrors the Mimir edge: a
# write-only HTTPRoute on the shared Cilium Gateway that FORCE-SETS X-Scope-OrgID to the mapped tenant
# (so a spoke can't spoof another tenant) and routes only the Loki push path. Auth = network isolation.
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
      hostnames = ["${each.key}-logs.${var.spoke_ingest.domain}"]
      rules = [{
        # Write-only: only the Loki push path is routed; everything else (incl. query APIs) 404s.
        matches = [{ path = { type = "PathPrefix", value = "/loki/api/v1/push" } }]
        # Default: FORCE-SET the tenant (a spoke can't spoof another). P13 per-team logs need the spoke to
        # set its own per-team tenant, so `spoke_ingest_passthrough` drops the force-set and passes the
        # Alloy-supplied X-Scope-OrgID through — a write-integrity tradeoff hardened later by ingest mTLS.
        filters = var.spoke_ingest_passthrough ? [] : [{
          type                  = "RequestHeaderModifier"
          requestHeaderModifier = { set = [{ name = "X-Scope-OrgID", value = each.value }] }
        }]
        backendRefs = [{
          name = "${var.helm_release_name}-gateway"
          port = 80
        }]
      }]
    }
  }
}

# Admit the Cilium Gateway Envoy (reserved `ingress` identity) to the Loki gateway past the observability
# ns default-deny — a standard NetworkPolicy `from:` can't match that identity (the documented gotcha).
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

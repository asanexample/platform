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
        s3 = { region = var.aws_region }
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

    # SingleBinary path (reference): one replica with a PVC. Zeroed when HA.
    singleBinary = {
      replicas    = var.high_availability ? 0 : 1
      persistence = { enabled = true, storageClass = var.storage_class, size = "10Gi" }
    }

    # SimpleScalable path (HA only): read/write/backend tiers, zeroed in single-binary mode.
    read    = { replicas = var.high_availability ? 3 : 0 }
    write   = { replicas = var.high_availability ? 3 : 0 }
    backend = { replicas = var.high_availability ? 3 : 0 }

    # Single push/query entry point (nginx gateway).
    gateway = { enabled = true, replicas = var.high_availability ? 2 : 1 }

    # Trim the reference footprint: memcached caches + canary + helm tests off unless HA.
    chunksCache  = { enabled = var.high_availability }
    resultsCache = { enabled = var.high_availability }
    lokiCanary   = { enabled = false }
    test         = { enabled = false }
  }

  # ---- Grafana datasource (auto-loaded by the observability Grafana sidecar) ----
  grafana_datasource = {
    apiVersion = 1
    datasources = [{
      name   = "Loki"
      type   = "loki"
      uid    = "loki"
      access = "proxy"
      url    = "http://${var.helm_release_name}-gateway.${var.namespace}.svc"
      jsonData = {
        httpHeaderName1 = "X-Scope-OrgID"
        # A trace_id in a log line links straight to the Tempo trace (trace→logs↔logs→trace).
        derivedFields = [{
          name          = "trace_id"
          matcherRegex  = "trace_?[iI][dD]\"?[:=]\\s*\"?([0-9a-fA-F]+)"
          url           = "$${__value.raw}"
          datasourceUid = "tempo"
        }]
      }
      secureJsonData = { httpHeaderValue1 = var.default_tenant_id }
    }]
  }
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

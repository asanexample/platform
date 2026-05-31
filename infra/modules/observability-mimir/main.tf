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
    metaMonitoring = {
      serviceMonitor = { enabled = true }
    }

    mimir = {
      structuredConfig = {
        # X-Scope-OrgID required on read+write. NOTE: this is a trust header, not auth — in-cluster
        # isolation rests on the observability ns default-deny NetworkPolicy (tenant pods can't reach us).
        multitenancy_enabled = true

        common = {
          storage = {
            backend = "s3"
            s3 = {
              region   = var.aws_region
              endpoint = "s3.${var.aws_region}.amazonaws.com"
              # IRSA: access_key_id/secret_access_key intentionally omitted -> AWS SDK web-identity chain.
            }
          }
        }

        blocks_storage = {
          backend = "s3"
          s3      = { bucket_name = try(aws_s3_bucket.blocks[0].bucket, "") }
        }

        # Single ingester => replication_factor must be 1 or writes are rejected.
        ingester = { ring = { replication_factor = var.high_availability ? 3 : 1 } }

        limits = {
          max_global_series_per_user        = var.max_global_series_per_user
          ingestion_rate                    = var.ingestion_rate
          ingestion_burst_size              = var.ingestion_burst_size
          compactor_blocks_retention_period = var.blocks_retention
        }
      }
    }

    # Single entry point (nginx) for push + query.
    gateway = { enabled = true, replicas = var.high_availability ? 2 : 1 }

    # --- Write/read path ---
    distributor     = { replicas = var.high_availability ? 3 : 1 }
    querier         = { replicas = var.high_availability ? 2 : 1 }
    query_frontend  = { replicas = var.high_availability ? 2 : 1 }
    query_scheduler = { enabled = var.high_availability }

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

  # ---- Grafana datasource (auto-loaded by the observability Grafana sidecar) ----
  grafana_datasource = {
    apiVersion = 1
    datasources = [{
      name           = "Mimir"
      type           = "prometheus"
      uid            = "mimir"
      access         = "proxy"
      url            = "http://${var.helm_release_name}-gateway.${var.namespace}.svc/prometheus"
      isDefault      = var.datasource_is_default
      jsonData       = { httpHeaderName1 = "X-Scope-OrgID", timeInterval = "30s" }
      secureJsonData = { httpHeaderValue1 = var.default_tenant_id }
    }]
  }
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

resource "kubernetes_config_map" "grafana_datasource" {
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

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

  # ---- Tempo helm values (grafana-community/tempo — single-binary monolith) ----
  # One pod (lands on a node with room) fits the cost-effective cluster — mirrors Loki's single-binary
  # choice. The chart moved to grafana-community/helm-charts (Jan 2026); it is NOT an operator pivot.
  # OTLP receivers ingest on 4317/4318; the query API serves on 3200. HA/prod = the tempo-distributed
  # chart (a future path).
  helm_values = {
    fullnameOverride = var.helm_release_name

    serviceAccount = {
      create = true
      name   = local.sa_name
      # Pod Identity (ADR-047) — NO IRSA annotation; the association below binds (ns, SA) -> role.
      annotations = {}
    }

    tempo = {
      reportingEnabled = false # no usage phone-home
      retention        = var.retention_period

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
          wal = { path = "/var/tempo/wal" }
        }
      }

      # OTLP only (the OTel collector speaks OTLP); drop the jaeger/opencensus receivers + ports.
      receivers = {
        otlp = {
          protocols = {
            grpc = { endpoint = "0.0.0.0:4317" }
            http = { endpoint = "0.0.0.0:4318" }
          }
        }
      }

      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "768Mi" }
      }
    }

    # WAL + local blocks before flush to S3 — a small PVC for the reference cluster.
    persistence = {
      enabled      = true
      storageClass = var.storage_class
      size         = "5Gi"
    }

    # The metrics-generator (service graphs / span metrics) needs Prometheus remote-write; defer (Mimir).
    metricsGenerator = { enabled = false }
  }

  # ---- Grafana datasource (auto-loaded by the observability Grafana sidecar) ----
  grafana_datasource = {
    apiVersion = 1
    datasources = [{
      name   = "Tempo"
      type   = "tempo"
      uid    = "tempo"
      access = "proxy"
      url    = "http://${var.helm_release_name}.${var.namespace}.svc:3200"
      jsonData = {
        # Trace -> logs: jump from a span to its pod's logs in Loki (pairs with the Loki datasource's
        # derivedField trace_id -> tempo, giving bidirectional correlation).
        tracesToLogsV2 = {
          datasourceUid      = var.loki_datasource_uid
          spanStartTimeShift = "-1h"
          spanEndTimeShift   = "1h"
          filterByTraceID    = true
          tags               = [{ key = "service.name", value = "service_name" }]
        }
      }
    }]
  }
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
# Helm release — grafana-community/tempo
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

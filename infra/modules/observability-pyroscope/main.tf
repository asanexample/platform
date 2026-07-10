locals {
  create  = var.create
  sa_name = var.helm_release_name

  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  profiles_bucket = try(aws_s3_bucket.profiles[0].bucket, "")

  # ---- Pyroscope helm values (grafana/pyroscope v2; monolithic single-binary) ----
  # The chart's final config = pyroscope.config (empty when minio off) mergeOverwrite pyroscope.structuredConfig,
  # so structuredConfig carries the whole storage + multitenancy config in Pyroscope's native schema.
  helm_values = {
    # Deterministic names: Service `pyroscope` (:4040 http datasource, :9095 grpc) and SA `pyroscope`.
    nameOverride     = var.helm_release_name
    fullnameOverride = var.helm_release_name

    # We use S3 — do NOT deploy the chart's bundled demo MinIO.
    minio = { enabled = false }

    # eBPF profile collection is a SEPARATE module (P8b) — disable the chart's bundled Alloy.
    alloy = { enabled = false }

    pyroscope = {
      replicaCount = 1

      # Karpenter must not voluntarily disrupt (consolidate/drift/expire) the node this single-binary
      # StatefulSet runs on — it holds the local WAL + the v2 metastore RAFT state on a PVC. The chart
      # renders pyroscope.podAnnotations onto the StatefulSet's pod template.
      podAnnotations = {
        "karpenter.sh/do-not-disrupt" = "true"
      }

      serviceAccount = {
        create = true
        name   = local.sa_name
        # Pod Identity (ADR-047) — NO IRSA `eks.amazonaws.com/role-arn` annotation.
        annotations = {}
      }

      # PVC for the local WAL + the v2 metastore RAFT state (default is emptyDir → lost on restart). The
      # durable profile store is S3; this protects in-flight/metadata state across restarts.
      persistence = {
        enabled      = true
        storageClass = var.storage_class
        size         = var.persistence_size
      }

      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }

      structuredConfig = {
        # Require X-Scope-OrgID on read+write (each cluster is a tenant, like the other stores). NOTE: a
        # trust header, not auth — in-cluster isolation rests on the observability ns default-deny NetworkPolicy.
        multitenancy_enabled = true

        storage = {
          backend = "s3"
          s3 = {
            bucket_name = local.profiles_bucket
            region      = var.aws_region
            # Pyroscope's S3 client requires an explicit endpoint (it doesn't derive it from region).
            endpoint = "s3.${var.aws_region}.amazonaws.com"
            # No static creds — Pod Identity injects via the AWS SDK credential chain.
            # SSE: the org `enforce-encryption` SCP denies any PutObject without the
            # x-amz-server-side-encryption header (bucket default encryption doesn't add it), so the client
            # must send it. Pyroscope's S3 config is Grafana/dskit-lineage (like Mimir) — the key is `sse.type`
            # (NOT Thanos's `sse_config`). SSE-S3 = AES256.
            sse = { type = "SSE-S3" }
          }
        }
      }
    }
  }

  # ---- Grafana datasources (auto-loaded by the observability Grafana sidecar) ----
  datasource_tenants = concat(
    [{ name = "Pyroscope (${var.default_tenant_id})", uid = "pyroscope", tenant = var.default_tenant_id }],
    [for t in var.extra_tenant_datasources : { name = "Pyroscope (${t})", uid = "pyroscope-${t}", tenant = t }],
  )

  grafana_datasource = {
    apiVersion = 1
    datasources = [for ds in local.datasource_tenants : {
      name           = ds.name
      type           = "grafana-pyroscope-datasource"
      uid            = ds.uid
      access         = "proxy"
      url            = "http://${var.helm_release_name}.${var.namespace}.svc:4040"
      jsonData       = { httpHeaderName1 = "X-Scope-OrgID" }
      secureJsonData = { httpHeaderValue1 = ds.tenant }
    }]
  }

  spoke_ingest_create = local.create && length(var.spoke_ingest.tenants) > 0

  # Pyroscope's two write paths (both routed on the spoke-ingest edge, both write-only):
  #  - `/push.v1.PusherService` — the Connect PusherService the Alloy `pyroscope.write` client (eBPF) posts to.
  #  - `/ingest` — the legacy HTTP push path the pyroscope-go SDK posts to (app span profiles, #1269). App SDKs
  #    push here (not push.v1), so the app-level trace→profiles pipeline needs this path matched too.
  pyroscope_push_paths = ["/push.v1.PusherService", "/ingest"]
}

# ---------------------------------------------------------------------------
# S3 — Pyroscope profiles storage (SSE-S3/AES256, mirrors observability-loki)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "profiles" {
  count = local.create ? 1 : 0

  bucket_prefix = "${var.cluster_name}-pyroscope-profiles-"
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "profiles" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.profiles[0].id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "profiles" {
  count = local.create ? 1 : 0

  bucket                  = aws_s3_bucket.profiles[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "profiles" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.profiles[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "profiles" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.profiles[0].id
  versioning_configuration { status = "Enabled" }
}

# Pyroscope manages object lifecycle/retention; versioning exists only for the security baseline.
resource "aws_s3_bucket_lifecycle_configuration" "profiles" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.profiles[0].id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

# ---------------------------------------------------------------------------
# EKS Pod Identity — IAM role for the Pyroscope ServiceAccount (S3 profiles access)
# (ADR-047 standard; trust pods.eks.amazonaws.com — no OIDC/IRSA.)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "pyroscope_trust" {
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

resource "aws_iam_role" "pyroscope" {
  count = local.create ? 1 : 0

  name_prefix        = "${var.cluster_name}-pyro-"
  assume_role_policy = data.aws_iam_policy_document.pyroscope_trust[0].json
  tags               = var.tags
}

# AES256 bucket => no KMS statement needed. Scoped to the profiles bucket only.
resource "aws_iam_role_policy" "pyroscope_s3" {
  count = local.create ? 1 : 0

  name = "profiles-storage"
  role = aws_iam_role.pyroscope[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.profiles[0].arn]
      },
      {
        Sid      = "ObjectRW"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.profiles[0].arn}/*"]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "pyroscope" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.sa_name
  role_arn        = aws_iam_role.pyroscope[0].arn
  tags            = var.tags
}

# ---------------------------------------------------------------------------
# Helm release — grafana/pyroscope
# ---------------------------------------------------------------------------

resource "helm_release" "pyroscope" {
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
    aws_iam_role_policy.pyroscope_s3,
    aws_eks_pod_identity_association.pyroscope,
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
    "pyroscope-datasource.yaml" = yamlencode(local.grafana_datasource)
  }
}

# ---------------------------------------------------------------------------
# Cross-cluster spoke PROFILE ingest edge (#629) — Gateway-API-native, no proxy. Mirrors the Loki/Tempo/Mimir
# edges: a write-only HTTPRoute on the shared Cilium Gateway that FORCE-SETS X-Scope-OrgID to the mapped tenant
# (so a spoke can't spoof another tenant) and routes only the Pyroscope push path. Auth = network isolation.
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
      hostnames = ["${each.key}-profiles.${var.spoke_ingest.domain}"]
      rules = [{
        # Write-only: only the Pyroscope push paths are routed (push.v1 for Alloy/eBPF, /ingest for app SDKs);
        # query APIs are never exposed. Multiple matches are OR-ed by the Gateway.
        matches = [for p in local.pyroscope_push_paths : { path = { type = "PathPrefix", value = p } }]
        filters = [{
          type                  = "RequestHeaderModifier"
          requestHeaderModifier = { set = [{ name = "X-Scope-OrgID", value = each.value }] }
        }]
        backendRefs = [{
          name = var.helm_release_name
          port = 4040
        }]
      }]
    }
  }
}

# Admit the Cilium Gateway Envoy (reserved `ingress` identity) to Pyroscope past the observability ns
# default-deny — a standard NetworkPolicy `from:` can't match that identity (the documented gotcha).
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
          "app.kubernetes.io/name" = var.helm_release_name
        }
      }
      ingress = [{ fromEntities = ["ingress"] }]
    }
  }
}

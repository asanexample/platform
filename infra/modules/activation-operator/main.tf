# =============================================================================================
# Activation operator (ADR-088) — the temporary-power activation controller, delivered as a hub
# platform add-on (Terragrunt + Helm, like crossplane/kyverno/cert-manager).
#
# Three parts: (1) a platform-account Pod Identity role the operator's ServiceAccount assumes; that
# role may ONLY assume the management-account Identity-Center-admin role (the cross-account hop to the
# sso-admin plane — ADR-088, mgmt iam-roles unit). (2) the Pod Identity association binding the SA to
# that role. (3) the Helm release: the Activation CRD + RBAC + Deployment.
# =============================================================================================

locals {
  create = var.create

  # Must equal the principal the management activation-operator-identity-center role trusts (ArnLike on
  # aws:PrincipalArn). Derived from the cluster name so the two stay in lockstep.
  role_name = "${var.cluster_name}-activation-operator"

  mgmt_ic_role_arn = "arn:aws:iam::${var.management_account_id}:role/activation-operator-identity-center"

  # Inert checksum over the chart dir → forces the helm in-place upgrade when any template/value changes
  # (the gotcha that otherwise silently skips chart-only edits).
  chart_checksum = sha256(join(",", [
    for f in sort(tolist(fileset("${path.module}/chart", "**"))) : filesha256("${path.module}/chart/${f}")
  ]))
}

# ---------------------------------------------------------------------------------------------
# Pod Identity role (platform account) — assumed by the operator's ServiceAccount via EKS Pod Identity.
# ---------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
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

resource "aws_iam_role" "operator" {
  count = local.create ? 1 : 0

  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.trust[0].json
  tags               = var.tags
}

# The ONLY thing this role can do: assume the management-account Identity Center admin role. All the actual
# sso-admin power lives there (and is trust-locked back to this role) — least privilege on the platform side.
data "aws_iam_policy_document" "assume_mgmt" {
  count = local.create ? 1 : 0

  statement {
    sid    = "AssumeIdentityCenterAdmin"
    effect = "Allow"
    # TagSession alongside AssumeRole: EKS Pod Identity credentials carry session tags, so the cross-account
    # AssumeRole propagates them — the assume fails with AccessDenied on sts:TagSession otherwise. The mgmt
    # role's trust already permits both.
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = [local.mgmt_ic_role_arn]
  }
}

resource "aws_iam_role_policy" "assume_mgmt" {
  count = local.create ? 1 : 0

  name   = "assume-identity-center-admin"
  role   = aws_iam_role.operator[0].id
  policy = data.aws_iam_policy_document.assume_mgmt[0].json
}

resource "aws_eks_pod_identity_association" "operator" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.operator[0].arn
  tags            = var.tags
}

# ---------------------------------------------------------------------------------------------
# The operator workload (Activation CRD + RBAC + Deployment).
# ---------------------------------------------------------------------------------------------

# The namespace is created here (not by the chart): Helm needs the target namespace to exist before it can
# store its release metadata in it. Platform control-plane namespace — restricted PSA (the manager pod is
# distroless nonroot, drops all caps, read-only rootfs). NOT a tenant namespace (no platform.refplat.org/team
# label), so the Kyverno environment policies don't apply here.
resource "kubernetes_namespace_v1" "operator" {
  count = local.create ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "activation-operator"
      "app.kubernetes.io/managed-by" = "terraform"
      "control-plane"                = "activation-operator"
      # Lets the observability default-deny-ingress admit the operator's OTLP export to the collector.
      "platform.refplat.org/otel-export"   = "true"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "helm_release" "activation_operator" {
  count = local.create ? 1 : 0

  name             = "activation-operator"
  chart            = "${path.module}/chart"
  namespace        = var.namespace
  create_namespace = false # the namespace is created above (kubernetes_namespace_v1.operator)
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait

  values = [yamlencode({
    namespace             = var.namespace
    serviceAccountName    = var.service_account
    image                 = var.image
    replicas              = var.replicas
    activatorGroup        = var.activator_group
    awsRegion             = var.region
    identityCenterRoleArn = local.mgmt_ic_role_arn
    # Never let the operator assign in the org-root management account — break-glass there stays manual.
    excludeAccountIds = var.management_account_id
    syncPeriod        = var.sync_period
    otelEndpoint      = var.otel_endpoint
    auditDbSecret     = var.audit_db_secret
    auditDbSecretId   = var.audit_db_secret_id
    auditSecretStore  = var.audit_secret_store
    chartChecksum     = local.chart_checksum
  })]

  depends_on = [
    aws_eks_pod_identity_association.operator,
    kubernetes_namespace_v1.operator,
  ]
}

# ---------------------------------------------------------------------------------------------
# Grafana dashboard (dashboard-as-code). A ConfigMap the Grafana sidecar discovers by the
# grafana_dashboard=1 label in the observability namespace. Panels: leaked-grant (the paging signal),
# active borrows by role, mint/revoke rates + failures, and grant/revoke latency — against the operator's
# OTEL metrics (which reach Mimir via the collector's OTLP→Mimir pipeline).
# ---------------------------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "dashboard" {
  count = local.create ? 1 : 0

  metadata {
    name        = "activation-operator-dashboard"
    namespace   = var.grafana_namespace
    labels      = { grafana_dashboard = "1" }
    annotations = { grafana_folder = "Platform" }
  }

  data = {
    "activation-operator.json" = file("${path.module}/dashboards/activation-operator.json")
  }
}

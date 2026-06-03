locals {
  create = var.create
}

# Delivers the tenant XTenant claims to the federated Tenant control plane (ADR-046/048, BACK stack P3).
# A thin local chart renders one XTenant per var.tenants entry; the Composition (crossplane module) does the
# actual provisioning. Applied as PlatformDeployer (a platform principal) so it passes the S1
# restrict-tenant-control-plane backstop that denies XTenant creation by tenant principals.
resource "helm_release" "tenant_claims" {
  count = local.create ? 1 : 0

  name      = "tenant-claims"
  chart     = "${path.module}/chart"
  namespace = var.namespace
  timeout   = var.helm_timeout
  wait      = var.helm_wait

  values = [yamlencode({
    tenants = var.tenants
  })]
}

include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_mimir
}

locals {
  # Per-app availability SLOs (ADR-056 / W11), DERIVED from the prod XEnvironment claims (registries-as-source,
  # ADR-067) — every prod Environment gets a 99.9% HTTP success-rate SLO over its Beyla RED metrics, evaluated in
  # THIS hub's Mimir ruler for the spoke tenant (the app metrics live there). Auto-extends as products gain a prod
  # Environment. Default objective for now; a per-Product/tier override can be added later. NB the SLI filters by
  # the env namespace = the claim's metadata.name (truncate+hash on >63 chars not handled — fine for current names).
  envs_dir  = "${get_repo_root()}/gitops/environments"
  prod_envs = [for f in fileset(local.envs_dir, "**/prod.yaml") : yamldecode(file("${local.envs_dir}/${f}"))]
  app_slos = [for e in local.prod_envs : {
    id              = "${e.metadata.name}-availability"
    service         = "app-${e.spec.team}-${e.spec.product}"
    slo_name        = "requests-availability"
    objective       = 99.9
    alert_name      = "${replace(title(replace(e.metadata.name, "-", " ")), " ", "")}Availability"
    error_query     = "sum(rate(http_server_request_duration_seconds_count{k8s_namespace_name=\"${e.metadata.name}\",http_response_status_code=~\"5..\"}[{{window}}])) or vector(0)"
    total_query     = "sum(rate(http_server_request_duration_seconds_count{k8s_namespace_name=\"${e.metadata.name}\"}[{{window}}]))"
    page_severity   = "critical"
    ticket_severity = "warning"
  }]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
    oidc_provider_arn             = "arn:aws:iam::000000000000:oidc-provider/mock"
    oidc_provider_url             = "oidc.eks.mock.amazonaws.com/id/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Mimir deploys into the observability namespace (shares Grafana's datasource sidecar + the
# default-deny NetworkPolicy isolation). Depend on observability so the namespace exists first.
dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    namespace = "observability"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Shared Cilium Gateway — Mimir self-routes its cross-cluster spoke-ingest HTTPRoute onto it (P10),
# the same self-routing pattern keycloak uses (ADR-059). Gateway is EARLY in the DAG (no app deps).
dependency "gateway" {
  config_path = "../gateway"

  mock_outputs = {
    gateway_name      = "platform-gateway"
    gateway_namespace = "default"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "helm_provider" {
  path      = "helm-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes = {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
        }
      }
    }
  EOF
}

generate "kubernetes_provider" {
  path      = "kubernetes-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "kubernetes" {
      host                   = "${dependency.eks.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
      }
    }
  EOF
}

inputs = {
  # Cost-profile toggle: off in dev (Prometheus-only, no durable long-range store). Flip enable_mimir in
  # common.hcl to deploy it. create=false applies as a no-op (empty state, skipped on teardown).
  create       = include.base.locals.enable_mimir
  cluster_name = dependency.eks.outputs.cluster_id
  aws_region   = include.base.locals.region

  # Clean `cluster` label on Mimir's own self-metrics (#630) — the env name, matching the hub's
  # Prometheus externalLabels.cluster, not the chart default (release name "mimir").
  cluster_label = include.base.locals.env

  namespace = dependency.observability.outputs.namespace

  # AWS identity via EKS Pod Identity (ADR-047, #594) — no OIDC/IRSA inputs needed.

  helm_chart_version = include.base.locals.helm_versions.mimir
  helm_wait          = true

  # Sizing follows cost_profile (dev = single-replica minimal; prod = RF3 + zone-aware).
  high_availability = include.base.locals.high_availability
  storage_class     = "gp3"

  # Mimir is Grafana's default datasource (durable, full-range); the observability change sets the bundled
  # Prometheus datasource non-default so there's exactly one default.
  datasource_is_default = true

  # Cross-cluster spoke ingest (P10): self-route a write-only, tenant-overwriting HTTPRoute per spoke onto
  # the shared Gateway, and surface each spoke's tenant as its own Grafana datasource. preprod is the first
  # spoke; add a `<prefix> = <tenant>` entry (and the matching datasource) to onboard the next one.
  spoke_ingest = {
    domain            = "aws.refplat.org"
    gateway_name      = dependency.gateway.outputs.gateway_name
    gateway_namespace = dependency.gateway.outputs.gateway_namespace
    tenants           = { preprod = "preprod" }
    # Expose the read (/prometheus) path for preprod so its argo-rollouts controller can run metric-gated
    # canary AnalysisRuns against this hub Mimir (ADR-056 W8c). Force-set tenant ⇒ preprod reads only its own.
    query_tenants = ["preprod"]
    # P13 per-team DUAL-WRITE (#590): an additional `/push` route on the SAME preprod-mimir hostname (reusing
    # its DNS + TLS) that forwards to cortex-tenant instead of force-stamping. The preprod agent writes a second
    # copy here → cortex-tenant splits by route_tenant into per-team tenants. The existing `/api/v1/push`
    # force-stamp route (the `preprod` tenant + its ruler/canary/cost consumers) is untouched. Gated on the hub.
    cortex_tenant_route = include.base.locals.enable_per_team_tenants ? {
      hostname_prefix = "preprod-mimir"
      service_name    = "cortex-tenant"
      service_port    = 8080
    } : null
  }
  extra_tenant_datasources = ["preprod"]

  # Multi-cluster single pane (#626): enable read-path tenant federation + a `Mimir (all clusters)`
  # datasource spanning platform|preprod. Platform-admin overview lane (per-team scoping = P13).
  enable_federated_datasource = true

  # P4 / ADR-082: the ruler evaluates alerting rules against EACH tenant's metrics (incl. preprod's
  # remote-written data) and posts fired alerts to the hub Alertmanager → the triage agent. The rules-sync
  # CronJob loads the curated spoke ruleset into the ruler for each ruler_tenant (mimirtool rules sync).
  enable_ruler  = true
  ruler_tenants = ["preprod"] # the spoke tenant(s) whose metrics get evaluated

  # Per-app SLO rules (ADR-056 / W11) — registry-derived above; rendered into the `app-slos` ruler namespace and
  # synced into the preprod tenant's ruler (the burn-rate metric + budget alerts the freeze gate will use).
  app_slos = local.app_slos

  # ADR-091 A3: admit Backstage's Cost tab to query the Mimir gateway directly (the ns default-denies ingress).
  query_consumer_namespaces = ["backstage"]

  tags = include.base.locals.tags
}

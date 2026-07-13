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
  # Per-app availability + latency SLOs (ADR-056 / W11), DERIVED from the prod XEnvironment claims
  # (registries-as-source, ADR-067) — every prod Environment gets a 99.9% HTTP success-rate SLO AND a 99%
  # sub-500ms latency SLO over its Beyla RED metrics, evaluated in THIS hub's Mimir ruler for the spoke tenant
  # (the app metrics live there). Auto-extends as products gain a prod Environment. Fixed objective/threshold
  # for now, same as the availability SLO's fixed 99.9% — no per-Product/tier override yet: the XEnvironment
  # XRD schema is strict/structural (no freeform passthrough), so adding one is a live XRD edit with real
  # cascade-delete risk (crossplane-composition-authoring's safe-apply rule) and nobody has asked to override
  # this threshold yet — a follow-up once a real need shows up, not built speculatively. NB the SLI filters by
  # the env namespace = the claim's metadata.name (truncate+hash on >63 chars not handled — fine for current names).
  #
  # Latency threshold = 500ms via the `le="0.5"` bucket — verified live against Beyla's actual histogram
  # buckets (`0.0,0.005,0.01,0.025,0.05,0.075,0.1,0.25,0.5,0.75,1,...`); there is NO `le="0.3"` bucket, so a
  # 300ms threshold would silently match zero series (permanently 0% "good" — a broken SLO), not error.
  envs_dir             = "${get_repo_root()}/gitops/environments"
  prod_envs            = [for f in fileset(local.envs_dir, "**/prod.yaml") : yamldecode(file("${local.envs_dir}/${f}"))]
  latency_threshold_le = "0.5" # 500ms — must be an actual Beyla histogram bucket boundary, not an arbitrary value
  app_slos = flatten([for e in local.prod_envs : [
    {
      id              = "${e.metadata.name}-availability"
      service         = "app-${e.spec.team}-${e.spec.product}"
      slo_name        = "requests-availability"
      objective       = 99.9
      alert_name      = "${replace(title(replace(e.metadata.name, "-", " ")), " ", "")}Availability"
      error_query     = "sum(rate(http_server_request_duration_seconds_count{k8s_namespace_name=\"${e.metadata.name}\",http_response_status_code=~\"5..\"}[{{window}}])) or vector(0)"
      total_query     = "sum(rate(http_server_request_duration_seconds_count{k8s_namespace_name=\"${e.metadata.name}\"}[{{window}}]))"
      page_severity   = "critical"
      ticket_severity = "warning"
    },
    {
      id         = "${e.metadata.name}-latency"
      service    = "app-${e.spec.team}-${e.spec.product}"
      slo_name   = "requests-latency"
      objective  = 99 # 99% of requests complete within latency_threshold_le
      alert_name = "${replace(title(replace(e.metadata.name, "-", " ")), " ", "")}Latency"
      # "bad" = requests slower than the threshold = total - (requests within the cumulative le bucket).
      error_query     = "(sum(rate(http_server_request_duration_seconds_count{k8s_namespace_name=\"${e.metadata.name}\"}[{{window}}])) - sum(rate(http_server_request_duration_seconds_bucket{k8s_namespace_name=\"${e.metadata.name}\",le=\"${local.latency_threshold_le}\"}[{{window}}]))) or vector(0)"
      total_query     = "sum(rate(http_server_request_duration_seconds_count{k8s_namespace_name=\"${e.metadata.name}\"}[{{window}}]))"
      page_severity   = "critical"
      ticket_severity = "warning"
    },
  ]])
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
  # Surface every tenant as its own direct Grafana datasource + fold them into the federated `mimir-all`
  # view: the two cluster tenants (preprod spoke; platform is the default below) and the two per-team app
  # tenants cortex-tenant splits out (alpha, bravo). This replaces the break-glass admin datasource — with
  # the read proxy retired (see read_proxy_url), these direct datasources are the reliable read path.
  extra_tenant_datasources = ["preprod", "alpha", "bravo"]

  # Multi-cluster single pane (#626): enable read-path tenant federation + a `Mimir (all clusters)`
  # datasource spanning platform|preprod. Platform-admin overview lane (per-team scoping = P13).
  enable_federated_datasource = true

  # P13 read-proxy RETIRED (#1269). This was `enable_per_team_tenants ? "http://tenant-proxy…" : ""` — every
  # Grafana metrics datasource routed through the tenant-proxy, which scoped the query from the caller's SSO
  # identity forwarded by Grafana as X-Id-Token. That forwarding is fundamentally unreliable in OSS Grafana
  # (oauthPassThru drops the token; even a fresh Keycloak login forwarded nothing), so every dashboard query
  # failed closed `no_token` and admins lost all metrics. Per-team read isolation moves to the soft model that
  # was the actual need: dashboard folder permissions + the namespace-filtered per-team dashboards (#1157).
  # Empty ⇒ the datasources above point straight at the gateway with a static per-tenant X-Scope-OrgID
  # (reliable, no token dependency). The write-side per-team tenant split (cortex-tenant) is untouched.
  read_proxy_url = ""

  # Admin break-glass datasource is now redundant — with the proxy retired, the direct `mimir-all` datasource
  # already federates the full tenant set. Only ever rendered while the proxy was enforced (a no-op now); kept
  # false-by-effect so re-enabling the proxy would also restore it.
  enable_admin_all_datasource  = false
  admin_all_datasource_tenants = ["alpha", "bravo", "platform", "preprod"]

  # P4 / ADR-082: the ruler evaluates alerting rules against EACH tenant's metrics (incl. preprod's
  # remote-written data) and posts fired alerts to the hub Alertmanager → the triage agent. The rules-sync
  # CronJob loads the curated spoke ruleset into the ruler for each ruler_tenant (mimirtool rules sync).
  enable_ruler  = true
  ruler_tenants = ["preprod"] # the spoke tenant(s) whose metrics get evaluated

  # Per-app SLO rules (ADR-056 / W11) — registry-derived above; rendered into the `app-slos` ruler namespace and
  # synced into the preprod tenant's ruler (the burn-rate metric + budget alerts the freeze gate will use).
  app_slos = local.app_slos

  # Spoke metrics freshness ("who watches the watcher") — a dead/stuck spoke shows zero errors under
  # availability-only SLOs. Evaluated inside every ruler_tenants entry (currently just preprod).
  spoke_metrics_freshness = { enabled = true }

  # ADR-091 A3: admit Backstage's Cost tab to query the Mimir gateway directly (the ns default-denies ingress).
  query_consumer_namespaces = ["backstage"]

  tags = include.base.locals.tags
}

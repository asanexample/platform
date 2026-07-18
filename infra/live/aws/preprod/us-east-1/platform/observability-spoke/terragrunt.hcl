include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_prom_agent
}

dependency "prometheus_operator_crds" {
  config_path = "../prometheus-operator-crds"

  # Ordering-only: the Prometheus Operator CRDs (ServiceMonitor, ...) must exist before this unit's
  # chart renders one, else the helm provider fails ("no matches for kind ServiceMonitor ... ensure CRDs
  # are installed first") on a from-scratch bootstrap.
  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The agent ships over Transit Gateway to the platform hub (private). Order after the TGW spoke attachment
# so the cross-VPC route to the hub VPC exists before remote_write starts.
dependency "transit_gateway" {
  config_path = "../transit-gateway"

  mock_outputs                            = {}
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
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id
  aws_region   = include.base.locals.region

  # Stamped on every series so the hub isolates preprod under its tenant (`up{cluster="preprod"}`).
  cluster_label = "preprod"

  # Ship to the platform hub's Mimir spoke-ingest edge. The hub Gateway force-sets X-Scope-OrgID=preprod
  # per-hostname (write-only), so no tenant header is sent from here. Reached privately over the TGW.
  remote_write_url = "https://preprod-mimir.aws.refplat.org/api/v1/push"

  # P13 per-team DUAL-WRITE (#590): additionally ship a second copy to cortex-tenant (the `/push` route on the
  # same host), with a forced namespace→route_tenant relabel, so preprod's metrics ALSO land in per-team
  # tenants (alpha/bravo/platform) — without disturbing the primary `preprod`-tenant write above. Gated on
  # preprod's enable_per_team_tenants; empty = single-write (unchanged).
  per_team_write_url = include.base.locals.enable_per_team_tenants ? "https://preprod-mimir.aws.refplat.org/push" : ""

  helm_chart_version = include.base.locals.helm_versions.kube_prometheus_stack
  helm_wait          = true

  # Sizing follows cost_profile (dev = single replica; prod = HA).
  high_availability = include.base.locals.high_availability

  # ADR-091: emit team_budget_monthly_usd{team} via KSM CustomResourceState from the Team CRs (which live on
  # this env-API cluster) → hub Mimir tenant preprod → the cost dashboard's spend-vs-budget overlay.
  enable_team_budget_metric = true
  # Durable remote-write WAL on a PVC (encrypted `gp3`, the cluster default). The spoke remote-writes across
  # the TGW to the hub, so a transient hub/network outage together with a pod restart (Karpenter consolidation,
  # node rotation, OOM) is the realistic data-loss window the WAL exists to survive — and on an emptyDir the
  # growing buffer competes for node ephemeral storage, so a long outage can trigger eviction and make it worse.
  # `gp3` is provisioned cluster-default by eks-addons (create_default_storageclass) and already backs
  # CNPG/SPIRE here. NB: flipping emptyDir→PVC recreates the agent StatefulSet (immutable volumeClaimTemplates)
  # — apply with helm_wait=false, then flip back (the emptyDir→PVC gotcha in the observability-authoring skill).
  storage_class = "gp3"
  wal_size      = "10Gi"

  # P14 log→trace: allow OTLP (4317/4318) to the OTel collector from environment namespaces labeled
  # platform.refplat.org/otel-export=true (the Composition stamps it), so SDK-instrumented tenant apps
  # (ADR-077 Layer 1) can export traces. The collector ns otherwise default-denies cross-namespace ingress.
  enable_otlp_ingress = true

  # Crossplane runs HERE too — XEnvironment claims actually reconcile on preprod (ADR-048), not the hub, so
  # the core-controller SLO (#102 phase 4) and the composed-resource reconcile signal (#1423) both need this
  # spoke's own PodMonitors, not just the hub's (#1422/#1423).
  enable_crossplane_pod_monitor          = true
  enable_crossplane_provider_pod_monitor = true
  # The default 512Mi/1Gi OOM-killed the agent within ~30s of scraping crossplane core + 5 provider pods'
  # controller-runtime metrics (11 CrashLoopBackOff restarts observed live) — bump headroom for the added
  # scrape cardinality. First bump (768Mi/2Gi) stopped the crashloop but settled at ~98% of the limit
  # (~1.95-2Gi steady-state, verified live) — too tight a margin for comfort; bumped further for real slack.
  memory_request = "1Gi"
  memory_limit   = "3Gi"

  tags = include.base.locals.tags
}

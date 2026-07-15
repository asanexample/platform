include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.karpenter
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
    cluster_security_group_id     = "sg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Karpenter runs on the system node group + reuses its node IAM role; depend on node-groups so both exist.
dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs = {
    node_role_arn = "arn:aws:iam::000000000000:role/mock-node"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    subnet_ids = { "az1-kubernetes" = "subnet-mock" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Cilium must be on every node before pods schedule (BYOCNI); eks-addons carries the Pod Identity agent the
# controller authenticates through. Order after both.
dependency "cilium" {
  config_path = "../cilium"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "eks_addons" {
  config_path = "../eks-addons"

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

inputs = {
  # Foundational — on by default (enable_karpenter, dev+prod). create=false applies as a no-op.
  create       = include.base.locals.enable_karpenter
  cluster_name = dependency.eks.outputs.cluster_id
  aws_region   = include.base.locals.region

  node_role_arn             = dependency.node_groups.outputs.node_role_arn
  cluster_security_group_id = dependency.eks.outputs.cluster_security_group_id
  subnet_ids                = [for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))]
  single_az                 = include.base.locals.single_az_nodes
  node_arch                 = include.base.locals.node_arch

  # This is the stateful hub (Prometheus/Mimir/Loki/Tempo/Pyroscope, Keycloak, CNPG). WhenEmptyOrUnderutilized
  # lets Karpenter reclaim UNDERUTILIZED nodes (not just fully-empty ones) — needed because the post-unpark
  # scheduling storm over-provisions small on-demand nodes that WhenEmpty then never reclaimed (6 nodes at
  # ~20% CPU / ~13-32% mem observed 2026-07-13, pure waste on a nightly-parked cost-demo cluster).
  #
  # ⚠️ consolidate_after = 15m is DELIBERATELY long (module default is 1m). The post-unpark reschedule storm
  # settles in ~10 min; a short (1m) consolidateAfter makes Karpenter consolidate DURING the storm — on preprod
  # (spot + WhenEmptyOrUnderutilized + 1m) that produced a node-churn thrash loop 2026-07-14 (scale 3->6, disrupt,
  # re-pend, Cilium-429, repeat). 15m lets the storm fully settle FIRST, then reclaims only stably-idle nodes as a
  # calm one-time right-sizing. Platform avoids preprod's other amplifier by design: it is on-demand (no spot
  # interruptions). Stateful TSDBs/DBs stay protected — they carry `karpenter.sh/do-not-disrupt` + PDBs, honored
  # under either policy, so consolidation drains only stateless/underutilized capacity. (ADR-078.)
  capacity_types       = ["on-demand"]
  consolidation_policy = "WhenEmptyOrUnderutilized"
  consolidate_after    = "15m"
  # Cost guardrail (deliberately CONSERVATIVE — this is a nightly-parked demo; a runaway node-count is worse than
  # a few Pending pods). With the 4-vCPU floor below, the hub's schedulable workload (obs stack + argocd/crossplane/
  # keycloak/backstage) rides ~2-3 xlarge Karpenter nodes; the post-unpark storm peaks higher before consolidation.
  # 16 vCPU / 64 GiB caps Karpenter at ~4 xlarge nodes — comfortable headroom over normal + spike, but a hard ceiling
  # that HALVES the old 32/128 blast radius. When the cap is hit Karpenter STOPS provisioning (pods go Pending, event
  # "all available instance types exceed limits") — never a runaway. Outages from hitting this are ACCEPTABLE and are
  # surfaced by the KarpenterNodePoolAtCapacity alert so capacity-exhaustion is diagnosable as the root cause. (This
  # bounds Karpenter only; the system node group has its own maxSize=3.)
  cpu_limit    = 16
  memory_limit = "64Gi"
  # Require 8 GiB+ nodes. The observability hub's per-node DaemonSets (Cilium, Beyla, Alloy, node-exporter) eat
  # ~3.2 GiB — a 4 GiB t4g.medium exhausts memory and flaps NotReady.
  min_instance_memory_mib = 6144
  # Require 4 vCPU+ nodes (Gt 3). WITHOUT this, Karpenter provisioned the cheapest node meeting the 8 GiB floor —
  # r6g.medium (1 vCPU) — which, after the fixed ~410m DaemonSet slab, has no room for a single heavy obs pod
  # (Mimir/Loki/Tempo ingesters, Grafana). So the entire LGTM+P stack piled onto the fixed system node group,
  # overcommitting it to ~87% CPU / ~127% mem-limits until its kubelet starved and flapped NotReady (a system node
  # went unregistered, orphaning the stack onto the survivor; Tempo OOM-flapped — confirmed 2026-07-15). A 4-vCPU
  # floor lands on r6g.xlarge/m7g.xlarge — nodes big enough to actually HOST the obs stack, so it rides Karpenter's
  # autoscaling capacity (grows with load, WhenEmptyOrUnderutilized reclaims when idle) INSTEAD of a fixed floor
  # that can't scale. Also amortizes the DaemonSet slab (~12% of a 4-vCPU node vs ~43% of a 1-vCPU one) — fewer,
  # better-utilized nodes: cheaper per usable vCPU, not more. Mirrors the preprod karpenter unit's same floor.
  min_instance_cpu = 3

  high_availability  = include.base.locals.high_availability
  helm_chart_version = include.base.locals.helm_versions.karpenter
  helm_wait          = true

  tags = include.base.locals.tags
}

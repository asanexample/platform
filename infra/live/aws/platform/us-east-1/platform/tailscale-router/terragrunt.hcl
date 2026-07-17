include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.tailscale_router
}

# Cluster-independent by design — depends only on networking (VPC + subnet). It does
# NOT depend on eks: the EKS API is opened to the VPC CIDR on the eks side
# (additional_api_ingress_cidrs), so this router forwards to it without referencing the
# cluster. That decoupling is the whole point — the router outlives cluster
# parking/teardown and provides private-API reach when the in-cluster connector is down.
dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    vpc_id         = "vpc-mock"
    subnet_ids     = { "kubernetes" = "subnet-mock" }
    vpc_cidr_block = "10.100.0.0/16"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  create = true
  name   = "${include.base.locals.env}-${include.base.locals.region_abbv}-tsrouter"
  region = include.base.locals.region
  vpc_id = dependency.networking.outputs.vpc_id

  # Same kubernetes-tier subnet as the nodes/bastion; it has NAT egress for Tailscale.
  subnet_id = [
    for name, id in dependency.networking.outputs.subnet_ids :
    id if can(regex("kubernetes$", name))
  ][0]

  # Advertise the VPC CIDR; auto-approves via the tailnet autoApprovers for tag:k8s-operator.
  # Reuses the existing k8s-operator OAuth client (zero ACL change) for phase 1 — a dedicated
  # tag:subnet-router + its own OAuth client is the hardening follow-up.
  advertise_routes = [dependency.networking.outputs.vpc_cidr_block]
  advertise_tags   = ["tag:k8s-operator"]
  auth_secret_id   = "platform/tailscale/oauth"

  tags = include.base.locals.tags
}

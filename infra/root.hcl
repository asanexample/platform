// Base Terragrunt configuration for all modules

terraform_binary = "tofu"

// Remote state: S3 + DynamoDB locking (bucket created by state-bootstrap module).
// The state-bootstrap module overrides this with a local backend.
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = local._secrets.state_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
    role_arn       = local._secrets.state_role_arn
  }
}

// Provider version pins and generation
generate "versions" {
  path = "versions.tf"
  # FALLBACK ONLY — `skip` means this is used solely for a unit whose sourced module ships NO versions.tf.
  # Every shared module now declares its own required_providers (ADR-083), so in practice this is skipped and
  # the MODULE's versions.tf is authoritative. Keep these bounds in lockstep with ADR-083 so the fallback can't
  # drift from the module standard. (Earlier this pinned aws = "6.47.0" exact, which was dead — silently
  # skipped by the module's own versions.tf — so units actually resolved the module's looser bound, not 6.47.0.)
  if_exists = "skip"
  contents  = <<EOF
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}
EOF
}

generate "provider_aws" {
  path      = "provider_aws.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    local.aws_assume_role ? <<EOF
provider "aws" {
  region = "${local.aws_region}"

  assume_role {
    role_arn = "arn:aws:iam::${local.aws_account_id}:role/PlatformDeployer"
  }
}
EOF
    : <<EOF
provider "aws" {
  region = "${local.aws_region}"
}
EOF
  )
}

inputs = {
  common_tags = {
    Environment = local.environment
    ManagedBy   = "Terragrunt"
    Project     = "Multi-Cloud Infrastructure"
    CostCenter  = local.cost_center
    Owner       = local.owner
  }
}

locals {
  # Detect cloud provider from directory path (kept for future multi-cloud)
  _path_parts_cloud = split("/", path_relative_to_include())
  _cloud            = try(local._path_parts_cloud[1], "aws")

  # Config secrets, ADR-066: decrypted from the committed SOPS secrets.enc.yaml. TG_SOPS_BOOTSTRAP=1 falls back to
  # the plaintext secrets.hcl for greenfield bootstrap (before the platform-sops key exists). See common.hcl.
  _secrets = get_env("TG_SOPS_BOOTSTRAP", "") == "1" ? read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl").locals : yamldecode(sops_decrypt_file("${get_repo_root()}/infra/live/aws/secrets.enc.yaml"))

  environment = get_env("TF_VAR_environment", "dev")

  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl", "${get_terragrunt_dir()}/dummy.hcl"))

  aws_region     = get_env("TF_VAR_aws_region", "us-east-1")
  aws_account_id = try(local.environment_vars.locals.account_id, "")

  # CI escape hatch (#305 / ADR-065). The normal rule assumes PlatformDeployer only when the caller's account
  # differs from the target — true for an operator running from `management`, but NOT for the in-VPC ARC runner,
  # which lives IN the platform account. Without this, an in-account runner would run the providers as its bare
  # (non-admin) role. `TG_FORCE_DEPLOYER=1` forces the assume even in-account, making the runner a faithful
  # stand-in for the operator's cross-account identity. Default off → byte-identical for local operators.
  force_deployer  = get_env("TG_FORCE_DEPLOYER", "") == "1"
  aws_assume_role = local.force_deployer || (local.aws_account_id != "" ? local.aws_account_id != get_aws_account_id() : false)

  cost_center = get_env("TF_VAR_cost_center", "Engineering")
  owner       = get_env("TF_VAR_owner", "Platform Team")

  common_tags = {
    Environment = local.environment
    ManagedBy   = "Terragrunt"
    Project     = "Multi-Cloud Infrastructure"
    CostCenter  = local.cost_center
    Owner       = local.owner
  }
}

include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.networking

  # Destroy+recreate of VPC flow logs leaves an orphaned CloudWatch log group
  # that blocks the next apply. This hook deletes it preemptively.
  # Shell hooks run with the caller's credentials (management), so we STS
  # assume-role into the target account.
  before_hook "cleanup_orphaned_log_group" {
    commands = ["apply"]
    execute  = ["bash", "-c", "CREDS=$(aws sts assume-role --role-arn 'arn:aws:iam::${include.base.locals.account_id}:role/OrganizationAccountAccessRole' --role-session-name tg-hook --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text) && read -r AKI SAK ST <<< \"$CREDS\" && AWS_ACCESS_KEY_ID=$AKI AWS_SECRET_ACCESS_KEY=$SAK AWS_SESSION_TOKEN=$ST aws logs delete-log-group --log-group-name '/aws/vpc/flow-log/${include.base.locals.env}-${include.base.locals.region_abbv}-vpc' --region ${include.base.locals.region} 2>/dev/null; exit 0"]
  }

  # On teardown the EKS cloud-controller is gone before this unit destroys, so the internal Cilium Gateway NLB is
  # orphaned and its ENIs block subnet deletion (DeleteSubnet DependencyViolation). Sweep orphaned k8s LBs + wait
  # for their ENIs to release first. Best-effort (the script always exits 0); same break-glass role as above.
  before_hook "sweep_orphaned_lbs" {
    commands = ["destroy"]
    execute = ["bash", "${get_repo_root()}/scripts/vpc-orphan-lb-sweep.sh",
      include.base.locals.region,
      "arn:aws:iam::${include.base.locals.account_id}:role/OrganizationAccountAccessRole",
      "${include.base.locals.env}-${include.base.locals.region_abbv}-vpc",
    ]
  }
}

inputs = {
  create        = true
  vpc_name      = "${include.base.locals.env}-${include.base.locals.region_abbv}-vpc"
  address_space = include.base.locals.all_vars.address_space
  subnets       = include.base.locals.all_vars.subnets
  environment   = include.base.locals.env
  workload      = include.base.locals.workload
  region_abbv   = include.base.locals.region_abbv
  tags          = include.base.locals.tags

  create_internet_gateway = true
  create_nat_gateways     = true
  single_nat_gateway      = true

  enable_eks_networking = true
  eks_cluster_name      = "${include.base.locals.env}-${include.base.locals.region_abbv}-eks"

  interface_vpc_endpoints = [
    "secretsmanager",
    "ssm",
    "sts",
    "kms",
  ]

  enable_flow_logs        = true
  flow_log_retention_days = 30
}

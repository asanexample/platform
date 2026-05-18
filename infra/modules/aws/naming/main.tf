locals {
  # Workload name and abbreviated form for tight-constraint resources
  default_workload = var.workload

  workload_abbreviations = {
    platform     = "plat"
    connectivity = "conn"
    data         = "data"
    hipaa        = "hipa"
    pci          = "pci"
    shared       = "shrd"
    mgmt         = "mgmt"
  }

  abbreviated_workload = lookup(
    local.workload_abbreviations,
    local.default_workload,
    substr(local.default_workload, 0, 4)
  )

  region_abbv = var.region_abbv

  # Unique suffix for globally unique resources (S3, etc.)
  unique_suffix = var.unique_seed != "" ? substr(md5(var.unique_seed), 0, 6) : ""

  # Resource type abbreviations
  resource_types = {
    vpc            = "vpc"
    subnet         = "snet"
    igw            = "igw"
    natgw          = "natgw"
    rtb            = "rtb"
    sg             = "sg"
    eks            = "eks"
    s3             = "s3"
    ecr            = "ecr"
    alb            = "alb"
    nlb            = "nlb"
    tg             = "tg"
    lambda         = "lmb"
    rds            = "rds"
    dynamodb       = "ddb"
    sqs            = "sqs"
    sns            = "sns"
    kms            = "kms"
    iam_role       = "role"
    iam_policy     = "pol"
    cloudwatch_lg  = "cwlg"
    efs            = "efs"
    secretsmanager = "sm"
  }

  # AWS resource naming constraints
  naming_rules = {
    vpc = {
      max_length  = 255
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    subnet = {
      max_length  = 255
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    igw = {
      max_length  = 255
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    natgw = {
      max_length  = 255
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    rtb = {
      max_length  = 255
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    sg = {
      max_length  = 255
      valid_chars = "^[a-zA-Z0-9\\-_\\.\\s]+$"
    }
    eks = {
      max_length  = 100
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    s3 = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-\\.]+$"
      no_hyphens  = true
      lowercase   = true
    }
    ecr = {
      max_length  = 256
      valid_chars = "^[a-z0-9\\-_/]+$"
      no_hyphens  = true
      lowercase   = true
    }
    alb = {
      max_length  = 32
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    nlb = {
      max_length  = 32
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    tg = {
      max_length  = 32
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    lambda = {
      max_length  = 64
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    rds = {
      max_length  = 63
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    dynamodb = {
      max_length  = 255
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    sqs = {
      max_length  = 80
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    sns = {
      max_length  = 256
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    kms = {
      max_length  = 256
      valid_chars = "^[a-zA-Z0-9\\-_/]+$"
    }
    iam_role = {
      max_length  = 64
      valid_chars = "^[a-zA-Z0-9\\-_+=,\\.@]+$"
    }
    iam_policy = {
      max_length  = 128
      valid_chars = "^[a-zA-Z0-9\\-_+=,\\.@]+$"
    }
    cloudwatch_lg = {
      max_length  = 512
      valid_chars = "^[a-zA-Z0-9\\-_/\\.]+$"
    }
    efs = {
      max_length  = 255
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    secretsmanager = {
      max_length  = 512
      valid_chars = "^[a-zA-Z0-9\\-_/\\.]+$"
    }
  }

  # Naming pattern: {type}-{workload}-{env}-{region}
  # For tight-constraint / globally-unique resources: {type}{abbreviated_workload}{env}{region}
  names = {
    vpc            = "${local.resource_types.vpc}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    subnet         = "${local.resource_types.subnet}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    igw            = "${local.resource_types.igw}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    natgw          = "${local.resource_types.natgw}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    rtb            = "${local.resource_types.rtb}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    sg             = "${local.resource_types.sg}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    eks            = "${local.resource_types.eks}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    s3             = "${local.resource_types.s3}${local.abbreviated_workload}${var.environment}${local.region_abbv}${local.unique_suffix}"
    ecr            = "${local.resource_types.ecr}${local.abbreviated_workload}${var.environment}${local.region_abbv}"
    alb            = "${local.resource_types.alb}-${local.abbreviated_workload}-${var.environment}-${local.region_abbv}"
    nlb            = "${local.resource_types.nlb}-${local.abbreviated_workload}-${var.environment}-${local.region_abbv}"
    tg             = "${local.resource_types.tg}-${local.abbreviated_workload}-${var.environment}-${local.region_abbv}"
    lambda         = "${local.resource_types.lambda}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    rds            = "${local.resource_types.rds}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    dynamodb       = "${local.resource_types.dynamodb}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    sqs            = "${local.resource_types.sqs}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    sns            = "${local.resource_types.sns}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    kms            = "${local.resource_types.kms}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    iam_role       = "${local.resource_types.iam_role}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    iam_policy     = "${local.resource_types.iam_policy}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    cloudwatch_lg  = "/${local.resource_types.cloudwatch_lg}/${local.default_workload}/${var.environment}/${local.region_abbv}"
    efs            = "${local.resource_types.efs}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    secretsmanager = "${local.resource_types.secretsmanager}-${local.default_workload}-${var.environment}-${local.region_abbv}"
  }

  # Subnet naming helpers
  subnet_name    = "${local.resource_types.subnet}-${local.default_workload}-${var.environment}"
  subnet_public  = "${local.subnet_name}-public-${local.region_abbv}"
  subnet_private = "${local.subnet_name}-private-${local.region_abbv}"
  subnet_data    = "${local.subnet_name}-data-${local.region_abbv}"
  subnet_intra   = "${local.subnet_name}-intra-${local.region_abbv}"

  # Validate names against AWS restrictions and truncate if necessary
  validated_names = {
    for resource_type, name in local.names :
    resource_type => (
      contains(keys(local.naming_rules), resource_type) ? (
        length(name) > local.naming_rules[resource_type].max_length ?
        substr(name, 0, local.naming_rules[resource_type].max_length) :
        lookup(local.naming_rules[resource_type], "lowercase", false) ? lower(name) : name
      ) : name
    )
  }
}

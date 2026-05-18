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

  # Unique suffix for globally unique resources (GCS, etc.)
  unique_suffix = var.unique_seed != "" ? substr(md5(var.unique_seed), 0, 6) : ""

  # Resource type abbreviations
  resource_types = {
    vpc          = "vpc"
    subnet       = "snet"
    gke          = "gke"
    gcs          = "gcs"
    gcr          = "gcr"
    fw           = "fw"
    router       = "rtr"
    nat          = "nat"
    lb           = "lb"
    cloudsql     = "sql"
    memorystore  = "redis"
    pubsub_topic = "pst"
    pubsub_sub   = "pss"
    kms_keyring  = "kr"
    kms_key      = "key"
    sa           = "sa"
    cloudrun     = "run"
    gce          = "gce"
    cloudfunc    = "gcf"
  }

  # GCP resource naming constraints
  naming_rules = {
    vpc = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-]+$"
      lowercase   = true
    }
    subnet = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-]+$"
      lowercase   = true
    }
    gke = {
      max_length  = 40
      valid_chars = "^[a-z0-9\\-]+$"
      lowercase   = true
    }
    gcs = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-\\.]+$"
      no_hyphens  = true
      lowercase   = true
    }
    gcr = {
      max_length  = 255
      valid_chars = "^[a-z0-9\\-_]+$"
      lowercase   = true
    }
    fw = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-]+$"
      lowercase   = true
    }
    router = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-]+$"
      lowercase   = true
    }
    nat = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-]+$"
      lowercase   = true
    }
    lb = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-]+$"
      lowercase   = true
    }
    cloudsql = {
      max_length  = 88
      valid_chars = "^[a-z0-9\\-]+$"
      lowercase   = true
    }
    memorystore = {
      max_length  = 40
      valid_chars = "^[a-z0-9\\-]+$"
      lowercase   = true
    }
    pubsub_topic = {
      max_length  = 255
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    pubsub_sub = {
      max_length  = 255
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    kms_keyring = {
      max_length  = 63
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    kms_key = {
      max_length  = 63
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    sa = {
      max_length  = 30
      valid_chars = "^[a-z0-9\\-]+$"
      no_hyphens  = true
      lowercase   = true
    }
    cloudrun = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-]+$"
      lowercase   = true
    }
    gce = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-]+$"
      lowercase   = true
    }
    cloudfunc = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-_]+$"
      lowercase   = true
    }
  }

  # Naming pattern: {type}-{workload}-{env}-{region}
  # For tight-constraint / globally-unique resources: {type}{abbreviated_workload}{env}{region}
  # Service accounts: sa-{abbreviated_workload}-{env}-{region} (30 char max)
  names = {
    vpc          = "${local.resource_types.vpc}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    subnet       = "${local.resource_types.subnet}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    gke          = "${local.resource_types.gke}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    gcs          = "${local.resource_types.gcs}${local.abbreviated_workload}${var.environment}${local.region_abbv}${local.unique_suffix}"
    gcr          = "${local.resource_types.gcr}${local.abbreviated_workload}${var.environment}${local.region_abbv}"
    fw           = "${local.resource_types.fw}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    router       = "${local.resource_types.router}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    nat          = "${local.resource_types.nat}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    lb           = "${local.resource_types.lb}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    cloudsql     = "${local.resource_types.cloudsql}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    memorystore  = "${local.resource_types.memorystore}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    pubsub_topic = "${local.resource_types.pubsub_topic}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    pubsub_sub   = "${local.resource_types.pubsub_sub}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    kms_keyring  = "${local.resource_types.kms_keyring}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    kms_key      = "${local.resource_types.kms_key}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    sa           = "${local.resource_types.sa}-${local.abbreviated_workload}-${var.environment}-${local.region_abbv}"
    cloudrun     = "${local.resource_types.cloudrun}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    gce          = "${local.resource_types.gce}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    cloudfunc    = "${local.resource_types.cloudfunc}-${local.default_workload}-${var.environment}-${local.region_abbv}"
  }

  # Subnet naming helpers
  subnet_name    = "${local.resource_types.subnet}-${local.default_workload}-${var.environment}"
  subnet_public  = "${local.subnet_name}-public-${local.region_abbv}"
  subnet_private = "${local.subnet_name}-private-${local.region_abbv}"
  subnet_data    = "${local.subnet_name}-data-${local.region_abbv}"
  subnet_gke     = "${local.subnet_name}-gke-${local.region_abbv}"
  subnet_proxy   = "${local.subnet_name}-proxy-${local.region_abbv}"

  # Validate names against GCP restrictions and truncate if necessary
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

locals {
  vpc_cidr = "10.102.0.0/16"
  azs      = ["us-east-1a", "us-east-1b", "us-east-1c"]

  subnet_tiers = {
    kubernetes = { newbits = 2, netnum = 0, public = false }  # /26 (62 IPs)
    endpoints  = { newbits = 2, netnum = 1, public = false }  # /26 (62 IPs)
    firewall   = { newbits = 2, netnum = 2, public = false }  # /26 (62 IPs)
    services   = { newbits = 3, netnum = 6, public = false }  # /27 (30 IPs)
    public     = { newbits = 4, netnum = 14, public = true }  # /28 (14 IPs)
    transit    = { newbits = 5, netnum = 30, public = false } # /29 (6 IPs)
  }

  subnets = merge([
    for az_idx, az in local.azs : {
      for tier_name, tier in local.subnet_tiers :
      "az${az_idx + 1}-${tier_name}" => {
        address_prefixes  = [cidrsubnet(cidrsubnet(local.vpc_cidr, 8, az_idx), tier.newbits, tier.netnum)]
        availability_zone = az
        public            = tier.public
      }
    }
  ]...)

  address_space = [local.vpc_cidr]
}

# Network configuration for azure centralus region based on allocations.csv

locals {
  # VNet/VPC CIDR block for centralus region
  address_space = ["10.200.16.0/21"]
  
  # Subnet allocations for this region
  subnets = {
    az1 = {
      node      = cidrsubnet(local.address_space[0], 5, 0)  # /26
      services  = cidrsubnet(local.address_space[0], 6, 4)  # /27
      endpoints = cidrsubnet(local.address_space[0], 7, 10) # /28
      transit   = cidrsubnet(local.address_space[0], 8, 22) # /29
    }
    az2 = {
      node      = cidrsubnet(local.address_space[0], 5, 1)  # /26
      services  = cidrsubnet(local.address_space[0], 6, 5)  # /27
      endpoints = cidrsubnet(local.address_space[0], 7, 11) # /28
      transit   = cidrsubnet(local.address_space[0], 8, 23) # /29
    }
    az3 = {
      node      = cidrsubnet(local.address_space[0], 5, 2)  # /26
      services  = cidrsubnet(local.address_space[0], 6, 6)  # /27
      endpoints = cidrsubnet(local.address_space[0], 7, 12) # /28
      transit   = cidrsubnet(local.address_space[0], 8, 24) # /29
    }
  }
}

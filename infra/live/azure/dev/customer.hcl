# Customer configuration for all regions in an environment

locals {
  # Customer name to use in resource naming
  customer = "contoso"
  
  # Customer-specific tags
  customer_tags = {
    Customer         = "Contoso Corp."
    Project          = "Multi-Cloud Platform"
    CustomerContact  = "john.doe@contoso.com"
    ClientId         = "contoso-123"
  }
} 
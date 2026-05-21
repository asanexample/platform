# Common variables shared across all regions and environments
# This file contains global configuration for the AWS platform

locals {
  # Project variables
  workload = "platform"

  # Common tags
  tags = {
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
    CostCenter         = "Engineering"
    Owner              = "Platform Team"
  }

  # External DNS delegation
  cloudflare_zone_id = "373f3d8528f115c9583798ec11b6ed1e"

  # ArgoCD SSO (Identity Center SAML)
  argocd_sso_url     = "https://portal.sso.us-east-1.amazonaws.com/saml/assertion/ODUxNzI1MzUzMjAyX2lucy03MjIzYmQxMzhkZTNjMzkx"
  argocd_sso_ca_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURCekNDQWUrZ0F3SUJBZ0lGQU5qWDhtMHdEUVlKS29aSWh2Y05BUUVMQlFBd1JURVdNQlFHQTFVRUF3d04KWVcxaGVtOXVZWGR6TG1OdmJURU5NQXNHQTFVRUN3d0VTVVJCVXpFUE1BMEdBMVVFQ2d3R1FXMWhlbTl1TVFzdwpDUVlEVlFRR0V3SlZVekFlRncweU5qQTFNakV4TmpBeU5UaGFGdzB6TVRBMU1qRXhOakF5TlRoYU1FVXhGakFVCkJnTlZCQU1NRFdGdFlYcHZibUYzY3k1amIyMHhEVEFMQmdOVkJBc01CRWxFUVZNeER6QU5CZ05WQkFvTUJrRnQKWVhwdmJqRUxNQWtHQTFVRUJoTUNWVk13Z2dFaU1BMEdDU3FHU0liM0RRRUJBUVVBQTRJQkR3QXdnZ0VLQW9JQgpBUURDNGV4dURjL1h0YTlBTVRPNmJLNkcxS3hqaFp5SVNpM0hUSjdid0FWYi9reVJXdEkwNWVkUmtiTVJQencyCkkzM2tKRnAxbTk0NEZXRWRXcW00TWZUMm9FclFBNG9QaWdvSGFPMGFYM2dqOXRnR2w1VmJuVy9EUlA2aUZJaFMKSEFXbTg0bWF3Z0ZSSCtzTm1iSDhxVE1OL3JSYlR2TEtVQnVOaXVsMXE4RkU0Z3ZJUVJvK09rc043SllvRTBOTgpBUWZXb1I2VmY4UUROSGFPY3pLV205OHdPNW1GQURWS20zOWZwaW9vOHFoQ2s2OXN5SjlrOFM2Zk9oS2M1MytNCno1bnJ4cDJPWm9uU1d1SzBFUmk1S1l4TGxjSnFiNnFwa3pJMFAxYkVaWTlHRDAybWdHZWkydkltVmxwaVcyd0QKaTNjcFd2SkI2TFkyZ0JVejhVVmg1cUc3QWdNQkFBRXdEUVlKS29aSWh2Y05BUUVMQlFBRGdnRUJBRnE2QXNtdwpBNzE1VmJIendmY1hFdmFjczYrRWM5VUVjTDJqc2Y3ZTFWRUJwUkJETCtxOUwrVkJhRGxiWTNBWGlORXFpeFhTCjg5SFQwS0VQa0ZGQXRnamtSQkxabzR5K3Jjc3ZFNEhRTjZrOFdCNUh6R0cyRGFRazAzSkQyTDZQYzFMMlpWTEIKbDBWNHNZS1JzMHZha25taldua2JESzhOVmFsczhyRjQvRnJnRVRtZTN6UFJzOElha1FHeWR1YTNPRUhmcjJZQgo3bEo1VVNSQ2IrRnhZUmlxRE83K09GdlJpaWtTM1M5c2dsQU1scm8zU24rZFJQbCtxVWtxZU9ENjZNR2J6VHVwClZnRXlRamI2WHBiV1BDK0tORFhHdHVZREFZNVo5a2lTS3lrZFIraFhaRmJBTVZLOFhHY2lxZ3lTZFBtOXRFV2UKMW5YcDdTOWlWNzVraGs0PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg=="

  # Azure global configuration (not applicable for AWS)
  azure_config = {}

  # Environment -> AWS account ID mapping (safety validation)
  # Used by _base.hcl to verify env.hcl account_id matches the expected value.
  # Add new environments here as they are onboarded.
  environment_account_map = {
    "platform" = "829808296602"
    "mgmt"     = "851725353202"
    "test"     = "157263244316"
    "preprod"  = "620830101009"
    "prod"     = "554518885123"
  }
}

locals {
  workload        = "platform"
  compliance_tier = "standard" # standard | hipaa | pci

  workload_tags = {
    Workload       = local.workload
    ComplianceTier = local.compliance_tier
  }
}

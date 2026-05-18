locals {
  workload        = "test"
  compliance_tier = "standard"
  workload_tags   = { Workload = local.workload, ComplianceTier = local.compliance_tier }
}

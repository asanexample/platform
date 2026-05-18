locals {
  workload        = "platform"
  compliance_tier = "high"
  workload_tags   = { Workload = local.workload, ComplianceTier = local.compliance_tier }
}

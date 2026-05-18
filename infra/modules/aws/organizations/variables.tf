variable "create" {
  description = "Whether to create any resources in this module."
  type        = bool
  default     = true
}

variable "create_organization" {
  description = "Whether to create the AWS Organization (false to data-source an existing one)."
  type        = bool
  default     = false
}

variable "organization_aws_service_access_principals" {
  description = "AWS service principals to enable for organization integration."
  type        = list(string)
  default = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "access-analyzer.amazonaws.com",
    "sso.amazonaws.com",
    "tagpolicies.tag.amazonaws.com",
  ]
}

variable "organization_enabled_policy_types" {
  description = "Policy types to enable in the organization."
  type        = list(string)
  default     = ["SERVICE_CONTROL_POLICY", "TAG_POLICY"]
}

variable "organizational_units" {
  description = "Map of OU names to their configuration. Key is the OU name, parent=null for root-level OUs."
  type = map(object({
    parent = optional(string)
  }))
  default = {}
}

variable "accounts" {
  description = "Map of account names to their configuration."
  type = map(object({
    email = string
    ou    = optional(string)
  }))
  default = {}
}

variable "service_control_policies" {
  description = "Custom SCP JSON map override. When set, replaces all built-in default SCPs."
  type        = map(string)
  default     = null
}

variable "scp_attachments" {
  description = "Map of target name to list of SCP names to attach. Use 'root' for the org root."
  type        = map(list(string))
  default = {
    "root"      = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
    "Platform"  = ["protect-data-and-network"]
    "Workloads" = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
  }
}

variable "allowed_regions" {
  description = "AWS regions where resources are allowed (used by region-deny SCP)."
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "required_tags" {
  description = "Tag keys that must be present on supported resources."
  type        = list(string)
  default     = ["Environment", "ManagedBy", "Owner"]
}

variable "exempt_roles" {
  description = "IAM role names exempt from SCP deny statements."
  type        = list(string)
  default     = ["OrganizationAccountAccessRole"]
}

variable "enable_hipaa_scp" {
  description = "Whether to enable the HIPAA eligible services allowlist SCP."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to SCPs and OUs."
  type        = map(string)
  default     = {}
}

variable "create" {
  description = "Controls whether resources are created"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name the Pod Identity association is created for"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID (scopes the Bedrock inference-profile ARN)"
  type        = string
}

variable "namespace" {
  description = "Namespace the triage-copilot agent runs in"
  type        = string
  default     = "triage-copilot"
}

variable "service_account" {
  description = "ServiceAccount the agent runs as (bound to the role via Pod Identity)"
  type        = string
  default     = "triage-copilot"
}

variable "inference_profile_id" {
  description = "Bedrock cross-region inference-profile id the agent invokes"
  type        = string
  default     = "us.anthropic.claude-sonnet-4-6"
}

variable "foundation_model_id" {
  description = "Foundation model the inference profile routes to (cross-region invoke needs the model ARN too; trailing * allows minor revisions)"
  type        = string
  default     = "anthropic.claude-sonnet-4-6*"
}

variable "tags" {
  description = "Tags applied to the IAM role and the Pod Identity association"
  type        = map(string)
  default     = {}
}

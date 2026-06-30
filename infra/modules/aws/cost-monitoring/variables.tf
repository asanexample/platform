variable "create" {
  description = "Whether to create the cost-monitoring resources."
  type        = bool
  default     = true
}

variable "name_prefix" {
  description = "Prefix for named resources (anomaly monitor/subscription, Chatbot role + configuration)."
  type        = string
  default     = "platform-cost"
}

variable "topic_name" {
  description = "Name of the SNS topic Budgets + Cost Anomaly Detection publish to."
  type        = string
  default     = "platform-cost-alerts"
}

variable "alert_emails" {
  description = "Email addresses subscribed to the cost-alerts topic (each must confirm the AWS subscription email)."
  type        = list(string)
  default     = []
}

variable "budgets" {
  description = "Monthly cost budgets, keyed by budget name. Omit linked_accounts for a consolidated (all-account) total. Keep to <= 2 budgets to stay within the AWS Budgets free tier."
  type = map(object({
    limit_usd       = number
    linked_accounts = optional(list(string))
  }))
  default = {}
}

variable "anomaly_threshold_usd" {
  description = "Absolute total-impact threshold (USD) above which a detected anomaly raises an IMMEDIATE alert."
  type        = number
  default     = 50
}

variable "anomaly_monitor_dimension" {
  description = "Dimension for the DIMENSIONAL Cost Anomaly Detection monitor (SERVICE or LINKED_ACCOUNT)."
  type        = string
  default     = "SERVICE"
}

variable "slack_team_id" {
  description = "Slack workspace (team) ID from the one-time AWS Chatbot authorization. Empty disables the Chatbot/Slack delivery (email still works)."
  type        = string
  default     = ""
}

variable "slack_channel_id" {
  description = "Slack channel ID the cost alerts post to (e.g. the #cost channel). Required when slack_team_id is set."
  type        = string
  default     = ""
}

variable "chatbot_guardrail_policy_arns" {
  description = "Guardrail policy ARNs bounding what the Chatbot configuration may do. Pinned read-only by default (the resource defaults to AdministratorAccess otherwise); cost notifications need no AWS permissions."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

variable "tags" {
  description = "Tags applied to taggable resources."
  type        = map(string)
  default     = {}
}

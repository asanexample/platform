variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "topic_name" {
  description = "SNS topic name for platform alert notifications (e.g. Alertmanager critical alerts, Falco security events)."
  type        = string
  default     = "platform-alerts"
}

variable "alert_emails" {
  description = "Email addresses subscribed to the topic. Each subscription must be confirmed via the email AWS sends before notifications flow."
  type        = list(string)
  default     = []
}

variable "kms_master_key_id" {
  description = "KMS key ID/alias for SNS server-side encryption. Defaults to the AWS-managed SNS key (alias/aws/sns); a customer-managed CMK upgrade is tracked in #118. Publishers need kms:GenerateDataKey*/Decrypt on this key."
  type        = string
  default     = "alias/aws/sns"
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}

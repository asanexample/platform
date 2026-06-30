variable "create" {
  type    = bool
  default = true
}

variable "alert_emails" {
  type    = list(string)
  default = []
}

variable "budgets" {
  type = map(object({
    limit_usd       = number
    linked_accounts = optional(list(string))
  }))
  default = {}
}

variable "existing_monitor_arn" {
  type    = string
  default = ""
}

variable "slack_team_id" {
  type    = string
  default = ""
}

variable "slack_channel_id" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

module "cost_monitoring" {
  source = "../../../../modules/aws/cost-monitoring"

  create               = var.create
  alert_emails         = var.alert_emails
  budgets              = var.budgets
  existing_monitor_arn = var.existing_monitor_arn
  slack_team_id        = var.slack_team_id
  slack_channel_id     = var.slack_channel_id
  tags                 = var.tags
}

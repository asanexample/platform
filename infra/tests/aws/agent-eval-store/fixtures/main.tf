variable "create" {
  type    = bool
  default = true
}

variable "bucket_name" {
  type    = string
  default = "test-agent-eval-corpus"
}

variable "reader_role_arns" {
  type    = list(string)
  default = []
}

variable "transition_to_ia_days" {
  type    = number
  default = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}

module "agent_eval_store" {
  source = "../../../../modules/aws/agent-eval-store"

  create                = var.create
  bucket_name           = var.bucket_name
  reader_role_arns      = var.reader_role_arns
  transition_to_ia_days = var.transition_to_ia_days
  force_destroy         = true
  tags                  = var.tags
}

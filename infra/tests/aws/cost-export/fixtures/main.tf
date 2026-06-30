variable "create" {
  type    = bool
  default = true
}

variable "reader_trusted_principal_arns" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

module "cost_export" {
  source = "../../../../modules/aws/cost-export"

  create                        = var.create
  reader_trusted_principal_arns = var.reader_trusted_principal_arns
  force_destroy                 = true
  tags                          = var.tags
}

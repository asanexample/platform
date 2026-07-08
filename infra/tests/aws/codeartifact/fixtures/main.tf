variable "create" {
  type    = bool
  default = true
}

variable "domain_name" {
  type    = string
  default = "test-refplat"
}

variable "kms_key_arn" {
  type    = string
  default = ""
}

variable "store_repositories" {
  type = map(object({
    external_connection = string
    description         = optional(string)
    tags                = optional(map(string), {})
  }))
  default = {}
}

variable "repositories" {
  type = map(object({
    description = optional(string)
    upstreams   = optional(list(string), [])
    tags        = optional(map(string), {})
  }))
  default = {}
}

variable "read_account_ids" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

module "codeartifact" {
  source = "../../../../modules/aws/codeartifact"

  create             = var.create
  domain_name        = var.domain_name
  kms_key_arn        = var.kms_key_arn
  store_repositories = var.store_repositories
  repositories       = var.repositories
  read_account_ids   = var.read_account_ids
  tags               = var.tags
}

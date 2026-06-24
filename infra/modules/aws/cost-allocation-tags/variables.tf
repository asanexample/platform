variable "create" {
  description = "Whether to activate the cost-allocation tags."
  type        = bool
  default     = true
}

variable "tag_keys" {
  description = "User-defined tag keys to activate as AWS cost-allocation tags (billing). Each must already appear on at least one resource. Payer/management account only; activation is forward-only."
  type        = list(string)
  default     = []
}

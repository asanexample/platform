variable "test_role_arn" {
  type    = string
  default = ""
}

provider "aws" {
  region = var.test_region

  dynamic "assume_role" {
    for_each = var.test_role_arn != "" ? [var.test_role_arn] : []
    content {
      role_arn = assume_role.value
    }
  }
}

variable "test_region" {
  type    = string
  default = "us-west-2"
}

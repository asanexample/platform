variable "test_role_arn" {
  type    = string
  default = ""
}

variable "test_region" {
  type    = string
  default = "us-west-2"
}

# Plan-only/hermetic: the trust policy is an aws_iam_policy_document (computed locally) and
# the role/OIDC-provider resources are not read from AWS at plan time, so no credentials or
# account lookups are needed. Skip them so the test runs offline.
provider "aws" {
  region = var.test_region

  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  dynamic "assume_role" {
    for_each = var.test_role_arn != "" ? [var.test_role_arn] : []
    content {
      role_arn = assume_role.value
    }
  }
}

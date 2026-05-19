variable "test_role_arn" {
  type    = string
  default = ""
}

variable "test_region" {
  type    = string
  default = "us-west-2"
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

provider "helm" {
  kubernetes {
    host                   = try(module.eks.cluster_endpoint, "")
    cluster_ca_certificate = try(base64decode(module.eks.cluster_certificate_authority), "")

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = compact([
        "eks", "get-token",
        "--cluster-name", var.cluster_name,
        "--region", var.test_region,
        var.test_role_arn != "" ? "--role-arn" : "",
        var.test_role_arn != "" ? var.test_role_arn : "",
      ])
    }
  }
}

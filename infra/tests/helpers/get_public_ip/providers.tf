/**
 * # Get Public IP Helper Providers
 */

terraform {
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.3.0"
} 
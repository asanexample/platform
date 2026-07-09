variable "create" {
  description = "Whether to create the CodeArtifact domain and repositories"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "CodeArtifact domain name — the dedupe + encryption boundary that all repositories live within (e.g. 'refplat')"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,48}[a-z0-9]$", var.domain_name))
    error_message = "domain_name must be 2-50 chars, lowercase alphanumeric or hyphen, starting with a letter."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for domain asset encryption. Empty string creates a customer-managed CMK in this module (with rotation). Provide an ARN to use an existing key."
  type        = string
  default     = ""
}

variable "store_repositories" {
  description = "Upstream 'store' repositories, each with a single external connection that proxies + caches one public source (e.g. { npm-store = { external_connection = \"public:npmjs\" } }). A CodeArtifact repository may have at most ONE external connection, so proxy each format via its own store repo and reference them as upstreams from consumer repositories."
  type = map(object({
    external_connection = string
    description         = optional(string)
    tags                = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.store_repositories) : startswith(r.external_connection, "public:")])
    error_message = "Each store repository's external_connection must be a public source (e.g. 'public:npmjs', 'public:pypi', 'public:maven-central', 'public:nuget-org')."
  }
}

variable "repositories" {
  description = "Consumer repositories (typically per-Team/Product). Each may list store/other repositories in this domain as upstreams; a package not found locally is fetched (and cached) from an upstream's external connection. Keys are repository names (e.g. 'alpha-shop')."
  type = map(object({
    description = optional(string)
    upstreams   = optional(list(string), [])
    tags        = optional(map(string), {})
  }))
  default = {}
}

variable "read_account_ids" {
  description = "AWS account IDs granted cross-account read (pull) access to the domain + consumer repositories (e.g. preprod, prod). Empty disables cross-account policies."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "domain" {
  description = "Base domain for the routes (e.g. aws.refplat.org). Route hostnames are <key>.<domain>."
  type        = string
}

# ---------------------------------------------------------------------------
# Gateway (created by the `gateway` module; referenced here by name for parentRefs)
# ---------------------------------------------------------------------------

variable "gateway_name" {
  description = "Name of the shared Gateway to attach routes to (from the gateway unit)."
  type        = string
  default     = "platform-gateway"
}

variable "gateway_namespace" {
  description = "Namespace of the shared Gateway (parentRef)."
  type        = string
  default     = "default"
}

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

variable "routes" {
  description = "Map of hostname prefix to service routing config"
  type = map(object({
    namespace = string
    service   = string
    port      = number
  }))
  default = {}
}

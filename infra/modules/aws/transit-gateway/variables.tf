variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "name" {
  description = "Name prefix for transit gateway resources"
  type        = string
}

variable "create_tgw" {
  description = "Create the Transit Gateway (hub mode). False for spoke mode."
  type        = bool
  default     = false
}

variable "transit_gateway_id" {
  description = "Existing TGW ID (spoke mode, required when create_tgw is false)"
  type        = string
  default     = null
}

variable "amazon_side_asn" {
  description = "Private ASN for the Transit Gateway"
  type        = number
  default     = 64512
}

variable "ram_share_principals" {
  description = "AWS account IDs to share the TGW with via RAM (hub mode only)"
  type        = list(string)
  default     = []
}

variable "ram_share_arn" {
  description = "ARN of the RAM resource share to accept (spoke mode only)"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC ID to attach to the Transit Gateway"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the TGW attachment (one per AZ, use transit subnets)"
  type        = list(string)
}

variable "route_table_ids" {
  description = "Map of route table name to ID for adding TGW routes"
  type        = map(string)
  default     = {}
}

variable "destination_cidrs" {
  description = "CIDR blocks to route via the Transit Gateway"
  type        = list(string)
  default     = []
}

variable "security_group_id" {
  description = "Security group ID to add ingress rules to (e.g. EKS cluster SG)"
  type        = string
  default     = null
}

variable "security_group_ingress_cidrs" {
  description = "CIDR blocks to allow inbound on port 443"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

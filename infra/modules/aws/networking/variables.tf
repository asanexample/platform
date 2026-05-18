variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "Name of the VPC to create"
  type        = string
}

variable "address_space" {
  description = "CIDR blocks for the VPC"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnets" {
  description = "Map of subnet names to configuration"
  type = map(object({
    address_prefixes  = list(string)
    availability_zone = optional(string)
    public            = optional(bool, false)
  }))
  default = {}
}

variable "environment" {
  description = "Environment name (e.g. ops, dev, staging, prod)"
  type        = string
}

variable "workload" {
  description = "Workload identifier for resource names"
  type        = string
}

variable "region_abbv" {
  description = "Abbreviated region name for resource naming"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "create_internet_gateway" {
  description = "Create an internet gateway. Set false for airgapped environments."
  type        = bool
  default     = true
}

variable "create_nat_gateways" {
  description = "Create NAT gateways for private subnet internet egress. Set false for public or airgapped topologies."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway instead of one per AZ. Ignored if create_nat_gateways is false."
  type        = bool
  default     = false
}

variable "enable_eks_networking" {
  description = "Whether to enable EKS-specific networking features (security groups, subnet tags)"
  type        = bool
  default     = false
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster. Used for subnet tagging when enable_eks_networking is true."
  type        = string
  default     = null
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "flow_log_destination" {
  description = "Flow log destination: cloud-watch-logs or s3"
  type        = string
  default     = "cloud-watch-logs"

  validation {
    condition     = contains(["cloud-watch-logs", "s3"], var.flow_log_destination)
    error_message = "Must be cloud-watch-logs or s3."
  }
}

variable "flow_log_retention_days" {
  description = "CloudWatch log group retention in days (ignored when destination is s3)"
  type        = number
  default     = 30
}

variable "flow_log_s3_bucket_arn" {
  description = "S3 bucket ARN for flow logs (required when flow_log_destination is s3)"
  type        = string
  default     = null
}

variable "create" {
  description = "Whether to create the state storage resources."
  type        = bool
  default     = true
}

variable "bucket_name" {
  description = "Name of the S3 bucket for Terraform state."
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking."
  type        = string
  default     = "terraform-locks"
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}

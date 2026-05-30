resource "aws_s3_bucket" "state" {
  count  = var.create ? 1 : 0
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "state" {
  count  = var.create ? 1 : 0
  bucket = aws_s3_bucket.state[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  count  = var.create ? 1 : 0
  bucket = aws_s3_bucket.state[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  count                   = var.create ? 1 : 0
  bucket                  = aws_s3_bucket.state[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# nosemgrep: terraform.aws.security.aws-dynamodb-table-unencrypted.aws-dynamodb-table-unencrypted
# DynamoDB encrypts at rest by default (AWS-owned key); this lock table holds only state-lock
# metadata (LockID), no sensitive data. A customer-managed CMK would be tracked with #118 if needed.
resource "aws_dynamodb_table" "locks" {
  count        = var.create ? 1 : 0
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID" # Partition key expected by the Terraform/OpenTofu S3 backend for state locking

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = var.tags
}

# State Bootstrap Module

This module provisions the S3 bucket and DynamoDB table that serve as the
Terraform/OpenTofu remote state backend. It is the first module deployed in
any new AWS environment and uses a local backend for its own state.

---

## Purpose

Every Terragrunt module in this repository stores its state in an S3 bucket
with DynamoDB-based locking. Before any module can be deployed, that bucket
and table must exist. This module creates them.

---

## Why Local State

This module is the one exception to the rule that all state is stored remotely.
It stores its own state in a local `terraform.tfstate` file within the
Terragrunt working directory. This is intentional: the S3 bucket that would
hold the state file is the very resource being created. You cannot store state
in a bucket that does not exist yet.

This chicken-and-egg problem means:

1. The state bootstrap module runs with `backend = "local"`.
2. Its `terraform.tfstate` file lives on the local filesystem.
3. All other modules use the S3 backend that this module created.

The local state file should be committed to version control or otherwise
preserved. Losing it means you cannot manage the state bucket through
Terragrunt without re-importing the resources.

---

## Usage

### Terragrunt Configuration

```hcl
# infra/live/aws/mgmt/global/state-bootstrap/terragrunt.hcl

include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders()
}

# Override remote_state to use local backend (bootstrapping)
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

terraform {
  source = include.base.locals.module_source.state_bootstrap
}

inputs = {
  create              = true
  bucket_name         = "tfstate-mgmt-851725353202"
  dynamodb_table_name = "terraform-locks"
  tags = {
    ManagedBy   = "Terragrunt"
    Environment = "mgmt"
    Owner       = "Platform Team"
  }
}
```

### Direct Module Usage

```hcl
module "state_bootstrap" {
  source = "../../modules/aws/state_bootstrap"

  create              = true
  bucket_name         = "tfstate-mgmt-851725353202"
  dynamodb_table_name = "terraform-locks"

  tags = {
    ManagedBy   = "Terragrunt"
    Environment = "mgmt"
  }
}
```

---

## Variables

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `create` | `bool` | `true` | No | Whether to create the state storage resources. Set to `false` to disable the module. |
| `bucket_name` | `string` | -- | **Yes** | Name of the S3 bucket for Terraform state. Must be globally unique across all AWS accounts. Convention: `tfstate-{environment}-{account_id}`. |
| `dynamodb_table_name` | `string` | `"terraform-locks"` | No | Name of the DynamoDB table for state locking. |
| `tags` | `map(string)` | `{}` | No | Tags applied to all created resources. |

---

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `bucket_name` | `string` | Name of the created S3 state bucket. |
| `bucket_arn` | `string` | ARN of the created S3 state bucket. |
| `dynamodb_table_name` | `string` | Name of the created DynamoDB lock table. |
| `dynamodb_table_arn` | `string` | ARN of the created DynamoDB lock table. |

---

## Security Considerations

This module applies the following security controls to the state backend:

### S3 Bucket

- **Versioning enabled.** Every state file write creates a new version. This
  allows recovery from accidental overwrites or corruption. Versioning cannot
  be disabled once enabled on the bucket.

- **Server-side encryption with KMS.** All objects are encrypted at rest using
  AWS KMS (SSE-KMS) with bucket key optimization enabled. This satisfies
  encryption-at-rest requirements for SOC 2, HIPAA, and PCI DSS.

- **Public access fully blocked.** All four public access block settings are
  enabled:
  - `block_public_acls = true`
  - `block_public_policy = true`
  - `ignore_public_acls = true`
  - `restrict_public_buckets = true`

  This prevents any public access to state files, which may contain sensitive
  resource attributes (IP addresses, ARNs, configuration values).

### DynamoDB Table

- **PAY_PER_REQUEST billing.** The table uses on-demand capacity, which
  eliminates the need to provision read/write capacity and avoids throttling
  during concurrent operations.

- **LockID hash key.** The table uses a string `LockID` attribute as its
  partition key, which is the schema expected by the Terraform S3 backend for
  state locking.

- **Encryption at rest.** DynamoDB tables are encrypted at rest by default
  using AWS-owned keys.

---

## Deploy Instructions

### First-Time Deployment

```bash
cd infra/live/aws/mgmt/global/state-bootstrap

# Initialize (downloads providers, generates backend.tf)
terragrunt init

# Review the plan
terragrunt plan

# Expected resources:
#   + aws_s3_bucket.state
#   + aws_s3_bucket_versioning.state
#   + aws_s3_bucket_server_side_encryption_configuration.state
#   + aws_s3_bucket_public_access_block.state
#   + aws_dynamodb_table.locks

# Apply
terragrunt apply
```

### Verify the Deployment

```bash
# Confirm the bucket exists and has versioning
aws s3api get-bucket-versioning --bucket tfstate-mgmt-851725353202
# Expected: {"Status": "Enabled"}

# Confirm encryption
aws s3api get-bucket-encryption --bucket tfstate-mgmt-851725353202
# Expected: SSEAlgorithm = aws:kms

# Confirm public access block
aws s3api get-public-access-block --bucket tfstate-mgmt-851725353202
# Expected: all four settings = true

# Confirm the DynamoDB table
aws dynamodb describe-table --table-name terraform-locks --query 'Table.TableStatus'
# Expected: "ACTIVE"
```

### After Deployment

Once the state bootstrap is deployed, all other modules in the repository
automatically use the S3 bucket for remote state. The root `terragrunt.hcl`
hardcodes the bucket name and DynamoDB table:

```hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = "tfstate-mgmt-851725353202"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

No additional configuration is needed in downstream modules.

---

## Requirements

| Provider | Version | Source |
|----------|---------|--------|
| `aws` | `>= 5.91.0` | `hashicorp/aws` |

### IAM Permissions

The deploying principal needs the following permissions:

- `s3:CreateBucket`, `s3:PutBucketVersioning`, `s3:PutEncryptionConfiguration`,
  `s3:PutBucketPublicAccessBlock`, `s3:GetBucket*`, `s3:ListBucket`
- `dynamodb:CreateTable`, `dynamodb:DescribeTable`, `dynamodb:TagResource`
- `kms:CreateKey` (if using a customer-managed KMS key)

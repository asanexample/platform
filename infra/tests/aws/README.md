# AWS Module Tests (Terratest)

Go-based infrastructure tests using [Terratest](https://terratest.gruntwork.io/). These tests perform real AWS apply/destroy cycles to validate module behavior.

## Prerequisites

- Go 1.22+
- OpenTofu (`tofu` binary in PATH)
- AWS credentials capable of assuming `OrganizationAccountAccessRole` into the platform account

## Running Tests

```bash
# All AWS tests
make test-aws

# Networking module only
make test-aws-networking

# Single test case
cd infra/tests/aws
go test -v -run TestNetworking_PrivateTopology -timeout 30m ./networking/...
```

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `TEST_AWS_REGION` | `us-west-2` | Region to deploy test resources |
| `TEST_ROLE_ARN` | `arn:aws:iam::829808296602:role/OrganizationAccountAccessRole` | IAM role to assume |

## Cost

Each full test run creates and destroys real AWS resources. Estimated cost: ~$0.10-0.20 per run (NAT gateway hourly charges). Tests clean up after themselves via `defer terraform.Destroy`.

## Test Cases

| Test | Topology | Time | What it validates |
|------|----------|------|-------------------|
| `TestNetworking_PrivateTopology` | Private + NAT | ~3-4 min | IGW, single NAT, private/public routing, EKS tags, flow logs, S3 endpoint |
| `TestNetworking_PublicTopology` | Public | ~1-2 min | IGW, no NAT, public IP mapping, no private default route |
| `TestNetworking_AirgappedTopology` | Airgapped | ~1 min | No IGW, no NAT, no public RT, S3 endpoint only |
| `TestNetworking_Disabled` | N/A | ~5 sec | `create=false` produces zero resources (plan-only) |
| `TestNetworking_MultiAZNAT` | Private + per-AZ NAT | ~4-5 min | 2 NATs, AZ-correct routing |

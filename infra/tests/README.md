# Infrastructure Tests

Automated tests for the platform's OpenTofu modules. Tests are **Terratest (Go)** —
real plan/apply/destroy cycles against AWS — not OpenTofu native (`.tftest.hcl`) tests.

## Layout

| Path | What |
|------|------|
| [`aws/`](aws/) | The Terratest suite (`networking`, `eks`, `ssm-bastion`). See [`aws/README.md`](aws/README.md) for prerequisites and how to run. |
| `helpers/` | Shared Go test helpers (e.g. `get_public_ip`). |

## Running

```bash
# All AWS Terratest tests (requires AWS credentials)
make test-aws

# A single suite
make test-aws-networking
make test-aws-eks

# Or directly
cd infra/tests/aws && go test -v -timeout 45m ./...
```

House conventions (see the **testing** memory and CLAUDE.md):

- Terratest (Go), **not** `.tftest.hcl`.
- Test helpers must set `TerraformBinary: "tofu"` — the platform runs OpenTofu, not Terraform.
- Plan-only is acceptable for modules that can't be safely apply/destroyed in CI;
  the primary cluster/networking tests do a real apply + AWS-API assertions.

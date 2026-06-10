# sops-kms

The dedicated AWS KMS key that encrypts the platform's config secrets (ADR-066). SOPS encrypts
`infra/live/aws/secrets.enc.yaml` to this key; `root.hcl` + `common.hcl` decrypt it inline via Terragrunt's
`sops_decrypt_file` at config-eval time.

Decryption is gated entirely by the key policy:

- **Operators** (SSO `AdministratorAccess`, scoped by an `aws:PrincipalArn` `ArnLike`) — encrypt **and**
  decrypt, so `sops <file>` editing works.
- **Decrypt-only principals** (the ARC runner role) — decrypt in CI, never edit.

**Bootstrap-tier.** Every Terragrunt run depends on this key (config load decrypts the SOPS file), so it must
exist before anything else — like the S3 state backend (ADR-006). It is created here while config is still
plaintext; making the unit fully from-scratch-bootstrap-safe (no secrets chain) is a documented follow-up.

| Input | Purpose |
|-------|---------|
| `alias_name` | KMS alias (default `platform-sops`) |
| `operator_account_roots` + `operator_principal_patterns` | Accounts + SSO-admin pattern allowed to encrypt+decrypt |
| `decrypt_principal_arns` | Exact principals allowed to decrypt only (the runner role) |

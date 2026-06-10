include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.sops_kms
}

# SOPS config-encryption key (ADR-066). Encrypts infra/live/aws/secrets.enc.yaml; root.hcl + common.hcl decrypt
# it inline. It lives in MANAGEMENT, alongside the state backend (ADR-006) — the bootstrap floor that is never
# torn down — so the committed secrets.enc.yaml stays decryptable across teardown/rebuild. `prevent_destroy`
# (in the module) is the seatbelt; teardown tooling (platctl) must also exclude this unit, like state_bootstrap.
inputs = {
  create     = true
  alias_name = "platform-sops"

  # Operators authenticate from management (and occasionally platform) as SSO AdministratorAccess — encrypt +
  # decrypt so `sops` editing works. Management operators decrypt this key same-account; platform operators
  # cross-account (their SSO admin IAM allows it).
  operator_account_roots = [
    "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:root",
    "arn:aws:iam::${include.base.locals.account_ids["platform"]}:root",
  ]
  operator_principal_patterns = [
    "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
    "arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
  ]

  # The ARC runner (platform account) reads config in CI — decrypt only, CROSS-account. The key policy admits
  # it here; the runner role's IAM also grants kms:Decrypt (cross-account KMS needs both — actions-runner-controller).
  decrypt_principal_arns = [
    "arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/platform-use1-eks-arc-runner",
  ]

  tags = include.base.locals.tags
}

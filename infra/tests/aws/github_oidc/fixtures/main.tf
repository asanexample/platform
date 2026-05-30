variable "create" {
  type    = bool
  default = true
}

variable "github_org" {
  type    = string
  default = "asanexample"
}

# Passed through to the module untyped so each test can supply its own role shapes
# (sub-scoped, job_workflow_ref-scoped, or invalid) without HCL object-unification issues.
variable "roles" {
  type    = any
  default = {}
}

module "github_oidc" {
  source = "../../../../modules/aws/github_oidc"

  create     = var.create
  github_org = var.github_org
  roles      = var.roles
}

output "role_arns" {
  value = module.github_oidc.role_arns
}

output "role_subject_claims" {
  value = module.github_oidc.role_subject_claims
}

output "role_job_workflow_ref_claims" {
  value = module.github_oidc.role_job_workflow_ref_claims
}

variable "create" {
  type    = bool
  default = true
}

variable "name" {
  type = string
}

variable "vpc_id" {
  type    = string
  default = "vpc-12345678"
}

variable "subnet_id" {
  type    = string
  default = "subnet-12345678"
}

variable "tags" {
  type    = map(string)
  default = {}
}

module "ssm_bastion" {
  source = "../../../../modules/aws/ssm-bastion"

  create    = var.create
  name      = var.name
  vpc_id    = var.vpc_id
  subnet_id = var.subnet_id
  tags      = var.tags
}

output "instance_id" {
  value = module.ssm_bastion.instance_id
}

output "security_group_id" {
  value = module.ssm_bastion.security_group_id
}

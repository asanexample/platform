output "instance_id" {
  description = "EC2 instance ID for SSM session targets"
  value       = local.create ? aws_instance.bastion[0].id : null
}

output "security_group_id" {
  description = "Security group ID of the bastion"
  value       = local.create ? aws_security_group.bastion[0].id : null
}

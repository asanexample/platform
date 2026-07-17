output "instance_id" {
  description = "EC2 instance ID of the Tailscale subnet router (SSM session target)"
  value       = local.create ? aws_instance.router[0].id : null
}

output "security_group_id" {
  description = "Security group ID of the router"
  value       = local.create ? aws_security_group.router[0].id : null
}

output "private_ip" {
  description = "Private IP of the router — the SNAT source that in-VPC targets (e.g. the EKS API SG) see"
  value       = local.create ? aws_instance.router[0].private_ip : null
}

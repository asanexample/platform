output "active_tag_keys" {
  description = "Tag keys activated as cost-allocation tags."
  value       = sort([for t in aws_ce_cost_allocation_tag.this : t.tag_key])
}

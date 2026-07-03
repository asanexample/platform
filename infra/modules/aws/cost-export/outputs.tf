output "bucket_name" {
  description = "Name of the CUR / Athena-results S3 bucket."
  value       = try(aws_s3_bucket.cur[0].id, null)
}

output "cur_report_name" {
  description = "Name of the Cost & Usage Report."
  value       = try(aws_cur_report_definition.this[0].report_name, null)
}

output "glue_database_name" {
  description = "Glue database holding the crawled CUR table."
  value       = try(aws_glue_catalog_database.cur[0].name, null)
}

output "athena_workgroup_name" {
  description = "Athena workgroup for CUR queries."
  value       = try(aws_athena_workgroup.cur[0].name, null)
}

output "cost_reader_role_arn" {
  description = "ARN of the cross-account read role OpenCost assumes (null when no trust principals are given)."
  value       = try(aws_iam_role.cost_reader[0].arn, null)
}

output "athena_results_location" {
  description = "s3:// URI Athena writes query RESULTS to (the workgroup's configured output_location) — NOT the CUR data location, which is implicit in the Glue table."
  value       = try(aws_athena_workgroup.cur[0].configuration[0].result_configuration[0].output_location, null)
}

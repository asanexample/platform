output "namespace" {
  description = "Namespace the kube-bench scan runs in"
  value       = var.namespace
}

output "cronjob_name" {
  description = "Name of the kube-bench CronJob"
  value       = local.create ? kubernetes_cron_job_v1.kube_bench[0].metadata[0].name : null
}

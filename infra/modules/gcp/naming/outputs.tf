output "vpc" {
  description = "Standardized name for a GCP VPC network."
  value       = local.validated_names.vpc
}

output "subnet" {
  description = "Base subnet name for generating type-specific subnet names."
  value       = local.subnet_name
}

output "subnet_public" {
  description = "Standardized name for a public subnet."
  value       = local.subnet_public
}

output "subnet_private" {
  description = "Standardized name for a private subnet."
  value       = local.subnet_private
}

output "subnet_data" {
  description = "Standardized name for a data subnet."
  value       = local.subnet_data
}

output "subnet_gke" {
  description = "Standardized name for a GKE subnet."
  value       = local.subnet_gke
}

output "subnet_proxy" {
  description = "Standardized name for a proxy-only subnet."
  value       = local.subnet_proxy
}

output "gke" {
  description = "Standardized name for a GKE cluster."
  value       = local.validated_names.gke
}

output "gcs" {
  description = "Standardized name for a Cloud Storage bucket (globally unique, lowercase)."
  value       = local.validated_names.gcs
}

output "gcr" {
  description = "Standardized name for an Artifact Registry repository."
  value       = local.validated_names.gcr
}

output "fw" {
  description = "Standardized name for a firewall rule."
  value       = local.validated_names.fw
}

output "router" {
  description = "Standardized name for a Cloud Router."
  value       = local.validated_names.router
}

output "nat" {
  description = "Standardized name for a Cloud NAT."
  value       = local.validated_names.nat
}

output "lb" {
  description = "Standardized name for a load balancer."
  value       = local.validated_names.lb
}

output "cloudsql" {
  description = "Standardized name for a Cloud SQL instance."
  value       = local.validated_names.cloudsql
}

output "memorystore" {
  description = "Standardized name for a Memorystore instance."
  value       = local.validated_names.memorystore
}

output "pubsub_topic" {
  description = "Standardized name for a Pub/Sub topic."
  value       = local.validated_names.pubsub_topic
}

output "pubsub_sub" {
  description = "Standardized name for a Pub/Sub subscription."
  value       = local.validated_names.pubsub_sub
}

output "kms_keyring" {
  description = "Standardized name for a KMS key ring."
  value       = local.validated_names.kms_keyring
}

output "kms_key" {
  description = "Standardized name for a KMS key."
  value       = local.validated_names.kms_key
}

output "sa" {
  description = "Standardized name for a service account (30 char max, lowercase)."
  value       = local.validated_names.sa
}

output "cloudrun" {
  description = "Standardized name for a Cloud Run service."
  value       = local.validated_names.cloudrun
}

output "gce" {
  description = "Standardized name for a Compute Engine instance."
  value       = local.validated_names.gce
}

output "cloudfunc" {
  description = "Standardized name for a Cloud Function."
  value       = local.validated_names.cloudfunc
}

output "resource_types" {
  description = "All resource type abbreviations."
  value       = local.resource_types
}

output "names" {
  description = "Map of all generated resource names."
  value       = local.validated_names
}

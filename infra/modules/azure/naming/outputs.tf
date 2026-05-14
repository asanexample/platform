output "resource_group" {
  description = "Standardized name for an Azure Resource Group."
  value       = local.validated_names.resource_group
}

output "storage_account" {
  description = "Standardized name for an Azure Storage Account."
  value       = local.validated_names.storage_account
}

output "key_vault" {
  description = "Standardized name for an Azure Key Vault."
  value       = local.validated_names.key_vault
}

output "aks_cluster" {
  description = "Standardized name for an Azure Kubernetes Service cluster."
  value       = local.validated_names.aks_cluster
}

output "workload_identity" {
  description = "Standardized name for a workload identity."
  value       = local.validated_names.workload_identity
}

output "federated_identity" {
  description = "Standardized name for a federated identity."
  value       = local.validated_names.federated_identity
}

output "log_analytics_workspace" {
  description = "Standardized name for a Log Analytics Workspace."
  value       = local.validated_names.log_analytics_workspace
}

output "app_service" {
  description = "Standardized name for an App Service."
  value       = local.validated_names.app_service
}

output "function_app" {
  description = "Standardized name for a Function App."
  value       = local.validated_names.function_app
}

output "virtual_network" {
  description = "Standardized name for a Virtual Network."
  value       = local.validated_names.virtual_network
}

output "subnet" {
  description = "Base subnet name for generating type-specific subnet names."
  value       = local.subnet_name
}

output "subnet_node" {
  description = "Standardized name for a node subnet."
  value       = local.subnet_node
}

output "subnet_api" {
  description = "Standardized name for an API subnet."
  value       = local.subnet_api
}

output "subnet_app" {
  description = "Standardized name for an application subnet."
  value       = local.subnet_app
}

output "subnet_db" {
  description = "Standardized name for a database subnet."
  value       = local.subnet_db
}

output "subnet_endpoint" {
  description = "Standardized name for a private endpoint subnet."
  value       = local.subnet_endpoint
}

output "subnet_service" {
  description = "Standardized name for a service subnet."
  value       = local.subnet_service
}

output "subnet_gateway" {
  description = "Standardized name for a gateway subnet."
  value       = local.subnet_gateway
}

output "subnet_with_type" {
  description = "Base subnet name for appending custom type suffixes."
  value       = local.subnet_name
}

output "front_door" {
  description = "Standardized name for a Front Door."
  value       = local.validated_names.front_door
}

output "frontdoor_profile" {
  description = "Standardized name for a Front Door Profile."
  value       = local.validated_names.frontdoor_profile
}

output "frontdoor_endpoint" {
  description = "Standardized name for a Front Door Endpoint."
  value       = local.validated_names.frontdoor_endpoint
}

output "frontdoor_origin_group" {
  description = "Standardized name for a Front Door Origin Group."
  value       = local.validated_names.frontdoor_origin_group
}

output "frontdoor_origin" {
  description = "Standardized name for a Front Door Origin."
  value       = local.validated_names.frontdoor_origin
}

output "frontdoor_route" {
  description = "Standardized name for a Front Door Route."
  value       = local.validated_names.frontdoor_route
}

output "container_registry" {
  description = "Standardized name for a Container Registry."
  value       = local.container_registry_name
}

output "event_hub_namespace" {
  description = "Standardized name for an Event Hub Namespace."
  value       = local.validated_names.event_hub_namespace
}

output "event_hub" {
  description = "Standardized name for an Event Hub."
  value       = local.validated_names.event_hub
}

output "monitor_workspace" {
  description = "Standardized name for an Azure Monitor workspace (Prometheus)."
  value       = "${local.names.monitor_workspace}-prometheus"
}

output "application_insights" {
  description = "Standardized name for Application Insights."
  value       = local.validated_names.application_insights
}

output "app_configuration" {
  description = "Standardized name for an App Configuration."
  value       = local.validated_names.app_configuration
}

output "sql_server" {
  description = "Standardized name for a SQL Server."
  value       = local.validated_names.sql_server
}

output "sql_database" {
  description = "Standardized name for a SQL Database."
  value       = local.validated_names.sql_database
}

output "cosmos_account" {
  description = "Standardized name for a Cosmos DB Account."
  value       = local.validated_names.cosmos_account
}

output "network_security_group" {
  description = "Standardized name for a Network Security Group."
  value       = local.validated_names.network_security_group
}

output "route_table" {
  description = "Standardized name for a Route Table."
  value       = local.validated_names.route_table
}

output "bastion_host" {
  description = "Standardized name for a Bastion Host."
  value       = local.validated_names.bastion_host
}

output "private_endpoint" {
  description = "Standardized name for a Private Endpoint."
  value       = local.validated_names.private_endpoint
}

output "public_ip" {
  description = "Standardized name for a Public IP."
  value       = local.validated_names.public_ip
}

output "load_balancer" {
  description = "Standardized name for a Load Balancer."
  value       = local.validated_names.load_balancer
}

output "aks_node_pool" {
  description = "Standardized name for an AKS node pool."
  value       = local.validated_names.aks_node_pool
}

output "managed_prometheus" {
  description = "Standardized name for an AKS managed Prometheus resource."
  value       = local.validated_names.managed_prometheus
}

output "container_insights" {
  description = "Standardized name for an AKS container insights resource."
  value       = local.validated_names.container_insights
}

output "aks_identity" {
  description = "Standardized name for an AKS managed identity."
  value       = local.validated_names.aks_identity
}

output "resource_types" {
  description = "All resource type abbreviations."
  value       = local.resource_types
}

output "names" {
  description = "Map of all generated resource names."
  value       = local.validated_names
}

output "grafana" {
  description = "Standardized name for an Azure Managed Grafana instance."
  value       = "${local.names.managed_grafana}"
}

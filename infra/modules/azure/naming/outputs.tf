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
  description = "Function to generate standardized subnet names with subnet type parameter."
  value       = "${local.subnet_name}"
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
  description = "Generate a subnet name with a specific type."
  value       = "${local.subnet_name}"
}

output "front_door" {
  description = "Standardized name for a Front Door."
  value       = local.validated_names.front_door
}

output "frontdoor_endpoint" {
  description = "Standardized name for a Front Door Endpoint."
  value       = local.validated_names.frontdoor_endpoint
}

output "container_registry" {
  description = "Standardized name for a Container Registry."
  value       = local.validated_names.container_registry
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
  description = "Standardized name for a Monitor Workspace."
  value       = local.validated_names.monitor_workspace
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

output "resource_types" {
  description = "Map of resource type abbreviations."
  value       = local.resource_types
}

output "names" {
  description = "Map of all generated resource names."
  value       = local.validated_names
}

output "normalized_customer" {
  description = "Normalized customer name for use in resource naming."
  value       = local.normalized_customer
} 
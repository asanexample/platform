output "namespace_tenants" {
  description = "Map of namespace-mode tenant names to their namespace"
  value       = { for k, v in kubernetes_namespace.tenant : k => v.metadata[0].name }
}

output "vcluster_tenants" {
  description = "Map of vcluster-mode tenant names to their vCluster details"
  value = { for k, v in module.vcluster : k => {
    namespace              = v.namespace
    kubeconfig_secret_name = v.kubeconfig_secret_name
  } }
}

output "all_namespaces" {
  description = "List of all tenant namespaces (both modes)"
  value = concat(
    [for k, v in kubernetes_namespace.tenant : v.metadata[0].name],
    [for k, v in module.vcluster : v.namespace],
  )
}

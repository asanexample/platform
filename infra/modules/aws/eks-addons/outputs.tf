output "addons" {
  description = "Map of installed addon names to their status"
  value = {
    for name, addon in aws_eks_addon.this : name => {
      version = addon.addon_version
    }
  }
}

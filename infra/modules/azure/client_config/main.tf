/**
 * # Azure Client Config Module
 *
 * This module exposes the current Azure client configuration,
 * which includes details about the current user/service principal.
 * This is useful for automatically configuring role assignments.
 */

data "azurerm_client_config" "current" {}

# No resources are created in this module; it just exposes the current client config 
# This configuration has been generated by the Azure deployments handler which utilizes Generative AI which may result in unintended or inaccurate configuration code. A human must validate that this configuration accomplishes the desired goal before applying the configuration.

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = var.acr_sku
  admin_enabled       = true
}
provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "restaurants_rg" {
  name     = var.restaurants_rg_name
  location = var.resource_group_location
}

resource "azurerm_resource_group" "devops_rg" {
  name     = var.devops_rg_name
  location = var.resource_group_location
}

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.devops_rg.name
  location            = azurerm_resource_group.devops_rg.location
  sku                 = var.acr_sku
  admin_enabled       = true
}

data "azurerm_storage_account" "tfstate" {
  name                = "restaurantstfstatesa"
  resource_group_name = azurerm_resource_group.devops_rg.name
}

data "azurerm_resource_group" "devops_rg" {
  name = var.devops_rg_name
}

resource "random_pet" "azurerm_kubernetes_cluster_dns_prefix" {
  length    = 2
  separator = "-"
}

resource "azurerm_kubernetes_cluster" "k8s" {
  location            = azurerm_resource_group.restaurants_rg.location
  name                = "restaurants-aks"
  resource_group_name = azurerm_resource_group.restaurants_rg.name
  dns_prefix          = random_pet.azurerm_kubernetes_cluster_dns_prefix.id

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name       = "agentpool"
    vm_size    = "Standard_D2_v2"
    node_count = var.node_count
  }

  linux_profile {
    admin_username = var.username

    ssh_key {
      key_data = jsondecode(azapi_resource.ssh_public_key.body).properties.publicKey
    }
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }
}

output "resource_group_name" {
  value = azurerm_resource_group.restaurants_rg.name
}

terraform {
  backend "azurerm" {
    storage_account_name = "restaurantstfstatesa"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
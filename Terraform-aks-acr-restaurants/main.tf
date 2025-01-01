provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

terraform {
  backend "azurerm" {
    resource_group_name  = "DevOps-rg"  # Use hardcoded value
    storage_account_name = "restaurantstfstatesa"  # Use hardcoded value
    container_name       = "tfstate"  # Use hardcoded value
    key                  = "terraform.tfstate"
  }
}

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.devops_rg_name
  location            = var.restaurants_rg_location
  sku                 = var.acr_sku
  admin_enabled       = true
}

data "azurerm_storage_account" "tfstate" {
  name                = var.storage_account_name
  resource_group_name = var.devops_rg_name
}

data "azurerm_resource_group" "devops_rg" {
  name = var.devops_rg_name
}

resource "random_pet" "azurerm_kubernetes_cluster_dns_prefix" {
  length    = 2
  separator = "-"
}

resource "azurerm_kubernetes_cluster" "k8s" {
  location            = var.restaurants_rg_location
  name                = "restaurants-aks"
  resource_group_name = var.restaurants_rg_name
  dns_prefix          = random_pet.azurerm_kubernetes_cluster_dns_prefix.id

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}

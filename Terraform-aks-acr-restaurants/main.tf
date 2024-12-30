provider "azurerm" {
  features {}

  subscription_id = "80fab2d0-ef24-4ff6-a7ed-02a816eee488"
  client_id       = "8b1fe80d-d185-45dc-b711-6e1c6ad0b243"
  client_secret   = "restaurants-sp-secret-value"
  tenant_id       = "339e2a15-710e-4162-ab7e-8d1199b663b9"
}

terraform {
  backend "azurerm" {
    resource_group_name  = "DevOps-rg"
    storage_account_name = "restaurantstfstatesa"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
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

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}

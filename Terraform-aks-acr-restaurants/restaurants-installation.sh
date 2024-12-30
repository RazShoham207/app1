#!/bin/bash

start_time=$(date +%s)
echo "### Running Terraform - START - $(date '+%d-%m-%Y %H:%M:%S')"

# Variables
SUBSCRIPTION_ID="80fab2d0-ef24-4ff6-a7ed-02a816eee488"
DEVOPS_RESOURCE_GROUP_NAME="DevOps-rg"
STORAGE_ACCOUNT_NAME="restaurantstfstatesa"
CONTAINER_NAME="tfstate"
RESTAURANTS_RESOURCE_GROUP_NAME="Restaurants-rg"
CLIENT_ID="8b1fe80d-d185-45dc-b711-6e1c6ad0b243"
CLIENT_SECRET="<restaurants-sp-secret-value>"
TENANT_ID="339e2a15-710e-4162-ab7e-8d1199b663b9"

authenticate_azure() {
  echo "### Authenticating with Azure using Service Principal"
  az login --service-principal -u $CLIENT_ID -p $CLIENT_SECRET --tenant $TENANT_ID
}

set_subscription() {
  echo "### Setting the Azure subscription"
  az account set --subscription $SUBSCRIPTION_ID
}

get_storage_account_key() {
  echo "### Getting storage account key"
  STORAGE_ACCOUNT_KEY=$(az storage account keys list --resource-group $DEVOPS_RESOURCE_GROUP_NAME --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' --output tsv)
  export ARM_ACCESS_KEY=$STORAGE_ACCOUNT_KEY
}

initialize_terraform() {
  echo "### Initializing Terraform - $(date '+%d-%m-%Y %H:%M:%S')"
  terraform init -upgrade -reconfigure -backend-config="access_key=$STORAGE_ACCOUNT_KEY"
}

import_resource_group() {
  local rg_name=$1
  local rg_id=$2
  echo "### Importing resource group $rg_name into the state"
  if ! terraform state list | grep -q "azurerm_resource_group.$rg_name"; then
    terraform import azurerm_resource_group.$rg_name $rg_id
  else
    echo "### Resource group $rg_name is already managed by Terraform. Skipping import."
  fi
}

create_execution_plan() {
  echo "### Creating an execution plan - $(date '+%d-%m-%Y %H:%M:%S')"
  terraform plan -out=tfplan
}

apply_execution_plan() {
  echo "### Applying the execution plan - $(date '+%d-%m-%Y %H:%M:%S')"
  terraform apply -auto-approve tfplan
}

get_kube_config() {
  echo "### Getting the Kubernetes configuration from the Terraform state"
  terraform output -raw kube_config > ./azurek8s
}

remove_resource_group_from_state() {
  local rg_name=$1
  echo "### Checking if $rg_name exists in the state"
  if terraform state list | grep -q "azurerm_resource_group.$rg_name"; then
    echo "### Removing $rg_name from the state"
    terraform state rm azurerm_resource_group.$rg_name
  else
    echo "### $rg_name does not exist in the state. Skipping removal."
  fi
}

check_and_create_resource_group() {
  local rg_name=$1
  echo "### Checking if the resource group $rg_name exists"
  if az group show --name $rg_name &> /dev/null; then
    echo "### Resource group $rg_name already exists. Skipping creation."
  else
    echo "### Creating resource group $rg_name"
    az group create --name $rg_name --location eastus
  fi
}

check_and_create_storage_account() {
  echo "### Checking if the storage account $STORAGE_ACCOUNT_NAME exists"
  if az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME &> /dev/null; then
    echo "### Storage account $STORAGE_ACCOUNT_NAME already exists. Skipping creation."
  else
    echo "### Creating storage account $STORAGE_ACCOUNT_NAME"
    az storage account create --name $STORAGE_ACCOUNT_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --location eastus --sku Standard_LRS
  fi
}

check_and_create_storage_container() {
  echo "### Checking if the storage container $CONTAINER_NAME exists"
  if az storage container list --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY --query "[?name=='$CONTAINER_NAME']" | grep -q $CONTAINER_NAME; then
    echo "### Storage container $CONTAINER_NAME already exists. Skipping creation."
  else
    echo "### Creating storage container $CONTAINER_NAME"
    az storage container create --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY
  fi
}

generate_ssh_key() {
  echo "### Generating the SSH Public key"
  if [ ! -f ~/.ssh/id_rsa.pub ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
  fi
}

refresh_resource_groups() {
  # List the current state and filter for DevOps-rg
  echo "### Listing the current state"
  terraform state list

  # Remove existing resource groups from the state if they exist
  if terraform state list | grep -q "data.azurerm_resource_group.devops_rg"; then
    echo "### Removing devops_rg from the state"
    terraform state rm data.azurerm_resource_group.devops_rg
  else
    echo "### devops_rg does not exist in the state. Skipping removal."
  fi

  if terraform state list | grep -q "azurerm_resource_group.restaurants_rg"; then
    echo "### Removing restaurants_rg from the state"
    terraform state rm azurerm_resource_group.restaurants_rg
  else
    echo "### restaurants_rg does not exist in the state. Skipping removal."
  fi

  # Import existing resource groups into the state again
  import_resource_group "restaurants_rg" "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESTAURANTS_RESOURCE_GROUP_NAME"
  import_resource_group "devops_rg" "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$DEVOPS_RESOURCE_GROUP_NAME"
}

main() {
  authenticate_azure
  set_subscription
  get_storage_account_key
  initialize_terraform

  # Import existing resource groups into the state
  import_resource_group "restaurants_rg" "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESTAURANTS_RESOURCE_GROUP_NAME"
  import_resource_group "devops_rg" "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$DEVOPS_RESOURCE_GROUP_NAME"

  # Refresh resource groups
  refresh_resource_groups

  create_execution_plan
  apply_execution_plan
  get_kube_config

  # Refresh resource groups
  refresh_resource_groups

  # Check and create resource groups and storage account
  check_and_create_resource_group $DEVOPS_RESOURCE_GROUP_NAME
  check_and_create_resource_group $RESTAURANTS_RESOURCE_GROUP_NAME
  check_and_create_storage_account
  get_storage_account_key
  check_and_create_storage_container

  # Initialize Terraform again
  initialize_terraform

  # Generate SSH key if it does not exist
  generate_ssh_key

  # Initialize Terraform again
  initialize_terraform

  # Refresh resource groups
  refresh_resource_groups

  create_execution_plan
  apply_execution_plan
  get_kube_config

  # Remove << EOT and EOT from the azurek8s file
  echo "### Remove << EOT and EOT from the azurek8s file"
  sed -i '/<< EOT/d' ./azurek8s
  sed -i '/EOT/d' ./azurek8s

  # Set an environment variable so kubectl can pick up the correct config
  echo "### Setting an environment variable so kubectl can pick up the correct config"
  export KUBECONFIG=./azurek8s
  chmod 600 ./azurek8s

  # Verify the health of the cluster using the kubectl get nodes command
  echo "### Verifying the health of the cluster using the kubectl get nodes command"
  kubectl get nodes

  # Attach the Azure Container Registry to the AKS cluster
  echo "### Attaching the Azure Container Registry to the AKS cluster - $(date '+%d-%m-%Y %H:%M:%S')"
  az aks update -n restaurants-aks -g $RESTAURANTS_RESOURCE_GROUP_NAME --attach-acr restaurantsacr

  # Check the health of the Azure Container Registry
  echo "### Checking the health of the Azure Container Registry - $(date '+%d-%m-%Y %H:%M:%S')"
  az acr check-health --name restaurantsacr --ignore-errors --yes

  # Create a Kubernetes secret for the ACR credentials
  echo "### Creating a Kubernetes secret for the ACR credentials - $(date '+%d-%m-%Y %H:%M:%S')"
  ACR_USERNAME=$(az acr credential show --name restaurantsacr --query "username" --output tsv)
  ACR_PASSWORD=$(az acr credential show --name restaurantsacr --query "passwords[0].value" --output tsv)

  # Create the ACR SECRET
  echo "### Creating the ACR SECRET"
  ACR_SECRET=$(cat << EOT
apiVersion: v1
kind: Secret
metadata:
  name: acr-secret
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $(echo -n '{"auths":{"restaurantsacr.azurecr.io":{"username":"$ACR_USERNAME","password":"$ACR_PASSWORD","email":"raz.shoham207@gmail.com"}}}' | base64 -w 0)
EOT
  )

  # Apply the ACR SECRET into the AKS
  echo "### Applying the ACR SECRET into the AKS"
  echo "$ACR_SECRET" | kubectl apply -f -

  # Authenticate with the AKS cluster
  echo "### Authenticating with the AKS cluster"
  az aks get-credentials --resource-group Restaurants-rg --name restaurants-aks

  # Verify authentication
  echo "### Verifying authentication"
  kubectl get nodes

  # Check if the restaurants-app service exists
  if kubectl get svc restaurants-app -n default > /dev/null 2>&1; then
    # Get the External IP from a LoadBalancer service
    EXTERNAL_IP=$(kubectl get svc restaurants-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo "#####################################################################################################"
    echo "## The URL for the application is: http://$EXTERNAL_IP/recommend?style=American&vegetarian=false ##"
    echo "####################### Replace style and vegetarian with the desired values ########################"
    echo "#####################################################################################################"
    echo ""
    echo ""
    echo "### Running Terraform - END - $(date '+%d-%m-%Y %H:%M:%S')"
    end_time=$(date +%s)
    # Calculate the duration
    duration=$((end_time - start_time))
    # Convert the duration to hours, minutes, and seconds
    hours=$((duration / 3600))
    minutes=$(( (duration % 3600) / 60 ))
    seconds=$((duration % 60))
    echo "### Total Duration: $hours hours, $minutes minutes, and $seconds seconds"
  else
    echo "This is the first installation and there was no deploy yet. Therefore the restaurants-app service does not exist yet."
    echo ""
    echo "### Running Terraform - END - $(date '+%d-%m-%Y %H:%M:%S')"
    end_time=$(date +%s)
    # Calculate the duration
    duration=$((end_time - start_time))
    # Convert the duration to hours, minutes, and seconds
    hours=$((duration / 3600))
    minutes=$(( (duration % 3600) / 60 ))
    seconds=$((duration % 60))
    echo "### Total Duration: $hours hours, $minutes minutes, and $seconds seconds"
  fi
}

main

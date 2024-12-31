#!/bin/bash

start_time=$(date +%s)
echo "### Running Terraform - START - $(date '+%d-%m-%Y %H:%M:%S')"

# Variables
SUBSCRIPTION_ID="80fab2d0-ef24-4ff6-a7ed-02a816eee488"
DEVOPS_RESOURCE_GROUP_NAME="DevOps-rg"
STORAGE_ACCOUNT_NAME="restaurantstfstatesa"
CONTAINER_NAME="tfstate"
RESTAURANTS_RESOURCE_GROUP_NAME="Restaurants-rg"
RESTAURANTS_RESOURCE_GROUP_LOCATION="eastus"
CLIENT_ID="8b1fe80d-d185-45dc-b711-6e1c6ad0b243"
CLIENT_SECRET="<restaurants-sp-secret-value>"
TENANT_ID="339e2a15-710e-4162-ab7e-8d1199b663b9"
AKS_CLUSTER_NAME="restaurants-aks"

# Flag to determine if only plan should be run
RUN_PLAN_ONLY=false

# Parse command line arguments
for arg in "$@"
do
  case $arg in
    --plan)
    RUN_PLAN_ONLY=true
    shift # Remove --plan from processing
    ;;
    *)
    shift # Remove generic argument from processing
    ;;
  esac
done

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

create_execution_plan() {
  echo "### Creating an execution plan - $(date '+%d-%m-%Y %H:%M:%S')"
  terraform plan -out=tfplan -var="devops_rg_name=$DEVOPS_RESOURCE_GROUP_NAME" -var="restaurants_rg_name=$RESTAURANTS_RESOURCE_GROUP_NAME" -var="restaurants_rg_location=$RESTAURANTS_RESOURCE_GROUP_LOCATION"
}

apply_execution_plan() {
  echo "### Applying the execution plan - $(date '+%d-%m-%Y %H:%M:%S')"
  terraform apply -auto-approve tfplan
}

check_and_create_resource_group() {
  local rg_name=$1
  local rg_location=$2
  echo "### Checking if the resource group $rg_name exists"
  if az group show --name $rg_name &> /dev/null; then
    echo "### Resource group $rg_name already exists. Skipping creation."
  else
    echo "### Creating resource group $rg_name"
    az group create --name $rg_name --location $rg_location
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

remove_resource_group_from_state() {
  local rg_name=$1
  echo "### Checking if $rg_name exists in the state"
  terraform state list
  if $rg_name="devops_rg"; then
    terraform state list "data.azurerm_resource_group.$rg_name"
    echo "### Removing $rg_name from the state"
    terraform state rm "data.azurerm_resource_group.$rg_name"
  elif $rg_name="restaurants-rg"; then
    terraform state list "azurerm_resource_group.$rg_name"
    echo "### Removing $rg_name from the state"
    terraform state rm "azurerm_resource_group.$rg_name"
  else
    echo "### $rg_name does not exist in the state. Skipping removal."
  fi
}



main() {
  authenticate_azure
  set_subscription
  get_storage_account_key
  initialize_terraform

  # Generate SSH key if it does not exist
  generate_ssh_key

  # Check and create resource groups and storage account
  check_and_create_resource_group $DEVOPS_RESOURCE_GROUP_NAME $RESTAURANTS_RESOURCE_GROUP_LOCATION
  check_and_create_resource_group $RESTAURANTS_RESOURCE_GROUP_NAME $RESTAURANTS_RESOURCE_GROUP_LOCATION
  check_and_create_storage_account
  get_storage_account_key
  check_and_create_storage_container

  # Initialize Terraform again
  initialize_terraform

  # Remove resource groups from Terraform state if they exist
  remove_resource_group_from_state "devops_rg"
  remove_resource_group_from_state "restaurants_rg"

  create_execution_plan

  if [ "$RUN_PLAN_ONLY" = true ]; then
    echo "### Terraform plan has been created. Exiting as --plan flag was provided."
    exit 0
  fi

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
  az aks get-credentials --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME

  # Verify authentication
  echo "### Verifying authentication"
  kubectl get nodes

  # Assign the Owner Role to the Service Principal
  echo "### Assigning the Owner Role to the Service Principal"
  az role assignment create --assignee $CLIENT_ID --role Owner --scope /subscriptions/$SUBSCRIPTION_ID

  # # Verify Role Assignment
  # echo "### Verify Role Assignment"
  # az role assignment list --assignee $CLIENT_ID --scope /subscriptions/$SUBSCRIPTION_ID

  # # Assign Reader role on the Resource Group
  # echo "### Assign Reader role on the Resource Group"
  # az role assignment create --assignee $CLIENT_ID --role Reader --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESTAURANTS_RESOURCE_GROUP_NAME

  # # Assign Contributor role on the AKS Cluster
  # echo "Assign Contributor role on the AKS Cluster"
  # az role assignment create --assignee $CLIENT_ID --role Contributor --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESTAURANTS_RESOURCE_GROUP_NAME/providers/Microsoft.ContainerService/managedClusters/$AKS_CLUSTER_NAME

  # # Assign Azure Kubernetes Service Cluster User Role
  # echo "Assign Azure Kubernetes Service Cluster User Role"
  # az role assignment create --assignee $CLIENT_ID --role "Azure Kubernetes Service Cluster User Role" --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESTAURANTS_RESOURCE_GROUP_NAME/providers/Microsoft.ContainerService/managedClusters/$AKS_CLUSTER_NAME

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

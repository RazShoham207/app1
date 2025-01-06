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
CLIENT_SECRET="9wB8Q~S2mlaN7.AI2ZH0tIcenSQ5uyLN-TNBzasz"
TENANT_ID="339e2a15-710e-4162-ab7e-8d1199b663b9"
AKS_CLUSTER_NAME="restaurants-aks"
ACR_NAME="restaurantsacr"
ACR_SKU="Premium"
NODE_COUNT=1
RELEASE_NAME="restaurants-app"
CHART_PATH="./restaurants-charts"
FILE_SHARE_NAME="aksshare"
VNET_NAME="restaurants-vnet"
SUBNET_NAME="restaurants-subnet"
ACR_PRIVATE_ENDPOINT_NAME="acr-private-endpoint"
STORAGE_PRIVATE_ENDPOINT_NAME="storage-private-endpoint"

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

create_k8s_secret() {
  echo "### Creating Kubernetes secret for Azure Storage Account"
  kubectl create secret generic azure-secret --from-literal=azurestorageaccountname=$STORAGE_ACCOUNT_NAME --from-literal=azurestorageaccountkey=$STORAGE_ACCOUNT_KEY --namespace default
}

create_file_share() {
  echo "### Creating Azure File share"
  az storage share create --name $FILE_SHARE_NAME --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY
}

create_vnet_and_subnet() {
  echo "### Creating Virtual Network and Subnet"
  az network vnet create --name $VNET_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --location $RESTAURANTS_RESOURCE_GROUP_LOCATION --address-prefix 10.0.0.0/16
  az network vnet subnet create --name $SUBNET_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --vnet-name $VNET_NAME --address-prefix 10.0.1.0/24
}

create_private_endpoint() {
  local endpoint_name=$1
  local resource_id=$2
  local group_id=$3

  echo "### Creating Private Endpoint: $endpoint_name"
  az network private-endpoint create --name $endpoint_name --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --vnet-name $VNET_NAME --subnet $SUBNET_NAME --private-connection-resource-id $resource_id --group-id $group_id --connection-name "${endpoint_name}-connection"
}

create_private_dns_zone() {
  local zone_name=$1

  echo "### Creating Private DNS Zone: $zone_name"
  az network private-dns zone create --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --name $zone_name
}

link_private_dns_zone() {
  local zone_name=$1
  local vnet_id=$2

  echo "### Linking Private DNS Zone: $zone_name to VNet: $vnet_id"
  az network private-dns link vnet create --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --zone-name $zone_name --name "${zone_name}-link" --virtual-network $vnet_id --registration-enabled false
}

create_private_dns_zone_record() {
  local zone_name=$1
  local record_name=$2
  local ip_address=$3

  echo "### Creating Private DNS Zone Record: $record_name in Zone: $zone_name"
  az network private-dns record-set a create --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --zone-name $zone_name --name $record_name
  az network private-dns record-set a add-record --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --zone-name $zone_name --record-set-name $record_name --ipv4-address $ip_address
}

# Set environment variables for Terraform
export ARM_CLIENT_ID=$CLIENT_ID
export ARM_CLIENT_SECRET=$CLIENT_SECRET
export ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID
export ARM_TENANT_ID=$TENANT_ID

initialize_terraform() {
  echo "### Initializing Terraform - $(date '+%d-%m-%Y %H:%M:%S')"
  terraform init -upgrade -reconfigure -backend-config="access_key=$ARM_ACCESS_KEY"
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

get_storage_account_key() {
  echo "### Getting storage account key"
  STORAGE_ACCOUNT_KEY=$(az storage account keys list --resource-group $DEVOPS_RESOURCE_GROUP_NAME --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' --output tsv)
  export ARM_ACCESS_KEY=$STORAGE_ACCOUNT_KEY
}

check_and_create_storage_container() {
  echo "### Checking if the storage container $CONTAINER_NAME exists"
  if az storage container list --account-name $STORAGE_ACCOUNT_NAME --account-key $ARM_ACCESS_KEY --query "[?name=='$CONTAINER_NAME']" | grep -q $CONTAINER_NAME; then
    echo "### Storage container $CONTAINER_NAME already exists. Skipping creation."
  else
    echo "### Creating storage container $CONTAINER_NAME"
    az storage container create --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT_NAME --account-key $ARM_ACCESS_KEY
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
  if [ "$rg_name" == "devops_rg" ]; then
    terraform state list "data.azurerm_resource_group.$rg_name"
    echo "### Removing $rg_name from the state"
    terraform state rm "data.azurerm_resource_group.$rg_name"
  elif [ "$rg_name" == "Restaurants-rg" ]; then
    terraform state list "azurerm_resource_group.$rg_name"
    echo "### Removing $rg_name from the state"
    terraform state rm "azurerm_resource_group.$rg_name"
  else
    echo "### $rg_name does not exist in the state. Skipping removal."
  fi
}

check_and_create_acr() {
  echo "### Checking if the ACR $ACR_NAME exists"
  while true; do
    if az acr check-name --name $ACR_NAME --query "nameAvailable" --output tsv | grep -q "true"; then
      echo "### Creating ACR $ACR_NAME"
      az acr create --name $ACR_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --sku $ACR_SKU --admin-enabled true
      break
    else
      echo "### ACR name $ACR_NAME is already in use. Generating a new name."
      ACR_NAME="restaurantsacr$RANDOM"
    fi
  done
}

enable_acr_managed_identity() {
  echo "### Enabling system-assigned managed identity for ACR"
  az acr identity assign --name $ACR_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --identities [system]
}

assign_acr_pull_role() {
  echo "### Assigning AcrPull role to AKS managed identity"
  AKS_MANAGED_IDENTITY_CLIENT_ID=$(az aks show --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME --query "identityProfile.kubeletidentity.clientId" --output tsv)
  az role assignment create --assignee-object-id $AKS_MANAGED_IDENTITY_CLIENT_ID --role AcrPull --scope $(az acr show --name $ACR_NAME --query "id" --output tsv) --assignee-principal-type ServicePrincipal
}
disable_public_network_access() {
  echo "### Disabling public network access for the storage account"
  az storage account update --name $STORAGE_ACCOUNT_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --default-action Deny
}
create_pv_and_pvc() {
  echo "### Creating Storage Class, Persistent Volume, and Persistent Volume Claim"
  kubectl apply -f storage-class.yaml
  kubectl apply -f persistent-volume.yaml
  kubectl apply -f persistent-volume-claim.yaml
}

main() {
  authenticate_azure
  set_subscription
  check_and_create_resource_group $DEVOPS_RESOURCE_GROUP_NAME $RESTAURANTS_RESOURCE_GROUP_LOCATION
  check_and_create_resource_group $RESTAURANTS_RESOURCE_GROUP_NAME $RESTAURANTS_RESOURCE_GROUP_LOCATION
  check_and_create_storage_account
  get_storage_account_key
  create_k8s_secret
  create_file_share
  check_and_create_storage_container
  generate_ssh_key
    create_vnet_and_subnet

  # Create Private Endpoints
  ACR_RESOURCE_ID=$(az acr show --name $ACR_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --query "id" --output tsv)
  STORAGE_RESOURCE_ID=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --query "id" --output tsv)
  create_private_endpoint $ACR_PRIVATE_ENDPOINT_NAME $ACR_RESOURCE_ID "registry"
  create_private_endpoint $STORAGE_PRIVATE_ENDPOINT_NAME $STORAGE_RESOURCE_ID "file"

  # Create Private DNS Zones and Link to VNet
  create_private_dns_zone "privatelink.azurecr.io"
  create_private_dns_zone "privatelink.file.core.windows.net"
  VNET_ID=$(az network vnet show --name $VNET_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --query "id" --output tsv)
  link_private_dns_zone "privatelink.azurecr.io" $VNET_ID
  link_private_dns_zone "privatelink.file.core.windows.net" $VNET_ID

  # Initialize Terraform
  echo "### Initializing Terraform"
  terraform init -backend-config="storage_account_name=$STORAGE_ACCOUNT_NAME" \
                 -backend-config="container_name=$CONTAINER_NAME" \
                 -backend-config="key=terraform.tfstate" \
                 -backend-config="access_key=$STORAGE_ACCOUNT_KEY" -reconfigure

  # Remove resource groups from Terraform state if they exist
  remove_resource_group_from_state "$DEVOPS_RESOURCE_GROUP_NAME"
  remove_resource_group_from_state "$RESTAURANTS_RESOURCE_GROUP_NAME"

  if [ "$RUN_PLAN_ONLY" = true ]; then
    echo "### Running Terraform plan"
    terraform plan -var "subscription_id=$SUBSCRIPTION_ID" \
                   -var "client_id=$CLIENT_ID" \
                   -var "client_secret=$CLIENT_SECRET" \
                   -var "tenant_id=$TENANT_ID" \
                   -var "devops_rg_name=$DEVOPS_RESOURCE_GROUP_NAME" \
                   -var "storage_account_name=$STORAGE_ACCOUNT_NAME" \
                   -var "container_name=$CONTAINER_NAME" \
                   -var "restaurants_rg_name=$RESTAURANTS_RESOURCE_GROUP_NAME" \
                   -var "restaurants_rg_location=$RESTAURANTS_RESOURCE_GROUP_LOCATION" \
                   -var "acr_name=$ACR_NAME" \
                   -var "acr_sku=$ACR_SKU" \
                   -var "node_count=$NODE_COUNT"
  else
    echo "### Running Terraform apply"
    terraform apply -auto-approve -var "subscription_id=$SUBSCRIPTION_ID" \
                                  -var "client_id=$CLIENT_ID" \
                                  -var "client_secret=$CLIENT_SECRET" \
                                  -var "tenant_id=$TENANT_ID" \
                                  -var "devops_rg_name=$DEVOPS_RESOURCE_GROUP_NAME" \
                                  -var "storage_account_name=$STORAGE_ACCOUNT_NAME" \
                                  -var "container_name=$CONTAINER_NAME" \
                                  -var "restaurants_rg_name=$RESTAURANTS_RESOURCE_GROUP_NAME" \
                                  -var "restaurants_rg_location=$RESTAURANTS_RESOURCE_GROUP_LOCATION" \
                                  -var "acr_name=$ACR_NAME" \
                                  -var "acr_sku=$ACR_SKU" \
                                  -var "node_count=$NODE_COUNT"
  fi

  check_and_create_acr
  enable_acr_managed_identity
  assign_acr_pull_role

  # Disable public network access for the storage account
  disable_public_network_access
  create_pv_and_pvc

  # Check if the azurek8s file exists before attempting to modify it
  if [ -f ./azurek8s ]; then
    echo "### Remove << EOT and EOT from the azurek8s file"
    sed -i '/<< EOT/d' ./azurek8s
    sed -i '/EOT/d' ./azurek8s

    # Set an environment variable so kubectl can pick up the correct config
    echo "### Setting an environment variable so kubectl can pick up the correct config"
    export KUBECONFIG=./azurek8s
    chmod 600 ./azurek8s
  else
    echo "### azurek8s file not found. Skipping modification."
  fi

  # Verify the health of the cluster using the kubectl get nodes command
  echo "### Verifying the health of the cluster using the kubectl get nodes command"
  kubectl get nodes

  # Attach the Azure Container Registry to the AKS cluster
  echo "### Attaching the Azure Container Registry to the AKS cluster - $(date '+%d-%m-%Y %H:%M:%S')"
  az aks update -n $AKS_CLUSTER_NAME -g $RESTAURANTS_RESOURCE_GROUP_NAME --attach-acr $ACR_NAME

  # Check the health of the Azure Container Registry
  echo "### Checking the health of the Azure Container Registry - $(date '+%d-%m-%Y %H:%M:%S')"
  az acr check-health --name $ACR_NAME --ignore-errors --yes

  # Authenticate with the AKS cluster
  echo "### Authenticating with the AKS cluster"
  az aks get-credentials --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME

  # Verify authentication
  echo "### Verifying authentication"
  kubectl get nodes

  # Assign the Owner Role to the Service Principal
  echo "### Assigning the Owner Role to the Service Principal"
  az role assignment create --assignee $CLIENT_ID --role Owner --scope /subscriptions/$SUBSCRIPTION_ID

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
    elapsed_time=$((end_time - start_time))
    echo "### Terraform script completed in $elapsed_time seconds" 
    hours=$((elapsed_time / 3600))
    minutes=$(( (elapsed_time % 3600) / 60 ))
    seconds=$((elapsed_time % 60))
    echo "### Total Duration: $hours hours, $minutes minutes, and $seconds seconds"
  fi
}

main "$@"

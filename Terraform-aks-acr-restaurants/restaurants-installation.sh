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
VNET_ADDRESS_PREFIX="10.0.0.0/16"
SUBNET_ADDRESS_PREFIX="10.0.0.0/24"
MI_NAME="my-managed-identity"

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

is_cloud_shell() {
  if [ -n "$ACC_CLOUD" ]; then
    return 0
  else
    return 1
  fi
}

authenticate_azure() {
  echo "### Authenticating with Azure"
  if is_cloud_shell; then
    echo "### Running in Azure Cloud Shell. Skipping 'az login'."
  else
    echo "### Authenticating with Azure using Service Principal"
    az login --service-principal -u $CLIENT_ID -p $CLIENT_SECRET --tenant $TENANT_ID
  fi
}

set_subscription() {
  echo "### Setting Azure subscription"
  az account set --subscription $SUBSCRIPTION_ID
}

create_vnet_and_subnet() {
  echo "### Creating Virtual Network and Subnet"
  echo "### Checking if the virtual network $VNET_NAME exists"
  if az network vnet show --name $VNET_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME &> /dev/null; then
    echo "### Virtual network $VNET_NAME already exists. Using the existing virtual network."
  else
    echo "### Creating virtual network $VNET_NAME"
    az network vnet create --name $VNET_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --address-prefix $VNET_ADDRESS_PREFIX
  fi

  echo "### Checking if the subnet $SUBNET_NAME exists in the virtual network $VNET_NAME"
  if az network vnet subnet show --name $SUBNET_NAME --vnet-name $VNET_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME &> /dev/null; then
    echo "### Subnet $SUBNET_NAME already exists. Using the existing subnet."
  else
    echo "### Creating subnet $SUBNET_NAME"
    az network vnet subnet create --name $SUBNET_NAME --vnet-name $VNET_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --address-prefixes $SUBNET_ADDRESS_PREFIX
  fi
}

create_private_endpoint() {
  local endpoint_name=$1
  local resource_id=$2
  local group_id=$3
  local connection_name=$4
  echo "### Creating private endpoint $endpoint_name"
  az network private-endpoint create --name $endpoint_name --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --vnet-name $VNET_NAME --subnet $SUBNET_NAME --private-connection-resource-id $resource_id --group-id $group_id --connection-name $connection_name
}

create_private_dns_zone() {
  local zone_name=$1
  echo "### Checking if the Private DNS Zone $zone_name exists"
  if az network private-dns zone show --name $zone_name --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME &> /dev/null; then
    echo "### Private DNS Zone $zone_name already exists. Using the existing zone."
  else
    echo "### Creating Private DNS Zone: $zone_name"
    az network private-dns zone create --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --name $zone_name
  fi
}

link_private_dns_zone() {
  local zone_name=$1
  local vnet_id=$2
  local link_name="${zone_name}-link"
  echo "### Linking private DNS zone $zone_name to VNet"
  if az network private-dns link vnet show --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --zone-name $zone_name --name $link_name &> /dev/null; then
    echo "### Private DNS zone link $link_name already exists. Skipping creation."
  else
    az network private-dns link vnet create --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --zone-name $zone_name --name $link_name --virtual-network $vnet_id --registration-enabled false
  fi
}

create_private_dns_zone_record() {
  local zone_name=$1
  local record_name=$2
  local ip_address=$3
  echo "### Checking if the Private DNS Zone Record: $record_name exists in Zone: $zone_name"
  if az network private-dns record-set a show --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --zone-name $zone_name --name $record_name &> /dev/null; then
    echo "### Private DNS Zone Record: $record_name already exists in Zone: $zone_name. Skipping creation."
  else
    echo "### Creating Private DNS Zone Record: $record_name in Zone: $zone_name"
    az network private-dns record-set a create --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --zone-name $zone_name --name $record_name
    az network private-dns record-set a add-record --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --zone-name $zone_name --record-set-name $record_name --ipv4-address $ip_address
  fi
}

# Set environment variables for Terraform
export ARM_CLIENT_ID=$CLIENT_ID
export ARM_CLIENT_SECRET=$CLIENT_SECRET
export ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID
export ARM_TENANT_ID=$TENANT_ID

initialize_terraform() {
  get_storage_account_key
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
  echo "### Checking if resource group $rg_name exists"
  if az group show --name $rg_name &> /dev/null; then
    echo "### Resource group $rg_name already exists. Skipping creation."
  else
    echo "### Creating resource group $rg_name"
    az group create --name $rg_name --location $rg_location
  fi
}

check_and_create_storage_account() {
  local retries=5
  local count=0
  local delay=30

  while [ $count -lt $retries ]; do
    echo "### Attempting to create storage account $STORAGE_ACCOUNT_NAME (Attempt $((count + 1))/$retries)"
    if az storage account create --name $STORAGE_ACCOUNT_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --location $RESTAURANTS_RESOURCE_GROUP_LOCATION --sku Standard_LRS; then
      echo "### Storage account $STORAGE_ACCOUNT_NAME created successfully"
      return 0
    else
      echo "### Failed to create storage account $STORAGE_ACCOUNT_NAME. Retrying in $delay seconds..."
      sleep $delay
      count=$((count + 1))
    fi
  done

  echo "### Failed to create storage account $STORAGE_ACCOUNT_NAME after $retries attempts"
  return 1
}

# Function to wait for storage account provisioning state to be 'Succeeded'
wait_for_storage_account_provisioning() {
  local retries=10
  local count=0
  local delay=30

  while [ $count -lt $retries ]; do
    provisioning_state=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --query "provisioningState" --output tsv)
    if [ "$provisioning_state" == "Succeeded" ]; then
      echo "### Storage account $STORAGE_ACCOUNT_NAME is provisioned successfully"
      return 0
    else
      echo "### Storage account $STORAGE_ACCOUNT_NAME is in provisioning state: $provisioning_state. Waiting for $delay seconds..."
      sleep $delay
      count=$((count + 1))
    fi
  done

  echo "### Storage account $STORAGE_ACCOUNT_NAME failed to reach 'Succeeded' state after $retries attempts"
  return 1
}

get_storage_account_key() {
  echo "### Getting storage account key"
  STORAGE_ACCOUNT_KEY=$(az storage account keys list --resource-group $DEVOPS_RESOURCE_GROUP_NAME --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' --output tsv)
}

# Function to create Azure File share
create_file_share() {
  get_storage_account_key
  echo "### Creating Azure File share $FILE_SHARE_NAME"
  az storage share create --name $FILE_SHARE_NAME --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY
}

check_and_create_aks() {
  echo "### Checking if AKS cluster $AKS_CLUSTER_NAME exists"
  if az aks show --name $AKS_CLUSTER_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME &> /dev/null; then
    echo "### AKS cluster $AKS_CLUSTER_NAME already exists"
  else
    echo "### Creating AKS cluster $AKS_CLUSTER_NAME"
    az aks create --name $AKS_CLUSTER_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --node-count $NODE_COUNT --enable-managed-identity --generate-ssh-keys
  fi
}

check_and_create_storage_container() {
  get_storage_account_key
  echo "### Checking if storage container $CONTAINER_NAME exists"
  if az storage container show --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY &> /dev/null; then
    echo "### Storage container $CONTAINER_NAME already exists. Skipping creation."
  else
    echo "### Creating storage container $CONTAINER_NAME"
    az storage container create --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY
  fi
}

generate_ssh_key() {
  echo "### Generating SSH key"
  if [ ! -f ~/.ssh/id_rsa.pub ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
  fi
}

remove_resource_group_from_state() {
  local rg_name=$1
  echo "### Checking if $rg_name exists in Azure"
  if az group show --name $rg_name &> /dev/null; then
    echo "### Resource group $rg_name exists in Azure. Checking if it exists in the state."
    if terraform state list | grep -q "azurerm_resource_group.$rg_name"; then
      echo "### Removing $rg_name from the state"
      terraform state rm "azurerm_resource_group.$rg_name"
    else
      echo "### $rg_name does not exist in the state. Skipping removal."
    fi
  else
    echo "### Resource group $rg_name does not exist in Azure. Skipping state removal."
  fi
}

check_and_create_acr() {
  echo "### Checking if ACR $ACR_NAME exists"
  if az acr show --name $ACR_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME &> /dev/null; then
    echo "### ACR $ACR_NAME already exists. Using the existing ACR."
  else
    echo "### Creating ACR $ACR_NAME"
    az acr create --name $ACR_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --sku $ACR_SKU --admin-enabled true
  fi
}

create_managed_identity() {
  echo "### Creating Managed Identity"
  az identity create --name $MI_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME
  MI_ID=$(az identity show --name $MI_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --query 'id' -o tsv)
  MI_CLIENT_ID=$(az identity show --name $MI_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --query 'clientId' -o tsv)
  export MI_ID=$MI_ID
  export MI_CLIENT_ID=$MI_CLIENT_ID
}

authenticate_with_aks() {
  echo "### Authenticating with the AKS cluster"
  az aks get-credentials --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME --overwrite-existing
  az aks update -n $AKS_CLUSTER_NAME -g $RESTAURANTS_RESOURCE_GROUP_NAME --attach-acr $ACR_NAME
}

install_azure_workload_identity() {
  echo "### Installing Azure Workload Identity on AKS"
  az aks update -n $AKS_CLUSTER_NAME -g $RESTAURANTS_RESOURCE_GROUP_NAME --enable-oidc-issuer --enable-workload-identity
}

create_azure_identity() {
  echo "### Creating AzureIdentity and AzureIdentityBinding"
  cat <<EOF | kubectl apply -f -
apiVersion: workload.identity.azure.com/v1alpha1
kind: AzureIdentity
metadata:
  name: $MI_NAME
spec:
  type: UserAssigned
  resourceID: $MI_ID
  clientID: $MI_CLIENT_ID
EOF

  cat <<EOF | kubectl apply -f -
apiVersion: workload.identity.azure.com/v1alpha1
kind: AzureIdentityBinding
metadata:
  name: my-azure-identity-binding
spec:
  azureIdentity: $MI_NAME
  selector: my-app
EOF

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: default
  annotations:
    azure.workload.identity/client-id: $MI_CLIENT_ID
EOF
}

check_acr_health() {
  echo "### Checking ACR health - $(date '+%d-%m-%Y %H:%M:%S')"
  az acr check-health --name $ACR_NAME --yes
}

create_azurefile_secret() {
  get_storage_account_key
  echo "### Checking if the azurefile-secret exists"
  if kubectl get secret azurefile-secret --namespace=default &> /dev/null; then
    echo "### Secret azurefile-secret already exists. Skipping creation."
  else
    echo "### Creating azurefile-secret"
    kubectl create secret generic azurefile-secret --from-literal=azurestorageaccountname=$STORAGE_ACCOUNT_NAME --from-literal=azurestorageaccountkey=$STORAGE_ACCOUNT_KEY --namespace=default
  fi
}

enable_aks_managed_identity() {
  echo "### Enabling Managed Identity for AKS cluster"
  az aks update --name $AKS_CLUSTER_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --enable-managed-identity
  echo "Getting the MI Object ID"
  AKS_MI_ID=$(az aks show --name $AKS_CLUSTER_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --query "identityProfile.kubeletidentity.objectId" --output tsv)
  export AKS_MI_ID=$AKS_MI_ID
}

assign_acr_pull_role() {
  echo "### Assigning AcrPull role to AKS managed identity"
  AKS_MI_ID=$(az aks show --name $AKS_CLUSTER_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --query "identityProfile.kubeletidentity.objectId" --output tsv)
  if [ -z "$AKS_MI_ID" ]; then
    echo "### Failed to retrieve Managed Identity Object ID for AKS cluster"
    exit 1
  fi
  az role assignment create --assignee-object-id $AKS_MI_ID --role AcrPull --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$DEVOPS_RESOURCE_GROUP_NAME/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME --assignee-principal-type ServicePrincipal
}

assign_owner_role_to_sp() {
  echo "### Assigning the Owner Role to the Service Principal" 
  # Retry mechanism for role assignment
  for i in {1..5}; do
    az role assignment create --assignee $CLIENT_ID --role Owner --scope /subscriptions/$SUBSCRIPTION_ID && break
    echo "### Failed to assign role. Retrying in 5 seconds..."
    sleep 5
  done
}

# Assign the `Storage Account Key Operator Service Role` role to the service principal or managed identity at the scope of the storage account.
assign_sa_key_operator_to_sp() {
    AKS_MI_ID=$(az aks show --name $AKS_CLUSTER_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --query "identityProfile.kubeletidentity.objectId" --output tsv)
  if [ -z "$AKS_MI_ID" ]; then
    echo "### Failed to retrieve Managed Identity Object ID for AKS cluster"
    exit 1
  fi
  az role assignment create --assignee $AKS_MI_ID --role "Storage Account Key Operator Service Role" --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$DEVOPS_RESOURCE_GROUP_NAME/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME
}

main() {
  authenticate_azure
  set_subscription
  check_and_create_resource_group $DEVOPS_RESOURCE_GROUP_NAME $RESTAURANTS_RESOURCE_GROUP_LOCATION
  check_and_create_resource_group $RESTAURANTS_RESOURCE_GROUP_NAME $RESTAURANTS_RESOURCE_GROUP_LOCATION
  check_and_create_storage_account
  wait_for_storage_account_provisioning
  get_storage_account_key
  create_file_share
  check_and_create_storage_container
  generate_ssh_key
  create_vnet_and_subnet
  check_and_create_acr
  check_acr_health

  # Create Private Endpoints
  ACR_RESOURCE_ID=$(az acr show --name $ACR_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --query "id" --output tsv)
  STORAGE_RESOURCE_ID=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --query "id" --output tsv)
  create_private_endpoint $ACR_PRIVATE_ENDPOINT_NAME $ACR_RESOURCE_ID "registry" "acr-connection"
  create_private_endpoint $STORAGE_PRIVATE_ENDPOINT_NAME $STORAGE_RESOURCE_ID "file" "storage-connection"

  # Get the private IP address of the storage account private endpoint
  STORAGE_PRIVATE_EP_IP=$(az network private-endpoint show --name $STORAGE_PRIVATE_ENDPOINT_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --query "customDnsConfigs[0].ipAddresses[0]" --output tsv)

  # Get the private IP address of the ACR private endpoint
  ACR_PRIVATE_EP_IP=$(az network private-endpoint show --name $ACR_PRIVATE_ENDPOINT_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --query "customDnsConfigs[0].ipAddresses[0]" --output tsv)

  # Create Private DNS Zones and Link to VNet
  create_private_dns_zone "privatelink.azurecr.io"
  create_private_dns_zone "privatelink.file.core.windows.net"
  VNET_ID=$(az network vnet show --name $VNET_NAME --resource-group $RESTAURANTS_RESOURCE_GROUP_NAME --query "id" --output tsv)
  link_private_dns_zone "privatelink.azurecr.io" $VNET_ID
  link_private_dns_zone "privatelink.file.core.windows.net" $VNET_ID

  # Create A record for the storage account in the private DNS zone
  create_private_dns_zone_record "privatelink.file.core.windows.net" $STORAGE_ACCOUNT_NAME $STORAGE_PRIVATE_EP_IP

  # Create A record for the ACR in the private DNS zone
  create_private_dns_zone_record "privatelink.azurecr.io" $ACR_NAME $ACR_PRIVATE_EP_IP

  # Set the FQDN of the storage account
  STORAGE_ACCOUNT_FQDN="${STORAGE_ACCOUNT_NAME}.privatelink.file.core.windows.net"
  export STORAGE_ACCOUNT_FQDN=$STORAGE_ACCOUNT_FQDN

  # Set the FQDN of the ACR
  ACR_FQDN="${ACR_NAME}.privatelink.azurecr.io"
  export ACR_FQDN=$ACR_FQDN

  # Initialize Terraform
  echo "### Initializing Terraform"
  get_storage_account_key
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

  # Authenticate with the AKS cluster
  authenticate_with_aks
  create_azurefile_secret

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

  # Enable Managed Identity for AKS cluster
  enable_aks_managed_identity

  # Assign AcrPull role to AKS managed identity
  assign_acr_pull_role

  # Assign the Owner Role to the Service Principal
  assign_owner_role_to_sp

  # Assign the `Storage Account Key Operator Service Role` role to the service principal or managed identity at the scope of the storage account.
  assign_sa_key_operator_to_sp

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
    echo ""
    echo "###### This is the first installation and there was no deploy yet. Therefore the restaurants-app service does not exist yet. ######"
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

#!/bin/bash
start_time=$(date +%s)
echo "### Running Terraform - START - $(date +"%A, %B %d, %Y - %H:%M:%S")"

# Variables
SUBSCRIPTION_ID="80fab2d0-ef24-4ff6-a7ed-02a816eee488"
DEVOPS_RESOURCE_GROUP_NAME="DevOps-rg"
STORAGE_ACCOUNT_NAME="restaurantstfstatesa"
CONTAINER_NAME="tfstate"
RESTAURANTS_RESOURCE_GROUP_NAME="Restaurants-rg"

# Authenticate with Azure
echo "### Authenticating with Azure"
az login --identity

# Set the Azure subscription
echo "### Setting the Azure subscription"
az account set --subscription $SUBSCRIPTION_ID

# Check if the DevOps resource group exists
echo "### Checking if the resource group $DEVOPS_RESOURCE_GROUP_NAME exists"
if az group show --name $DEVOPS_RESOURCE_GROUP_NAME &> /dev/null; then
  echo "### Resource group $DEVOPS_RESOURCE_GROUP_NAME already exists. Skipping creation."
else
  echo "### Creating resource group $DEVOPS_RESOURCE_GROUP_NAME"
  az group create --name $DEVOPS_RESOURCE_GROUP_NAME --location eastus
fi

# Check if the storage account exists
echo "### Checking if the storage account $STORAGE_ACCOUNT_NAME exists"
if az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME &> /dev/null; then
  echo "### Storage account $STORAGE_ACCOUNT_NAME already exists. Skipping creation."
else
  echo "### Creating storage account $STORAGE_ACCOUNT_NAME"
  az storage account create --name $STORAGE_ACCOUNT_NAME --resource-group $DEVOPS_RESOURCE_GROUP_NAME --location eastus --sku Standard_LRS
fi

# Get storage account key
echo "### Getting storage account key"
STORAGE_ACCOUNT_KEY=$(az storage account keys list --resource-group $DEVOPS_RESOURCE_GROUP_NAME --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' --output tsv)

# Export the storage account key as an environment variable
export ARM_ACCESS_KEY=$STORAGE_ACCOUNT_KEY

# Check if the storage container exists
echo "### Checking if the storage container $CONTAINER_NAME exists"
if az storage container list --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY --query "[?name=='$CONTAINER_NAME']" | grep -q $CONTAINER_NAME; then
  echo "### Storage container $CONTAINER_NAME already exists. Skipping creation."
else
  echo "### Creating storage container $CONTAINER_NAME"
  az storage container create --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY
fi

# Check if the restaurants resource group exists
echo "### Checking if the resource group $RESTAURANTS_RESOURCE_GROUP_NAME exists"
if az group show --name $RESTAURANTS_RESOURCE_GROUP_NAME &> /dev/null; then
  echo "### Resource group $RESTAURANTS_RESOURCE_GROUP_NAME already exists. Skipping creation."
else
  echo "### Creating resource group $RESTAURANTS_RESOURCE_GROUP_NAME"
  az group create --name $RESTAURANTS_RESOURCE_GROUP_NAME --location eastus
fi

# Initialize Terraform
echo "### Initializing Terraform - $(date +"%A, %B %d, %Y - %H:%M:%S")"
terraform init -upgrade -reconfigure 

# Generate the SSH Public key if it does not exist
echo "### Generating the SSH Public key"
if [ ! -f ~/.ssh/id_rsa.pub ]; then
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

# List the current state and filter for DevOps-rg
echo "### Listing the current state"
terraform state list

# Remove existing resource groups from the state if they exist
echo "### Checking if DevOps-rg exists in the state"
if terraform state list | grep -q "azurerm_resource_group.devops_rg"; then
  echo "### Removing DevOps-rg from the state"
  terraform state rm azurerm_resource_group.devops_rg
fi

echo "### Checking if Restaurants-rg exists in the state"
if terraform state list | grep -q "azurerm_resource_group.restaurants_rg"; then
  echo "### Removing Restaurants-rg from the state"
  terraform state rm azurerm_resource_group.restaurants_rg
fi

# Import existing resource groups into the state
echo "### Importing existing resource groups into the state"
terraform import azurerm_resource_group.restaurants_rg /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESTAURANTS_RESOURCE_GROUP_NAME
terraform import azurerm_resource_group.devops_rg /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$DEVOPS_RESOURCE_GROUP_NAME

# Create an execution plan and save it to a file
echo "### Creating an execution plan - $(date +"%A, %B %d, %Y - %H:%M:%S")"
terraform plan -out=tfplan

# Apply the execution plan
echo "### Applying the execution plan - $(date +"%A, %B %d, %Y - %H:%M:%S")"
terraform apply -auto-approve tfplan

# Get the Kubernetes configuration from the Terraform state and store it in a file that kubectl can read
echo "### Getting the Kubernetes configuration from the Terraform state"
terraform output -raw kube_config > ./azurek8s

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
echo "### Attaching the Azure Container Registry to the AKS cluster - $(date +"%A, %B %d, %Y - %H:%M:%S")"
az aks update -n restaurants-aks -g $RESTAURANTS_RESOURCE_GROUP_NAME --attach-acr restaurantsacr

# Check the health of the Azure Container Registry
echo "### Checking the health of the Azure Container Registry - $(date +"%A, %B %d, %Y - %H:%M:%S")"
az acr check-health --name restaurantsacr --ignore-errors --yes

# Create a Kubernetes secret for the ACR credentials
echo "### Creating a Kubernetes secret for the ACR credentials - $(date +"%A, %B %d, %Y - %H:%M:%S")"
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

# Apply the ACR_SECRET into the AKS
echo "### Applying the ACR SECRET into the AKS"
echo "$ACR_SECRET" | kubectl apply -f -

# Check if NGINX Ingress Controller is already installed
if ! helm list -q | grep -q nginx-ingress; then
  echo "### Installing NGINX Ingress Controller - $(date +"%A, %B %d, %Y - %H:%M:%S")"
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update
  helm install nginx-ingress ingress-nginx/ingress-nginx
else
  echo "### NGINX Ingress Controller is already installed - $(date +"%A, %B %d, %Y - %H:%M:%S")"
fi

# Setup the Certificates for the Ingress Controller
# Do not use the ClusterIssuer, Certificate and Ingress in Helm Chart
# 1. Install Cert-Manager
# Cert-Manager is a Kubernetes add-on that automates the management and issuance of TLS certificates
echo "### Installing Cert-Manager"
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.3/cert-manager.yaml

# 2. Create the ClusterIssuer for Let's Encrypt Production Certificate Authority (CA) - letsencrypt-prod
# The ClusterIssuer resource represents a certificate authority (CA) that should be used to sign certificates
echo "### Creating the ClusterIssuer for Let's Encrypt Production Certificate Authority (CA) - letsencrypt-prod"
cat <<EOF > restaurants-app-clusterissuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: restaurants-app
    meta.helm.sh/release-namespace: default
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: raz.shoham207@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

CLUSTERISSUER_CONFIG=$(cat restaurants-app-clusterissuer.yaml)

# 3. Create the Certificate resource
# Define a Certificate resource to request a TLS certificate for your application from Let's Encrypt using the ClusterIssuer
echo "### Creating the Certificate resource"
cat <<EOF > restaurants-app-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: restaurants-app-tls
  namespace: default
spec:
  secretName: restaurants-app-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: your-ip-address.nip.io
  dnsNames:
    - your-ip-address.nip.io
EOF

CERTIFICATE_CONFIG=$(cat restaurants-app-certificate.yaml)

# 4. Update the Ingress resource
# Update the Ingress resource to use the TLS certificate and key that Cert-Manager will generate
echo "### Updating the Ingress resource"
cat <<EOF > restaurants-app-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: restaurants-app-ingress
  namespace: default
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    meta.helm.sh/release-name: restaurants-app
    meta.helm.sh/release-namespace: default
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - your-ip-address.nip.io
    secretName: restaurants-app-tls
  rules:
  - host: your-ip-address.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: restaurants-app-service
            port:
              number: 80
EOF

INGRESS_CONFIG=$(cat restaurants-app-ingress.yaml)

# 5. Replace your-ip-address with the value of $EXTERNAL_IP and restaurants-app-tls with the value of $TLS_SECRET_NAME
# Get the External IP from a LoadBalancer service
echo "### Getting the External IP from a LoadBalancer service"
EXTERNAL_IP=$(kubectl get svc nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Get the restaurants-app-tls full name
echo "### Getting the restaurants-app-tls full name"
TLS_SECRET_NAME=$(kubectl get secrets | grep "restaurants-app-tls" | awk '{print $1}')

echo "### Replace your-ip-address with the value of $EXTERNAL_IP and restaurants-app-tls with the value of $TLS_SECRET_NAME"
UPDATED_CLUSTERISSUER_CONFIG=$(echo "$CLUSTERISSUER_CONFIG" | sed "s/your-ip-address/$EXTERNAL_IP/g")
UPDATED_CLUSTERISSUER_CONFIG=$(echo "$UPDATED_CLUSTERISSUER_CONFIG" | sed "s/restaurants-app-tls/$TLS_SECRET_NAME/g")
UPDATED_CERTIFICATE_CONFIG=$(echo "$CERTIFICATE_CONFIG" | sed "s/your-ip-address/$EXTERNAL_IP/g")
UPDATED_CERTIFICATE_CONFIG=$(echo "$UPDATED_CERTIFICATE_CONFIG" | sed "s/restaurants-app-tls/$TLS_SECRET_NAME/g")
UPDATED_INGRESS_CONFIG=$(echo "$INGRESS_CONFIG" | sed "s/your-ip-address/$EXTERNAL_IP/g")
UPDATED_INGRESS_CONFIG=$(echo "$UPDATED_INGRESS_CONFIG" | sed "s/restaurants-app-tls/$TLS_SECRET_NAME/g")

# Check if the variables are not empty
if [ -z "$UPDATED_CLUSTERISSUER_CONFIG" ]; then
  echo "Error: UPDATED_CLUSTERISSUER_CONFIG is empty"
  exit 1
else
  echo "### UPDATED_CLUSTERISSUER_CONFIG: "
  echo "$UPDATED_CLUSTERISSUER_CONFIG"
fi

if [ -z "$UPDATED_CERTIFICATE_CONFIG" ]; then
  echo "Error: UPDATED_CERTIFICATE_CONFIG is empty"
  exit 1
else
  echo "### UPDATED_CERTIFICATE_CONFIG: "
  echo "$UPDATED_CERTIFICATE_CONFIG"
fi

if [ -z "$UPDATED_INGRESS_CONFIG" ]; then
  echo "Error: UPDATED_INGRESS_CONFIG is empty"
  exit 1
else
  echo "### UPDATED_INGRESS_CONFIG: "
  echo "$UPDATED_INGRESS_CONFIG"
fi

# Apply the updated INGRESS_CONFIG and CERTIFICATE_CONFIG into the AKS
echo "### Applying the updated INGRESS_CONFIG and CERTIFICATE_CONFIG into the AKS"
echo "$UPDATED_CLUSTERISSUER_CONFIG" | kubectl apply -f -
echo "$UPDATED_CERTIFICATE_CONFIG" | kubectl apply -f -
echo "$UPDATED_INGRESS_CONFIG" | kubectl apply -f -

# Authenticate with the AKS cluster
echo "### Authenticating with the AKS cluster"
az aks get-credentials --resource-group Restaurants-rg --name restaurants-aks

# Verify authentication
echo "### Verifying authentication"
kubectl get nodes

# Patch the Ingress resource
echo "### Patching the Ingress resource"
kubectl patch ingress restaurants-app-ingress -n default --type='json' -p='[ {"op": "add", "path": "/metadata/labels/app.kubernetes.io~1managed-by", "value": "Helm"}, {"op": "add", "path": "/metadata/annotations/meta.helm.sh~1release-name", "value": "restaurants-app"}, {"op": "add", "path": "/metadata/annotations/meta.helm.sh~1release-namespace", "value": "default"} ]'

# Create the TLS certificate and key with the external IP
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/$EXTERNAL_IP"

echo "#####################################################################################################"
echo "## The URL for the application is: https://$EXTERNAL_IP/recommend?style=American&vegetarian=false ##"
echo "####################### Replcae style and vegetarian with the desired values ########################"
echo "#####################################################################################################"
echo ""
echo ""
echo "### Running Terraform - END - $(date +"%A, %B %d, %Y - %H:%M:%S")"
end_time=$(date +%s)
# Calculate the duration
duration=$((end_time - start_time))
# Convert the duration to hours, minutes, and seconds
hours=$((duration / 3600))
minutes=$(( (duration % 3600) / 60 ))
seconds=$((duration % 60))
echo "### Total Duration: $hours hours, $minutes minutes, and $seconds seconds"
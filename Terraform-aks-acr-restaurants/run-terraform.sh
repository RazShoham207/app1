#!/bin/bash

echo "### Running Terraform - start"

# Initialize Terraform - Run terraform init to initialize the Terraform deployment. This command downloads the Azure provider required to manage your Azure resources.
# The -upgrade parameter upgrades the necessary provider plugins to the newest version that complies with the configuration's version constraints.
echo "### Initializing Terraform"
terraform init -upgrade

# Create an execution plan and save it to a file
echo "### Creating an execution plan"
terraform plan -out main.tfplan

# Apply the execution plan
echo "### Applying the execution plan"
terraform apply main.tfplan

# Get the Azure resource group name
echo "### Get the Azure resource group name"
resource_group_name=$(terraform output -raw resource_group_name)

# Display the name of your new Kubernetes cluster
echo "### Display the name of the new Kubernetes cluster"
az aks list --resource-group $resource_group_name --query "[].{\"K8s cluster name\":name}" --output table

# Get the Kubernetes configuration from the Terraform state and store it in a azurek8s file that kubectl can read
echo "### Get the Kubernetes configuration from the Terraform state and store it in a file that kubectl can read"
echo "$(terraform output kube_config)" > ./azurek8s

# Remove << EOT and EOT from the azurek8s file
echo "### Remove << EOT and EOT from the azurek8s file"
sed -i '/<< EOT/d' ./azurek8s
sed -i '/EOT/d' ./azurek8s

# Set an environment variable so kubectl can pick up the correct config
echo "### Set an environment variable so kubectl can pick up the correct config"
export KUBECONFIG=./azurek8s

# Verify the health of the cluster using the kubectl get nodes command
echo "### Verify the health of the cluster using the kubectl get nodes command"
kubectl get nodes

echo "### Running Terraform - end"
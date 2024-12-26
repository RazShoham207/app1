# restaurants-app
## Prerequisite installations
## IaC Installation using Terraform
## Create secrets in GitHub
## Create acr-secret
To create a Kubernetes secret of type `docker-registry` that contains the `.dockerconfigjson` file for authenticating with Azure Container Registry (ACR), you can use the `kubectl create secret docker-registry` command. Here is how you can do it:

1. **Log in to Azure and ACR:**
   - Ensure you have the Azure CLI installed and logged in.
   - Log in to your ACR using the Azure CLI.

2. **Create the Kubernetes secret:**
   - Use the `kubectl create secret docker-registry` command to create the secret.

Here is an example command:

```sh
kubectl create secret docker-registry acr-secret --docker-server=restaurantsacr.azurecr.io --docker-username=restaurantsacr --docker-password=<acr access keys password> --docker-email=raz.shoham207@gmail.com
```

This command will create a Kubernetes secret named `acr-secret` with the necessary credentials to authenticate with your ACR.

3. **Verify the secret:**
   - You can verify that the secret has been created correctly by running:

```sh
kubectl get secret acr-secret --output=jsonpath='{.data.\.dockerconfigjson}' | base64 --decode
```

This will output the `.dockerconfigjson` content, which should look like the example you provided.

4. **Use the secret in your Kubernetes deployment:**
   - Reference the secret in your Kubernetes deployment YAML file to pull images from your ACR.

Here is an example of how to reference the secret in a deployment YAML file:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: tendermulletacr.azurecr.io/my-app:latest
        ports:
        - containerPort: 80
      imagePullSecrets:
      - name: acr-secret
```

This configuration ensures that Kubernetes uses the `acr-secret` to authenticate with your ACR when pulling the Docker image.

Similar code found with 1 license type
## Run GitHub action for CI/CD

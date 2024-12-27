variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

resource "azapi_resource" "ssh_public_key" {
  type      = "Microsoft.Compute/sshPublicKeys@2021-03-01"
  name      = "devops-ssh-key"
  location  = data.azurerm_resource_group.devops_rg.location
  parent_id = data.azurerm_resource_group.devops_rg.id

  body = jsonencode({
    properties = {
      publicKey = file(var.ssh_public_key_path)
    }
  })
}

output "key_data" {
  value = jsondecode(azapi_resource.ssh_public_key.body).properties.publicKey
}
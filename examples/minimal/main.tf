# An AKS cluster run by Qovery, with a staging and a production environment.
# No database and no application.

terraform {
  required_version = ">= 1.6"

  required_providers {
    qovery = {
      source  = "qovery/qovery"
      version = "~> 1.0"
    }
  }
}

# Reads the API token from the QOVERY_API_TOKEN environment variable.
provider "qovery" {}

variable "organization_id" {
  description = "ID of the Qovery organization."
  type        = string
}

variable "azure_credentials_id" {
  description = "ID of the Qovery Azure credentials, created in the Qovery Console."
  type        = string
}

module "qovery" {
  source = "../../"

  organization_id      = var.organization_id
  name                 = "starter"
  azure_credentials_id = var.azure_credentials_id
  azure_region         = "westeurope"

  database = {
    enabled = false
  }
}

output "cluster_id" {
  value = module.qovery.cluster_id
}

output "environment_ids" {
  value = module.qovery.environment_ids
}

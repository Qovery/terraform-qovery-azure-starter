variable "organization_id" {
  description = "ID of the Qovery organization that owns the cluster and the project."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.organization_id))
    error_message = "organization_id must be a UUID, for example 01234567-89ab-cdef-0123-456789abcdef."
  }
}

variable "name" {
  description = "Base name of the resources. The cluster and the project are named after it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3 to 32 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "azure_credentials_id" {
  description = "ID of the Qovery Azure credentials. Terraform cannot create them: create them in the Qovery Console, as described in https://www.qovery.com/docs/getting-started/installation/azure, then pass their ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.azure_credentials_id))
    error_message = "azure_credentials_id must be the UUID of Qovery Azure credentials, for example 01234567-89ab-cdef-0123-456789abcdef."
  }
}

variable "azure_region" {
  description = "Azure region of the AKS cluster."
  type        = string
  default     = "westeurope"

  validation {
    condition     = can(regex("^[a-z]+[a-z0-9]*$", var.azure_region))
    error_message = "azure_region must be an Azure region name, for example westeurope or eastus2, in lowercase and without spaces."
  }
}

variable "cluster" {
  description = "Node pool of the AKS cluster. The VM size must be available in the chosen region and within your subscription's vCPU quota."
  type = object({
    instance_type     = optional(string, "Standard_B2s_v2")
    disk_size_in_gib  = optional(number, 40)
    min_running_nodes = optional(number, 3)
    max_running_nodes = optional(number, 10)
  })
  default = {}

  validation {
    condition     = can(regex("^Standard_[A-Za-z0-9_]+$", var.cluster.instance_type))
    error_message = "cluster.instance_type must be an Azure VM size, for example Standard_B2s_v2 or Standard_D4s_v5."
  }

  validation {
    condition     = var.cluster.disk_size_in_gib >= 20
    error_message = "cluster.disk_size_in_gib must be at least 20."
  }

  validation {
    condition     = var.cluster.min_running_nodes >= 1 && var.cluster.min_running_nodes <= var.cluster.max_running_nodes
    error_message = "cluster.min_running_nodes must be at least 1 and must not exceed cluster.max_running_nodes."
  }
}

variable "environments" {
  description = "Environments to create in the project, as a map of environment name to mode (DEVELOPMENT, STAGING, PRODUCTION or PREVIEW)."
  type        = map(string)
  default = {
    staging    = "STAGING"
    production = "PRODUCTION"
  }

  validation {
    condition     = length(var.environments) > 0
    error_message = "environments must declare at least one environment."
  }

  validation {
    condition     = alltrue([for mode in values(var.environments) : contains(["DEVELOPMENT", "STAGING", "PRODUCTION", "PREVIEW"], mode)])
    error_message = "Each environment mode must be DEVELOPMENT, STAGING, PRODUCTION or PREVIEW."
  }
}

variable "database" {
  description = "PostgreSQL database created in each environment. Set enabled to false to skip it, or list the environments that get one in environments (null means all of them). The database runs as a container on the cluster."
  type = object({
    enabled       = optional(bool, true)
    environments  = optional(set(string))
    name          = optional(string, "postgres")
    version       = optional(string, "16")
    accessibility = optional(string, "PRIVATE")
    cpu           = optional(number, 250)
    memory        = optional(number, 512)
    storage       = optional(number, 10)
  })
  default = {}

  validation {
    condition     = contains(["PRIVATE", "PUBLIC"], var.database.accessibility)
    error_message = "database.accessibility must be PRIVATE or PUBLIC."
  }

  validation {
    condition     = var.database.cpu >= 250 && var.database.memory >= 100 && var.database.storage >= 10
    error_message = "database.cpu must be at least 250, database.memory at least 100 and database.storage at least 10."
  }
}

variable "application" {
  description = "Application built from a git repository and deployed in every environment. Leave it null to create no application. The branch defaults to main and can be set per environment in branches. When the environment has a database, the application reads its connection string from the variable named database_url_variable."
  type = object({
    name                  = optional(string, "app")
    git_url               = string
    git_token_id          = optional(string)
    branches              = optional(map(string), {})
    default_branch        = optional(string, "main")
    root_path             = optional(string, "/")
    dockerfile_path       = optional(string, "Dockerfile")
    port                  = optional(number, 8080)
    publicly_accessible   = optional(bool, true)
    cpu                   = optional(number, 500)
    memory                = optional(number, 512)
    min_running_instances = optional(number, 1)
    max_running_instances = optional(number, 1)
    auto_deploy           = optional(bool, true)
    database_url_variable = optional(string, "DATABASE_URL")
    environment_variables = optional(map(string), {})
  })
  default = null

  validation {
    condition     = try(length(regex("^https://", var.application.git_url)) > 0, var.application == null)
    error_message = "application.git_url must be an HTTPS URL, for example https://github.com/my-org/my-app.git."
  }

  validation {
    condition     = try(var.application.port >= 1 && var.application.port <= 65535, var.application == null)
    error_message = "application.port must be between 1 and 65535."
  }

  validation {
    condition     = try(var.application.min_running_instances <= var.application.max_running_instances, var.application == null)
    error_message = "application.min_running_instances must not exceed application.max_running_instances."
  }

  validation {
    condition     = try(length(regex("^[A-Za-z_][A-Za-z0-9_]*$", var.application.database_url_variable)) > 0, var.application == null)
    error_message = "application.database_url_variable must be a valid environment variable name, for example DATABASE_URL."
  }
}

variable "deploy" {
  description = "Whether to deploy each environment after Terraform creates or changes it. Set to false to create the resources without deploying them."
  type        = bool
  default     = true
}

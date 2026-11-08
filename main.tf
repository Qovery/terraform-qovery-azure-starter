locals {
  database_environments = var.database.enabled ? (
    var.database.environments == null ? toset(keys(var.environments)) : setintersection(var.database.environments, toset(keys(var.environments)))
  ) : toset([])

  application_environments = var.application == null ? toset([]) : toset(keys(var.environments))
}

# AKS cluster with a node pool that Qovery sizes between the minimum and maximum node counts.
# The Azure credentials come from the Qovery Console: the provider cannot create them.
resource "qovery_cluster" "this" {
  organization_id   = var.organization_id
  credentials_id    = var.azure_credentials_id
  name              = var.name
  cloud_provider    = "AZURE"
  region            = var.azure_region
  instance_type     = var.cluster.instance_type
  disk_size         = var.cluster.disk_size_in_gib
  min_running_nodes = var.cluster.min_running_nodes
  max_running_nodes = var.cluster.max_running_nodes
}

resource "qovery_project" "this" {
  organization_id = var.organization_id
  name            = var.name
}

resource "qovery_environment" "this" {
  for_each = var.environments

  project_id = qovery_project.this.id
  cluster_id = qovery_cluster.this.id
  name       = each.key
  mode       = each.value
}

resource "qovery_database" "postgres" {
  for_each = local.database_environments

  environment_id = qovery_environment.this[each.key].id
  name           = var.database.name
  type           = "POSTGRESQL"
  version        = var.database.version
  mode           = "CONTAINER"
  accessibility  = var.database.accessibility
  cpu            = var.database.cpu
  memory         = var.database.memory
  storage        = var.database.storage
}

resource "qovery_application" "this" {
  for_each = local.application_environments

  environment_id = qovery_environment.this[each.key].id
  name           = var.application.name

  git_repository = {
    url          = var.application.git_url
    branch       = lookup(var.application.branches, each.key, var.application.default_branch)
    root_path    = var.application.root_path
    git_token_id = var.application.git_token_id
  }
  build_mode      = "DOCKER"
  dockerfile_path = var.application.dockerfile_path
  auto_deploy     = var.application.auto_deploy

  cpu                   = var.application.cpu
  memory                = var.application.memory
  min_running_instances = var.application.min_running_instances
  max_running_instances = var.application.max_running_instances

  ports = [
    {
      internal_port       = var.application.port
      external_port       = var.application.publicly_accessible ? 443 : null
      protocol            = "HTTP"
      publicly_accessible = var.application.publicly_accessible
    }
  ]

  healthchecks = {
    readiness_probe = {
      type = {
        tcp = {
          port = var.application.port
        }
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      success_threshold     = 1
      failure_threshold     = 3
    }
  }

  environment_variables = length(var.application.environment_variables) == 0 ? null : [
    for key, value in var.application.environment_variables : {
      key   = key
      value = value
    }
  ]

  # The connection string comes from the database's built-in DATABASE_URL_INTERNAL secret.
  # Qovery resolves the alias at deploy time, so the password never enters the Terraform state.
  secret_aliases = contains(local.database_environments, each.key) ? [
    {
      key   = var.application.database_url_variable
      value = "QOVERY_POSTGRESQL_Z${upper(split("-", qovery_database.postgres[each.key].id)[0])}_DATABASE_URL_INTERNAL"
    }
  ] : null
}

resource "qovery_deployment" "this" {
  for_each = var.deploy ? var.environments : {}

  environment_id = qovery_environment.this[each.key].id
  desired_state  = "RUNNING"

  depends_on = [
    qovery_database.postgres,
    qovery_application.this,
  ]
}

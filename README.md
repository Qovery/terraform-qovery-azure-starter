# Qovery Azure starter module

Terraform and OpenTofu module that sets up a Kubernetes platform on your own Azure subscription, run by [Qovery](https://www.qovery.com).

One `module` block gives you:

- an AKS cluster in your Azure subscription
- a project with staging and production environments (or any set you choose)
- a PostgreSQL database in each environment (optional)
- your application, built from a git repository and deployed to each environment (optional)

You do not write an AKS module, Helm releases or Kubernetes provider glue. Qovery creates the cluster, deploys your services and upgrades both. Everything runs in your Azure subscription.

Registry address: `qovery/azure-starter/qovery`. Until the module is listed on the Terraform Registry and the OpenTofu Registry, use the GitHub source instead:

```hcl
source = "github.com/Qovery/terraform-qovery-azure-starter?ref=v0.1.0"
```

## Usage

```hcl
terraform {
  required_providers {
    qovery = {
      source  = "qovery/qovery"
      version = "~> 1.0"
    }
  }
}

# Reads the API token from the QOVERY_API_TOKEN environment variable.
provider "qovery" {}

module "qovery" {
  source  = "qovery/azure-starter/qovery"
  version = "~> 0.1"

  organization_id      = "your-qovery-organization-id"
  name                 = "acme"
  azure_credentials_id = "your-qovery-azure-credentials-id"
  azure_region         = "westeurope"

  application = {
    git_url = "https://github.com/your-org/your-app.git"
    port    = 8080
  }
}
```

With these inputs the module creates the cluster, the `staging` and `production` environments, a Postgres database in each, and the application built from the `main` branch. The application reads the database connection string from `DATABASE_URL`.

Run it with Terraform:

```sh
export QOVERY_API_TOKEN="your-api-token"
terraform init
terraform apply
```

Or with OpenTofu:

```sh
export QOVERY_API_TOKEN="your-api-token"
tofu init
tofu apply
```

### Examples

- [examples/minimal](examples/minimal): the cluster and two environments, nothing else.
- [examples/complete](examples/complete): the cluster, two environments, Postgres in each, and an application with a different branch per environment.

## Prerequisites

- A Qovery organization. Sign up at [console.qovery.com](https://console.qovery.com).
- A Qovery API token, exported as `QOVERY_API_TOKEN`. Create one in the Qovery Console under Settings > API Tokens.
- An Azure subscription, and Qovery Azure credentials for it, created in the Qovery Console. See [Azure credentials](#azure-credentials) below.
- Terraform 1.6 or later, or OpenTofu 1.6 or later.

Clusters that Qovery creates and manages need a paid plan. Every paid plan starts with a 14-day free trial. The Free plan works with a Kubernetes cluster you already run, which this module does not create.

## Azure credentials

The Qovery provider cannot create Azure credentials: their setup runs a script in Azure Cloud Shell that creates a service principal. Create them once in the Qovery Console, then pass their ID to the module:

1. Follow the [Azure installation guide](https://www.qovery.com/docs/getting-started/installation/azure): in the Qovery Console, start creating an Azure cluster, enter your tenant ID and subscription ID, and run the generated command in Azure Cloud Shell (Bash mode).
2. When the script finishes, the credentials are linked to your Qovery organization. Leave the wizard without creating the cluster: the module creates it.
3. Get the credentials ID from the Qovery API:

   ```sh
   curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
     "https://api.qovery.com/organization/<organization_id>/azure/credentials"
   ```

   Each entry has an `id` and a `name`. Pass the `id` as `azure_credentials_id`.

To check the ID in Terraform, or to read the tenant and subscription the credentials point to, use the `qovery_azure_credentials` data source:

```hcl
data "qovery_azure_credentials" "this" {
  id              = "your-qovery-azure-credentials-id"
  organization_id = "your-qovery-organization-id"
}

# data.qovery_azure_credentials.this.azure_subscription_id
# data.qovery_azure_credentials.this.azure_tenant_id
```

## The cluster

Qovery creates an AKS cluster with a node pool that runs between `cluster.min_running_nodes` and `cluster.max_running_nodes` nodes. The default VM size is `Standard_B2s_v2` (2 vCPUs, 8 GB). For heavier workloads, pick a larger size such as `Standard_D4s_v5`. The size must be available in your region, and the node count must fit your subscription's regional vCPU quota.

## How the database connection works

The database runs as a container on the cluster: Qovery's `MANAGED` database mode is not available on Azure. If you need Azure Database for PostgreSQL, create it next to the module with your own Terraform.

When Qovery creates a database, it adds built-in variables to the environment, including a `DATABASE_URL_INTERNAL` secret. The module gives the application a secret alias that points to it:

```hcl
secret_aliases = [
  {
    key   = "DATABASE_URL"
    value = "QOVERY_POSTGRESQL_Z${upper(split("-", qovery_database.postgres["production"].id)[0])}_DATABASE_URL_INTERNAL"
  }
]
```

Qovery resolves the alias when it deploys the application. The password is never set in Terraform, so it does not end up in your state file. Change the variable name with `application.database_url_variable`.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `organization_id` | ID of the Qovery organization. | `string` | n/a | yes |
| `name` | Base name of the cluster and the project. 3 to 32 lowercase letters, digits and hyphens. | `string` | n/a | yes |
| `azure_credentials_id` | ID of the Qovery Azure credentials, created in the Qovery Console. | `string` | n/a | yes |
| `azure_region` | Azure region of the AKS cluster. | `string` | `"westeurope"` | no |
| `cluster` | Node pool settings: `instance_type` (`Standard_B2s_v2`), `disk_size_in_gib` (40), `min_running_nodes` (3), `max_running_nodes` (10). | `object` | `{}` | no |
| `environments` | Map of environment name to mode: `DEVELOPMENT`, `STAGING`, `PRODUCTION` or `PREVIEW`. | `map(string)` | `{ staging = "STAGING", production = "PRODUCTION" }` | no |
| `database` | PostgreSQL settings: `enabled` (`true`), `environments` (null for all), `name` (`postgres`), `version` (`16`), `accessibility` (`PRIVATE`), `cpu` (250), `memory` (512), `storage` (10). | `object` | `{}` | no |
| `application` | Application built from git: `git_url` (required), `name` (`app`), `git_token_id`, `branches` (per environment), `default_branch` (`main`), `root_path` (`/`), `dockerfile_path` (`Dockerfile`), `port` (8080), `publicly_accessible` (`true`), `cpu` (500), `memory` (512), `min_running_instances` (1), `max_running_instances` (1), `auto_deploy` (`true`), `database_url_variable` (`DATABASE_URL`), `environment_variables` (`{}`). Null creates no application. | `object` | `null` | no |
| `deploy` | Whether to deploy each environment after Terraform creates or changes it. | `bool` | `true` | no |

The application gets a TCP readiness probe on `port`. A publicly accessible port is exposed on 443 over HTTPS. For a private repository, create a `qovery_git_token` and pass its ID as `git_token_id`.

## Outputs

| Name | Description |
|------|-------------|
| `cluster_id` | ID of the Qovery cluster. |
| `project_id` | ID of the Qovery project. |
| `environment_ids` | IDs of the environments, by environment name. |
| `database_ids` | IDs of the PostgreSQL databases, by environment name. |
| `application_ids` | IDs of the applications, by environment name. |
| `application_external_hosts` | Public hosts of the applications, by environment name. |

## Going further

The module covers a common starting point. For anything else, use the Qovery provider resources directly next to it, with the module outputs as inputs: more services, jobs, Helm charts, cloud resources from the service catalog, custom domains or preview environments.

- [Qovery Terraform provider overview](https://www.qovery.com/interfaces/terraform-provider)
- [Provider documentation on the Terraform Registry](https://registry.terraform.io/providers/qovery/qovery/latest/docs)

## License

[MPL-2.0](LICENSE)

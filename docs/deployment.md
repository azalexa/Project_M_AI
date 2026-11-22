# Deploy MechMaster

Check access and regional availability, bootstrap state, and generate plans for SHARED, DEV, and PROD. Review each saved plan and obtain explicit approval for that plan and its cost before applying it. Apply SHARED first, followed by DEV and PROD. Plan files can include sensitive data. Keep them in the ignored `.local-plans/` directory.

## Readiness and configuration

```powershell
& .\scripts\Test-AzureReadiness.ps1
terraform fmt -check -recursive
```

The operator needs permissions to manage project resources, assign roles at the relevant scopes, and create Cost Management budgets. Each Terraform root requires data access to its own state container. Verify provider registration, quota, and availability in West Europe. If PostgreSQL B1ms is unavailable, select the lowest-cost verified compatible SKU and update the estimate. Static Web Apps distributes content globally. The Azure Monitor action group is global. [Static Web Apps hosting](https://learn.microsoft.com/en-us/azure/static-web-apps/faq)

Regional services target West Europe. DEV uses scale-to-zero API compute and supports stopping PostgreSQL. PROD keeps one API replica warm and enables monitoring. SHARED contains the registry and approved CI identities. BOOTSTRAP contains Terraform state. Private DNS zones are global even though they belong to West Europe resource groups. The global Monitor action group can process notifications outside West Europe. Record the actual location and supported SKU for each regional service before approving a plan. If the provider metadata is empty or inconclusive, verify through the service-specific API instead of selecting a fallback region. [Private DNS reliability](https://learn.microsoft.com/en-us/azure/reliability/reliability-dns-private) · [Action group processing](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups)

Follow the [state bootstrap procedure](terraform-state.md). Set the following inputs through environment variables or ignored local `terraform.tfvars` files:

| Input | Scope | Value |
| --- | --- | --- |
| `database_admin` | DEV, PROD | Entra administrator object with `object_id`, `principal_name`, and `principal_type`. |
| `alert_email` | SHARED, PROD | Monitored address for budget and operational alerts. |
| `monthly_budgets` | SHARED | Object with `dev`, `prod`, and `shared` amounts in the billing currency. |
| `budget_start` | SHARED | Start of the current UTC month in `YYYY-MM-01T00:00:00Z` format. |
| `postgres_sku` | DEV, PROD | Defaults to `B_Standard_B1ms`. Verify availability and cost. |

Estimate production for 730 hours, development for its expected running hours, and persistent storage for two 32 GiB database disks. Include ACR Basic, Static Web Apps Standard, 60 GB of Blob Hot LRS, two private DNS zones, state storage, and expected traffic, logs, and alerts. Confirm eligibility before including free allowances. Budget alerts at 80% and 100% do not stop billing. [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices) · [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)

```powershell
& .\scripts\New-TerraformPlans.ps1 -StateAccountName $stateAccount
```

Check existing Azure resources before any change. Review every deletion and replacement, and obtain separate approval before importing an existing resource. Keep the exact plan that was reviewed. If configuration, state, or access changes, regenerate the plan and obtain approval again. Apply only the approved saved plan.

## GitHub Actions and Azure DevOps

After SHARED is deployed, configure GitHub Environments `dev` and `prod` for `azalexa/Project_M_AI`. Limit deployment to `main` and set up production reviewers where supported. For each environment, set `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `TF_STATE_ACCOUNT`, `ACR_NAME`, and `DATABASE_ADMIN`. Set `ALERT_EMAIL` for PROD. `DATABASE_ADMIN` uses the same fields as the Terraform object in JSON. `POSTGRES_SKU` is optional. The SHARED output `github_client_ids` provides the client IDs.

See the Azure DevOps plan and apply section for workflow ownership and authorization.

## Existing infrastructure and Azure DevOps reuse

An Azure subscription inventory identified the legacy `rg-project-m-ai-dev` and a Visual Studio Online resource group in West Europe. Leave both outside these Terraform roots. The project owner reports that `sc-project-m-ai-dev` uses workload identity federation and passed an Azure connectivity test for the legacy DEV group. Its current principal, effective Azure RBAC scope, and pipeline authorizations still need verification. A successful connectivity test does not establish authorization for any MechMaster resource group.

Reuse the existing CI jobs and federation pattern once their definitions are available for review. Keep the legacy service connection for its current pipeline. Before proposing reuse of a connection for MechMaster, compare its Azure DevOps pipeline authorization with the federated identity's effective Azure roles and scopes. Verify the subscription, tenant, identity, and issuer/subject using Azure DevOps and Azure RBAC metadata. Avoid logging access tokens or federated assertions.

If Azure Pipelines needs MechMaster access, use an Azure Resource Manager service connection with a separate federated identity for each environment that needs one. Use the issuer and subject generated by Azure DevOps, and authorize only the named pipeline. Keep SHARED and BOOTSTRAP under the operator unless a separate pipeline is approved for those scopes.

| Proposed connection | Initial Azure access | Additional access only when required |
| --- | --- | --- |
| `sc-mechmaster-dev` | Reader on `rg-mechmaster-dev` for inventory and verification jobs | Resource-specific write permissions for an approved deployment job. |
| `sc-mechmaster-prod` | Reader on `rg-mechmaster-prod` for inventory and verification jobs | Separate approval for production deployment access and pipeline authorization. |

Scope API deployment permissions to the target Container App and grant registry access only if the job interacts with ACR. An Azure pipeline that runs Terraform against remote state also needs explicitly approved data-plane access. Grant approved Azure DevOps identities access only to the matching `tfstate-dev` or `tfstate-prod` container after any required state migration is verified. Keep role-assignment changes and resource-group creation in separately reviewed plans. [Azure DevOps workload identity setup](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/configure-workload-identity) · [Service connection pipeline authorization](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure)

## Network design and API diagnostics

| Environment | Virtual network | Container Apps subnet | PostgreSQL subnet |
| --- | --- | --- | --- |
| DEV | `10.30.0.0/24` | `10.30.0.0/27` | `10.30.0.32/28` |
| PROD | `10.40.0.0/24` | `10.40.0.0/27` | `10.40.0.32/28` |

The /27 subnets are delegated to `Microsoft.App/environments` for Workload Profiles environments using Consumption. The /28 subnets are dedicated to `Microsoft.DBforPostgreSQL/flexibleServers`. These are the documented minimum sizes for this topology and the replica limits leave room for platform addresses and revision updates. [Container Apps networking](https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom) · [PostgreSQL private networking](https://learn.microsoft.com/en-us/azure/postgresql/network/concepts-networking-private)

- Internet clients connect to each environment's public Container Apps ingress over HTTPS. Azure terminates TLS and forwards HTTP to the API on port 8080.
- The API resolves PostgreSQL's FQDN through Azure-provided DNS and the private DNS zone linked only to its own VNet. The API connects to the database's private address over TCP 5432 with TLS. PostgreSQL public access is disabled.
- The app's managed identity pulls images from its own repository in the shared Basic ACR using a repository-scoped ABAC Reader role and accesses its own file container using Azure RBAC. Key Vault secret access uses the same identity. The sample API needs no credentials. PostgreSQL administrative authentication uses Entra ID.
- The two environments use separate VNets with no peering. This design uses no Azure Firewall, NAT Gateway, Application Gateway, VPN Gateway, or Bastion.
- Both API apps request 0.5 vCPU and 1 GiB. DEV uses 0 to 2 replicas. PROD uses 1 to 3. Rate and total time at active and idle utilization affect Consumption charges. [Container Apps sizing](https://learn.microsoft.com/en-us/azure/container-apps/containers) · [Container Apps billing](https://learn.microsoft.com/en-us/azure/container-apps/billing)
- The initial Terraform revision uses a public placeholder image. GitHub publishes the sample API to ACR and records its digest. Deploy the approved digest from Azure DevOps or through an explicitly authorized operator, then check `GET /health`. Inspect console and system events using Container Apps Log Stream. PROD also sends environment logs to Log Analytics. `GET /readyz` verifies DNS, TCP and PostgreSQL TLS with hostname verification. Check Entra login and SQL separately.

## Verification and operations

- Check `/health` and `/readyz` after deploying the API image. Review the corresponding console and system logs.
- Terraform allowlists PostGIS. An administrator runs `CREATE EXTENSION IF NOT EXISTS postgis;` in the `mechmaster` database over the private network and provisions the application identity's database privileges before the application uses SQL.
- Preview stopping the DEV database with `& .\scripts\Set-DevState.ps1 -Action Stop -WhatIf`. After approval, run without `-WhatIf`. Resume with `-Action Start`. Storage and backups can still incur charges while compute is stopped. Azure automatically starts the server after its maximum stop period. [PostgreSQL stop and start](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/how-to-stop-start-server)
- For removal, back up state and data and pause deployment workflows. Generate a saved destroy plan for the specific environment and obtain explicit approval before executing it. Remove DEV and PROD before SHARED during a full teardown. Retain the state account until recovery and teardown verification are complete.
- For state recovery, pause concurrent writes and inspect the versions of the affected blob. Retain a copy of the current version. Review and authorize the recovery before restoring a version, then compare the recovered state with Azure using `terraform plan -refresh-only`.

## Azure DevOps plan and apply

The local `azure-pipelines.yml` is a new definition for MechMaster. Compare it with the existing remote pipeline before publishing or registering it. It has no push or pull-request triggers. A manual run plans only by default. An explicit apply request adds a named manual review and an Azure DevOps deployment environment, then verifies and applies the saved binary plan from that same run. The pipeline rejects plans containing deletion or replacement. Configure branch control, an exclusive lock, and production approval checks in Azure DevOps before authorizing pipeline access.

Use a dedicated, trusted Linux agent pool with Terraform 1.17.2, Azure CLI, Python 3, and access to Azure. Create environment-specific variable groups with `TF_STATE_ACCOUNT`, `DATABASE_ADMIN`, `POSTGRES_SKU`, `ALERT_EMAIL` for PROD, and `PLAN_APPROVERS`. Restrict who can change these variables, the pipeline definition, and the service connections. Use a private project with restricted build and artifact read access. The saved plan is sensitive and must stay in the restricted same-run artifact with short retention. The plan and its SHA-256 are reviewed before apply. The CI pipeline rejects missing provider lock files.

Terraform apply identities require environment resource management permissions, state access for locking and writes, and scoped, conditional delegation for the exact role assignments Terraform manages. Assign these permissions in a separate review after SHARED is provisioned. Scope state permissions to the matching environment container and review inherited grants that could bypass that boundary. Approve and verify any required state migration before enabling a pipeline that uses the new backend. Keep SHARED and BOOTSTRAP under operator control. The service connection from the legacy project remains outside the MechMaster pipeline.

For Terraform, the current GitHub Actions workflow runs formatting checks, initialization with `-backend=false`, and validation. It does not run plans or apply changes and requires no access to the Terraform state containers. The GitHub OIDC publisher role is limited by Azure ABAC to the corresponding environment repository. [ACR repository permissions](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-abac-repository-permissions) To enable federation, supply the exact `github_oidc_subjects` for the protected `dev` and `prod` GitHub Environments after verifying the repository's OIDC mode. The legacy form is `repo:azalexa/Project_M_AI:environment:dev`. The immutable form includes verified owner and repository IDs. Never print an OIDC token. [GitHub OIDC subject reference](https://docs.github.com/en/actions/reference/security/oidc) · [Azure Pipelines manual validation](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/manual-validation-v1)

## Database and application data

Both environments use PostgreSQL 16, 32 GiB, seven-day backup retention, and no HA or geo-redundant backup. The region supports Flexible Server. Confirm `Standard_B1ms` in the subscription's live SKU list before planning. Azure controls the in-region backup redundancy in this configuration. Microsoft documentation describes zone-redundant backups in AZ-enabled regions, but its HA documentation also describes LRS for zonal and non-zone-redundant servers. Verify the actual redundancy for this SKU and configuration after deployment. [PostgreSQL reliability](https://learn.microsoft.com/en-us/azure/reliability/reliability-postgresql-flexible-server) · [High availability](https://learn.microsoft.com/en-us/azure/postgresql/high-availability/concepts-high-availability)

PostGIS is supported on PostgreSQL 16. Terraform allowlists it and the first migration creates it. Run `scripts/Invoke-DatabaseMigration.ps1` from a trusted client on the target VNet with `psql`, an approved Entra administrator, and the trusted Azure PostgreSQL root CA. Use `-WhatIf` to verify the target before authorizing changes. The script uses a short-lived Entra token in the process environment and verified TLS. The SQL manifest applies ordered migrations in a transaction, uses an advisory lock, and records applied versions. Append future migrations and version steps without editing already applied migrations. Use an Entra database role for application SQL access. [Supported PostgreSQL extensions](https://learn.microsoft.com/en-us/azure/postgresql/extensions/concepts-extensions-versions) · [Entra PostgreSQL authentication](https://learn.microsoft.com/en-us/azure/postgresql/security/security-entra-configure)

Use `scripts/Stop-Dev.ps1 -WhatIf` to preview stopping DEV, then run the approved operation. Use `scripts/Start-Dev.ps1` to resume. Azure restarts a stopped PostgreSQL server after seven days. Storage and backup charges can continue while compute is stopped. [PostgreSQL limits](https://learn.microsoft.com/en-us/azure/postgresql/configure-maintain/concepts-limits)

Application storage uses separate Standard Hot LRS accounts and private containers. The 10 GB DEV and 50 GB PROD figures are estimation inputs. Blob versioning and 14-day blob and container soft delete support recovery. For an overwritten blob, inspect versions and copy the approved version to a safe path before replacing production data. For deletion, review and recover within the retention window. Preserved versions increase billed capacity. Key Vault secrets are managed outside Terraform to keep their values out of state. Provider-managed outputs can still contain sensitive material. Protect Terraform state and plan data.

The test frontend is in `frontend/`. DEV uses Static Web Apps Free and PROD Standard. The Azure DevOps Static Web Apps deploy task uses a separate per-app deployment token. If Azure DevOps is selected for static delivery, keep each token in Key Vault or an approved protected secret store and expose it only to the dedicated task. Use GitHub-based authorization instead when supported and validated for the selected repository and app. Entra OIDC used for ARM access does not by itself authorize static content uploads. No frontend publishing workflow is enabled. [Static Web Apps build and deployment authorization](https://learn.microsoft.com/en-us/azure/static-web-apps/build-configuration)

## Provider locks

AzureRM is pinned to 4.81.0. Generate signed-platform checksum locks for Windows and Linux from the official Terraform Registry, then commit the three generated lock files:

```powershell
foreach ($root in @('shared', 'environments/dev', 'environments/prod')) {
    terraform "-chdir=$root" init -backend=false
    if ($LASTEXITCODE -ne 0) { throw "Terraform init failed for $root." }
    terraform "-chdir=$root" providers lock -platform=windows_amd64 -platform=linux_amd64
    if ($LASTEXITCODE -ne 0) { throw "Provider lock failed for $root." }
}
```

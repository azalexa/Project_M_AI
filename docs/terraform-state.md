# Terraform state bootstrap

Create Azure Storage before the first remote `terraform init`. The bootstrap script uses Azure CLI. The signed-in Microsoft Entra user needs permissions to create the resource group, manage its storage account and container, and read and write role assignments at container scope. Verify the `Microsoft.Storage` provider registration.

## Resource ownership and locking

| Owner | Resources and state |
| --- | --- |
| PowerShell bootstrap | `rg-mechmaster-tfstate`, its StorageV2 account, Blob protection settings, the private `tfstate-shared`, `tfstate-dev`, and `tfstate-prod` containers, and the bootstrap operator's data role assignment on each container. |
| `shared/` | Creates and owns `rg-mechmaster-shared`, `rg-mechmaster-dev`, and `rg-mechmaster-prod` in `tfstate-shared/shared.tfstate`. It also owns shared services and the GitHub OIDC identities and their registry and resource group permissions. |
| `environments/dev/` | Owns DEV resources inside `rg-mechmaster-dev` in `tfstate-dev/dev.tfstate`. |
| `environments/prod/` | Owns PROD resources inside `rg-mechmaster-prod` in `tfstate-prod/prod.tfstate`. |

Azure management-plane permissions are separate from Blob data-plane permissions. The operator needs Azure management permissions for bootstrap and role assignment writes. Terraform state users need `Storage Blob Data Contributor` at container scope for state operations and locking. Terraform uses a native Azure Blob lease; keep locking enabled, and do not break a lease while a Terraform operation is active. Bootstrap does not write state blobs. [AzureRM backend authentication and locking](https://developer.hashicorp.com/terraform/language/backend/azurerm)

## Select the storage account and preview changes

From the repository root, with `Project_M_AI` already active:

```powershell
$stateAccount = Read-Host 'Enter a globally unique storage account name (3 to 24 lowercase letters or digits)'
az storage account check-name --name $stateAccount --query '{available:nameAvailable,message:message}' --output table
& .\bootstrap\Initialize-TerraformState.ps1 -StorageAccountName $stateAccount -WhatIf
```

The name availability check applies to a new account. To resume a partial bootstrap, reuse the same name. `-WhatIf` verifies the subscription context and previews the operation without writing to Azure.

## Bootstrap after cost approval

Storage charges depend on data volume and operations. Run the following only after explicit approval for this stage:

```powershell
& .\bootstrap\Initialize-TerraformState.ps1 -StorageAccountName $stateAccount
```

The script confirms the operation and configures a West Europe StorageV2 Standard LRS account with three private state containers, HTTPS, minimum TLS 1.2, Blob versioning, and 30-day blob and container soft delete. It verifies encryption at rest and disables anonymous access and Shared Key authentication. New accounts use Microsoft-managed encryption keys. Older versions can increase storage costs. [Azure Storage CLI](https://learn.microsoft.com/en-us/cli/azure/storage/account) · [Blob data protection](https://learn.microsoft.com/en-us/azure/storage/blobs/data-protection-overview)

On retry, the script accepts only a compatible account with the `workload=mechmaster-tfstate` tag. It validates existing account settings, preserves longer retention periods, creates missing containers through Azure Resource Manager, and verifies that each container is private. It assigns `Storage Blob Data Contributor` to the signed-in user separately at each container scope and reuses existing matching assignments. Pipeline access requires separate authorization. Scope each approved pipeline identity to its own environment container and review inherited grants at the storage account and higher scopes. The Blob endpoint can be reachable over a public network. Data access requires Entra authentication and Azure RBAC. [AzureRM backend](https://developer.hashicorp.com/terraform/language/backend/azurerm) · [Azure RBAC](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-cli)

## Previous state versions

The bootstrap operator needs `Microsoft.Storage/storageAccounts/managementPolicies/read` and `Microsoft.Storage/storageAccounts/managementPolicies/write` on the storage account. Bootstrap creates an account-level lifecycle policy when none exists and leaves a matching policy in place. If a different policy exists, bootstrap stops for manual review. Coordinate policy changes with other storage administrators because the Azure CLI create operation can also replace an existing policy. Use `-WhatIf` to preview the operation without evaluating or writing the policy. [Azure CLI management policy commands](https://learn.microsoft.com/en-us/cli/azure/storage/account/management-policy)

The policy uses `version.delete` for block blobs under `tfstate-shared/`, `tfstate-dev/`, and `tfstate-prod/`. It applies only to previous versions older than 30 days from version creation. The current state blob and snapshots are outside the delete action. Azure processes the policy asynchronously. [Lifecycle deletion rules](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-policy-delete)

Blob soft delete retains each expired version for at least 30 more days from the lifecycle deletion, or longer if the account has a longer retention period. A version eligible for deletion just after day 30 can therefore remain recoverable and billable for roughly 60 days from creation, with additional time if it becomes a previous version later or Azure processes the rule later. Soft-deleted data is billed at its existing storage tier until permanent deletion. [Blob soft delete and billing](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-blob-overview)

## Verify access and initialize the backends

After RBAC propagates, confirm Entra data access:

```powershell
foreach ($container in @('tfstate-shared', 'tfstate-dev', 'tfstate-prod')) {
    az storage blob list --account-name $stateAccount --container-name $container --auth-mode login --output table
    if ($LASTEXITCODE -ne 0) { throw "Could not list blobs in $container." }
}
```

Before initializing a new backend, check the old `tfstate` container for existing state under the current keys and any legacy `*.terraform.tfstate` keys. If a root already has state there, pause Terraform operations for that root and arrange a separately approved migration. Preserve a backup, verify the destination and its permissions, and confirm that the migrated state contains the expected resources before planning. With the old backend initialized locally and verified, `terraform init -migrate-state` can copy state to the new backend. Keep the source state until migration verification is complete. [Terraform init migration options](https://developer.hashicorp.com/terraform/cli/commands/init)

For a fresh backend, pass `storage_account_name` and `use_cli=true` to `terraform init`. The signed-in Azure CLI session supplies the Entra tenant. Each root sets `container_name`, `key`, and `use_azuread_auth = true` in `versions.tf`. [AzureRM backend authentication](https://developer.hashicorp.com/terraform/language/backend/azurerm)

```powershell
foreach ($root in @('shared', 'environments/dev', 'environments/prod')) {
    terraform "-chdir=$root" init "-backend-config=storage_account_name=$stateAccount" '-backend-config=use_cli=true'
    if ($LASTEXITCODE -ne 0) { throw "Terraform init failed for $root." }
    terraform "-chdir=$root" validate
    if ($LASTEXITCODE -ne 0) { throw "Terraform validate failed for $root." }
}
```

Keep credentials out of backend arguments and version control. Commit the generated `.terraform.lock.hcl` files and review staged changes for state, plans, and secrets before publishing. Continue with the [deployment checks](deployment.md).

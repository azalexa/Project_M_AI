# Terraform state bootstrap

Create Azure Storage before the first remote `terraform init`. The bootstrap script uses Azure CLI. The signed-in Microsoft Entra user needs permissions to create the resource group, manage its storage account and container, and read and write role assignments at container scope. Verify the `Microsoft.Storage` provider registration.

## Resource ownership and locking

| Owner | Resources and state |
| --- | --- |
| PowerShell bootstrap | `rg-mechmaster-tfstate`, its StorageV2 account, Blob protection settings, the private `tfstate` container, and the bootstrap operator's container-scoped data assignment. |
| `shared/` | Creates and owns `rg-mechmaster-shared`, `rg-mechmaster-dev`, and `rg-mechmaster-prod` in `shared.tfstate`. It also owns shared services and the state access assignments for approved CI identities. |
| `environments/dev/` | Owns DEV resources inside `rg-mechmaster-dev` in `dev.tfstate`. |
| `environments/prod/` | Owns PROD resources inside `rg-mechmaster-prod` in `prod.tfstate`. |

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

The script confirms the operation and configures a West Europe StorageV2 Standard LRS account with a private `tfstate` container, HTTPS, minimum TLS 1.2, Blob versioning, and 30-day blob and container soft delete. It verifies encryption at rest and disables anonymous access and Shared Key authentication. New accounts use Microsoft-managed encryption keys. Older versions can increase storage costs. [Azure Storage CLI](https://learn.microsoft.com/en-us/cli/azure/storage/account) · [Blob data protection](https://learn.microsoft.com/en-us/azure/storage/blobs/data-protection-overview)

On retry, the script accepts only a compatible account with the `workload=mechmaster-tfstate` tag. It validates existing account settings, preserves longer retention periods, and creates the container through Azure Resource Manager only when missing. It grants the signed-in user `Storage Blob Data Contributor` at container scope. All three state keys share the same container access boundary. The Blob endpoint can be reachable over a public network. Data access requires Entra authentication and Azure RBAC. [AzureRM backend](https://developer.hashicorp.com/terraform/language/backend/azurerm) · [Azure RBAC](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-cli)

## Verify access and initialize the backends

After RBAC propagates, confirm Entra data access:

```powershell
az storage blob list --account-name $stateAccount --container-name tfstate --auth-mode login --output table
```

Check for existing state, including the legacy `*.terraform.tfstate` keys. Review and obtain explicit approval for a separate migration if an old key already contains state.

```powershell
foreach ($root in @('shared', 'environments/dev', 'environments/prod')) {
    terraform "-chdir=$root" init "-backend-config=storage_account_name=$stateAccount" '-backend-config=use_cli=true'
    if ($LASTEXITCODE -ne 0) { throw "Terraform init failed for $root." }
    terraform "-chdir=$root" validate
    if ($LASTEXITCODE -ne 0) { throw "Terraform validate failed for $root." }
}
```

Keep credentials out of backend arguments and version control. Commit the generated `.terraform.lock.hcl` files and review staged changes for state, plans, and secrets before publishing. Continue with the [deployment checks](deployment.md).

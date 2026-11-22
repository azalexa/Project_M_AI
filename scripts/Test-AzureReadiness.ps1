#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$context = az account show --query '{name:name,state:state,cloud:environmentName}' -o json
if ($LASTEXITCODE) { throw 'Azure CLI could not read the active subscription.' }
$account = $context | ConvertFrom-Json
if ($account.name -ne 'Project_M_AI' -or $account.state -ne 'Enabled' -or $account.cloud -ne 'AzureCloud') {
    throw 'The currently selected account must be Project_M_AI in AzureCloud.'
}

terraform version
if ($LASTEXITCODE) { throw 'Terraform could not run.' }
az version
if ($LASTEXITCODE) { throw 'Azure CLI could not report its version.' }

$types = [ordered]@{
    'Microsoft.App' = 'containerApps','managedEnvironments'
    'Microsoft.DBforPostgreSQL' = 'flexibleServers'
    'Microsoft.Network' = 'virtualNetworks','privateDnsZones'
    'Microsoft.Storage' = 'storageAccounts'
    'Microsoft.ContainerRegistry' = 'registries'
    'Microsoft.KeyVault' = 'vaults'
    'Microsoft.Web' = 'staticSites'
    'Microsoft.OperationalInsights' = 'workspaces'
    'Microsoft.Insights' = 'actionGroups','metricAlerts','diagnosticSettings'
    'Microsoft.ManagedIdentity' = 'userAssignedIdentities'
    'Microsoft.Consumption' = 'budgets'
}
foreach ($namespace in $types.Keys) {
    $raw = az provider show --namespace $namespace -o json
    if ($LASTEXITCODE) { throw "Cannot read provider $namespace." }
    $provider = $raw | ConvertFrom-Json
    foreach ($type in $types[$namespace]) {
        $metadata = $provider.resourceTypes | Where-Object { $_.resourceType -eq $type }
        [pscustomobject]@{
            Provider     = $namespace
            ResourceType = $type
            Registration = $provider.registrationState
            Locations    = $metadata.locations -join ', '
        }
    }
}

az postgres flexible-server list-skus --location westeurope --output table
if ($LASTEXITCODE) { throw 'Cannot list PostgreSQL SKUs for West Europe.' }
az containerapp env workload-profile list-supported --location westeurope --output table
if ($LASTEXITCODE) { throw 'Cannot list Container Apps workload profiles for West Europe.' }

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]{3,24}$', Options = [System.Text.RegularExpressions.RegexOptions]::None)]
    [string]$StorageAccountName
)

$ErrorActionPreference = 'Stop'
$resourceGroup = 'rg-mechmaster-tfstate'
$location = 'westeurope'
$container = 'tfstate'
$retentionDays = 30

function Invoke-AzureCli {
    param([string[]]$Arguments)

    # Windows PowerShell can treat redirected native stderr as a PowerShell error.
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $result = & az @Arguments --only-show-errors --output json 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $command = ($Arguments -join ' ') -replace '\s--.*$', ''
        $details = ($result | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Azure CLI failed: az $command (exit $exitCode).$([Environment]::NewLine)$details"
    }

    $json = ($result | Where-Object { $_ -is [string] }) -join [Environment]::NewLine
    if ($json -and $json.Trim() -ne 'null') {
        ConvertFrom-Json -InputObject $json -ErrorAction Stop
    }
}

$account = Invoke-AzureCli -Arguments @('account', 'show')
if ($account.name -ne 'Project_M_AI' -or $account.state -ne 'Enabled' -or $account.environmentName -ne 'AzureCloud') {
    throw 'Select the enabled Project_M_AI subscription in AzureCloud before running bootstrap.'
}

$target = "$($account.name)/$resourceGroup/$StorageAccountName/$container"
if (-not $PSCmdlet.ShouldProcess($target, 'Configure Terraform state storage and grant the signed-in user container access')) {
    return
}

$principal = Invoke-AzureCli -Arguments @('ad', 'signed-in-user', 'show', '--query', 'id')
if (-not $principal) {
    throw 'Azure CLI must be signed in as a Microsoft Entra user.'
}

$subscription = @('--subscription', $account.id)
$groupArgs = @('--resource-group', $resourceGroup) + $subscription
$storage = $null
$groupExists = Invoke-AzureCli -Arguments (@('group', 'exists', '--name', $resourceGroup) + $subscription)
if ($groupExists) {
    $group = Invoke-AzureCli -Arguments (@('group', 'show', '--name', $resourceGroup) + $subscription)
    if ($group.location -ne $location) {
        throw "Existing resource group $resourceGroup is outside $location."
    }
    $storage = Invoke-AzureCli -Arguments (@('storage', 'account', 'list', '--query', "[?name=='$StorageAccountName'] | [0]") + $groupArgs)
}

if (-not $storage) {
    $nameCheck = Invoke-AzureCli -Arguments (@('storage', 'account', 'check-name', '--name', $StorageAccountName) + $subscription)
    if (-not $nameCheck.nameAvailable) {
        throw "Storage account name is unavailable: $($nameCheck.message)"
    }
}

if (-not $groupExists) {
    $null = Invoke-AzureCli -Arguments (@('group', 'create', '--name', $resourceGroup, '--location', $location) + $subscription)
}

$accountArgs = @('--name', $StorageAccountName) + $groupArgs
$securityArgs = @(
    '--allow-blob-public-access', 'false',
    '--allow-shared-key-access', 'false',
    '--https-only', 'true',
    '--min-tls-version', 'TLS1_2'
)
if ($storage) {
    if ($storage.kind -ne 'StorageV2' -or $storage.sku.name -ne 'Standard_LRS' -or
        $storage.location -ne $location -or $storage.isHnsEnabled -or
        $storage.tags.workload -ne 'mechmaster-tfstate') {
        throw 'Existing storage account is incompatible or lacks the mechmaster-tfstate workload tag. Review it before proceeding.'
    }
    if ($storage.allowBlobPublicAccess -ne $false -or $storage.allowSharedKeyAccess -ne $false -or
        $storage.enableHttpsTrafficOnly -ne $true -or $storage.minimumTlsVersion -ne 'TLS1_2') {
        throw 'Existing storage account security settings do not match the bootstrap requirements. Review the account before proceeding.'
    }
} else {
    $storage = Invoke-AzureCli -Arguments (@(
        'storage', 'account', 'create', '--location', $location, '--sku', 'Standard_LRS',
        '--kind', 'StorageV2', '--access-tier', 'Hot', '--tags', 'workload=mechmaster-tfstate'
    ) + $accountArgs + $securityArgs)
}

if (-not $storage.encryption.services.blob.enabled) {
    throw 'Azure Storage did not report Blob encryption at rest as enabled.'
}

$blobService = Invoke-AzureCli -Arguments (@(
    'storage', 'account', 'blob-service-properties', 'show', '--account-name', $StorageAccountName
) + $groupArgs)
if (-not $blobService.isVersioningEnabled -or
    -not $blobService.deleteRetentionPolicy.enabled -or $blobService.deleteRetentionPolicy.days -lt $retentionDays -or
    -not $blobService.containerDeleteRetentionPolicy.enabled -or $blobService.containerDeleteRetentionPolicy.days -lt $retentionDays) {
    $blobDays = [string][Math]::Max($retentionDays, [int]$blobService.deleteRetentionPolicy.days)
    $containerDays = [string][Math]::Max($retentionDays, [int]$blobService.containerDeleteRetentionPolicy.days)
    $null = Invoke-AzureCli -Arguments (@(
        'storage', 'account', 'blob-service-properties', 'update',
        '--account-name', $StorageAccountName,
        '--enable-versioning', 'true',
        '--enable-delete-retention', 'true', '--delete-retention-days', $blobDays,
        '--enable-container-delete-retention', 'true', '--container-delete-retention-days', $containerDays
    ) + $groupArgs)
}

$containerArgs = @('--storage-account', $StorageAccountName, '--name', $container) + $groupArgs
$existingContainer = Invoke-AzureCli -Arguments (@(
    'storage', 'container-rm', 'list', '--storage-account', $StorageAccountName,
    '--query', "[?name=='$container'] | [0]"
) + $groupArgs)
if ($existingContainer) {
    if ($existingContainer.publicAccess -in @('Blob', 'Container')) {
        throw 'The existing Terraform state container has a public access policy. Review it before proceeding.'
    }
} else {
    $null = Invoke-AzureCli -Arguments (@(
        'storage', 'container-rm', 'create', '--public-access', 'off'
    ) + $containerArgs)
}

$scope = "$($storage.id)/blobServices/default/containers/$container"
$roleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' # Storage Blob Data Contributor
$assignments = Invoke-AzureCli -Arguments (@(
    'role', 'assignment', 'list', '--all', '--scope', $scope,
    '--assignee-object-id', $principal, '--fill-principal-name', 'false'
) + $subscription)
$matchingAssignment = $assignments | Where-Object {
    $_.scope -eq $scope -and $_.roleDefinitionId -like "*/$roleId" -and -not $_.condition
}
if (-not $matchingAssignment) {
    $null = Invoke-AzureCli -Arguments (@(
        'role', 'assignment', 'create', '--scope', $scope, '--role', $roleId,
        '--assignee-object-id', $principal, '--assignee-principal-type', 'User'
    ) + $subscription)
}

Write-Host "Backend configured: $StorageAccountName/$container. Wait for RBAC propagation before Terraform init."

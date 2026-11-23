#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]{3,24}$', Options = [System.Text.RegularExpressions.RegexOptions]::None)]
    [string]$StorageAccountName
)

$ErrorActionPreference = 'Stop'
$resourceGroup = 'rg-mechmaster-tfstate'
$location = 'northeurope'
$containers = @('tfstate-shared', 'tfstate-dev', 'tfstate-prod')
$retentionDays = 30

function Invoke-AzureCli {
    param([string[]]$Arguments, [string]$MissingErrorCode)

    # Windows PowerShell can treat redirected native stderr as a PowerShell error.
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $result = & az @Arguments --only-show-errors --output json 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $command = ($Arguments -join ' ') -replace '\s--.*$', ''
        $details = ($result | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        if ($MissingErrorCode) {
            $response = $details.TrimStart() -creplace '^ERROR:[\t ]*', ''
            $errorCode = $null
            if ($response.StartsWith('{')) {
                try {
                    $errorResponse = ConvertFrom-Json -InputObject $response -ErrorAction Stop
                    $errorCode = if ($null -ne $errorResponse.error) { $errorResponse.error.code } else { $errorResponse.code }
                } catch {
                    # Keep the original CLI failure when the error response is malformed.
                }
            } elseif ($response -cmatch '^\(([A-Za-z][A-Za-z0-9_.-]*)\)(?=\s|$)') {
                $errorCode = $Matches[1]
            } elseif ($response -cmatch '(?m)^[\t ]*Code:[\t ]*([A-Za-z][A-Za-z0-9_.-]*)[\t ]*\r?$') {
                $errorCode = $Matches[1]
            }
            if ($errorCode -is [string] -and $errorCode -ceq $MissingErrorCode) {
                return
            }
        }
        throw "Azure CLI failed: az $command (exit $exitCode).$([Environment]::NewLine)$details"
    }

    $json = ($result | Where-Object { $_ -is [string] }) -join [Environment]::NewLine
    if ($json -and $json.Trim() -ne 'null') {
        ConvertFrom-Json -InputObject $json -ErrorAction Stop
    } elseif ($MissingErrorCode) {
        throw 'Azure CLI returned no lifecycle policy response. Review the storage account before proceeding.'
    }
}

function Test-LifecyclePolicyMatch {
    param($Actual, $Expected)

    if ($Expected -is [pscustomobject]) {
        if ($Actual -isnot [pscustomobject]) { return $false }
        $actualProperties = @($Actual.PSObject.Properties | Where-Object { $null -ne $_.Value })
        if ($actualProperties.Count -ne @($Expected.PSObject.Properties).Count) { return $false }
        foreach ($property in $Expected.PSObject.Properties) {
            if (-not (Test-LifecyclePolicyMatch $Actual.($property.Name) $property.Value)) { return $false }
        }
        return $true
    }

    if ($Expected -is [array]) {
        if ($Actual -isnot [array] -or $Actual.Count -ne $Expected.Count) { return $false }
        # The policy has one rule, and the filter arrays are unordered.
        if ($Expected.Count -gt 1) {
            return $null -eq (Compare-Object $Expected $Actual -CaseSensitive)
        }
        return (Test-LifecyclePolicyMatch $Actual[0] $Expected[0])
    }

    return ($null -ne $Actual -and $Actual -ceq $Expected -and
        ($Expected -isnot [bool] -or $Actual -is [bool]))
}

function Get-LifecyclePolicy {
    param([string[]]$PolicyArgs, $Expected)

    $command = @('storage', 'account', 'management-policy', 'show') + $PolicyArgs
    $existing = Invoke-AzureCli -Arguments $command -MissingErrorCode 'ManagementPolicyNotFound'
    if ($null -eq $existing) { return }
    if (-not (Test-LifecyclePolicyMatch $existing.policy $Expected)) {
        throw 'The existing Azure Blob lifecycle policy differs from the Terraform state policy. Review it manually before rerunning bootstrap.'
    }
    return $existing
}

$account = Invoke-AzureCli -Arguments @('account', 'show')
if ($account.name -ne 'Project_M_AI' -or $account.state -ne 'Enabled' -or $account.environmentName -ne 'AzureCloud') {
    throw 'Select the enabled Project_M_AI subscription in AzureCloud before running bootstrap.'
}

$target = "$($account.name)/$resourceGroup/$StorageAccountName ($($containers -join ', '))"
if (-not $PSCmdlet.ShouldProcess($target, 'Configure Terraform state storage, lifecycle policy, and signed-in user container access')) {
    return
}

$principal = Invoke-AzureCli -Arguments @('ad', 'signed-in-user', 'show', '--query', 'id')
if (-not $principal) {
    throw 'Azure CLI must be signed in as a Microsoft Entra user.'
}

$subscription = @('--subscription', $account.id)
$groupArgs = @('--resource-group', $resourceGroup) + $subscription
$policyArgs = @('--account-name', $StorageAccountName) + $groupArgs
$policyJson = @{
    rules = @(
        @{
            enabled = $true
            name = 'expire-previous-terraform-state-versions'
            type = 'Lifecycle'
            definition = @{
                actions = @{ version = @{ delete = @{ daysAfterCreationGreaterThan = 30 } } }
                filters = @{
                    blobTypes = @('blockBlob')
                    prefixMatch = @($containers | ForEach-Object { "$_/" })
                }
            }
        }
    )
} | ConvertTo-Json -Depth 10
$expectedPolicy = ConvertFrom-Json -InputObject $policyJson
$existingPolicy = $null
$storage = $null
$groupExists = Invoke-AzureCli -Arguments (@('group', 'exists', '--name', $resourceGroup) + $subscription)
if ($groupExists) {
    $group = Invoke-AzureCli -Arguments (@('group', 'show', '--name', $resourceGroup) + $subscription)
    if ($group.location -ne $location) {
        throw "Existing resource group $resourceGroup is in '$($group.location)'. Bootstrap requires '$location'."
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
    $existingPolicy = Get-LifecyclePolicy -PolicyArgs $policyArgs -Expected $expectedPolicy
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

$roleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' # Storage Blob Data Contributor
foreach ($container in $containers) {
    $containerArgs = @('--storage-account', $StorageAccountName, '--name', $container) + $groupArgs
    $existingContainer = Invoke-AzureCli -Arguments (@(
        'storage', 'container-rm', 'list', '--storage-account', $StorageAccountName,
        '--query', "[?name=='$container'] | [0]"
    ) + $groupArgs)
    if (-not $existingContainer) {
        $null = Invoke-AzureCli -Arguments (@(
            'storage', 'container-rm', 'create', '--public-access', 'off'
        ) + $containerArgs)
    }

    $verifiedContainer = Invoke-AzureCli -Arguments (@('storage', 'container-rm', 'show') + $containerArgs)
    if ($verifiedContainer.name -ne $container -or $verifiedContainer.publicAccess -notin @($null, 'None', 'Off')) {
        throw "Could not verify that Terraform state container $container is private. Review it before proceeding."
    }

    $scope = "$($storage.id)/blobServices/default/containers/$container"
    $assignments = Invoke-AzureCli -Arguments (@(
        'role', 'assignment', 'list', '--scope', $scope,
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
}

if ($null -eq $existingPolicy -and $null -eq (Get-LifecyclePolicy -PolicyArgs $policyArgs -Expected $expectedPolicy)) {
    $policyFile = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($policyFile, $policyJson)
        $null = Invoke-AzureCli -Arguments (@(
            'storage', 'account', 'management-policy', 'create', '--policy', "@$policyFile"
        ) + $policyArgs)
    } finally {
        Remove-Item -LiteralPath $policyFile
    }
}

Write-Host "Backends configured: $StorageAccountName ($($containers -join ', ')). Wait for RBAC propagation before Terraform init."

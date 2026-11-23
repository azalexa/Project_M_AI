#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
$bootstrap = Join-Path (Split-Path $PSScriptRoot -Parent) 'Initialize-TerraformState.ps1'
$testState = @{ GroupLocation = 'northeurope'; Policy = $null; ErrorResponse = $null; Calls = @(); Creates = 0 }

function az {
    $global:LASTEXITCODE = 0
    $commandLength = [Array]::FindIndex([object[]]$args, [Predicate[object]]{ param($value) $value -like '--*' })
    $command = $args[0..($commandLength - 1)] -join ' '
    $testState.Calls += $command
    switch ($command) {
        'account show' { '{"name":"Project_M_AI","state":"Enabled","environmentName":"AzureCloud","id":"test-subscription"}' }
        'ad signed-in-user show' { '"test-user"' }
        'group exists' { 'true' }
        'group show' { @{ location = $testState.GroupLocation } | ConvertTo-Json }
        'storage account list' {
            '{"id":"/storage/test","kind":"StorageV2","sku":{"name":"Standard_LRS"},"location":"northeurope","tags":{"workload":"mechmaster-tfstate"},"allowBlobPublicAccess":false,"allowSharedKeyAccess":false,"enableHttpsTrafficOnly":true,"minimumTlsVersion":"TLS1_2","encryption":{"services":{"blob":{"enabled":true}}}}'
        }
        'storage account blob-service-properties show' {
            '{"isVersioningEnabled":true,"deleteRetentionPolicy":{"enabled":true,"days":30},"containerDeleteRetentionPolicy":{"enabled":true,"days":30}}'
        }
        'storage container-rm list' { '{}' }
        'storage container-rm show' {
            @{ name = $args[[Array]::IndexOf($args, '--name') + 1]; publicAccess = 'None' } | ConvertTo-Json
        }
        'role assignment list' {
            @{
                scope = $args[[Array]::IndexOf($args, '--scope') + 1]
                roleDefinitionId = '/roles/ba92f5b4-2d11-453d-a403-e96b0029c9fe'
            } | ConvertTo-Json
        }
        'storage account management-policy show' {
            if ($testState.ErrorResponse -or !$testState.Policy) {
                $global:LASTEXITCODE = 1
                Write-Error -Message $testState.ErrorResponse
                return
            }
            @{ policy = $testState.Policy } | ConvertTo-Json -Depth 10
        }
        'storage account management-policy create' {
            $testState.Creates++
            $policyArg = $args[[Array]::IndexOf($args, '--policy') + 1]
            $testState.Policy = Get-Content -LiteralPath $policyArg.Substring(1) -Raw | ConvertFrom-Json
            '{}'
        }
        default { throw "Unexpected Azure CLI command: $command" }
    }
}

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -cne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-BootstrapFailure([string]$ExpectedMessage) {
    $testState.Calls = @()
    $previousCreates = $testState.Creates
    try {
        & $bootstrap -StorageAccountName testmechmasterstate -Confirm:$false
        throw 'Bootstrap unexpectedly succeeded.'
    } catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") { throw }
    }
    Assert-Equal $testState.Calls[-1] 'storage account management-policy show' 'Bootstrap must stop after the policy read.'
    Assert-Equal $testState.Creates $previousCreates 'Bootstrap must not write another policy.'
}

& $bootstrap -StorageAccountName testmechmasterstate -WhatIf
Assert-Equal ($testState.Calls -join ',') 'account show' 'WhatIf must only read subscription context.'
Write-Host 'PASS: WhatIf makes no Azure writes.'

$testState.Calls = @()
$testState.GroupLocation = 'westeurope'
try {
    & $bootstrap -StorageAccountName testmechmasterstate -Confirm:$false
    throw 'Bootstrap unexpectedly accepted a resource group in the wrong region.'
} catch {
    Assert-Equal $_.Exception.Message "Existing resource group rg-mechmaster-tfstate is in 'westeurope'. Bootstrap requires 'northeurope'." 'Unexpected resource group location error.'
} finally {
    $testState.GroupLocation = 'northeurope'
}
Assert-Equal ($testState.Calls -join ',') 'account show,ad signed-in-user show,group exists,group show' 'Bootstrap must stop before checking or changing storage.'
Write-Host 'PASS: Bootstrap rejects a resource group outside North Europe.'

$missingResponses = [ordered]@{
    'Bare parenthesized code' = '(ManagementPolicyNotFound) Test response.'
    'Prefixed parenthesized code' = 'ERROR: (ManagementPolicyNotFound) Test response.'
    'Code line' = "ERROR: Policy is missing.`nCode: ManagementPolicyNotFound"
    'JSON code' = '{"code":"ManagementPolicyNotFound","message":"Policy is missing."}'
    'Nested JSON error code' = 'ERROR: {"error":{"code":"ManagementPolicyNotFound","message":"Policy is missing."}}'
}
foreach ($entry in $missingResponses.GetEnumerator()) {
    $testState.Policy = $null
    $testState.ErrorResponse = $entry.Value
    $previousCreates = $testState.Creates
    & $bootstrap -StorageAccountName testmechmasterstate -Confirm:$false
    Assert-Equal $testState.Creates ($previousCreates + 1) 'Missing policy must be created once.'
    Write-Host "PASS: $($entry.Key) identifies a missing policy."
}
$testState.ErrorResponse = $null
Assert-Equal $testState.Policy.rules.Count 1 'Expected one lifecycle rule.'
$rule = $testState.Policy.rules[0]
Assert-Equal $rule.enabled $true 'Rule must be enabled.'
Assert-Equal $rule.type 'Lifecycle' 'Unexpected rule type.'
Assert-Equal ($rule.definition.actions.PSObject.Properties.Name -join ',') 'version' 'Only previous versions may be affected.'
Assert-Equal ($rule.definition.actions.version.PSObject.Properties.Name -join ',') 'delete' 'Only deletion is expected.'
Assert-Equal $rule.definition.actions.version.delete.daysAfterCreationGreaterThan 30 'Unexpected version age threshold.'
Assert-Equal ($rule.definition.filters.blobTypes -join ',') 'blockBlob' 'Unexpected blob types.'
Assert-Equal ($rule.definition.filters.prefixMatch -join ',') 'tfstate-shared/,tfstate-dev/,tfstate-prod/' 'Unexpected container prefixes.'
Write-Host 'PASS: Missing policy is created with only the requested previous-version delete action.'

$rule.definition.filters.prefixMatch = @('tfstate-dev/', 'tfstate-prod/', 'tfstate-shared/')
& $bootstrap -StorageAccountName testmechmasterstate -Confirm:$false
Assert-Equal $testState.Creates $missingResponses.Count 'A matching policy must not be written again.'
Write-Host 'PASS: Matching policy is reused even when prefixes are reordered.'

$rule.definition.actions | Add-Member -NotePropertyName baseBlob -NotePropertyValue @{ delete = @{ daysAfterModificationGreaterThan = 30 } }
Assert-BootstrapFailure 'Review it manually'
Write-Host 'PASS: A policy that deletes current blobs stops bootstrap.'

$otherResponses = [ordered]@{
    'Authorization error with a misleading code line' = "ERROR: (AuthorizationFailed) Access denied.`nCode: ManagementPolicyNotFound"
    'Network error mentioning the code' = 'ERROR: Connection timed out while checking ManagementPolicyNotFound.'
    'Subscription error with a nested detail code' = '{"error":{"code":"SubscriptionNotFound","details":[{"code":"ManagementPolicyNotFound"}]}}'
    'Parenthesized code with a suffix' = '(ManagementPolicyNotFoundExtra) Different error.'
    'Code line with a suffix' = 'Code: ManagementPolicyNotFoundExtra'
    'JSON code with a suffix' = '{"error":{"code":"ManagementPolicyNotFoundExtra"}}'
    'Quoted code inside a JSON message' = '{"error":{"code":"ServiceUnavailable","message":"Upstream returned \"code\": \"ManagementPolicyNotFound\"."}}'
    'Malformed JSON' = '{"code":"ManagementPolicyNotFound"'
}
foreach ($entry in $otherResponses.GetEnumerator()) {
    $testState.ErrorResponse = $entry.Value
    Assert-BootstrapFailure 'Azure CLI failed'
    Write-Host "PASS: $($entry.Key) remains a failure."
}

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$StateAccountName
)

$ErrorActionPreference = 'Stop'
$accountJson = az account show --query '{name:name,id:id,state:state,cloud:environmentName}' -o json
if ($LASTEXITCODE) { throw 'Cannot access Azure CLI profile.' }
$account = $accountJson | ConvertFrom-Json
if ($account.name -ne 'Project_M_AI' -or $account.state -ne 'Enabled' -or $account.cloud -ne 'AzureCloud') {
    throw 'Active subscription must be Project_M_AI in AzureCloud.'
}

$repo = Split-Path $PSScriptRoot -Parent
$planDirectory = Join-Path $repo '.local-plans'
[void][IO.Directory]::CreateDirectory($planDirectory)
$previousSubscription = $env:ARM_SUBSCRIPTION_ID
$previousStateAccount = $env:TF_VAR_state_account_name
try {
    $env:ARM_SUBSCRIPTION_ID = $account.id
    $env:TF_VAR_state_account_name = $StateAccountName
    foreach ($name in @('shared','dev','prod')) {
        $root = if ($name -eq 'shared') { Join-Path $repo 'shared' } else { Join-Path $repo "environments/$name" }
        $plan = Join-Path $planDirectory "$name.tfplan"
        terraform "-chdir=$root" init -input=false "-backend-config=storage_account_name=$StateAccountName" "-backend-config=use_cli=true"
        if ($LASTEXITCODE) { throw "Terraform init failed for $name." }
        terraform "-chdir=$root" validate -no-color
        if ($LASTEXITCODE) { throw "Terraform validate failed for $name." }
        terraform "-chdir=$root" plan -input=false -lock-timeout=5m "-out=$plan"
        if ($LASTEXITCODE) { throw "Terraform plan failed for $name." }
    }
} finally {
    $env:ARM_SUBSCRIPTION_ID = $previousSubscription
    $env:TF_VAR_state_account_name = $previousStateAccount
}

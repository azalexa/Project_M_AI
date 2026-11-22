#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Start','Stop')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$context = az account show --query '{name:name,id:id,state:state}' -o json
if ($LASTEXITCODE) { throw 'Cannot read active Azure subscription.' }
$account = $context | ConvertFrom-Json
if ($account.name -ne 'Project_M_AI' -or $account.state -ne 'Enabled') {
    throw 'Select the enabled Project_M_AI subscription.'
}

$group = 'rg-mechmaster-dev'
$raw = az postgres flexible-server list --resource-group $group --subscription $account.id -o json
if ($LASTEXITCODE) { throw 'Cannot list DEV PostgreSQL servers.' }
$servers = @($raw | ConvertFrom-Json | Where-Object {
    $_.name -like 'pg-mechmaster-dev-*' -and $_.tags.project -eq 'mechmaster' -and $_.tags.environment -eq 'dev'
})
if ($servers.Count -ne 1) { throw 'Expected exactly one PostgreSQL server tagged MechMaster DEV.' }

$operation = $Action.ToLowerInvariant()
if ($PSCmdlet.ShouldProcess($servers[0].name, "$Action MechMaster DEV database")) {
    az postgres flexible-server $operation --resource-group $group --name $servers[0].name --subscription $account.id
    if ($LASTEXITCODE) { throw "PostgreSQL DEV operation $operation failed." }
}

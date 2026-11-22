#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory)]
    [string]$EntraUser,

    [Parameter(Mandatory)]
    [string]$RootCertificatePath
)

$ErrorActionPreference = 'Stop'
$null = Get-Command psql -ErrorAction Stop
$certificate = Get-Item -LiteralPath $RootCertificatePath -ErrorAction Stop
if ($certificate.PSIsContainer) { throw 'The root certificate path must point to a file.' }

$context = az account show --query '{name:name,id:id,state:state,cloud:environmentName}' -o json
if ($LASTEXITCODE) { throw 'Unable to read the active Azure CLI subscription.' }
$account = $context | ConvertFrom-Json
if ($account.name -ne 'Project_M_AI' -or $account.state -ne 'Enabled' -or $account.cloud -ne 'AzureCloud') {
    throw 'The active subscription must be Project_M_AI in AzureCloud.'
}

$group = "rg-mechmaster-$Environment"
$serversJson = az postgres flexible-server list --resource-group $group --subscription $account.id -o json
if ($LASTEXITCODE) { throw "Unable to list PostgreSQL servers in $group." }
$servers = @($serversJson | ConvertFrom-Json | Where-Object {
    $_.name -like "pg-mechmaster-$Environment-*" -and $_.tags.project -eq 'mechmaster' -and
    $_.tags.environment -eq $Environment
})
if ($servers.Count -ne 1 -or $servers[0].fullyQualifiedDomainName -notmatch '^[a-z0-9-]+\.postgres\.database\.azure\.com$') {
    throw 'Expected exactly one MechMaster PostgreSQL server with a valid Azure hostname.'
}

$hostname = $servers[0].fullyQualifiedDomainName
if (-not $PSCmdlet.ShouldProcess("$hostname/mechmaster", 'Apply approved database migrations')) { return }

$previousPassword = $env:PGPASSWORD
$previousSslMode = $env:PGSSLMODE
$previousSslRoot = $env:PGSSLROOTCERT
try {
    $token = az account get-access-token --subscription $account.id --resource-type oss-rdbms --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Unable to obtain a Microsoft Entra token for PostgreSQL.' }
    $env:PGPASSWORD = $token
    $env:PGSSLMODE = 'verify-full'
    $env:PGSSLROOTCERT = $certificate.FullName
    $manifest = Join-Path (Split-Path $PSScriptRoot -Parent) 'database/migrate.sql'
    psql --no-psqlrc --no-password --host=$hostname --port=5432 --username=$EntraUser --dbname=mechmaster --single-transaction --file=$manifest
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL migrations failed. Review the database diagnostics.' }
    Write-Host 'PostgreSQL migrations completed.'
} finally {
    $env:PGPASSWORD = $previousPassword
    $env:PGSSLMODE = $previousSslMode
    $env:PGSSLROOTCERT = $previousSslRoot
    Remove-Variable -Name token -ErrorAction SilentlyContinue
}

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$ApiClientId,
    [string]$ApiScope = '',
    [string]$SubscriptionId = '540bb61c-084d-44e0-a96a-59fb5a07bfa9',
    [string]$ResourceGroup = 'rg-mechmaster-dev',
    [string]$FunctionAppName = 'func-mm-api-b80b98b57ede',
    [string]$TenantId = '970b447f-8b34-437d-b665-1f05f66a1cd1',
    [string]$TenantName = 'mechmastercustomers',
    [string]$StorageAccount = 'stmmtdevb80b98b57ede'
)
$ErrorActionPreference = 'Stop'
function Assert-Exit([string]$Description) { if ($LASTEXITCODE -ne 0) { throw "$Description. Kod: $LASTEXITCODE" } }
foreach ($tool in @('az','node','npm','func')) { if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Brak narzedzia $tool. Sprawdz README.md." } }

if (-not $ApiScope) { $ApiScope = "api://$ApiClientId/access_as_user" }
if ($ApiScope -notmatch '^api://[a-zA-Z0-9-]+/access_as_user$') { throw 'Nieprawidlowy format API scope.' }

az account set --subscription $SubscriptionId
Assert-Exit 'Nie mozna wybrac subskrypcji'
az functionapp show --name $FunctionAppName --resource-group $ResourceGroup --query name -o tsv
Assert-Exit 'Function App nie istnieje. Najpierw uruchom skrypt 01'

Write-Host 'Konfiguruje API, bez zadnych hasel ani client secret...'
az functionapp config appsettings set --name $FunctionAppName --resource-group $ResourceGroup --settings "EXTERNAL_TENANT_ID=$TenantId" "EXTERNAL_TENANT_NAME=$TenantName" "API_CLIENT_ID=$ApiClientId" 'API_SCOPE_NAME=access_as_user' "TABLE_STORAGE_URL=https://$StorageAccount.table.core.windows.net" -o none
Assert-Exit 'Nie udalo sie zapisac ustawien Function App'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$apiDir = Join-Path $root 'api'
if (-not (Test-Path (Join-Path $apiDir 'host.json'))) { throw "Brak projektu Azure Functions: $apiDir" }
Push-Location $apiDir
try {
    Write-Host 'Instaluje zaleznosci i uruchamiam testy...'
    npm install --no-audit --no-fund
    Assert-Exit 'npm install'
    npm test
    Assert-Exit 'Testy API nie przeszly'
    Write-Host 'Publikuje Azure Functions...'
    func azure functionapp publish $FunctionAppName
    Assert-Exit 'Publikacja Azure Functions nie powiodla sie'
} finally { Pop-Location }

$apiBaseUrl = "https://$FunctionAppName.azurewebsites.net/api"
Write-Host 'Sprawdzam /health...'
try {
    $health = Invoke-RestMethod -Uri "$apiBaseUrl/health" -Method Get -TimeoutSec 40
    if ($health.status -ne 'ok') { throw 'Nieoczekiwana odpowiedz API.' }
    Write-Host 'Endpoint health odpowiada poprawnie.'
} catch {
    throw "API nie odpowiada na /health. Sprawdz Function App w Azure i logi. Szczegoly: $($_.Exception.Message)"
}

$configFile = Join-Path $root 'frontend/config.js'
if (-not (Test-Path $configFile)) { throw "Brak pliku $configFile. Skopiuj skrypty do katalogu repozytorium." }
$content = Get-Content -Raw -Encoding UTF8 $configFile
if ($content -notmatch "apiBaseUrl\s*:\s*'[^']*'" -or $content -notmatch "apiScope\s*:\s*'[^']*'") { throw 'Nie znaleziono apiBaseUrl / apiScope w frontend/config.js. Niczego nie nadpisano.' }
$content = $content -replace "apiBaseUrl\s*:\s*'[^']*'", "apiBaseUrl: '$apiBaseUrl'"
$content = $content -replace "apiScope\s*:\s*'[^']*'", "apiScope: '$ApiScope'"
$content = $content -replace "authority\s*:\s*'[^']*'", "authority: 'https://$TenantName.ciamlogin.com/$TenantId/'"
Set-Content -Path $configFile -Value $content -Encoding UTF8

# Odswiezenie config.js w CDN/przegladarce bez naruszania obecnego CSS i HTML.
$htmlFile = Join-Path $root 'frontend/index.html'
if (Test-Path $htmlFile) {
    $html = Get-Content -Raw -Encoding UTF8 $htmlFile
    $version = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
    if ($html -match 'config\.js(?:\?v=[a-zA-Z0-9_-]+)?') {
        $html = $html -replace 'config\.js(?:\?v=[a-zA-Z0-9_-]+)?', "config.js?v=api-$version"
        Set-Content -Path $htmlFile -Value $html -Encoding UTF8
    }
}
Write-Host ''
Write-Host "API dziala: $apiBaseUrl"
Write-Host 'Frontend zostal skonfigurowany lokalnie. Aby opublikowac konfiguracje, uruchom:'
Write-Host '  git add frontend/config.js frontend/index.html scripts api'
Write-Host '  git commit -m "Connect MechMaster to Azure API"'
Write-Host '  git push origin main'
Write-Host 'Po zakonczeniu pipeline przetestuj rejestracje, ogloszenia i dwie rozne sesje uzytkownikow.'

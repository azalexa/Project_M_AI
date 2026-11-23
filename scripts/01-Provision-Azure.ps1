[CmdletBinding()]
param(
    [string]$SubscriptionId = '540bb61c-084d-44e0-a96a-59fb5a07bfa9',
    [string]$ResourceGroup = 'rg-mechmaster-dev',
    [string]$StorageAccount = 'stmmtdevb80b98b57ede',
    [string]$FunctionAppName = 'func-mm-api-b80b98b57ede',
    [string]$Region = 'polandcentral'
)
$ErrorActionPreference = 'Stop'
function Assert-Az([string]$Operation) {
    if ($LASTEXITCODE -ne 0) { throw "$Operation. Azure CLI zwrocil kod $LASTEXITCODE." }
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Zainstaluj Azure CLI i zaloguj sie poleceniem az login.' }

az account set --subscription $SubscriptionId
Assert-Az 'Nie udalo sie ustawic subskrypcji Project_M_AI'
$current = az account show --query id -o tsv
Assert-Az 'Nie udalo sie odczytac subskrypcji'
if ($current.Trim() -ne $SubscriptionId) { throw 'Nieprawidlowa subskrypcja Azure.' }

$storageId = az storage account show --resource-group $ResourceGroup --name $StorageAccount --query id -o tsv
Assert-Az 'Nie znaleziono konta Storage w oczekiwanej grupie zasobow'
if (-not $storageId) { throw 'Brak identyfikatora konta Storage.' }
$tableEndpoint = az storage account show --resource-group $ResourceGroup --name $StorageAccount --query primaryEndpoints.table -o tsv
Assert-Az 'Nie mozna odczytac uslugi Table Storage'
if (-not $tableEndpoint) { throw 'To konto Storage nie udostepnia Azure Table Storage.' }

# Dostep uzytkownika do operacji data-plane Table Storage.
$userId = az ad signed-in-user show --query id -o tsv
Assert-Az 'Nie udalo sie znalezc zalogowanego uzytkownika; zaloguj sie do Azure CLI jako wlasciciel subskrypcji'
$roles = az role assignment list --assignee $userId --scope $storageId --include-inherited --query "[?roleDefinitionName=='Storage Table Data Contributor' || roleDefinitionName=='Storage Table Data Owner'].id" -o tsv
Assert-Az 'Nie mozna sprawdzic rol Table Storage'
if (-not $roles) {
    Write-Host 'Nadaje Twojemu kontu Storage Table Data Contributor...'
    az role assignment create --assignee-object-id $userId --assignee-principal-type User --role 'Storage Table Data Contributor' --scope $storageId -o none
    Assert-Az 'Nie udalo sie nadac Twojemu kontu Storage Table Data Contributor'
}

Write-Host 'Tworze tabele ogloszen, odpowiedzi i wiadomosci...'
foreach ($table in @('MechMasterPosts','MechMasterResponses','MechMasterMessages')) {
    az storage table create --account-name $StorageAccount --auth-mode login --name $table -o none
    Assert-Az "Nie udalo sie utworzyc tabeli $table. Jezeli role zostaly dopiero nadane, zaczekaj kilka minut i uruchom skrypt ponownie"
    Write-Host "OK: $table"
}

$existing = az functionapp list --resource-group $ResourceGroup --query "[?name=='$FunctionAppName'].name" -o tsv
Assert-Az 'Nie udalo sie sprawdzic Function App'
if (-not $existing) {
    $available = @(az functionapp list-flexconsumption-locations --query '[].name' -o tsv)
    Assert-Az 'Nie mozna sprawdzic dostepnych regionow Flex Consumption'
    if ($available -notcontains $Region) {
        Write-Host ('Dostepne regiony: ' + ($available -join ', '))
        throw "Flex Consumption niedostepny w regionie $Region. Wybierz swiadomie wspierany region przez parametr -Region."
    }
    Write-Host "Tworze Function App $FunctionAppName w regionie $Region (Flex Consumption, Node.js 22)..."
    az functionapp create --resource-group $ResourceGroup --name $FunctionAppName --storage-account $StorageAccount --flexconsumption-location $Region --runtime node --runtime-version 22 -o none
    Assert-Az 'Nie udalo sie utworzyc Function App'
} else { Write-Host "Function App $FunctionAppName juz istnieje. Nie tworzę ponownie." }

$principalId = az functionapp identity assign --name $FunctionAppName --resource-group $ResourceGroup --query principalId -o tsv
Assert-Az 'Nie udalo sie wlaczyc Managed Identity'
if (-not $principalId) { throw 'Brak principalId Managed Identity.' }

$assigned = az role assignment list --assignee $principalId --scope $storageId --include-inherited --query "[?roleDefinitionName=='Storage Table Data Contributor' || roleDefinitionName=='Storage Table Data Owner'].id" -o tsv
Assert-Az 'Nie mozna sprawdzic roli tozsamosci Function App'
if (-not $assigned) {
    az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role 'Storage Table Data Contributor' --scope $storageId -o none
    Assert-Az 'Nie udalo sie nadac Managed Identity roli Table Data Contributor'
}

$origin = 'https://stmmtdevb80b98b57ede.z16.web.core.windows.net'
az functionapp cors add --name $FunctionAppName --resource-group $ResourceGroup --allowed-origins $origin -o none
Assert-Az 'Nie udalo sie ustawic CORS'

Write-Host ''
Write-Host 'Zasoby Azure przygotowane.'
Write-Host "API: https://$FunctionAppName.azurewebsites.net/api"
Write-Host 'Kolejny krok: zarejestruj MechMaster API w katalogu MechMaster Customers i uruchom skrypt 02 z jego Application (client) ID.'

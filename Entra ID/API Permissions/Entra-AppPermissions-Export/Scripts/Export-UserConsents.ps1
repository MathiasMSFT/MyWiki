param (
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId
)

# ---------------- Helper functions ----------------
function Parse-JWTtoken {
    [cmdletbinding()]
    param([Parameter(Mandatory=$true)][string]$token)
    if (!$token.Contains(".") -or !$token.StartsWith("eyJ")) { Write-Error "Invalid token" -ErrorAction Stop }
    $tokenPayload = $token.Split(".")[1].Replace('-', '+').Replace('_', '/')
    while ($tokenPayload.Length % 4) { $tokenPayload += "=" }
    $tokenByteArray = [System.Convert]::FromBase64String($tokenPayload)
    $tokenArray = [System.Text.Encoding]::ASCII.GetString($tokenByteArray)
    $tokobj = $tokenArray | ConvertFrom-Json
    return $tokobj
}

$ErrorActionPreference = "Stop"

# Connexion Graph
# ---------------- Modules & Auth ----------------
$moduleName = "MSAL.PS"
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    try { Install-Module -Name $moduleName -Scope CurrentUser -Force } catch { Write-Warning "Failed to install MSAL.PS: $_" }
}

# ---- Get token (update these values before running) ----
$tenantId = "identityms.onmicrosoft.com"
$AppClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"

$MsalParams = @{
    ClientId = $AppClientId
    TenantId = $tenantId
    Scopes = 'https://graph.microsoft.com/.default'
}
try {
    $MsalResponse = Get-MsalToken @MsalParams
    $Token = $MsalResponse.AccessToken
    $authHeader = @{ 'Authorization' = "Bearer $Token" }
} catch { Write-Error "Failed to obtain token: $_"; return }

$tokenobj = Parse-JWTtoken $Token

# ---------------- Build list of oauth2PermissionGrants ----------------
$uri = "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$top=999"
$grants = @()

do {
    $resp = Invoke-WebRequest -Method GET -Uri $uri -Headers $authHeader -ErrorAction Stop -Verbose:$false
    $json = $resp.Content | ConvertFrom-Json
    $grants += $json.value
    $uri = $json.'@odata.nextLink'
} while ($uri)

# Initialise la collection des permissions
$userConsents = @()

# --- Préparer les maps nécessaires pour enrichir les grants ---
# Récupérer les service principals (paginé) pour construire les maps
$SPs = @()
$spUri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$top=999&`$select=id,appId,displayName,oauth2PermissionScopes"
try {
    do {
        $r = Invoke-WebRequest -Method Get -Uri $spUri -Headers $authHeader -ErrorAction Stop -Verbose:$false
        $json = $r.Content | ConvertFrom-Json
        $SPs += $json.value
        $spUri = $json.'@odata.nextLink'
    } while ($spUri)
} catch {
    Write-Warning "Failed to fetch service principals for mapping: $_"
}

# Construire deux maps :
# - $appByAppId keyed by servicePrincipal.objectId -> object (id, appId, displayName)
# - $delegatedPermissionMap keyed by "ResourceSpId|scopeValue" -> scopeId (GUID)
$appByAppId = @{}
$delegatedPermissionMap = @{}

foreach ($sp in ($SPs ?? @())) {
    $appByAppId[$sp.id] = @{
        Id = $sp.id
        AppId = $sp.appId
        DisplayName = $sp.displayName
    }

    foreach ($s in ($sp.oauth2PermissionScopes ?? @())) {
        if ($s.Value) {
            $k = "$($sp.id)|$($s.Value)"
            if (-not $delegatedPermissionMap.ContainsKey($k)) {
                $delegatedPermissionMap[$k] = $s.Id
            }
        }
    }
}

Write-Host "Mapping ready: service principals fetched="$($SPs.Count) " delegated scopes mapped="$($delegatedPermissionMap.Count)

foreach ($g in $grants | Where-Object { $_.consentType -eq "Principal" }) {
    if (-not $appByAppId.ContainsKey($g.clientId)) {
        continue
    }
    $app = $appByAppId[$g.clientId]
    foreach ($scope in ($g.scope -split " ")) {
        $key = "$($g.resourceId)|$scope"
        if (-not $delegatedPermissionMap.ContainsKey($key)) {
            continue
        }
        $userConsents += [PSCustomObject]@{
            AppObjectId        = $app.id
            AppId              = $app.appId
            UserId             = $g.principalId
            PermissionId       = $delegatedPermissionMap[$key]
        }
    }
}

$userConsents |
    Export-Csv `
        -Path "../data/UserConsents.csv" `
        -NoTypeInformation `
        -Encoding UTF8

Write-Host "User consents collected:" $userConsents.Count

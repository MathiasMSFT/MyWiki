param (
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [switch]$IncludeBuiltin = $false
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

# ---------------- Build list of service principals ----------------
$SPs = @()
if ($IncludeBuiltin) { $uri = "https://graph.microsoft.com/beta/servicePrincipals?`$top=999&`$select=appDisplayName,appId,appOwnerOrganizationId,displayName,id,servicePrincipalType,createdDateTime,AccountEnabled,passwordCredentials,keyCredentials,tokenEncryptionKeyId,verifiedPublisher,Homepage,PublisherName,tags,customSecurityAttributes,Oauth2PermissionScopes,AppRoles" }
else { $uri = "https://graph.microsoft.com/beta/servicePrincipals?`$top=999&`$filter=tags/any(t:t eq 'WindowsAzureActiveDirectoryIntegratedApp')&`$select=appDisplayName,appId,appOwnerOrganizationId,displayName,id,servicePrincipalType,createdDateTime,AccountEnabled,passwordCredentials,keyCredentials,tokenEncryptionKeyId,verifiedPublisher,Homepage,PublisherName,tags,customSecurityAttributes,Oauth2PermissionScopes,AppRoles" }

try {
    do {
        $result = Invoke-WebRequest -Method Get -Uri $uri -Headers $authHeader -ErrorAction Stop -Verbose:$false
        $uri = ($result.Content | ConvertFrom-Json).'@odata.nextLink'
        Start-Sleep -Milliseconds 200
        $SPs += ($result.Content | ConvertFrom-Json).Value
    } while ($uri)
} catch { Write-Error "Failed to retrieve service principals: $_"; return }
# Index des Service Principals par AppId
$spByAppId = @{}
foreach ($sp in $SPs) {
    if ($sp.AppId) {
        $spByAppId[$sp.AppId] = $sp
    }
}

# ---------------- Build list of applications ----------------
$ARs = @()
if ($IncludeBuiltin) { $uri = "https://graph.microsoft.com/beta/applications?`$top=999&`$select=appDisplayName,appId,appOwnerOrganizationId,displayName,id,servicePrincipalType,createdDateTime,AccountEnabled,passwordCredentials,keyCredentials,tokenEncryptionKeyId,verifiedPublisher,Homepage,PublisherName,tags,customSecurityAttributes,Oauth2PermissionScopes,AppRoles" }
else { $uri = "https://graph.microsoft.com/beta/applications?`$top=999&`$filter=tags/any(t:t eq 'WindowsAzureActiveDirectoryIntegratedApp')&`$select=appDisplayName,appId,appOwnerOrganizationId,displayName,id,servicePrincipalType,createdDateTime,AccountEnabled,passwordCredentials,keyCredentials,tokenEncryptionKeyId,verifiedPublisher,Homepage,PublisherName,tags,customSecurityAttributes,Oauth2PermissionScopes,AppRoles" }

try {
    do {
        $result = Invoke-WebRequest -Method Get -Uri $uri -Headers $authHeader -ErrorAction Stop -Verbose:$false
        $uri = ($result.Content | ConvertFrom-Json).'@odata.nextLink'
        Start-Sleep -Milliseconds 200
        $ARs += ($result.Content | ConvertFrom-Json).Value
    } while ($uri)
} catch { Write-Error "Failed to retrieve applications: $_"; return }
# Index des Applications par AppId
$arByAppId = @{}
foreach ($ar in $ARs) {
    if ($ar.AppId) {
        $arByAppId[$ar.AppId] = $ar
    }
}
# Rendre compatible l'usage ultérieur : nom attendu $applications
$applications = $ARs

# ------------------------------------------------
# A. Application permissions (App roles)
# ------------------------------------------------
$appPermissions = @()
foreach ($app in $applications) {

    if (-not $spByAppId.ContainsKey($app.AppId)) {
        continue
    }

    $sp = $spByAppId[$app.AppId]


    $uri = "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.Id)/appRoleAssignments?`$top=999"
    $result = Invoke-WebRequest -Method Get -Uri $uri -Headers $authHeader -ErrorAction Stop -Verbose:$false
    $data = ($result.Content | ConvertFrom-Json)
    $assignments = $data.value
    # $assignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All

    foreach ($a in $assignments) {
        $appPermissions += [PSCustomObject]@{
            AppObjectId   = $app.Id
            AppId         = $app.AppId
            ResourceAppId = $a.ResourceAppId
            PermissionId  = $a.AppRoleId
            PermissionType= "Application"
            ConsentType   = "Admin"
        }
    }
}

# ------------------------------------------------
# B. Delegated permissions (OAuth2 grants)
# ------------------------------------------------

$uri = "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$top=999"
$grants = @()

do {
    $resp = Invoke-WebRequest -Method GET -Uri $uri -Headers $authHeader -ErrorAction Stop -Verbose:$false
    $json = $resp.Content | ConvertFrom-Json
    $grants += $json.value
    $uri = $json.'@odata.nextLink'
} while ($uri)


<# # $grants = Get-MgOauth2PermissionGrant -All
foreach ($g in $grants) {

    if (-not $spByAppId.ContainsKey($g.ClientId)) {
        continue
    }

    $sp = $spByAppId[$g.ClientId]

    $app = $applications | Where-Object { $_.AppId -eq $g.ClientId }

    $consent = if ($g.ConsentType -eq "AllPrincipals") { "Admin" } else { "User" }

    foreach ($scope in ($g.Scope -split " ")) {
        $appPermissions += [PSCustomObject]@{
            AppObjectId   = $app.Id
            AppId         = $app.AppId
            ResourceAppId = $g.ResourceId
            PermissionId  = $scope
            PermissionType= "Delegated"
            ConsentType   = $consent
        }
    }
}#>

$grantsExpanded = foreach ($g in $grants) {
    foreach ($s in (($g.scope ?? "") -split " ")) {
        if (-not [string]::IsNullOrWhiteSpace($s)) {
            [pscustomobject]@{
                GrantId        = $g.id
                ClientSpId     = $g.clientId
                ResourceSpId   = $g.resourceId
                PrincipalId    = $g.principalId
                PermissionName = $s              # scope délégué
                ConsentType    = if ($g.consentType -eq "AllPrincipals") { "Admin" } else { "User" }
                CreatedDateTime= $g.createdDateTime
                       }
        }
    }
}

# Récupération des SP pour mapping
# --- Construire spMap complet à partir de la liste $SPs (déjà récupérée) ---
$spMap = @{}
foreach ($sp in ($SPs ?? @())) {
    $scopeMap = @{}
    foreach ($s in ($sp.oauth2PermissionScopes ?? $sp.Oauth2PermissionScopes ?? @())) {
        # s.Value = "User.Read", s.Id = GUID
        try { $scopeMap[$s.Value] = $s.Id } catch {}
    }
    $roleMap = @{}
    foreach ($r in ($sp.appRoles ?? @())) {
        try { $roleMap[$r.Value] = $r.Id } catch {}
    }

    $spMap[$sp.id] = @{
        AppId = $sp.appId
        DisplayName = $sp.displayName
        Scopes = $scopeMap
        AppRoles = $roleMap
    }
}

# --- Enrichir grantsExpanded -> grantsEnriched (conserver tel quel si déjà fait) ---
# (je suppose que $grantsExpanded existe comme dans votre script)

$grantsEnriched = foreach ($r in ($grantsExpanded ?? @())) {
    $res = $spMap[$r.ResourceSpId]
    [pscustomobject]@{
        GrantId            = $r.GrantId
        ClientSpId         = $r.ClientSpId
        ResourceSpId       = $r.ResourceSpId
        ResourceAppId      = $res?.AppId
        ResourceDisplayName= $res?.DisplayName
        PrincipalId        = $r.PrincipalId
        PermissionName     = $r.PermissionName
        ConsentType        = $r.ConsentType
        CreatedDateTime    = $r.CreatedDateTime
    }
}

# --- Ajouter les grants délégués dans $appPermissions en remplissant AppId/ResourceAppId/PermissionId si possible ---
foreach ($r in ($grantsEnriched ?? @())) {
    $clientObjectId = $r.ClientSpId
    $clientAppId = $null
    if ($clientObjectId -and $spMap.ContainsKey($clientObjectId)) { $clientAppId = $spMap[$clientObjectId].AppId }

    $resourceAppId = $r.ResourceAppId
    $permissionId = $null

    # si on a resource SP mapping, tenter de retrouver l'ID de la scope
    if ($r.ResourceSpId -and $spMap.ContainsKey($r.ResourceSpId)) {
        $resourceAppId = $spMap[$r.ResourceSpId].AppId
        $scopeDict = $spMap[$r.ResourceSpId].Scopes
        if ($scopeDict -and $scopeDict.ContainsKey($r.PermissionName)) {
            $permissionId = $scopeDict[$r.PermissionName]
        }
    }

    $appPermissions += [PSCustomObject]@{
        AppObjectId     = $clientObjectId
        AppId           = $clientAppId
        ResourceAppId   = $resourceAppId
        PermissionId    = $permissionId
        PermissionName  = $r.PermissionName
        PermissionType  = "Delegated"
        ConsentType     = $r.ConsentType
        CreatedDateTime = $r.CreatedDateTime
    }
}

Write-Host "App permissions collected:" $appPermissions.Count

# Export CSV
$appPermissions | Export-Csv `
    -Path "../data/AppPermissions.csv" `
    -NoTypeInformation `
    -Encoding UTF8

Write-Host "AppPermissions.csv generated successfully"

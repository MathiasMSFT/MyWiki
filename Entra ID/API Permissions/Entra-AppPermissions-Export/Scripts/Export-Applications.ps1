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

# ---------------- Build list of service principals ----------------
$SPs = @()
if ($IncludeBuiltin) { $uri = "https://graph.microsoft.com/beta/servicePrincipals?`$top=999&`$select=appDisplayName,appId,appOwnerOrganizationId,displayName,id,servicePrincipalType,createdDateTime,AccountEnabled,passwordCredentials,keyCredentials,tokenEncryptionKeyId,verifiedPublisher,Homepage,PublisherName,tags,customSecurityAttributes" }
else { $uri = "https://graph.microsoft.com/beta/servicePrincipals?`$top=999&`$filter=tags/any(t:t eq 'WindowsAzureActiveDirectoryIntegratedApp')&`$select=appDisplayName,appId,appOwnerOrganizationId,displayName,id,servicePrincipalType,createdDateTime,AccountEnabled,passwordCredentials,keyCredentials,tokenEncryptionKeyId,verifiedPublisher,Homepage,PublisherName,tags,customSecurityAttributes" }

try {
    do {
        $result = Invoke-WebRequest -Method Get -Uri $uri -Headers $authHeader -ErrorAction Stop -Verbose:$false
        $uri = ($result.Content | ConvertFrom-Json).'@odata.nextLink'
        Start-Sleep -Milliseconds 200
        $SPs += ($result.Content | ConvertFrom-Json).Value
    } while ($uri)
} catch { Write-Error "Failed to retrieve service principals: $_"; return }

Write-Host "Applications retrieved:" $SPs.Count

# Projection vers le modèle cible
$export = $SPs | Select-Object `
    @{ Name = "AppObjectId"; Expression = { $_.Id } },
    @{ Name = "AppId"; Expression = { $_.AppId } },
    @{ Name = "DisplayName"; Expression = { $_.DisplayName } },
    @{ Name = "Publisher"; Expression = { $_.PublisherDomain } },
    @{ Name = "SignInAudience"; Expression = { $_.SignInAudience } },
    @{ Name = "CreatedDateTime"; Expression = { $_.CreatedDateTime } },
    @{ Name = "Disabled"; Expression = { -not $_.AccountEnabled } }

# Export CSV
$export | Export-Csv `
    -Path "../data/Applications.csv" `
    -NoTypeInformation `
    -Encoding UTF8

Write-Host "Applications.csv generated successfully"

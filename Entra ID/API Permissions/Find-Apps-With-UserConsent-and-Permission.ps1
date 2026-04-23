param(
    [Parameter(Mandatory=$true)][string]$Permission,
    [ValidateSet("Contains","Exact")][string]$MatchMode = "Contains",
    [ValidateSet("All","Delegated","Application")][string]$PermissionType = "All",
    [string]$InputCsvPath = "GraphAppInventory.csv",
    [string]$OutputCsvPath = "Results\Apps_With_UserConsent_and_Permission.csv",
    [switch]$RequireUserConsent = $true
)

function Is-UserConsent {
    param([string]$consentedBy)
    if (-not $consentedBy) { return $false }
    # common admin markers
    if ($consentedBy -match "(?i)all users|administrator|admin|application") { return $false }
    # email-like -> user consent
    if ($consentedBy -match "[\w\.\-]+@[\w\.\-]+") { return $true }
    # fallback: treat short non-admin tokens as user consent
    return ($consentedBy.Length -gt 0 -and $consentedBy -notmatch "(?i)admin|administrator|all users|application")
}

if (-not (Test-Path $InputCsvPath)) {
    Write-Error "Input CSV introuvable: $InputCsvPath"
    exit 1
}

$rows = Import-Csv -Path $InputCsvPath

<#
# normalize column names (tolérance)
$normRows = $rows | ForEach-Object {
    [PSCustomObject]@{
        ApplicationId   = ($_.'ApplicationId'      -or $_.ApplicationId -or $_.AppId -or $_.AppId)
        ApplicationName = ($_.'ApplicationName'    -or $_.ApplicationName -or $_.'Application Name' -or $_.ApplicationName)
        Permission      = ($_.'Permission'         -or $_.PermissionName -or $_.Scope -or "")
        PermissionType  = ($_.'PermissionType'     -or $_.Type -or "")
        ConsentedBy     = ($_.'ConsentedBy'        -or $_.'Authorized By - delegate' -or $_.ConsentedBy -or "")
        AppKey          = if (($_.'ApplicationId' -and $_.'ApplicationId'.Trim()) -ne "") { $_.'ApplicationId' } elseif (($_.'AppId' -and $_.'AppId'.Trim()) -ne "") { $_.'AppId' } else { $_.'ApplicationId' -or $_.'AppId' -or $_.'ObjectId' }
    }
}#>
# normalize using the actual column names you have: ConsentedBy, Permission, SPName
$normRows = $rows | ForEach-Object {
    [PSCustomObject]@{
        ApplicationId   = ( $_.'ApplicationId' -or $_.AppId -or $_.AppId -or $_.ObjectId -or $null )
        ApplicationName = ( $_.'SPName' -or $_.'SP Name' -or $_.'ApplicationName' -or $_.'AppDisplayName' -or $null )
        Permission      = ( $_.'Permission' -or $_.'PermissionName' -or $_.'Scope' -or "" )
        PermissionType  = ( $_.'PermissionType' -or $_.'Type' -or "" )
        ConsentedBy     = ( $_.'ConsentedBy' -or $_.'Authorized By - delegate' -or $_.'AuthorizedBy' -or "" )
        AppKey          = if ((($_.'ApplicationId' -or $_.AppId -or $_.ObjectId) -and (($_.'ApplicationId' -or $_.AppId -or $_.ObjectId).ToString().Trim() -ne ""))) { ($_.ApplicationId -or $_.AppId -or $_.ObjectId) } else { ($_.SPName -or $_.'SP Name' -or $_.'ApplicationName' -or $_.'AppDisplayName') }
    }
}

# filter by permission (safe string coercion)
$filtered = $normRows | Where-Object {
    $p = [string]($_.Permission)
    if (-not $p) { return $false }
    if ($MatchMode -eq "Contains") {
        return $p.ToLower().Contains($Permission.ToLower())
    } else {
        return $p -ieq $Permission
    }
}

# filter by permission type if requested
if ($PermissionType -ne "All") {
    $filtered = $filtered | Where-Object { $_.PermissionType -and $_.PermissionType -ieq $PermissionType }
}

# group by app and check consents
$apps = @{}
foreach ($r in $filtered) {
    $key = $r.AppKey
    if (-not $key) { continue }
    if (-not $apps.ContainsKey($key)) {
        $apps[$key] = [PSCustomObject]@{
            AppKey = $key
            ApplicationId = $r.ApplicationId
            ApplicationName = $r.ApplicationName
            PermissionMatches = [System.Collections.Generic.HashSet[string]]::new()
            UserConsentingUpns = [System.Collections.Generic.HashSet[string]]::new()
            AdminConsented = $false
        }
    }
    $apps[$key].PermissionMatches.Add($r.Permission) | Out-Null

    <#
    $cons = $r.ConsentedBy
    if (Is-UserConsent -consentedBy $cons) {
        # extract emails if several (comma/; separated)
        $items = ($cons -split "[,;]" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        foreach ($it in $items) {
            if ($it -match "[\w\.\-]+@[\w\.\-]+") { $apps[$key].UserConsentingUpns.Add($it) | Out-Null }
            else { $apps[$key].UserConsentingUpns.Add($it) | Out-Null }
        }
    } else {
        if ($cons) { $apps[$key].AdminConsented = $true }
    }#>
    $cons = $r.ConsentedBy
    if ($cons) { $cons = $cons.ToString().Trim() }

    # if explicit user(s) (email-like) -> record user consent
    if ($cons -and (Is-UserConsent -consentedBy $cons)) {
        $items = ($cons -split "[,;]" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        foreach ($it in $items) {
            # add upn or token (we keep it as-is)
            $apps[$key].UserConsentingUpns.Add($it) | Out-Null
        }

    # if explicit admin marker -> mark admin consent
    } elseif ($cons -and ($cons -match "(?i)\b(all users|administrator|admin|application)\b")) {
        $apps[$key].AdminConsented = $true

    # otherwise ignore boolean flags like "True"/"False" or empty values
    } else {
        # no-op: do not mark AdminConsented just because a boolean flag exists
    }
}

# select apps that meet the user-consent requirement
$result = [System.Collections.Generic.List[Object]]::new()
foreach ($kv in $apps.GetEnumerator()) {
    $obj = $kv.Value
    if ($RequireUserConsent) {
        if ($obj.UserConsentingUpns.Count -gt 0) {
            $result.Add([PSCustomObject]@{
                AppKey = $obj.AppKey
                ApplicationId = $obj.ApplicationId
                ApplicationName = $obj.ApplicationName
                PermissionsMatched = ( ($obj.PermissionMatches | Sort-Object) -join ";")
                UserConsenting = ( ($obj.UserConsentingUpns | Sort-Object) -join ";")
                AdminConsented = $obj.AdminConsented
            }) | Out-Null
        }
    } else {
        # include apps with either user or admin consent
        if ($obj.UserConsentingUpns.Count -gt 0 -or $obj.AdminConsented) {
            $result.Add([PSCustomObject]@{
                AppKey = $obj.AppKey
                ApplicationId = $obj.ApplicationId
                ApplicationName = $obj.ApplicationName
                PermissionsMatched = (($obj.PermissionMatches | Sort-Object) -join ";")
                UserConsenting = (($obj.UserConsentingUpns | Sort-Object) -join ";")
                AdminConsented = $obj.AdminConsented
            }) | Out-Null
        }
    }
}

# ensure output dir
$outDir = Split-Path -Path $OutputCsvPath -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$result | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
Write-Host "Exporté $($result.Count) applications vers: $OutputCsvPath"

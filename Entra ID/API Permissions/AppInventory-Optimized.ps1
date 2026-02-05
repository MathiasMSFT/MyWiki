#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
Param(
    [string]$TenantId,
    [switch]$IncludeBuiltin = $false,
    [switch]$ExportCsv = $false,
    [string]$ExportCsvPath,
    [int]$ThrottleLimit = 10
)

# ---------------- Helper functions ----------------

function Parse-AppPermissions {
    Param(
        [Parameter(Mandatory = $true)]$appRoleAssignments,
        [Parameter(Mandatory = $true)][ref]$OAuthperm
    )

    foreach ($appRoleAssignment in $appRoleAssignments) {
        $resID = $appRoleAssignment.ResourceDisplayName
        $roleObj = $script:SPPermCache[$appRoleAssignment.resourceId]
        $roleID = $null
        if ($roleObj -and $roleObj.appRoles) {
            $roleID = ($roleObj.appRoles | Where-Object { $_.id -eq $appRoleAssignment.appRoleId } | Select-Object -ExpandProperty Value -ErrorAction SilentlyContinue)
        }
        if (-not $roleID) { $roleID = "Orphaned ($($appRoleAssignment.appRoleId))" }
        $key = "[$resID]"
        if (-not $OAuthperm.Value.ContainsKey($key)) { $OAuthperm.Value[$key] = "" }
        $OAuthperm.Value[$key] += "," + $roleID
    }
}

function Parse-DelegatePermissions {
    Param(
        [Parameter(Mandatory = $true)]$oauth2PermissionGrants,
        [Parameter(Mandatory = $true)][ref]$OAuthperm
    )

    foreach ($oauth2PermissionGrant in $oauth2PermissionGrants) {
        $resSP = $script:SPPermCache[$oauth2PermissionGrant.ResourceId]
        $resID = if ($resSP) {
            if ($resSP.appDisplayName) { $resSP.appDisplayName }
            elseif ($resSP.displayName) { $resSP.displayName }
            else { $oauth2PermissionGrant.ResourceId }
        }
        else { $oauth2PermissionGrant.ResourceId }

        if ($null -ne $oauth2PermissionGrant.PrincipalId) {
            $userId = "(" + ($script:UserCache[$oauth2PermissionGrant.principalId] ?? $oauth2PermissionGrant.principalId) + ")"
        }
        else { $userId = $null }

        if ($oauth2PermissionGrant.Scope) {
            $scopes = ($oauth2PermissionGrant.Scope.Split(" ") -join ",")
        }
        else { $scopes = "Orphaned scope" }

        $key = "[$resID$userId]"
        if (-not $OAuthperm.Value.ContainsKey($key)) { $OAuthperm.Value[$key] = "" }
        $OAuthperm.Value[$key] += "," + $scopes
    }
}

function Invoke-GraphRequestWithRetry {
    Param(
        [string]$Uri,
        [hashtable]$Headers,
        [int]$MaxRetries = 3
    )
    
    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            return Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -ErrorAction Stop
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq 429) {
                $retryAfter = $_.Exception.Response.Headers['Retry-After']
                $waitTime = if ($retryAfter) { [int]$retryAfter } else { [math]::Pow(2, $retryCount) * 5 }
                Write-Verbose "Throttled. Waiting $waitTime seconds..."
                Start-Sleep -Seconds $waitTime
                $retryCount++
            }
            else {
                throw
            }
        }
    }
}

function Get-AllGraphResults {
    Param(
        [string]$Uri,
        [hashtable]$Headers
    )
    
    $results = @()
    do {
        $response = Invoke-GraphRequestWithRetry -Uri $Uri -Headers $Headers
        if ($response.value) { $results += $response.value }
        $Uri = $response.'@odata.nextLink'
    } while ($Uri)
    return $results
}

# ---------------- Modules & Auth ----------------
$moduleName = "MSAL.PS"
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    try { Install-Module -Name $moduleName -Scope CurrentUser -Force } catch { Write-Warning "Failed to install MSAL.PS: $_" }
}

$AppClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"

$MsalParams = @{
    ClientId = $AppClientId
    TenantId = $tenantId
    Scopes   = 'https://graph.microsoft.com/.default'
}
try {
    $MsalResponse = Get-MsalToken @MsalParams
    $Token = $MsalResponse.AccessToken
    $authHeader = @{ 'Authorization' = "Bearer $Token" }
}
catch { Write-Error "Failed to obtain token: $_"; return }

# ---------------- Pre-fetch all data in bulk ----------------
Write-Host "Fetching all service principals..." -ForegroundColor Cyan

# Initialize caches
$script:SPPermCache = @{}
$script:UserCache = @{}

# Fetch ALL service principals first (we need them for permission resolution anyway)
$AllSPs = Get-AllGraphResults -Uri "https://graph.microsoft.com/beta/servicePrincipals?`$top=999&`$select=appDisplayName,appId,appOwnerOrganizationId,displayName,id,servicePrincipalType,createdDateTime,AccountEnabled,passwordCredentials,keyCredentials,tokenEncryptionKeyId,verifiedPublisher,Homepage,PublisherName,tags,appRoles" -Headers $authHeader

# Build SP cache for permission resolution
foreach ($sp in $AllSPs) {
    $script:SPPermCache[$sp.id] = $sp
}

Write-Host "Found $($AllSPs.Count) total service principals" -ForegroundColor Green

# Filter for processing based on IncludeBuiltin
if ($IncludeBuiltin) {
    $SPs = $AllSPs
}
else {
    $SPs = $AllSPs | Where-Object { $_.tags -contains "WindowsAzureActiveDirectoryIntegratedApp" }
}

Write-Host "Processing $($SPs.Count) service principals..." -ForegroundColor Cyan

# Bulk fetch ALL oauth2PermissionGrants (much faster than per-SP queries)
Write-Host "Fetching all OAuth2 permission grants..." -ForegroundColor Cyan
$AllOAuth2Grants = Get-AllGraphResults -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$top=999" -Headers $authHeader

# Index grants by clientId for fast lookup
$OAuth2GrantsByClient = @{}
$OAuth2GrantsByResource = @{}
foreach ($grant in $AllOAuth2Grants) {
    if (-not $OAuth2GrantsByClient[$grant.clientId]) { $OAuth2GrantsByClient[$grant.clientId] = @() }
    $OAuth2GrantsByClient[$grant.clientId] += $grant
    
    if (-not $OAuth2GrantsByResource[$grant.resourceId]) { $OAuth2GrantsByResource[$grant.resourceId] = @() }
    $OAuth2GrantsByResource[$grant.resourceId] += $grant
}

# Collect unique user IDs for bulk fetch
$userIds = ($AllOAuth2Grants | Where-Object { $_.principalId } | Select-Object -ExpandProperty principalId -Unique)
if ($userIds.Count -gt 0) {
    Write-Host "Fetching $($userIds.Count) users..." -ForegroundColor Cyan
    
    # Batch fetch users (up to 15 per batch to stay under URL length limits)
    $batchSize = 15
    for ($i = 0; $i -lt $userIds.Count; $i += $batchSize) {
        $batch = $userIds[$i..[math]::Min($i + $batchSize - 1, $userIds.Count - 1)]
        $filter = ($batch | ForEach-Object { "id eq '$_'" }) -join " or "
        try {
            $users = Get-AllGraphResults -Uri "https://graph.microsoft.com/v1.0/users?`$filter=$filter&`$select=id,userPrincipalName" -Headers $authHeader
            foreach ($u in $users) {
                $script:UserCache[$u.id] = $u.userPrincipalName
            }
        }
        catch { }
    }
}

# Bulk fetch all appRoleAssignments using batch requests
Write-Host "Fetching app role assignments..." -ForegroundColor Cyan
$AppRoleAssignmentsBySP = @{}

# Process in batches of 20 (Graph batch limit)
$batchSize = 20
$spIds = $SPs.id
$totalBatches = [math]::Ceiling($spIds.Count / $batchSize)

for ($batchNum = 0; $batchNum -lt $totalBatches; $batchNum++) {
    $startIdx = $batchNum * $batchSize
    $endIdx = [math]::Min($startIdx + $batchSize - 1, $spIds.Count - 1)
    $batchSpIds = $spIds[$startIdx..$endIdx]
    
    $requests = @()
    foreach ($spId in $batchSpIds) {
        $requests += @{
            id     = $spId
            method = "GET"
            url    = "/servicePrincipals/$spId/appRoleAssignments?`$top=999"
        }
    }
    
    $batchBody = @{ requests = $requests } | ConvertTo-Json -Depth 10
    
    try {
        $batchResponse = Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/v1.0/`$batch" -Headers $authHeader -Body $batchBody -ContentType "application/json"
        
        foreach ($response in $batchResponse.responses) {
            if ($response.status -eq 200 -and $response.body.value) {
                $AppRoleAssignmentsBySP[$response.id] = $response.body.value
            }
        }
    }
    catch {
        Write-Warning "Batch request failed: $_"
    }
    
    # Progress indicator
    if ($batchNum % 10 -eq 0) {
        Write-Progress -Activity "Fetching app role assignments" -Status "Batch $($batchNum + 1) of $totalBatches" -PercentComplete (($batchNum + 1) / $totalBatches * 100)
    }
}
Write-Progress -Activity "Fetching app role assignments" -Completed

# Bulk fetch owners using batch requests
Write-Host "Fetching owners..." -ForegroundColor Cyan
$OwnersBySP = @{}

for ($batchNum = 0; $batchNum -lt $totalBatches; $batchNum++) {
    $startIdx = $batchNum * $batchSize
    $endIdx = [math]::Min($startIdx + $batchSize - 1, $spIds.Count - 1)
    $batchSpIds = $spIds[$startIdx..$endIdx]
    
    $requests = @()
    foreach ($spId in $batchSpIds) {
        $requests += @{
            id     = $spId
            method = "GET"
            url    = "/servicePrincipals/$spId/owners?`$select=id,userPrincipalName&`$top=999"
        }
    }
    
    $batchBody = @{ requests = $requests } | ConvertTo-Json -Depth 10
    
    try {
        $batchResponse = Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/v1.0/`$batch" -Headers $authHeader -Body $batchBody -ContentType "application/json"
        
        foreach ($response in $batchResponse.responses) {
            if ($response.status -eq 200 -and $response.body.value) {
                $OwnersBySP[$response.id] = $response.body.value | ForEach-Object { $_.userPrincipalName }
            }
        }
    }
    catch { }
}

# Bulk fetch memberOf using batch requests
Write-Host "Fetching group/role memberships..." -ForegroundColor Cyan
$MemberOfBySP = @{}

for ($batchNum = 0; $batchNum -lt $totalBatches; $batchNum++) {
    $startIdx = $batchNum * $batchSize
    $endIdx = [math]::Min($startIdx + $batchSize - 1, $spIds.Count - 1)
    $batchSpIds = $spIds[$startIdx..$endIdx]
    
    $requests = @()
    foreach ($spId in $batchSpIds) {
        $requests += @{
            id     = $spId
            method = "GET"
            url    = "/servicePrincipals/$spId/memberOf?`$select=id,displayName&`$top=999"
        }
    }
    
    $batchBody = @{ requests = $requests } | ConvertTo-Json -Depth 10
    
    try {
        $batchResponse = Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/v1.0/`$batch" -Headers $authHeader -Body $batchBody -ContentType "application/json"
        
        foreach ($response in $batchResponse.responses) {
            if ($response.status -eq 200 -and $response.body.value) {
                $MemberOfBySP[$response.id] = $response.body.value
            }
        }
    }
    catch { }
}

# ---------------- Iterate and build output ----------------
Write-Host "Building output..." -ForegroundColor Cyan
$output = [System.Collections.Generic.List[Object]]::new()
$expanded = [System.Collections.Generic.List[Object]]::new()
$i = 0

foreach ($SP in $SPs) {
    $i++
    
    if ($i % 100 -eq 0) {
        Write-Progress -Activity "Processing service principals" -Status "$i of $($SPs.Count)" -PercentComplete ($i / $SPs.Count * 100)
    }

    # Get pre-fetched data
    $owners = $OwnersBySP[$SP.id]
    $memberOfData = $MemberOfBySP[$SP.id]
    $memberOfGroups = ($memberOfData | Where-Object { $_.'@odata.type' -eq "#microsoft.graph.group" } | Select-Object -ExpandProperty displayName) -join ";"
    $memberOfRoles = ($memberOfData | Where-Object { $_.'@odata.type' -eq "#microsoft.graph.directoryRole" } | Select-Object -ExpandProperty displayName) -join ";"

    $objPermissions = [PSCustomObject][ordered]@{
        "Number"                     = $i
        "Application Name"           = $SP.appDisplayName
        "ApplicationId"              = $SP.AppId
        "IsBuiltIn"                  = ($SP.tags -notcontains "WindowsAzureActiveDirectoryIntegratedApp")
        "Publisher"                  = $SP.PublisherName
        "Owned by org"               = $SP.appOwnerOrganizationId
        "Verified"                   = if ($SP.verifiedPublisher.displayName) { $SP.verifiedPublisher.displayName } else { "Not verified" }
        "Homepage"                   = $SP.Homepage
        "SP name"                    = $SP.displayName
        "ObjectId"                   = $SP.id
        "Type"                       = $SP.servicePrincipalType
        "Created on"                 = if ($SP.createdDateTime) { (Get-Date($SP.createdDateTime) -format g) } else { $null }
        "Enabled"                    = $SP.AccountEnabled
        "Owners"                     = if ($owners) { $owners -join ";" } else { $null }
        "Member of groups"           = $memberOfGroups
        "Member of roles"            = $memberOfRoles
        "PasswordCreds"              = if ($SP.passwordCredentials) { $SP.passwordCredentials.keyId -join ";" } else { $null }
        "KeyCreds"                   = if ($SP.keyCredentials) { $SP.keyCredentials.keyId -join ";" } else { $null }
        "TokenKey"                   = $SP.tokenEncryptionKeyId
        "Permissions - application"  = $null
        "Authorized By - application" = $null
        "Last modified - application" = $null
        "Permissions - delegate"     = $null
        "Authorized By - delegate"   = $null
        "Valid until - delegate"     = $null
    }

    # Application permissions (from pre-fetched data)
    $appRoleAssignments = $AppRoleAssignmentsBySP[$SP.id]
    if ($appRoleAssignments -and $appRoleAssignments.Count -gt 0) {
        $OAuthperm = @{ }
        # $objPermissions.'Last modified - application' = (Get-Date(($appRoleAssignments | Select-Object -ExpandProperty creationTimestamp -ErrorAction SilentlyContinue | Sort-Object -Descending | Select-Object -First 1)) -format g)
        # --
        # Safe date extraction - check if any valid timestamps exist
        $timestamps = $appRoleAssignments | 
            Where-Object { $_.creationTimestamp } | 
            Select-Object -ExpandProperty creationTimestamp -ErrorAction SilentlyContinue
        
        if ($timestamps) {
            $latestTimestamp = $timestamps | Sort-Object -Descending | Select-Object -First 1
            $objPermissions.'Last modified - application' = (Get-Date $latestTimestamp -Format g)
        }
        # --
        Parse-AppPermissions $appRoleAssignments ([ref]$OAuthperm)
        $objPermissions.'Permissions - application' = (($OAuthperm.GetEnumerator() | ForEach-Object { "$($_.Name):$($_.Value.ToString().TrimStart(','))" }) -join ";")
        $objPermissions.'Authorized By - application' = "An administrator (application permissions)"

        foreach ($k in $OAuthperm.Keys) {
            $resName = $k.TrimStart('[').TrimEnd(']')
            $perms = ($OAuthperm[$k].TrimStart(',') -split ',') | Where-Object { $_ -ne '' }
            foreach ($p in $perms) {
                $expanded.Add([PSCustomObject]@{
                        "ApplicationId"   = $SP.AppId
                        "ApplicationName" = $SP.appDisplayName
                        "PermissionType"  = "Application"
                        "Resource"        = $resName
                        "Permission"      = $p
                        "ConsentedBy"     = "An administrator (application permissions)"
                        "ValidUntil"      = $null
                    })
            }
        }
    }

    # Delegate permissions (from pre-indexed data)
    $oauth2PermissionGrants = @()
    if ($OAuth2GrantsByClient[$SP.id]) { $oauth2PermissionGrants += $OAuth2GrantsByClient[$SP.id] }
    if ($OAuth2GrantsByResource[$SP.id]) { $oauth2PermissionGrants += $OAuth2GrantsByResource[$SP.id] }
    $oauth2PermissionGrants = $oauth2PermissionGrants | Select-Object -Unique -Property id, clientId, resourceId, scope, principalId, expiryTime | Group-Object id | ForEach-Object { $_.Group[0] }

    if ($oauth2PermissionGrants -and $oauth2PermissionGrants.Count -gt 0) {
        $OAuthperm = @{ }
        Parse-DelegatePermissions $oauth2PermissionGrants ([ref]$OAuthperm)
        $objPermissions.'Permissions - delegate' = (($OAuthperm.GetEnumerator() | ForEach-Object { "$($_.Name):$($_.Value.ToString().TrimStart(','))" }) -join ";")
        
        $expDates = $oauth2PermissionGrants | Where-Object { $_.ExpiryTime } | Select-Object -ExpandProperty ExpiryTime -ErrorAction SilentlyContinue
        if ($expDates) {
            $objPermissions.'Valid until - delegate' = (Get-Date(($expDates | Sort-Object -Descending | Select-Object -First 1)) -format g)
        }
        
        $assignedto = @()
        $assignedto += ($OAuthperm.Keys | ForEach-Object {
                if ($_ -match "\(([^)]+)\)") { $Matches[1] } else { "All users (admin consent)" }
            })
        $objPermissions.'Authorized By - delegate' = (($assignedto | Select-Object -Unique) -join ",")

        foreach ($k in $OAuthperm.Keys) {
            $inner = $k.TrimStart('[').TrimEnd(']')
            if ($inner -match "^(.+)\(([^)]+)\)$") { $resName = $Matches[1]; $consentor = $Matches[2] } else { $resName = $inner; $consentor = "All users (admin consent)" }
            $perms = ($OAuthperm[$k].TrimStart(',') -split ',') | Where-Object { $_ -ne '' }
            foreach ($p in $perms) {
                $expanded.Add([PSCustomObject]@{
                        "ApplicationId"   = $SP.AppId
                        "ApplicationName" = $SP.appDisplayName
                        "PermissionType"  = "Delegated"
                        "Resource"        = $resName
                        "Permission"      = $p
                        "ConsentedBy"     = $consentor
                        "ValidUntil"      = ($objPermissions.'Valid until - delegate')
                    })
            }
        }
    }

    $output.Add($objPermissions)
}

Write-Progress -Activity "Processing service principals" -Completed

# ...existing CSV export code remains the same...
if ($ExportCsv) {
    $outDir = Split-Path -Path $ExportCsvPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    $seen = @{}
    $expandedUnique = [System.Collections.Generic.List[Object]]::new()
    foreach ($r in $expanded) {
        $k = "$($r.ApplicationId)|$($r.PermissionType)|$($r.Resource)|$($r.Permission)|$($r.ConsentedBy)"
        if (-not $seen.ContainsKey($k)) {
            $seen[$k] = $true
            $expandedUnique.Add($r)
        }
    }

    $flattened = [System.Collections.Generic.List[Object]]::new()

    foreach ($app in $output) {
        $appId = $app.'ApplicationId'
        $appDisplay = $app.'Application Name'
        $appMeta = @{
            ApplicationId   = $appId
            ApplicationName = $appDisplay
            Publisher       = $app.'Publisher'
            SPName          = $app.'SP name'
            ObjectId        = $app.'ObjectId'
            Type            = $app.'Type'
            CreatedOn       = $app.'Created on'
            Enabled         = $app.'Enabled'
            Owners          = $app.'Owners'
            MemberOfGroups  = $app.'Member of groups'
            MemberOfRoles   = $app.'Member of roles'
            Verified        = $app.'Verified'
            Homepage        = $app.'Homepage'
        }

        $permsForApp = $expandedUnique | Where-Object { $_.ApplicationId -eq $appId }

        if ($permsForApp -and $permsForApp.Count -gt 0) {
            foreach ($p in $permsForApp) {
                $ConsentType = switch ($p.ConsentedBy) {
                    "All users (admin consent)" { "Admin consent" }
                    "An administrator (application permissions)" { "Admin consent" }
                    Default { "User consent" }
                }

                $row = [PSCustomObject][ordered]@{
                    ApplicationId   = $appMeta.ApplicationId
                    ApplicationName = $appMeta.ApplicationName
                    Publisher       = $appMeta.Publisher
                    SPName          = $appMeta.SPName
                    ObjectId        = $appMeta.ObjectId
                    Type            = $appMeta.Type
                    CreatedOn       = $appMeta.CreatedOn
                    Enabled         = $appMeta.Enabled
                    Owners          = $appMeta.Owners
                    MemberOfGroups  = $appMeta.MemberOfGroups
                    MemberOfRoles   = $appMeta.MemberOfRoles
                    Verified        = $appMeta.Verified
                    Homepage        = $appMeta.Homepage
                    PermissionType  = $p.PermissionType
                    Resource        = $p.Resource
                    Permission      = $p.Permission
                    ConsentedBy     = $p.ConsentedBy
                    ConsentType     = $ConsentType
                    ValidUntil      = $p.ValidUntil
                }
                $flattened.Add($row)
            }
        }
        else {
            $row = [PSCustomObject][ordered]@{
                ApplicationId   = $appMeta.ApplicationId
                ApplicationName = $appMeta.ApplicationName
                Publisher       = $appMeta.Publisher
                SPName          = $appMeta.SPName
                ObjectId        = $appMeta.ObjectId
                Type            = $appMeta.Type
                CreatedOn       = $appMeta.CreatedOn
                Enabled         = $appMeta.Enabled
                Owners          = $appMeta.Owners
                MemberOfGroups  = $appMeta.MemberOfGroups
                MemberOfRoles   = $appMeta.MemberOfRoles
                Verified        = $appMeta.Verified
                Homepage        = $appMeta.Homepage
                PermissionType  = $null
                Resource        = $null
                Permission      = $null
                ConsentedBy     = $null
                ConsentType     = $null
                ValidUntil      = $null
            }
            $flattened.Add($row)
        }
    }

    $flattened | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Flat CSV exported to: $ExportCsvPath" -ForegroundColor Green
}

Write-Host "Done. Total apps processed: $($output.Count)" -ForegroundColor Green
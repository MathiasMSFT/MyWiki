#Requires -Version 3.0
[CmdletBinding(SupportsShouldProcess)]
Param(
    [switch]$IncludeBuiltin=$false,
    [switch]$ExportCsv=$false,
    [string]$ExportCsvPath
)

# ---------------- Helper functions ----------------

function Parse-AppPermissions {
    Param(
        [Parameter(Mandatory=$true)]$appRoleAssignments,
        [Parameter(Mandatory=$true)][ref]$OAuthperm
    )

    foreach ($appRoleAssignment in $appRoleAssignments) {
        $resID = $appRoleAssignment.ResourceDisplayName
        $roleObj = try { Get-ServicePrincipalRoleById $appRoleAssignment.resourceId } catch { $null }
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
        [Parameter(Mandatory=$true)]$oauth2PermissionGrants,
        [Parameter(Mandatory=$true)][ref]$OAuthperm
    )

    foreach ($oauth2PermissionGrant in $oauth2PermissionGrants) {
        $resSP = try { Get-ServicePrincipalRoleById $oauth2PermissionGrant.ResourceId } catch { $null }
        $resID = if ($resSP) {
            if ($resSP.appDisplayName) { $resSP.appDisplayName }
            elseif ($resSP.displayName) { $resSP.displayName }
            else { $oauth2PermissionGrant.ResourceId }
        } else { $oauth2PermissionGrant.ResourceId }

        if ($null -ne $oauth2PermissionGrant.PrincipalId) {
            $userId = "(" + (Get-UserUPNById -objectID $oauth2PermissionGrant.principalId) + ")"
        }
        else { $userId = $null }

        if ($oauth2PermissionGrant.Scope) {
            $scopes = ($oauth2PermissionGrant.Scope.Split(" ") -join ",")
        } else { $scopes = "Orphaned scope" }

        $key = "[$resID$userId]"
        if (-not $OAuthperm.Value.ContainsKey($key)) { $OAuthperm.Value[$key] = "" }
        $OAuthperm.Value[$key] += "," + $scopes
    }
}

function Get-ServicePrincipalRoleById {
    Param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]$spID
    )
    if (-not $script:SPPerm) { $script:SPPerm = @{} }
    if (-not $script:SPPerm[$spID]) {
        try {
            $res = Invoke-WebRequest -Method Get -Uri "https://graph.microsoft.com/beta/servicePrincipals/$spID" -Headers $authHeader -Verbose:$false
            $script:SPPerm[$spID] = ($res.Content | ConvertFrom-Json)
        } catch {
            $script:SPPerm[$spID] = $null
        }
    }
    return $script:SPPerm[$spID]
}

function Get-UserUPNById {
    Param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]$objectID)
    if (-not $script:SPusers) { $script:SPusers = @{} }
    if (-not $script:SPusers[$objectID]) {
        try {
            $res = Invoke-WebRequest -Method Get -Uri "https://graph.microsoft.com/v1.0/users/$($objectID)?`$select=UserPrincipalName" -Headers $authHeader -Verbose:$false
            $script:SPusers[$objectID] = ($res.Content | ConvertFrom-Json).UserPrincipalName
        } catch {
            $script:SPusers[$objectID] = $objectID
        }
    }
    return $script:SPusers[$objectID]
}

# ---------------- Modules & Auth ----------------
$moduleName = "MSAL.PS"
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    try { Install-Module -Name $moduleName -Scope CurrentUser -Force } catch { Write-Warning "Failed to install MSAL.PS: $_" }
}

# ---- Get token (update these values before running) ----
$tenantId = "contoso.onmicrosoft.com" # Your tenant ID or domain
$AppClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e" # Microsoft Graph PowerShell App


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

## NOT USED:  $tokenobj = Parse-JWTtoken $Token

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

# ---------------- Iterate and build output ----------------
$output = [System.Collections.Generic.List[Object]]::new()
# collection "exploded" une ligne par permission (pour Power BI)
$expanded = [System.Collections.Generic.List[Object]]::new()
$i = 0; $count = 1

foreach ($SP in $SPs) {
    $count++
    Start-Sleep -Milliseconds 200

    # owners
    $owners = @()
    try {
        $res = Invoke-WebRequest -Method Get -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($SP.id)/owners?`$select=id,userPrincipalName&`$top=999" -Headers $authHeader -ErrorAction Stop -Verbose:$false
        $owners = ($res.Content | ConvertFrom-Json).Value | ForEach-Object { $_.userPrincipalName } 
    } catch {}

    # group/role memberships
    $memberOfGroups = $null; $memberOfRoles = $null
    try {
        $res = Invoke-WebRequest -Method Get -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($SP.id)/memberOf?`$select=id,displayName&`$top=999" -Headers $authHeader -ErrorAction Stop -Verbose:$false
        $vals = ($res.Content | ConvertFrom-Json).Value
        $memberOfGroups = ($vals | ? { $_.'@odata.type' -eq "#microsoft.graph.group" } | Select-Object -ExpandProperty displayName) -join ";"
        $memberOfRoles  = ($vals | ? { $_.'@odata.type' -eq "#microsoft.graph.directoryRole" } | Select-Object -ExpandProperty displayName) -join ";"
    } catch {}

    $i++; $objPermissions = [PSCustomObject][ordered]@{
        "Number" = $i
        "Application Name" = ($SP.appDisplayName -or $null)
        "ApplicationId" = $SP.AppId
        "IsBuiltIn" = ($SP.tags -notcontains "WindowsAzureActiveDirectoryIntegratedApp")
        "Publisher" = ($SP.PublisherName -or $null)
        "Owned by org" = ($SP.appOwnerOrganizationId -or $null)
        "Verified" = (&{ if ($SP.verifiedPublisher -and $SP.verifiedPublisher.displayName) { $SP.verifiedPublisher.displayName } else { "Not verified" } })
        "Homepage" = ($SP.Homepage -or $null)
        "SP name" = $SP.displayName
        "ObjectId" = $SP.id
        "Type" = $SP.servicePrincipalType
        "Created on" = (&{ if ($SP.createdDateTime) { (Get-Date($SP.createdDateTime) -format g) } else { $null } })
        "Enabled" = $SP.AccountEnabled
        "Owners" = (&{ if ($owners) { $owners -join ";" } else { $null } })
        "Member of groups" = $memberOfGroups
        "Member of roles" = $memberOfRoles
        "PasswordCreds" = (&{ if ($SP.passwordCredentials) { $SP.passwordCredentials.keyId -join ";" } else { $null } })
        "KeyCreds" = (&{ if ($SP.keyCredentials) { $SP.keyCredentials.keyId -join ";" } else { $null } })
        "TokenKey" = ($SP.tokenEncryptionKeyId -or $null)
        "Permissions - application" = $null
        "Authorized By - application" = $null
        "Last modified - application" = $null
        "Permissions - delegate" = $null
        "Authorized By - delegate" = $null
        "Valid until - delegate" = $null
    }

    # Application permissions
    try {
        # collect assignments from multiple endpoints (some tenants/endpoints expose via different paths)
        $appRoleAssignments = @()

        # 1) try endpoint: servicePrincipals/{id}/appRoleAssignments (beta)
        try {
            $uriA = "https://graph.microsoft.com/beta/servicePrincipals/$($SP.id)/appRoleAssignments?`$top=999"
            do {
                $resA = Invoke-RestMethod -Method Get -Uri $uriA -Headers $authHeader -ErrorAction Stop
                if ($resA.value) { $appRoleAssignments += $resA.value }
                $uriA = $resA.'@odata.nextLink'
            } while ($uriA)
        } catch {}

        # 2) try endpoint: servicePrincipals/{id}/appRoleAssignedTo (some tenants return here)
        try {
            $uriB = "https://graph.microsoft.com/beta/servicePrincipals/$($SP.id)/appRoleAssignedTo?`$top=999"
            do {
                $resB = Invoke-RestMethod -Method Get -Uri $uriB -Headers $authHeader -ErrorAction Stop
                if ($resB.value) { $appRoleAssignments += $resB.value }
                $uriB = $resB.'@odata.nextLink'
            } while ($uriB)
        } catch {}

        # deduplicate by id (in case same assignment appears twice)
        if ($appRoleAssignments) {
            $appRoleAssignments = ($appRoleAssignments | Group-Object -Property id | ForEach-Object { $_.Group[0] })
        }

        $OAuthperm = @{ }

        if ($appRoleAssignments -and $appRoleAssignments.Count -gt 0) {
            $objPermissions.'Last modified - application' = (Get-Date(($appRoleAssignments | Select-Object -ExpandProperty creationTimestamp -ErrorAction SilentlyContinue | Sort-Object -Descending | Select-Object -First 1)) -format g)
            Parse-AppPermissions $appRoleAssignments ([ref]$OAuthperm)
            $objPermissions.'Permissions - application' = (($OAuthperm.GetEnumerator() | ForEach-Object { "$($_.Name):$($_.Value.ToString().TrimStart(','))" }) -join ";")
            $objPermissions.'Authorized By - application' = "An administrator (application permissions)"

            # --- explode application permissions into rows for Power BI
            if ($OAuthperm.Keys) {
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
        }
    } catch {}

    # Delegate permissions
    try {
        # Collect grants where this SP is client (clientId) or resource (resourceId).
        $oauth2PermissionGrants = @()

        # 1) grants where this SP is the client (clientId)
        try {
            $uriClient = "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$($SP.id)'&`$top=999"
            do {
                $resClient = Invoke-RestMethod -Method Get -Uri $uriClient -Headers $authHeader -ErrorAction Stop
                if ($resClient.value) { $oauth2PermissionGrants += $resClient.value }
                $uriClient = $resClient.'@odata.nextLink'
            } while ($uriClient)
        } catch {}

        # 2) grants where this SP is the resource (resourceId)
        try {
            $uriRes = "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=resourceId eq '$($SP.id)'&`$top=999"
            do {
                $resRes = Invoke-RestMethod -Method Get -Uri $uriRes -Headers $authHeader -ErrorAction Stop
                if ($resRes.value) { $oauth2PermissionGrants += $resRes.value }
                $uriRes = $resRes.'@odata.nextLink'
            } while ($uriRes)
        } catch {}

        # deduplicate by id (in case an item appears twice)
        if ($oauth2PermissionGrants) {
            $oauth2PermissionGrants = ($oauth2PermissionGrants | Group-Object -Property id | ForEach-Object { $_.Group[0] })
        }

        $OAuthperm = @{ }

        if ($oauth2PermissionGrants -and $oauth2PermissionGrants.Count -gt 0) {
            Parse-DelegatePermissions $oauth2PermissionGrants ([ref]$OAuthperm)
            $objPermissions.'Permissions - delegate' = (($OAuthperm.GetEnumerator() | ForEach-Object { "$($_.Name):$($_.Value.ToString().TrimStart(','))" }) -join ";")
            # compute latest expiry if present
            $expDates = $oauth2PermissionGrants | Where-Object { $_.ExpiryTime } | Select-Object -ExpandProperty ExpiryTime -ErrorAction SilentlyContinue
            if ($expDates) {
                $objPermissions.'Valid until - delegate' = (Get-Date(($expDates | Sort-Object -Descending | Select-Object -First 1)) -format g)
            }
            # authorized by: principal(s) extracted into keys (they include UPN in key when present)
            $assignedto = @()
            $assignedto += ($OAuthperm.Keys | ForEach-Object {
                # key format: [ResName] or [ResName(user@domain)]
                if ($_ -match "\(([^)]+)\)") { $Matches[1] } else { "All users (admin consent)" } 
            })
            $objPermissions.'Authorized By - delegate' = (($assignedto | Select-Object -Unique) -join ",")

            # --- explode delegated permissions into rows for Power BI
            if ($OAuthperm.Keys) {
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
                            "ValidUntil"      = ($objPermissions.'Valid until - delegate' -or $null)
                        })
                    }
                }
            }
        }
    } catch {}

    $output.Add($objPermissions)
}


if ($ExportCsv) {
    $outDir = Split-Path -Path $ExportCsvPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    # Dédupliquer $expanded : une ligne unique par (ApplicationId, PermissionType, Resource, Permission, ConsentedBy)
    $seen = @{}
    $expandedUnique = [System.Collections.Generic.List[Object]]::new()
    foreach ($r in $expanded) {
        $k = "$($r.ApplicationId)|$($r.PermissionType)|$($r.Resource)|$($r.Permission)|$($r.ConsentedBy)"
        if (-not $seen.ContainsKey($k)) {
            $seen[$k] = $true
            $expandedUnique.Add($r)
        }
    }

    # Construire un tableau "flattened" : une ligne par permission x authorized (utilise la liste dédupliquée)
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

        # trouver les permissions liées dans $expandedUnique (matching ApplicationId)
        $permsForApp = $expandedUnique | Where-Object { $_.ApplicationId -eq $appId }

        if ($permsForApp -and $permsForApp.Count -gt 0) {
            foreach ($p in $permsForApp) {
                Switch ($p.ConsentedBy) {
                    "All users (admin consent)" {
                        $ConsentType = "Admin consent"
                    }
                    "An administrator (application permissions)" {
                        $ConsentType = "Admin consent"
                    }
                    Default {
                        $ConsentType = "User consent"
                    }
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
            # pas de permission -> ligne app-level avec colonnes permission vides
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

    # Export unique (UTF8) pour Power BI
    $flattened | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Flat CSV exported to: $ExportCsvPath (one row per permission per authorized; apps without permissions included)"
}

Write-Host "Done. Total apps processed: $($output.Count)"
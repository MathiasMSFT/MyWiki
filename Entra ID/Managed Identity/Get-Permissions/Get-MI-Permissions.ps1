$TenantID = "ee942b75-82c7-42bc-9585-ccc5628492d9"
$DisplayNameMI = "Members-MFA-Reset"

Connect-MgGraph -TenantId $TenantID -Scopes "Application.Read.All","Directory.Read.All" -NoWelcome
Select-MgProfile -Name "v1.0"

# 1) SP de la MI
$sp = Get-MgServicePrincipal -Filter "displayName eq '$DisplayNameMI'"

# 2) App role assignments
$assignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id

# 3) Résolution des noms d’API et des rôles
$rows = @()
foreach ($a in $assignments) {
    $apiSp = Get-MgServicePrincipal -ServicePrincipalId $a.ResourceId
    $role = $apiSp.AppRoles | Where-Object { $_.Id -eq $a.AppRoleId }
    $rows += [pscustomobject]@{
        ManagedIdentityDisplayName = $sp.DisplayName
        ManagedIdentityObjectId    = $sp.Id
        ApiDisplayName             = $apiSp.DisplayName
        ApiObjectId                = $apiSp.Id
        AppRoleName                = $role.DisplayName
        AppRoleValue               = $role.Value
        AppRoleId                  = $a.AppRoleId
    }
}

# 4) OAuth2 permission grants (si existants)
$grants = Get-MgOauth2PermissionGrant -Filter "clientId eq '$($sp.Id)'"
foreach ($g in $grants) {
    $apiSp = Get-MgServicePrincipal -ServicePrincipalId $g.ResourceId
    $rows += [pscustomobject]@{
        ManagedIdentityDisplayName = $sp.DisplayName
        ManagedIdentityObjectId    = $sp.Id
        ApiDisplayName             = $apiSp.DisplayName
        ApiObjectId                = $apiSp.Id
        AppRoleName                = "[Delegated scopes]"
        AppRoleValue               = $g.Scope
        AppRoleId                  = ""
    }
}

# 5) Directory roles (memberOf)
$dirs = Get-MgServicePrincipalMemberOf -ServicePrincipalId $sp.Id
foreach ($d in $dirs) {
    $rows += [pscustomobject]@{
        ManagedIdentityDisplayName = $sp.DisplayName
        ManagedIdentityObjectId    = $sp.Id
        ApiDisplayName             = "[Directory Role]"
        ApiObjectId                = $d.Id
        AppRoleName                = $d.AdditionalProperties['displayName']
        AppRoleValue               = ""
        AppRoleId                  = ""
    }
}

$rows # | Export-Csv -NoTypeInformation -Path ".\MI-Permissions.csv"
Write-Host "Exporté: MI-Permissions.csv"

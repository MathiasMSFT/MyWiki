
# Install the ImportExcel module if not already installed
If (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
}

Connect-MgGraph -Scopes "RoleManagement.Read.All" -NoWelcome

# Check if the user is connected to Microsoft Graph
if (-not (Get-MgContext)) {
    Write-Error "Connection failed to Microsoft Graph."
    exit
}

# Get all roles and permissions
$rolesWithPermissions = @()
Get-MgRoleManagementDirectoryRoleDefinition -ExpandProperty 'InheritsPermissionsFrom' | ForEach-Object {
    $role = $_
    foreach ($rolePermission in $role.RolePermissions) {
        Write-Host "Role: $($role.DisplayName)" -ForegroundColor Cyan
        foreach ($permission in $rolePermission.AllowedResourceActions) {
            $rolesWithPermissions += [PSCustomObject]@{
                RoleId      = $role.Id
                RoleName    = $role.DisplayName
                Description = $role.Description
                Permission  = $permission
                BuiltIn     = $role.IsBuiltIn
                Enabled     = $role.IsEnabled
                Scopes      = $role.ResourceScopes
                InheritsPermissions  = $role.InheritsPermissionsFrom.Id

            }
        }
        If ($role.InheritsPermissionsFrom.Id) {
            Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $role.InheritsPermissionsFrom.Id | ForEach-Object {
                $inheritsRole = $_
                foreach ($InheritedPermission in $inheritsRole.RolePermissions.AllowedResourceActions) {
                    $rolesWithPermissions += [PSCustomObject]@{
                        RoleId      = $Role.Id
                        RoleName    = $Role.DisplayName
                        Description = $Role.Description
                        Permission  = $InheritedPermission
                        BuiltIn     = $role.IsBuiltIn
                        Enabled     = $role.IsEnabled
                        Scopes      = $role.ResourceScopes
                    }
                }
            }

        }
    }
}


# Export data to Excel
$xlsxFilePath = "roles_permissions.xlsx"
$rolesWithPermissions | Export-Excel -Path $xlsxFilePath -AutoSize -WorksheetName "RolesPermissions"
Write-Host "Roles and permissions have been successfully exported to $xlsxFilePath."

param (
    [Parameter(Mandatory=$true, Position=0)]
    $Name,
    [Parameter(Mandatory=$true, Position=1)]
    $TenantId,
    [Parameter(Mandatory=$true, Position=2)]
    $VaultName,
    [Parameter(Mandatory=$true, Position=3)]
    $AccountUPN
)
Connect-AzAccount -AccountId $AccountUPN
Connect-MgGraph -Scopes Application.ReadWrite.All -TenantId $TenantId -NoWelcome

# Create an application
$Config = @{
    DisplayName = $Name
    SignInAudience = "AzureADMyOrg"
}
$App = New-MgApplication -BodyParameter $Config
sleep -Seconds 10

# Create an associated service principal
$SP = New-MgServicePrincipal -AppId $App.AppId

## API permissions
$GraphAppId = "00000003-0000-0000-c000-000000000000"
$GraphPermissions = @('Application.Read.All','Group.Read.All','User.Read.All','PrivilegedAccess.Read.AzureResources')
ForEach ($Permission in $GraphPermissions) {
    ## Get Graph roles
    $GraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
    $AppRole = $GraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $Permission -and $_.AllowedMemberTypes -contains "Application"}

    $AppRole

    $params = @{
        principalId = $SP.Id
        resourceId = $GraphAppId
        appRoleId = $($AppRole.Id)
    }
    ## Add permission to Service Principal
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $SP.Id -ResourceId $GraphServicePrincipal.Id -PrincipalId $SP.Id -AppRoleId $AppRole.Id
}

# Generate a secret - App Registration
$SecretConfig = @{
    DisplayName = "AzGovVisualizer-Mathias"
    endDateTime = (Get-Date).AddMonths(6)
}
$App = Get-MgApplication -Filter "DisplayName eq 'sp-AzGovVisualizer'"
$MySecret = Add-MgApplicationPassword -ApplicationId $App.Id -BodyParameter $SecretConfig
# Store secret to Azure Key Vault
$secretName = $Name
$secret = ConvertTo-SecureString -String $($MySecret.SecretText) -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $VaultName -Name $secretName -SecretValue $Secret




Param (
    [Parameter(Mandatory=$true)]
    [String]$TenantId
)

# Fonction pour se connecter à Microsoft Graph API
function Connect-To-MicrosoftGraph {
    try {
        Connect-MgGraph -Scopes 'Policy.Read.All','Policy.ReadWrite.ConditionalAccess', 'Application.Read.All' -TenantId $TenantId -NoWelcome
        Write-Host "Connected to Microsoft Graph successfully." -ForegroundColor Green
    } catch {
        Write-Error "Error connecting to Microsoft Graph: $_"
        exit 1
    }
}

# Connexion à Microsoft Graph
Connect-To-MicrosoftGraph


Get-MgIdentityConditionalAccessPolicy | ForEach-Object {
    $policy = $_
    Write-Host "Deleting policy: $($policy.DisplayName)" -ForegroundColor Yellow
    Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy.Id -Confirm:$false
    Write-Host "Deleted policy: $($policy.DisplayName)" -ForegroundColor Green
}
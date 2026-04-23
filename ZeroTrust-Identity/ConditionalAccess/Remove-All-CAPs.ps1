Param (
    [Parameter(Mandatory=$true)]
    [String]$TenantId
)

# Avoid importing the rollup module directly to prevent assembly/version conflicts
# Check if Microsoft.Graph modules or assemblies are already loaded in this session.
$modulesLoaded = Get-Module Microsoft.Graph*
if ($modulesLoaded) {
    $authAssembly = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -like '*Microsoft.Graph.Authentication*' }
    if ($authAssembly) {
        $vers = ($authAssembly | ForEach-Object { $_.GetName().Version.ToString() }) -join ', '
        Write-Error "Microsoft.Graph assemblies already loaded (versions: $vers). Loading another Microsoft.Graph module may cause 'Assembly with same name is already loaded' errors. Restart PowerShell or run this script in a fresh session with a single Microsoft.Graph module version installed."
        exit 1
    }
} else {
    # No Microsoft.Graph module loaded; ensure it's available in the system but do not Import-Module.
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
        Write-Error 'Microsoft.Graph module not found. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser' 
        exit 1
    }
    # Intentionally do not call Import-Module to let Connect-MgGraph auto-load the correct submodules.
}

# Fonction pour se connecter à Microsoft Graph API
function Connect-To-MicrosoftGraph {
    try {
        Connect-MgGraph -Scopes 'Policy.Read.All','Policy.ReadWrite.ConditionalAccess', 'Application.Read.All' -TenantId $TenantId -NoWelcome -ErrorAction Stop
        Write-Host "Connected to Microsoft Graph successfully." -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -like '*User canceled authentication*' -or $_.Exception.Message -like '*cancel*') {
            Write-Error "Authentication cancelled by user. Exiting script."
        } else {
            Write-Error "Error connecting to Microsoft Graph: $_"
        }
        exit 1
    }
}

# Connexion à Microsoft Graph
Connect-To-MicrosoftGraph


Get-MgIdentityConditionalAccessPolicy -Filter "state eq 'enabledForReportingButNotEnforced'" | ForEach-Object {
    $policy = $_
    Write-Host "Deleting policy: $($policy.DisplayName)" -ForegroundColor Yellow
    Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy.Id -Confirm:$false
    Write-Host "Deleted policy: $($policy.DisplayName)" -ForegroundColor Green
}
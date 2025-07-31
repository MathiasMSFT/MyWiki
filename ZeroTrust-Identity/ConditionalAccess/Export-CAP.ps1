<#
    .SYNOPSIS
    Export-CAP.ps1

    .DESCRIPTION
    Export Conditional Access policies to json file (one by policy)
#>
Param (
    [Parameter(Mandatory=$true)]
    [String]$TenantId,
    [Parameter(Mandatory=$false)]
    [switch]$CAPs,
    [Parameter(Mandatory=$false)]
    [switch]$Locations
)
# Connect to Microsoft Graph
Connect-MgGraph -Scopes 'Policy.Read.All' -TenantId $TenantId -NoWelcome

# Export path for CAP
$ExportCAPsPath = ".\Export\CAPs"
$ExportLocationsPath = ".\Export\NamedLocations"

If ($CAPs){
    try {
        $AllCAPs = Get-MgIdentityConditionalAccessPolicy -All

        If ($AllCAPs.Count -eq 0) {
            Write-Host "There are no CA policies found to export." -ForegroundColor Yellow
        } Else {
            # For each policy
            ForEach ($Policy in $AllCAPs){
                try {
                    $PolicyName = $Policy.DisplayName
                    $Policy = $Policy | ConvertTo-Json -Depth 10
                    $Policy | Out-File "$ExportCAPsPath\$PolicyName.json" -Force
                    Write-Host "Successfully export CAP named $($PolicyName)" -ForegroundColor Green
                }
                catch {
                    Write-Host "Error: $($PolicyName). $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

If ($Locations){
    $AllLocations = Get-MgIdentityConditionalAccessNamedLocation
    If ($AllLocations.Count -eq 0) {
        Write-Host "There are no locations found to export." -ForegroundColor Yellow
    } Else {
        # For each policy
        ForEach ($Location in $AllLocations){
            try {
                $LocationName = $Location.DisplayName
                $Location = $Location | ConvertTo-Json -Depth 10
                $Location | Out-File "$ExportLocationsPath\$LocationName.json" -Force
                Write-Host "Successfully export location named $($Location.DisplayName)" -ForegroundColor Green
            }
            catch {
                Write-Host "Error: $($Location.DisplayName). $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}
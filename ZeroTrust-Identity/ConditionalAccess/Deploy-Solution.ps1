<#
    .SYNOPSIS
    Deploy-ZeroTrust-Solution.ps1

    .DESCRIPTION
    Deploy Groups and Conditional Access policies from json files.
#>

Param (
    [Parameter(Mandatory=$true)]
    [String]$TenantId,
    [Parameter(Mandatory=$false)]
    [switch]$Groups,
    [Parameter(Mandatory=$false)]
    [switch]$CAPs
)

# Connect to Microsoft Graph
Connect-MgGraph -Scopes 'Policy.Read.All', 'Policy.ReadWrite.ConditionalAccess', 'Application.Read.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory' -TenantId $TenantId -NoWelcome

# Path of deployment directory
$DeploymentDirectory = ".\Deployment\"

# Path of import directory containing your json files
$CAPDirectory = ".\Import\"

If ($Groups) {
    $Groups = Get-Content -Path "$DeploymentDirectory/Groups.json" | ConvertFrom-Json -Depth 10

    # Personas
    try {

        ForEach ($persona in $Groups.Personas){
            # Switch manual vs dynamic
            Switch ($persona.Type){
                "manual" {
                    $personaObject = [PSCustomObject]@{
                        DisplayName = $persona.Name
                        GroupTypes = @()
                        SecurityEnabled = $true
                        IsAssignableToRole = $persona.IsAssignable
                        MailEnabled = $false
                        MailNickname = (New-Guid).Guid.Substring(0,10)
                        Description = $persona.Description
                        # restrictedau = $persona.RestrictedAU
                    }
                }
                "dynamic" {
                    $personaObject = [PSCustomObject]@{
                        DisplayName = $persona.Name
                        GroupTypes = @('DynamicMembership')
                        SecurityEnabled = $true
                        IsAssignableToRole = $persona.IsAssignable
                        MailEnabled = $false
                        MailNickname = (New-Guid).Guid.Substring(0,10)
                        Description = $persona.Description
                        membershipRuleProcessingState = 'On'
                        MembershipRule = $persona.Rule
                        # restrictedau = $persona.RestrictedAU
                    }
                }
                Default {Write-Host "Type of group is unknown" -ForegroundColor Red}
            }

            $personaBodyParam = $personaObject | ConvertTo-Json -Depth 10

            # Create the CAP
            Write-Host "Creating group named $($persona.Name)" -ForegroundColor Yellow
            If (!(Get-MgGroup -Filter "displayName eq '$($persona.Name)'")){
                $null = New-MgGroup -BodyParameter $personaBodyParam
                Write-Host "Group created successfully: $($persona.Name) - Type: $($persona.Type) " -ForegroundColor Green
            } Else {
                Write-Host "Group named $($persona.Name) already exist" -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Host "Error while creating the group: $_" -ForegroundColor Red
    }

    # Exclusions
    try {

        ForEach ($exclusiongrp in $Groups.Exclusions){
            # Switch manual vs dynamic
            Switch ($exclusiongrp.Type){
                "manual" {
                    # Create a custom object
                    $exclusiongrpObject = [PSCustomObject]@{
                        DisplayName = $exclusiongrp.Name
                        GroupTypes = @()
                        SecurityEnabled = $true
                        IsAssignableToRole = $exclusiongrp.IsAssignableToRole
                        MailEnabled = $false
                        MailNickname = (New-Guid).Guid.Substring(0,10)
                        Description = $exclusiongrp.Description
                        # restrictedau = $exclusiongrp.RestrictedAU
                    }
                }
                "dynamic" {
                    # Create a custom object
                    $exclusiongrpObject = [PSCustomObject]@{
                        DisplayName = $exclusiongrp.Name
                        GroupTypes = @('DynamicMembership')
                        SecurityEnabled = $true
                        IsAssignableToRole = $exclusiongrp.IsAssignableToRole
                        MailEnabled = $false
                        MailNickname = (New-Guid).Guid.Substring(0,10)
                        Description = $exclusiongrp.Description
                        membershipRuleProcessingState = 'On'
                        MembershipRule = $exclusiongrp.Rule
                        # restrictedau = $exclusiongrp.RestrictedAU
                    }
                }
                Default {Write-Host "Type of group is unknown" -ForegroundColor Red}
            }

            $exclusionsBodyParam = $exclusiongrpObject | ConvertTo-Json -Depth 10
            # Create the group using Microsoft Graph
            Write-Host "Creating group named $($exclusiongrp.Name)" -ForegroundColor Yellow
            If (!(Get-MgGroup -Filter "displayName eq '$($exclusiongrp.Name)'")){
                $null = New-MgGroup -BodyParameter $exclusionsBodyParam
                Write-Host "Group created successfully: $($exclusiongrp.Name) - Type: $($exclusiongrp.Type) " -ForegroundColor Green
            } Else {
                Write-Host "Group named $($exclusiongrp.Name) already exist" -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Host "Error while creating the group of exclusion: $_" -ForegroundColor Red
    }
}

If ($CAPs) {
    # Conditional Access
    # Get all json files in the directory
    $AllCAPs = Get-ChildItem -Path $CAPDirectory -Filter *.json

    ## Check if there are no json files
    If ($CAPs.Count -eq 0) {
        Write-Host "json files not found in the directory" -ForegroundColor Yellow
    } Else {
        ForEach ($Policy in $AllCAPs) {
            try {
                $Policy = Get-Content -Path $Policy.FullName | ConvertFrom-Json
                $PolicyObject = [PSCustomObject]@{
                    displayName     = $Policy.displayName
                    conditions      = $Policy.conditions
                    grantControls   = $Policy.grantControls
                    sessionControls = $Policy.sessionControls
                    state           = $Policy.state
                }
                $PolicyBodyParam = $PolicyObject | ConvertTo-Json -Depth 10
                # Create the CAP using Microsoft Graph
                $null = New-MgIdentityConditionalAccessPolicy -Body $PolicyBodyParam
                Write-Host "Policy created successfully: $($Policy.displayName) " -ForegroundColor Green
            }
            catch {
                Write-Host "Error while creating the policy: $_" -ForegroundColor Red
            }
        }
    }
}


##########################################################
#### Notes

## Administrative Unit
# Impossible to use groups under Administrative Unit with Identity Governance: https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/admin-units-restricted-management#limitations
# Only modifiable by GA and PIM Admin (not owner)

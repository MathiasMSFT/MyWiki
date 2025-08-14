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
    [switch]$DeployCAs,
    [Parameter(Mandatory=$false)]
    [switch]$RAUs,
    [Parameter(Mandatory=$false)]
    [switch]$GenerateCAs,
    [Parameter(Mandatory=$false)]
    [switch]$Locations
)


# Get Terms Of use
Function SearchTOU {
    Write-Host "    [-] Search Terms Of Use" -ForegroundColor Yellow
    $ExportTOU = $true
    ## Get InTune app
    $InTuneApp = Get-MgServicePrincipal -Filter "displayName eq 'Microsoft Intune'"
    $InTuneEnrollApp = Get-MgServicePrincipal -Filter "displayName eq 'Microsoft Intune Enrollment'"
    # Get TOU
    $TOUs = Get-MgAgreement -Property Id,DisplayName -ErrorAction SilentlyContinue
    If ($TOUs.DisplayName -contains "TOU-External-People") {
        # Write-Host "[✅] Terms Of Use found"
        $IdTOU = $(Get-MgAgreement -Filter 'DisplayName eq "TOU-External-People"' -ErrorAction SilentlyContinue).Id
    } elseif ($TOUs) {
        # Write-Host "[⚠️] Terms Of Use not found, but you've TOU. Modify "
        $SelectedTOU = $TOUs # | Out-GridView -Title "Select the Terms of Use" -PassThru
        if ($SelectedTOU) {
            $SelectedTOU | ForEach-Object {
                $IdTOU = $_.Id
            }
            # Write-Host "[✅] $($_.DisplayName) selected ($IdTOU)"
        } else {
            # Write-Host "[ℹ️] No TOU selected."
            $ExportTOU = $false
        }
    } else {
        $ExportTOU = $false
    }
    Return $ExportTOU
}
Function SearchTOU {
    Write-Host "    [-] Search Terms Of Use" -ForegroundColor Yellow
    $ExportTOU = $true
    ## Get TOU
    $TOUs = Get-MgAgreement -Property Id,DisplayName -ErrorAction SilentlyContinue
    If ($TOUs.DisplayName -contains "TOU-External-People") {
        # Write-Host "[✅] Terms Of Use found"
        $IdTOU = $(Get-MgAgreement -Filter 'DisplayName eq "TOU-External-People"' -ErrorAction SilentlyContinue).Id
    } elseif ($TOUs) {
        # Write-Host "[⚠️] Terms Of Use not found, but you've TOU. Modify "
        $SelectedTOU = $TOUs # | Out-GridView -Title "Select the Terms of Use" -PassThru
        if ($SelectedTOU) {
            $SelectedTOU | ForEach-Object {
                $IdTOU = $_.Id
            }
            # Write-Host "[✅] $($_.DisplayName) selected ($IdTOU)"
        } else {
            # Write-Host "[ℹ️] No TOU selected."
            $ExportTOU = $false
        }
    } else {
        $ExportTOU = $false
    }
    Return $ExportTOU
}
$global:IdTOU

# Connect to Microsoft Graph
Connect-MgGraph -Scopes 'Policy.Read.All', 'Policy.ReadWrite.ConditionalAccess', 'Application.Read.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'AdministrativeUnit.ReadWrite.All' -TenantId $TenantId -NoWelcome

# Path of deployment directory
$DeploymentDirectory = ".\Deployment"

If ($RAUs) {
    # Restricted Administrative Unit
    $AllRAUs = Get-Content -Path "$DeploymentDirectory\RestrictedAU.json" | ConvertFrom-Json -Depth 10

    ForEach ($RAU in $AllRAUs.RestrictedAU) {
        try {
            $RAUObject = [PSCustomObject]@{
                displayName     = $RAU.displayName
                description     = $RAU.description
                IsMemberManagementRestricted = $true
            }
            $RAUBodyParam = $RAUObject | ConvertTo-Json -Depth 10

            # Create the RAU using Microsoft Graph
            $null = New-MgDirectoryAdministrativeUnit -Body $RAUBodyParam
            Write-Host "    RAU created successfully: $($RAU.displayName) " -ForegroundColor Green
        }
        catch {
            Write-Host "    Error while creating the RAU: $_" -ForegroundColor Red
        }
    }
}

If ($Groups) {
    # To store details of groups to update all CAPs json files
    $GroupDetails = @()
    # All groups
    $AllGroups = Get-Content -Path "$DeploymentDirectory\Groups.json" -Raw | ConvertFrom-Json -Depth 10
    # Personas
    ForEach ($persona in $AllGroups.Personas) {
        try {
            # Switch manual vs dynamic
            Switch ($($persona.Type)){
                "manual" {
                    $PersonaObject = [PSCustomObject]@{
                        "@odata.type" = "#microsoft.graph.group"
                        DisplayName = $persona.Name
                        GroupTypes = @()
                        SecurityEnabled = $true
                        IsAssignableToRole = $persona.IsAssignable
                        MailEnabled = $false
                        MailNickname = (New-Guid).Guid.Substring(0,10)
                        Description = $persona.Description
                    }
                }
                "dynamic" {
                    $PersonaObject = [PSCustomObject]@{
                        "@odata.type" = "#microsoft.graph.group"
                        DisplayName = $persona.Name
                        GroupTypes = @('DynamicMembership')
                        SecurityEnabled = $true
                        IsAssignableToRole = $persona.IsAssignable
                        MailEnabled = $false
                        MailNickname = (New-Guid).Guid.Substring(0,10)
                        Description = $persona.Description
                        membershipRuleProcessingState = 'On'
                        MembershipRule = $persona.Rule
                    }
                }
                Default {Write-Host "Type of group is unknown" -ForegroundColor Red}
            }
            Write-Host "Persona : $($persona.Name)" -ForegroundColor Cyan
            $personaBodyParam = $personaObject | ConvertTo-Json -Depth 10

            # Get RestrictedAdministrativeUnit
            If ($persona.RestrictedAU -eq $true) {
                # Validate if the RAU exist
                $RestrictedAUObj = Get-MgDirectoryAdministrativeUnit -Filter "DisplayName eq '$($persona.RestrictedAUName)'"
                If ($RestrictedAUObj) {
                    # Create the group using Microsoft Graph to the RAU
                    Write-Host "    Creating group named $($persona.Name)" -ForegroundColor Yellow
                    If (!(Get-MgGroup -Filter "displayName eq '$($persona.Name)'")){
                        $CreateGroup = New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $($RestrictedAUObj.Id) -BodyParameter $personaBodyParam
                        $GroupDetails += @{
                            Id = $persona.Id
                            DisplayName = $persona.Name
                            ObjectGuid = $CreateGroup.Id
                        }
                        Write-Host "    [✅] Group created successfully: $($persona.Name) - Type: $($persona.Type) " -ForegroundColor Green
                    } Else {
                        $GroupId = (Get-MgGRoup -Filter "displayName eq '$($persona.Name)'").Id
                        $GroupDetails += @{
                            Id = $persona.Id
                            DisplayName = $persona.Name
                            ObjectGuid = $GroupId
                        }
                        Write-Host "    [✅] Group named $($persona.Name) already exist" -ForegroundColor Magenta
                    }
                } Else {
                    # Create the group using Microsoft Graph to the RAU
                    Write-Host "    Creating group named $($persona.Name)" -ForegroundColor Yellow
                    If (!(Get-MgGroup -Filter "displayName eq '$($persona.Name)'")){
                        $CreateGroup = New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $($RestrictedAUObj.Id) -BodyParameter $personaBodyParam
                        $GroupDetails += @{
                            Id = $persona.Id
                            DisplayName = $persona.Name
                            ObjectGuid = $CreateGroup.Id
                        }
                        Write-Host "    [✅] Group created successfully: $($persona.Name) - Type: $($persona.Type) " -ForegroundColor Green
                    } Else {
                        $GroupId = (Get-MgGRoup -Filter "displayName eq '$($persona.Name)'").Id
                        $GroupDetails += @{
                            Id = $persona.Id
                            DisplayName = $persona.Name
                            ObjectGuid = $GroupId
                        }
                        Write-Host "    [✅] Group named $($persona.Name) already exist" -ForegroundColor Magenta
                    }
                }
            } Else {
                # Create the group using Microsoft Graph
                Write-Host "    Creating group named $($persona.Name)" -ForegroundColor Yellow
                If (!(Get-MgGroup -Filter "displayName eq '$($persona.Name)'")){
                    $CreateGroup = New-MgGroup -BodyParameter $personaBodyParam
                    $GroupDetails += @{
                        Id = $persona.Id
                        DisplayName = $persona.Name
                        ObjectGuid = $CreateGroup.Id
                    }
                    Write-Host "    [✅] Group created successfully: $($persona.Name) - Type: $($persona.Type) " -ForegroundColor Green
                } Else {
                    $GroupId = (Get-MgGRoup -Filter "displayName eq '$($persona.Name)'").Id
                    $GroupDetails += @{
                        Id = $persona.Id
                        DisplayName = $persona.Name
                        ObjectGuid = $GroupId
                    }
                    Write-Host "    [✅] Group named $($persona.Name) already exist" -ForegroundColor Magenta
                }
            }
        }
        catch {
            Write-Host "    [❌] Error while creating the group: $_" -ForegroundColor Red
        }
    }

    # Exclusions
    ForEach ($exclusiongrp in $AllGroups.Exclusions){
        try{
            # Switch manual vs dynamic
            Switch ($exclusiongrp.Type){
                "manual" {
                    # Create a custom object
                    $exclusiongrpObject = [PSCustomObject]@{
                        "@odata.type" = "#microsoft.graph.group"
                        DisplayName = $exclusiongrp.Name
                        GroupTypes = @()
                        SecurityEnabled = $true
                        IsAssignableToRole = $exclusiongrp.IsAssignableToRole
                        MailEnabled = $false
                        MailNickname = (New-Guid).Guid.Substring(0,10)
                        Description = $exclusiongrp.Description
                    }
                }
                "dynamic" {
                    # Create a custom object
                    $exclusiongrpObject = [PSCustomObject]@{
                        "@odata.type" = "#microsoft.graph.group"
                        DisplayName = $exclusiongrp.Name
                        GroupTypes = @('DynamicMembership')
                        SecurityEnabled = $true
                        IsAssignableToRole = $exclusiongrp.IsAssignableToRole
                        MailEnabled = $false
                        MailNickname = (New-Guid).Guid.Substring(0,10)
                        Description = $exclusiongrp.Description
                        membershipRuleProcessingState = 'On'
                        MembershipRule = $exclusiongrp.Rule
                    }
                }
                Default {Write-Host "Type of group is unknown" -ForegroundColor Red}
            }
            Write-Host "Exclusions : $($exclusiongrp.Name)" -ForegroundColor Cyan
            $exclusionsBodyParam = $exclusiongrpObject | ConvertTo-Json -Depth 10
            # Create the group using Microsoft Graph
            Write-Host "    Creating group named $($exclusiongrp.Name)" -ForegroundColor Yellow
            If (!(Get-MgGroup -Filter "displayName eq '$($exclusiongrp.Name)'")){
                $CreateGroup = New-MgGroup -BodyParameter $exclusionsBodyParam
                $GroupDetails += @{
                    Id = $exclusiongrp.Id
                    DisplayName = $exclusiongrp.Name
                    ObjectGuid = $CreateGroup.Id
                }
                Write-Host "    [✅] Group created successfully: $($exclusiongrp.Name) - Type: $($exclusiongrp.Type) " -ForegroundColor Green
            } Else {
                $GroupId = (Get-MgGRoup -Filter "displayName eq '$($exclusiongrp.Name)'").Id
                $GroupDetails += @{
                    Id = $exclusiongrp.Id
                    DisplayName = $exclusiongrp.Name
                    ObjectGuid = $GroupId
                }
                Write-Host "    [✅] Group named $($exclusiongrp.Name) already exist" -ForegroundColor Magenta
            }
        }
        catch {
            Write-Host "    [❌] Error while creating the group of exclusion: $_" -ForegroundColor Red
        }
    }
    # Write the details of groups to update all CAPs json files
    $GroupDetails | ConvertTo-Json -Depth 10 | Set-Content -Path "$DeploymentDirectory\GroupDetails.json" -Force
}

If ($Locations) {
    # Locations
    $AllLocations = Get-Content -Path "$DeploymentDirectory\Locations.json" -Raw | ConvertFrom-Json -Depth 10
    ForEach ($location in $AllLocations.Locations) {
        try {
            If (!(Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq '$($location.Name)'")) {
                $namedLocation = @{
                    "@odata.type" = "#microsoft.graph.ipNamedLocation"
                    displayName = $location.Name
                    ipRanges = $location.IpRanges
                    isTrusted = $location.IsTrusted
                }

                # Create the location using Microsoft Graph
                $null = New-MgIdentityConditionalAccessNamedLocation -BodyParameter $namedLocation
                Write-Host "    Location created successfully: $($location.Name)" -ForegroundColor Green
            } else {
                Write-Host "    Location already exists: $($location.Name)" -ForegroundColor Magenta
            }
        } catch {
            Write-Host "    Error while creating the location: $_" -ForegroundColor Red
        }
    }
}

If ($GenerateCAs) {
    # Get all groups details
    $GroupDetails = Get-Content -Path "$DeploymentDirectory\GroupDetails.json" -Raw | ConvertFrom-Json  -Depth 10
    # Define $NewGroupIds based on $GroupDetails values
    $NewGroupIds = @{}
    foreach ($Group in $GroupDetails) {
        $NewGroupIds[$Group.Id] = $Group.ObjectGuid
    }

    # Get all json files in the directory
    $AllCAPs = Get-ChildItem -Path "$DeploymentDirectory\Templates\" -Filter *.json
    ## Check if there are no json files
    If ($AllCAPs.Count -eq 0) {
        Write-Host "[⚠️] Json files not found in the directory" -ForegroundColor Yellow
    } Else {
        ForEach ($Policy in $AllCAPs) {
            try {
                $Export = $true
                $ContentPolicy = Get-Content -Path $Policy.FullName | ConvertFrom-Json
                Write-Host "[-] Updating group IDs to $($ContentPolicy.DisplayName)" -ForegroundColor Yellow
                # User/Group assignment
                ## Exclude
                $UpdatedExcludeGroups = @()
                ForEach ($Group in $ContentPolicy.Conditions.Users.ExcludeGroups) {
                    # Write-Host "    GroupId in CAP: $Group" -ForegroundColor Yellow
                    $Match = $GroupDetails | Where-Object {$_.Id -eq $Group}
                    if ($Match) {
                        Write-Host "  [✅] Group matched '$($Group)' to '$($Match.ObjectGuid)'"
                        # $Group = $Match.ObjectGuid
                        $UpdatedExcludeGroups += $Match.ObjectGuid
                    } else {
                        Write-Host "  [⚠️] No match found for group '$($Group)' to '$($Match.ObjectGuid)'"
                        $UpdatedExcludeGroups += $Group
                    }
                }
                $ContentPolicy.Conditions.Users.ExcludeGroups = $UpdatedExcludeGroups

                ## Include
                $UpdatedIncludeGroups = @()
                ForEach ($Group in $ContentPolicy.Conditions.Users.IncludeGroups) {
                    # Write-Host "    GroupId in CAP: $Group" -ForegroundColor Yellow
                    $Match = $GroupDetails | Where-Object {$_.Id -eq $Group}
                    if ($Match) {
                        Write-Host "  [✅] Group matched '$($Group)' to '$($Match.ObjectGuid)'"
                        # $Group = $Match.ObjectGuid
                        $UpdatedIncludeGroups += $Match.ObjectGuid
                    } else {
                        Write-Host "  [⚠️] No match found for group '$($Group)' to '$($Match.ObjectGuid)'"
                        $UpdatedIncludeGroups += $Group
                    }
                }
                $ContentPolicy.Conditions.Users.IncludeGroups = $UpdatedIncludeGroups
                
                # Resource assignment
                ## ExcludeApplications
                If ($ContentPolicy.Conditions.Applications.ExcludeApplications -contains "d4ebce55-015a-49b5-a083-c84d1797ae8c") {
                    ## Get InTune Enrollment app
                    Write-Host "    [ℹ️] Try to find InTune in your tenant"
                    If (!(Get-MgServicePrincipal -Filter "displayName eq 'Microsoft Intune Enrollment'")) {
                        $ContentPolicy.Conditions.Applications.ExcludeApplications = $null
                        Write-Host "      [⚠️] InTune Enrollment will be removed from the policy"
                        $Export = $false
                    }
                }

                # Terms Of Use
                If ($ContentPolicy.GrantControls.TermsOfUse) {
                    Write-Host "    [ℹ️] Terms Of Use found in policy"
                    If (!(SearchTOU)) {
                        Write-Host "      [ℹ️] Terms Of Use policy will be excluded"
                        $Export = $false
                    } Else {
                        Write-Host "      [✅] Terms Of Use policy found"
                        $UpdatedTOUs = @()
                        ForEach ($TOU in $ContentPolicy.GrantControls.TermsOfUse) {
                            $UpdatedTOUs += $IdTOU
                        }
                        $ContentPolicy.GrantControls.TermsOfUse = $UpdatedTOUs
                    }
                }

                # Export the file
                If ($Export -eq $true) {
                    # Save new file
                    $UpdatedJson = $ContentPolicy | ConvertTo-Json -Depth 10
                    $Path = "$DeploymentDirectory\MyCAs\$($Policy.Name)"
                    Set-Content -Path $Path -Value $UpdatedJson -Encoding UTF8
                    Write-Host "  [✅] Group IDs updated successfully"
                }
            }
            catch {
                Write-Host "  [❌] Error while update the policy file: $_"
            }
        }
    }
}

If ($DeployCAs) {
    # Conditional Access
    # Get all json files in the directory
    $AllCAPs = Get-ChildItem -Path "$DeploymentDirectory\MyCAs\" -Filter *.json

    ## Check if there are no json files
    If ($AllCAPs.Count -eq 0) {
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
                If (!(Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$($Policy.displayName)'")) {
                    $null = New-MgIdentityConditionalAccessPolicy -Body $PolicyBodyParam
                    Write-Host "    [✅] Policy created successfully: $($Policy.displayName)"
                } Else {
                    Write-Host "    [✅] Policy named $($Policy.displayName) already exist" -ForegroundColor Magenta
                }
            }
            catch {
                Write-Host "    [❌] Error while creating the policy: $_"
            }
        }
    }
}


##########################################################
#### Notes
# Use an app and not an account

<#
    .SYNOPSIS
    Deploy-ZeroTrust-Solution.ps1

    .DESCRIPTION
    Deploy Groups and Conditional Access policies from json files.

    .MODULES
    Install-Module -Name Microsoft.Graph -Force -AllowClobber.
    Install-Module -Name Microsoft.Graph.Beta -Force -AllowClobber.

    .VERSION PS
    PowerShell v7
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
    [switch]$Locations,
    [Parameter(Mandatory=$false)]
    [switch]$FR
)


# Get Terms Of use
Function SearchInTune {
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
    param(
        [Parameter(Mandatory=$false)]
        [string]$PolicyName = ""
    )
    
    if ($PolicyName -ne "") {
        Write-Host "    [-] Select Terms Of Use for policy: $PolicyName" -ForegroundColor Yellow
    } else {
        Write-Host "    [-] Search Terms Of Use" -ForegroundColor Yellow
    }
    
    $ExportTOU = $true
    
    # Try to get TOU with diagnostic information
    try {
        Write-Host "      [ℹ️] Attempting to retrieve Terms of Use from tenant..." -ForegroundColor Gray
        $TOUs = Get-MgBetaAgreement -Property Id,DisplayName -ErrorAction SilentlyContinue
        
        # If Beta doesn't work, try v1.0
        if (!$TOUs) {
            Write-Host "      [ℹ️] Beta endpoint empty, trying v1.0..." -ForegroundColor Gray
            $TOUs = Get-MgAgreement -Property Id,DisplayName -ErrorAction SilentlyContinue
        }
        
        # Additional diagnostic
        if (!$TOUs) {
            Write-Host "      [ℹ️] Checking Graph permissions..." -ForegroundColor Gray
            $context = Get-MgContext
            Write-Host "      [ℹ️] Current scopes: $($context.Scopes -join ', ')" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "      [❌] Error retrieving Terms of Use: $($_.Exception.Message)" -ForegroundColor Red
        $ExportTOU = $false
        return $ExportTOU
    }
    
    if ($TOUs) {
        Write-Host "      [ℹ️] Found $($TOUs.Count) Terms Of Use in tenant:" -ForegroundColor Cyan
        
        # Display available Terms of Use
        for ($i = 0; $i -lt $TOUs.Count; $i++) {
            Write-Host "        [$($i+1)] $($TOUs[$i].DisplayName)" -ForegroundColor White
        }
        Write-Host "        [0] Skip Terms of Use (policy will be excluded)" -ForegroundColor Gray
        
        # Ask user to select  
        if ($PolicyName -ne "") {
            $prompt = "      Select Terms of Use for '$PolicyName' (0-$($TOUs.Count))"
        } else {
            $prompt = "      Please select a Terms of Use for external users (0-$($TOUs.Count))"
        }
        
        do {
            $choice = Read-Host $prompt
            if ($choice -match '^\d+$') {
                $choice = [int]$choice
            } else {
                $choice = -1
            }
        } while ($choice -lt 0 -or $choice -gt $TOUs.Count)
        
        if ($choice -eq 0) {
            Write-Host "      [ℹ️] No Terms of Use selected - Policy will be skipped" -ForegroundColor Yellow
            $ExportTOU = $false
        } else {
            $SelectedTOU = $TOUs[$choice - 1]
            $global:IdTOU = $SelectedTOU.Id
            Write-Host "      [✅] Selected TOU: $($SelectedTOU.DisplayName)" -ForegroundColor Green
        }
    } else {
        Write-Host "      [⚠️] No Terms Of Use found in tenant" -ForegroundColor Yellow
        Write-Host "      [ℹ️] Possible reasons:" -ForegroundColor Gray
        Write-Host "        • No Terms of Use are configured in Entra ID" -ForegroundColor Gray
        Write-Host "        • Missing Agreement.Read.All permission" -ForegroundColor Gray
        Write-Host "        • Terms of Use feature not enabled" -ForegroundColor Gray
        $ExportTOU = $false
    }
    Return $ExportTOU
}
Function Connect-To-MicrosoftGraph {
    try {
        Connect-MgGraph -Scopes 'Policy.Read.All','Policy.ReadWrite.ConditionalAccess', 'Application.Read.All', 'Agreement.Read.All' -TenantId $TenantId -NoWelcome -ErrorAction Stop
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


Import-Module Microsoft.Graph.Beta.Groups

# Connect to Microsoft Graph
Connect-To-MicrosoftGraph

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
            If (!(Get-MgBetaAdministrativeUnit -Filter "displayName eq '$($RAU.displayName)'")) {
                $null = New-MgBetaDirectoryAdministrativeUnit -Body $RAUBodyParam
                Write-Host "    RAU created successfully: $($RAU.displayName) " -ForegroundColor Green
            } Else {
                Write-Host "    RAU named $($RAU.displayName) already exist" -ForegroundColor Magenta
            }
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
                #V1.0 - $RestrictedAUObj = Get-MgDirectoryAdministrativeUnit -Filter "DisplayName eq '$($persona.RestrictedAUName)'"
                $RestrictedAUObj = Get-MgBetaAdministrativeUnit -Filter "DisplayName eq '$($persona.RestrictedAUName)'"
                If ($RestrictedAUObj) {
                    # Create the group using Microsoft Graph to the RAU
                    Write-Host "    Creating group named $($persona.Name)" -ForegroundColor Yellow
                    #V1.0 - If (!(Get-MgGroup -Filter "displayName eq '$($persona.Name)'")){
                    If (!(Get-MgBetaGroup -Filter "displayName eq '$($persona.Name)'")){
                        $CreateGroup = New-MgBetaDirectoryAdministrativeUnitMember -AdministrativeUnitId $($RestrictedAUObj.Id) -BodyParameter $personaBodyParam
                        $GroupDetails += @{
                            Id = $persona.Id
                            DisplayName = $persona.Name
                            ObjectGuid = $CreateGroup.Id
                        }
                        Write-Host "    [✅] Group created successfully: $($persona.Name) - Type: $($persona.Type) " -ForegroundColor Green
                    } Else {
                        #V1.0 - $GroupId = (Get-MgGRoup -Filter "displayName eq '$($persona.Name)'").Id
                        $GroupId = (Get-MgBetaGRoup -Filter "displayName eq '$($persona.Name)'").Id
                        
                        # Check if group is already in the RAU
                        $GroupInRAU = Get-MgBetaDirectoryAdministrativeUnitMember -AdministrativeUnitId $($RestrictedAUObj.Id) -Filter "id eq '$GroupId'" -ErrorAction SilentlyContinue
                        
                        If (!$GroupInRAU) {
                            # Group exists but is not in RAU, add it
                            Write-Host "    [⚠️] Group $($persona.Name) exists but not in RAU. Adding to RAU..." -ForegroundColor Yellow
                            $GroupRef = @{
                                "@odata.id" = "https://graph.microsoft.com/beta/directoryObjects/$GroupId"
                            }
                            New-MgBetaDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $($RestrictedAUObj.Id) -BodyParameter $GroupRef
                            Write-Host "    [✅] Group $($persona.Name) added to RAU successfully" -ForegroundColor Green
                        } Else {
                            Write-Host "    [✅] Group $($persona.Name) already exists and is in RAU" -ForegroundColor Green
                        }
                        
                        $GroupDetails += @{
                            Id = $persona.Id
                            DisplayName = $persona.Name
                            ObjectGuid = $GroupId
                        }
                    }
                } Else {
                    # Create the group using Microsoft Graph to the RAU
                    Write-Host "    Creating group named $($persona.Name)" -ForegroundColor Yellow
                    #V1.0 - If (!(Get-MgGroup -Filter "displayName eq '$($persona.Name)'")){
                    If (!(Get-MgBetaGroup -Filter "displayName eq '$($persona.Name)'")){
                        #V1.0 - $CreateGroup = New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $($RestrictedAUObj.Id) -BodyParameter $personaBodyParam
                        $CreateGroup = New-MgBetaDirectoryAdministrativeUnitMember -AdministrativeUnitId $($RestrictedAUObj.Id) -BodyParameter $personaBodyParam
                        $GroupDetails += @{
                            Id = $persona.Id
                            DisplayName = $persona.Name
                            ObjectGuid = $CreateGroup.Id
                        }
                        Write-Host "    [✅] Group created successfully: $($persona.Name) - Type: $($persona.Type) " -ForegroundColor Green
                    } Else {
                        $GroupId = (Get-MgBetaGRoup -Filter "displayName eq '$($persona.Name)'").Id
                        $GroupDetails += @{
                            Id = $persona.Id
                            DisplayName = $persona.Name
                            ObjectGuid = $GroupId
                        }
                        Write-Host "    [✅] Group named $($persona.Name) already exist (but RAU doesn't exist)" -ForegroundColor Magenta
                    }
                }
            } Else {
                # Create the group using Microsoft Graph
                Write-Host "    Creating group named $($persona.Name)" -ForegroundColor Yellow
                If (!(Get-MgBetaGroup -Filter "displayName eq '$($persona.Name)'")){
                    $CreateGroup = New-MgBetaGroup -BodyParameter $personaBodyParam
                    $GroupDetails += @{
                        Id = $persona.Id
                        DisplayName = $persona.Name
                        ObjectGuid = $CreateGroup.Id
                    }
                    Write-Host "    [✅] Group created successfully: $($persona.Name) - Type: $($persona.Type) " -ForegroundColor Green
                } Else {
                    $GroupId = (Get-MgBetaGroup -Filter "displayName eq '$($persona.Name)'").Id
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
            
            # Get RestrictedAdministrativeUnit for exclusion groups
            If ($exclusiongrp.RestrictedAU -eq $true) {
                # Validate if the RAU exist
                $RestrictedAUObj = Get-MgBetaAdministrativeUnit -Filter "DisplayName eq '$($exclusiongrp.RestrictedAUName)'"
                If ($RestrictedAUObj) {
                    # Create the group using Microsoft Graph to the RAU
                    Write-Host "    Creating exclusion group named $($exclusiongrp.Name)" -ForegroundColor Yellow
                    If (!(Get-MgBetaGroup -Filter "displayName eq '$($exclusiongrp.Name)'")){
                        $CreateGroup = New-MgBetaDirectoryAdministrativeUnitMember -AdministrativeUnitId $($RestrictedAUObj.Id) -BodyParameter $exclusionsBodyParam
                        $GroupDetails += @{
                            Id = $exclusiongrp.Id
                            DisplayName = $exclusiongrp.Name
                            ObjectGuid = $CreateGroup.Id
                        }
                        Write-Host "    [✅] Exclusion group created successfully: $($exclusiongrp.Name) - Type: $($exclusiongrp.Type) " -ForegroundColor Green
                    } Else {
                        $GroupId = (Get-MgBetaGRoup -Filter "displayName eq '$($exclusiongrp.Name)'").Id
                        
                        # Check if group is already in the RAU
                        $GroupInRAU = Get-MgBetaDirectoryAdministrativeUnitMember -AdministrativeUnitId $($RestrictedAUObj.Id) -Filter "id eq '$GroupId'" -ErrorAction SilentlyContinue
                        
                        If (!$GroupInRAU) {
                            # Group exists but is not in RAU, add it
                            Write-Host "    [⚠️] Exclusion group $($exclusiongrp.Name) exists but not in RAU. Adding to RAU..." -ForegroundColor Yellow
                            $GroupRef = @{
                                "@odata.id" = "https://graph.microsoft.com/beta/directoryObjects/$GroupId"
                            }
                            New-MgBetaDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $($RestrictedAUObj.Id) -BodyParameter $GroupRef
                            Write-Host "    [✅] Exclusion group $($exclusiongrp.Name) added to RAU successfully" -ForegroundColor Green
                        } Else {
                            Write-Host "    [✅] Exclusion group $($exclusiongrp.Name) already exists and is in RAU" -ForegroundColor Green
                        }
                        
                        $GroupDetails += @{
                            Id = $exclusiongrp.Id
                            DisplayName = $exclusiongrp.Name
                            ObjectGuid = $GroupId
                        }
                    }
                } Else {
                    # Create the group using Microsoft Graph (RAU doesn't exist)
                    Write-Host "    Creating exclusion group named $($exclusiongrp.Name)" -ForegroundColor Yellow
                    If (!(Get-MgBetaGroup -Filter "displayName eq '$($exclusiongrp.Name)'")){
                        $CreateGroup = New-MgBetaGroup -BodyParameter $exclusionsBodyParam
                        $GroupDetails += @{
                            Id = $exclusiongrp.Id
                            DisplayName = $exclusiongrp.Name
                            ObjectGuid = $CreateGroup.Id
                        }
                        Write-Host "    [✅] Exclusion group created successfully: $($exclusiongrp.Name) - Type: $($exclusiongrp.Type) " -ForegroundColor Green
                    } Else {
                        $GroupId = (Get-MgBetaGroup -Filter "displayName eq '$($exclusiongrp.Name)'").Id
                        $GroupDetails += @{
                            Id = $exclusiongrp.Id
                            DisplayName = $exclusiongrp.Name
                            ObjectGuid = $GroupId
                        }
                        Write-Host "    [✅] Exclusion group named $($exclusiongrp.Name) already exist (but RAU doesn't exist)" -ForegroundColor Magenta
                    }
                }
            } Else {
                # Create the group using Microsoft Graph (no RAU required)
                Write-Host "    Creating exclusion group named $($exclusiongrp.Name)" -ForegroundColor Yellow
                If (!(Get-MgBetaGroup -Filter "displayName eq '$($exclusiongrp.Name)'")){
                    $CreateGroup = New-MgBetaGroup -BodyParameter $exclusionsBodyParam
                    $GroupDetails += @{
                        Id = $exclusiongrp.Id
                        DisplayName = $exclusiongrp.Name
                        ObjectGuid = $CreateGroup.Id
                    }
                    Write-Host "    [✅] Exclusion group created successfully: $($exclusiongrp.Name) - Type: $($exclusiongrp.Type) " -ForegroundColor Green
                } Else {
                    $GroupId = (Get-MgBetaGroup -Filter "displayName eq '$($exclusiongrp.Name)'").Id
                    $GroupDetails += @{
                        Id = $exclusiongrp.Id
                        DisplayName = $exclusiongrp.Name
                        ObjectGuid = $GroupId
                    }
                    Write-Host "    [✅] Exclusion group named $($exclusiongrp.Name) already exist" -ForegroundColor Magenta
                }
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
    # To store details of groups to update all CAPs json files
    $LocationDetails = @()
    # Create / Update Named Locations (Trusted IP ranges)
    $LocationsFile = Join-Path $DeploymentDirectory 'Locations.json'
    if (!(Test-Path $LocationsFile)) {
        Write-Host "    [⚠️] Locations file not found: $LocationsFile" -ForegroundColor Yellow
    } else {
        try {
            $AllLocations = Get-Content -Path $LocationsFile -Raw | ConvertFrom-Json -Depth 10
        } catch {
            Write-Host "    [❌] Unable to parse Locations.json : $($_.Exception.Message)" -ForegroundColor Red
            return
        }

        foreach ($location in $AllLocations.namedLocations) {
            try {
                if (Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq '$($location.DisplayName)'") {
                    Write-Host "    [⚠️] Location already exists: $($location.DisplayName)" -ForegroundColor Yellow
                    $LocationId = (Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq '$($location.DisplayName)'").Id
                    $LocationDetails += @{
                        Id = $Location.Id
                        DisplayName = $location.DisplayName
                        ObjectGuid = $LocationId
                    }
                } Else {
                    # Build ipRanges objects with correct @odata.type
                    if ($location.ipRanges) {
                        $ipRanges = @()
                        foreach ($range in $location.ipRanges.CidrAddress) {
                        if ($range -match ":") {
                            # IPv6
                            $ipRanges += @{
                                "@odata.type" = "#microsoft.graph.iPv6CidrRange"
                                CidrAddress = $range
                            }
                        } else {
                            # IPv4
                            $ipRanges += @{
                                "@odata.type" = "#microsoft.graph.iPv4CidrRange"
                                CidrAddress = $range
                            }
                        }
                        }
                        $namedLocation = @{
                            "@odata.type" = "#microsoft.graph.ipNamedLocation"
                            displayName  = $location.DisplayName
                            ipRanges     = $ipRanges
                            isTrusted    = [bool]$location.IsTrusted
                        }
                        $null = New-MgIdentityConditionalAccessNamedLocation -BodyParameter $namedLocation
                        Write-Host "    [✅] Location created: $($location.DisplayName) (Ranges: $($location.ipRanges.CidrAddress -join ', '))" -ForegroundColor Green
                    }
                    # Build countrie objects with correct @odata.type
                    if ($location.countriesAndRegions) {
                        # Build countries objects with correct @odata.type
                        $namedLocation = @{
                            "@odata.type" = "#microsoft.graph.countryNamedLocation"
                            displayName  = $location.DisplayName
                            countriesAndRegions     = $location.countriesAndRegions
                            isTrusted    = [bool]$location.IsTrusted
                        }
                        $null = New-MgIdentityConditionalAccessNamedLocation -BodyParameter $namedLocation
                        Write-Host "    [✅] Location created: $($location.DisplayName) (Countries: $($location.CountriesAndRegions -join ', '))" -ForegroundColor Green
                    }
                    $LocationId = (Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq '$($location.DisplayName)'").Id
                    $LocationDetails += @{
                        Id = $Location.Id
                        DisplayName = $location.DisplayName
                        ObjectGuid = $LocationId
                    }
                }
            } catch {
                Write-Host "    [❌] Error processing location '$($location.DisplayName)': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    # Write the details of locations to update all CAs json files
    $LocationDetails | ConvertTo-Json -Depth 10 | Set-Content -Path "$DeploymentDirectory\LocationDetails.json" -Force
}

If ($GenerateCAs) {
    # Check if Terms of Use are available first
    Write-Host "[ℹ️] Checking for Terms of Use availability..." -ForegroundColor Cyan
    $TOUAvailable = SearchTOU
    if ($TOUAvailable) {
        Write-Host "  [✅] Terms of Use found - CA340 template will be included if available" -ForegroundColor Green
    } else {
        Write-Host "  [⚠️] No Terms of Use found - CA340 template will be skipped" -ForegroundColor Yellow
    }
    
    # Get all groups details
    $GroupDetails = Get-Content -Path "$DeploymentDirectory\GroupDetails.json" -Raw | ConvertFrom-Json  -Depth 10
    # Define $NewGroupIds based on $GroupDetails values
    $NewGroupIds = @{}
    foreach ($Group in $GroupDetails) {
        $NewGroupIds[$Group.Id] = $Group.ObjectGuid
    }

    # Get all locations details
    $LocationDetails = Get-Content -Path "$DeploymentDirectory\LocationDetails.json" -Raw | ConvertFrom-Json  -Depth 10
    # Define $NewLocationIds based on $LocationDetails values
    $NewLocationIds = @{}
    foreach ($Location in $LocationDetails) {
        $NewLocationIds[$Location.Id] = $Location.ObjectGuid
    }

    # Get all json files in the directory
    If ($FR) {
        $AllCAPs = Get-ChildItem -Path "$DeploymentDirectory\Templates\FR\" -Filter *.json
    } Else {
        $AllCAPs = Get-ChildItem -Path "$DeploymentDirectory\Templates\EN\" -Filter *.json
    }
    
    # Filter out 340A if Terms of Use are not available
    $ExcludedTemplateCount = 0
    if (!$TOUAvailable) {
        $OriginalCount = $AllCAPs.Count
        $AllCAPs = $AllCAPs | Where-Object { $_.Name -notlike "*340A*" }
        if ($AllCAPs -eq $null) { $AllCAPs = @() }
        $ExcludedTemplateCount = $OriginalCount - $AllCAPs.Count
        if ($ExcludedTemplateCount -gt 0) {
            Write-Host "  [ℹ️] $ExcludedTemplateCount template(s) excluded from processing (no Terms of Use)" -ForegroundColor Yellow
        }
    }
    
    # Count templates and generated policies (after filtering)
    $TemplateCount = $AllCAPs.Count
    $GeneratedCount = 0
    $FailedPolicies = @()
    
    ## Check if there are no json files
    If ($AllCAPs.Count -eq 0) {
        Write-Host "[⚠️] Json files not found in the directory" -ForegroundColor Yellow
    } Else {
        Write-Host "[ℹ️] Found $TemplateCount template(s) to process..." -ForegroundColor Cyan
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
                
                Write-Host "[-] Updating location IDs to $($ContentPolicy.DisplayName)" -ForegroundColor Yellow
                # Locations
                ## Exclude
                $UpdatedExcludeLocations = @()
                If ($($ContentPolicy.Conditions.Locations.ExcludeLocations) -ne $null) {
                    ForEach ($Location in $ContentPolicy.Conditions.Locations.ExcludeLocations) {
                        # Write-Host "    LocationId in CA: $Location" -ForegroundColor Yellow
                        $Match = $LocationDetails | Where-Object {$_.Id -eq $Location}
                        if ($Match) {
                            Write-Host "  [✅] Location matched '$($Location)' to '$($Match.ObjectGuid)'"
                            # $Location = $Match.ObjectGuid
                            $UpdatedExcludeLocations += $Match.ObjectGuid
                        } else {
                            Write-Host "  [⚠️] No match found for location '$($Location)' to '$($Match.ObjectGuid)'"
                            $UpdatedExcludeLocations += $Location
                        }
                    }
                    $ContentPolicy.Conditions.Locations.ExcludeLocations = $UpdatedExcludeLocations
                }
                ## Include
                $UpdatedIncludeLocations = @()
                If ($($ContentPolicy.Conditions.Locations.IncludeLocations) -ne $null) {
                    ForEach ($Location in $ContentPolicy.Conditions.Locations.IncludeLocations) {
                        # Write-Host "    LocationId in CA: $Location" -ForegroundColor Yellow
                        $Match = $LocationDetails | Where-Object {$_.Id -eq $Location}
                        if ($Match) {
                            Write-Host "  [✅] Location matched '$($Location)' to '$($Match.ObjectGuid)'"
                            # $Location = $Match.ObjectGuid
                            $UpdatedIncludeLocations += $Match.ObjectGuid
                        } else {
                            Write-Host "  [⚠️] No match found for location '$($Location)' to '$($Match.ObjectGuid)'"
                            $UpdatedIncludeLocations += $Location
                        }
                    }
                    $ContentPolicy.Conditions.Locations.IncludeLocations = $UpdatedIncludeLocations
                }

                # Resource assignment
                ## ExcludeApplications
                If ($ContentPolicy.Conditions.Applications.ExcludeApplications -contains "d4ebce55-015a-49b5-a083-c84d1797ae8c") {
                    ## Get InTune Enrollment app
                    Write-Host "    [ℹ️] Try to find InTune in your tenant"
                    If (!(Get-MgBetaServicePrincipal -Filter "displayName eq 'Microsoft Intune Enrollment'")) {
                        $ContentPolicy.Conditions.Applications.ExcludeApplications = $null
                        Write-Host "      [⚠️] InTune Enrollment will be removed from the policy"
                        $Export = $false
                    }
                }

                # Terms Of Use
                If ($ContentPolicy.GrantControls.TermsOfUse) {
                    Write-Host "    [ℹ️] Terms Of Use required for policy: $($ContentPolicy.DisplayName)" -ForegroundColor Magenta
                    If (!(SearchTOU -PolicyName $ContentPolicy.DisplayName)) {
                        Write-Host "      [ℹ️] Terms Of Use policy will be excluded"
                        $Export = $false
                    } Else {
                        Write-Host "      [✅] Terms Of Use selected for this policy"
                        $UpdatedTOUs = @()
                        ForEach ($TOU in $ContentPolicy.GrantControls.TermsOfUse) {
                            $UpdatedTOUs += $global:IdTOU
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
                    $GeneratedCount++
                } Else {
                    # Policy was not generated, add to failed list
                    $FailedPolicies += $ContentPolicy.DisplayName
                }
            }
            catch {
                Write-Host "  [❌] Error while update the policy file: $_"
                # Add to failed list in case of error
                try {
                    $ContentPolicy = Get-Content -Path $Policy.FullName | ConvertFrom-Json
                    $FailedPolicies += $ContentPolicy.DisplayName
                } catch {
                    $FailedPolicies += $Policy.Name
                }
            }
        }
        
        # Display comparison summary
        Write-Host "`n" -NoNewline
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "         GENERATION SUMMARY" -ForegroundColor Green  
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Templates found:       $TemplateCount" -ForegroundColor Cyan
        Write-Host "Policies generated:    $GeneratedCount" -ForegroundColor Cyan
        if ($ExcludedTemplateCount -gt 0) {
            Write-Host "Templates excluded:    $ExcludedTemplateCount (missing Terms of Use)" -ForegroundColor Yellow
        }
        
        if ($GeneratedCount -eq $TemplateCount) {
            if ($ExcludedTemplateCount -gt 0) {
                Write-Host "Status:                ✅ All available templates processed successfully ($ExcludedTemplateCount excluded)" -ForegroundColor Green
            } else {
                Write-Host "Status:                ✅ All templates processed successfully" -ForegroundColor Green
            }
        } elseif ($GeneratedCount -gt 0) {
            $MissingCount = $TemplateCount - $GeneratedCount
            Write-Host "Status:                ⚠️ $MissingCount template(s) not generated (see errors above)" -ForegroundColor Yellow
        } else {
            Write-Host "Status:                ❌ No policies generated" -ForegroundColor Red
        }
        
        # Show failed policies in markdown format
        if ($FailedPolicies.Count -gt 0) {
            Write-Host "`nFailed Policies:" -ForegroundColor Yellow
            Write-Host "## ⚠️ Policies Not Generated" -ForegroundColor Yellow
            Write-Host "" -ForegroundColor Gray
            foreach ($PolicyName in $FailedPolicies) {
                Write-Host "- ❌ **$PolicyName**" -ForegroundColor Yellow
            }
            Write-Host "" -ForegroundColor Gray
            Write-Host "**Possible reasons:**" -ForegroundColor Gray
            Write-Host "- Missing Terms of Use configuration" -ForegroundColor Gray
            Write-Host "- Microsoft Intune Enrollment not found" -ForegroundColor Gray
            Write-Host "- Invalid group or location references" -ForegroundColor Gray
            Write-Host "- JSON parsing errors" -ForegroundColor Gray
        }
        
        Write-Host "========================================" -ForegroundColor Green
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
                # V1.0 - If (!(Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$($Policy.displayName)'")) {
                If (!(Get-MgBetaIdentityConditionalAccessPolicy -Filter "displayName eq '$($Policy.displayName)'")) {
                    $null = New-MgBetaIdentityConditionalAccessPolicy -Body $PolicyBodyParam
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

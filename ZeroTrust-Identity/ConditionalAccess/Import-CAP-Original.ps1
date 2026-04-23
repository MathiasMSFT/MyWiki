<#
    .SYNOPSIS
    Import-CAP.ps1

    .DESCRIPTION
    Import Conditional Access policies from json file (one by policy)
#>
Param (
    [Parameter(Mandatory=$true)]
    [String]$TenantId,
    [Parameter(Mandatory=$false)]
    [switch]$CAPs,
    [Parameter(Mandatory=$false)]
    [switch]$Locations
)

# Connect to Microsoft Graph API
Connect-MgGraph -Scopes 'Policy.Read.All','Policy.ReadWrite.ConditionalAccess', 'Application.Read.All' -TenantId $TenantId -NoWelcome
$Path = (Get-Location).Path

If ($CAPs) {
    # Define the path to the directory containing your JSON files
    #$ImportCAPsDirectory = ".\Import\CAPs\"
    $ImportCAPsDirectory = "C:\GitHub\MathiasDumontOrg\ZeroTrust-Identity\ConditionalAccess\RAMQ\Import\CAPs"
    #$ImportCAPsDirectory = ".\RAMQ\Import\CAPs"
    Write-Host $ImportCAPsDirectory

    # Get all JSON files in the directory
    $CAPs = Get-ChildItem -Path "C:\GitHub\MathiasDumontOrg\ZeroTrust-Identity\ConditionalAccess\RAMQ\Import\CAPs" -Filter *.json

    # Check if there are no JSON files
    If ($CAPs.Count -ne 0) {
        ForEach ($Policy in $CAPs) {
            try {
                # Vérifie si le fichier existe et est lisible
                if (Test-Path -Path $Policy.FullName) {
                    Write-Host "Reading file: $($Policy.FullName)" -ForegroundColor Cyan
                    $PolicyContent = Get-Content -Path $Policy.FullName -ErrorAction Stop
                    $PolicyObject = $PolicyContent | ConvertFrom-Json -ErrorAction Stop
                    
                    # Assure-toi que les propriétés nécessaires existent dans le JSON
                    if ($PolicyObject.PSObject.Properties['displayName']) {
                        $displayName = $PolicyObject.displayName
                    } else {
                        Write-Host "Missing displayName in policy: $($Policy.FullName)" -ForegroundColor Red
                        continue
                    }
        
                    # Crée l'objet politique
                    $PolicyBodyParam = [PSCustomObject]@{
                        displayName = $PolicyObject.displayName
                        conditions = $PolicyObject.conditions
                        grantControls = $PolicyObject.grantControls
                        sessionControls = $PolicyObject.sessionControls
                        state = $PolicyObject.state
                    }
        
                    # Convertir en JSON pour l'API
                    $PolicyBodyParamJson = $PolicyBodyParam | ConvertTo-Json -Depth 10
        
                    # Vérifie l'existence de la politique
                    If ((Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$($PolicyObject.displayName)'").Count -eq 0) {
                        # Crée la politique via l'API
                        $null = New-MgIdentityConditionalAccessPolicy -Body $PolicyBodyParamJson
                        Write-Host "Policy created successfully: $($PolicyObject.displayName)" -ForegroundColor Green
                    } Else {
                        Write-Host "Policy already exists: $($PolicyObject.displayName)" -ForegroundColor Magenta
                    }
                } else {
                    Write-Host "File not found: $($Policy.FullName)" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "Error reading or processing the policy: $_" -ForegroundColor Red
            }
        }
        
        <# ForEach ($Policy in $CAPs) {
            try {
                $Policy
                $Policy = Get-Content -Path $($Policy) | ConvertFrom-Json

                # Create a custom object
                $PolicyObject = [PSCustomObject]@{
                    displayName = $Policy.displayName
                    conditions = $Policy.conditions
                    grantControls = $Policy.grantControls
                    sessionControls = $Policy.sessionControls
                    state = $Policy.state
                }

                # Convert the custom object to JSON with a depth of 10
                $PolicyBodyParam = $PolicyObject | ConvertTo-Json -Depth 10

                If ((Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$($Policy.displayName)'").Count -eq 0) {
                    # Create the Conditional Access policy using the Microsoft Graph API
                    $null = New-MgIdentityConditionalAccessPolicy -Body $PolicyBodyParam
                    Write-Host "Policy created successfully: $($Policy.displayName) " -ForegroundColor Green
                } Else {
                    Write-Host "Policy already exists: $($Policy.displayName) " -ForegroundColor Magenta
                }

            }
            catch {
                Write-Host "Error while creating the policy: $_" -ForegroundColor Red
            }
        }#>
        
    } Else {
        Write-Host "No JSON files found in the directory to import." -ForegroundColor Yellow
    }
}

If ($Locations){
    #$ImportLocationsDirectory = ".\Import\Locations\"
    $ImportLocationsDirectory = ".\RAMQ\Import\Locations\"

    # Get all json files in the directory
    $AllLocations = Get-ChildItem -Path $ImportLocationsDirectory -Filter *.json

    # Check if there are no JSON files
    If ($AllLocations.Count -eq 0) {
        Write-Host "No JSON files found in the directory to import." -ForegroundColor Yellow
    } Else {
        ForEach ($Location in $AllLocations) {
            try {
                # Lire le fichier JSON
                $Location = Get-Content -Path $Location.FullName | ConvertFrom-Json
                $Type = $Location.AdditionalProperties.'@odata.type'
                Switch ($Type) {
                    "#microsoft.graph.ipNamedLocation" {
                        # IpRanges
                        $IpRangeObjects = $Location.AdditionalProperties.ipRanges | ForEach-Object {
                            @{
                                '@odata.type' = $_.'@odata.type'
                                'cidrAddress' = $_.cidrAddress
                            }
                        }
                        $Body = @{
                            "@odata.type"= $Location.AdditionalProperties.'@odata.type'
                            "DisplayName"= $Location.DisplayName
                            "isTrusted"= $Location.AdditionalProperties.isTrusted
                            "IpRanges"= @(
                                $IpRangeObjects
                            )
                        }
                    }
                    "#microsoft.graph.countryNamedLocation" {
                        # Countries
                        $Body = @{
                            "@odata.type"= $Location.AdditionalProperties.'@odata.type'
                            "DisplayName"= $Location.DisplayName
                            "CountriesAndRegions"= $Location.AdditionalProperties.CountriesAndRegions
                            "IncludeUnknownCountriesAndRegions" = $Location.AdditionalProperties.IncludeUnknownCountriesAndRegions
                            "countryLookupMethod" = $Location.AdditionalProperties.countryLookupMethod
                        }
                    }
                }

                If ((Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq '$($Location.displayName)'").Count -eq 0) {
                    # Create the named location using Microsoft Graph
                    $null = New-MgIdentityConditionalAccessNamedLocation -Body $Body
                    Write-Host "Location created successfully: $($Location.displayName) " -ForegroundColor Green
                } Else {
                    Write-Host "Location already exists: $($Location.displayName) " -ForegroundColor Magenta
                }
            }
            catch {
                Write-Host "Error while creating the location: $_" -ForegroundColor Red
            }
        }
    }
}

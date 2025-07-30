<#
    .SYNOPSIS
    Import-CAP.ps1

    .DESCRIPTION
    Import Conditional Access policies from json file (one by policy).
#>

Param (
    [Parameter(Mandatory=$true)]
    [String]$TenantId,

    [Parameter(Mandatory=$false)]
    [switch]$CAPs,

    [Parameter(Mandatory=$false)]
    [switch]$Locations
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

# Fonction pour lire et valider un fichier JSON
function Get-ValidJson {
    param (
        [string]$FilePath
    )

    try {
        $JsonContent = Get-Content -Path $FilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        Write-Host "Successfully read JSON from file: $FilePath" -ForegroundColor Cyan
        return $JsonContent
    } catch {
        Write-Error "Error reading or parsing JSON from file: $FilePath. Error: $_"
        return $null
    }
}

# Fonction pour créer une politique d'accès conditionnel
function Create-ConditionalAccessPolicy {
    param (
        [PSCustomObject]$PolicyObject
    )

    $PolicyBody = [PSCustomObject]@{
        displayName   = $PolicyObject.displayName
        conditions    = $PolicyObject.conditions
        grantControls = $PolicyObject.grantControls
        sessionControls = $PolicyObject.sessionControls
        state         = $PolicyObject.state
    }

    $PolicyJson = $PolicyBody | ConvertTo-Json -Depth 10
    $existingPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$($PolicyObject.displayName)'"

    if ($existingPolicy.Count -eq 0) {
        New-MgIdentityConditionalAccessPolicy -Body $PolicyJson
        Write-Host "Policy created successfully: $($PolicyObject.displayName)" -ForegroundColor Green
    } else {
        Write-Host "Policy already exists: $($PolicyObject.displayName)" -ForegroundColor Magenta
    }
}

# Fonction pour créer une location nommée
function Create-NamedLocation {
    param (
        [PSCustomObject]$LocationObject
    )

    $Body = @{}

    switch ($LocationObject.AdditionalProperties.'@odata.type') {
        "#microsoft.graph.ipNamedLocation" {
            $IpRangeObjects = $LocationObject.AdditionalProperties.ipRanges | ForEach-Object {
                @{ '@odata.type' = $_.'@odata.type'; 'cidrAddress' = $_.cidrAddress }
            }
            $Body = @{
                "@odata.type"     = $LocationObject.AdditionalProperties.'@odata.type'
                "DisplayName"     = $LocationObject.DisplayName
                "isTrusted"       = $LocationObject.AdditionalProperties.isTrusted
                "IpRanges"        = $IpRangeObjects
            }
        }
        "#microsoft.graph.countryNamedLocation" {
            $Body = @{
                "@odata.type"                    = $LocationObject.AdditionalProperties.'@odata.type'
                "DisplayName"                    = $LocationObject.DisplayName
                "CountriesAndRegions"            = $LocationObject.AdditionalProperties.CountriesAndRegions
                "IncludeUnknownCountriesAndRegions" = $LocationObject.AdditionalProperties.IncludeUnknownCountriesAndRegions
                "countryLookupMethod"           = $LocationObject.AdditionalProperties.countryLookupMethod
            }
        }
    }

    $existingLocation = Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq '$($LocationObject.displayName)'"

    if ($existingLocation.Count -eq 0) {
        New-MgIdentityConditionalAccessNamedLocation -Body $Body
        Write-Host "Location created successfully: $($LocationObject.displayName)" -ForegroundColor Green
    } else {
        Write-Host "Location already exists: $($LocationObject.displayName)" -ForegroundColor Magenta
    }
}

# Connexion à Microsoft Graph
Connect-To-MicrosoftGraph

# Si l'option CAPs est activée
if ($CAPs) {
    $ImportCAPsDirectory = ".\RAMQ\Import\CAPs"

    # Récupérer tous les fichiers JSON dans le répertoire spécifié
    $CAPFiles = Get-ChildItem -Path $ImportCAPsDirectory -Filter *.json

    # Vérifier si aucun fichier JSON n'a été trouvé
    If ($CAPFiles.Count -ne 0) {
        ForEach ($PolicyFile in $CAPFiles) {
            $PolicyObject = Get-ValidJson -FilePath $PolicyFile.FullName
            if ($PolicyObject) {
                Create-ConditionalAccessPolicy -PolicyObject $PolicyObject
            }
        }
    } else {
        Write-Host "No JSON files found in the directory to import." -ForegroundColor Yellow
    }

}

# Si l'option Locations est activée
if ($Locations) {
    $ImportLocationsDirectory = ".\RAMQ\Import\Locations\"
    $AllLocations = Get-ChildItem -Path $ImportLocationsDirectory -Filter *.json

    if ($AllLocations.Count -eq 0) {
        Write-Host "No JSON files found in the directory to import." -ForegroundColor Yellow
    } else {
        foreach ($LocationFile in $AllLocations) {
            $LocationObject = Get-ValidJson -FilePath $LocationFile.FullName
            if ($LocationObject) {
                Create-NamedLocation -LocationObject $LocationObject
            }
        }
    }
}

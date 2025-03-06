Param (
    [Parameter(Mandatory=$true)]
    [String]$TenantId,
    [Parameter(Mandatory=$true)]
    [string]$DaysToCheck,
    [Parameter(Mandatory=$true)]
    [array]$Regions
)
# .\Named-Location.ps1 -TenantId "ee942b75-82c7-42bc-9585-ccc5628492d9" -daystocheck 7 -region canadaeast,canadacentral
# Source: https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-assignment-network#ipv4-and-ipv6-address-ranges

# Loop to check the files of the last days
for ($i = 0; $i -lt $DaysToCheck; $i++) {
    # Calculate the date to check
    $DateToCheck = (Get-Date).AddDays(-$i).ToString("yyyyMMdd")
    
    # Build the URL with the date
    $downloadUrl = "https://download.microsoft.com/download/7/1/D/71D86715-5596-4529-9B13-DA13A5DE5B63/ServiceTags_Public_$DateToCheck.json"
    
    # Try to download the file
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile ".\ServiceTags_Public_$DateToCheck.json" -ErrorAction Stop
        Write-Host "File downloaded successfully for the date: $DateToCheck"
        break
    } catch {
        Write-Host "File not available for the date: $DateToCheck"
    }
}

## Connection - Conditional Access
Connect-MgGraph -Scopes "Policy.Read.All,Policy.ReadWrite.ConditionalAccess" -TenantId $TenantId -NoWelcome

## Open json file and filter data
$jsonContent = Get-Content ".\ServiceTags_Public_$DateToCheck.json" | ConvertFrom-Json


# Entra ID services
# - Entra ID
# - Entra Domain Services
# - Entra Service Endpoint
Write-Host "Processing Entra ID services" -ForegroundColor Yellow
# Filter by a specific property
$filteredData = $jsonContent.values | Where-Object {($_.id -eq "AzureActiveDirectory") -or ($_.id -eq "AzureActiveDirectoryDomainServices") -or ($_.id -eq "AzureActiveDirectory.ServiceEndpoint")}

# Extract the addressPrefixes property
$addressPrefixes = $filteredData.properties.addressPrefixes
# Output the addressPrefixes
Write-Host "    $($addressPrefixes.Count) IP ranges found for Entra ID"

# Format the addressPrefixes for ipRanges
$ipRanges = @()
foreach ($prefix in $addressPrefixes) {
    if ($prefix -match ":") {
        $ipRanges += @{
            "@odata.type" = "#microsoft.graph.iPv6CidrRange"
            CidrAddress = $prefix
        }
    } else {
        $ipRanges += @{
            "@odata.type" = "#microsoft.graph.iPv4CidrRange"
            CidrAddress = $prefix
        }
    }
}
# $ipRanges

# Create a named location in Azure AD Conditional Access
If (Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq 'Microsoft - Entra ID'") {
    Write-Host "Named location already exists: Microsoft - Entra ID" -ForegroundColor Magenta
} else {
    $namedLocation = @{
        "@odata.type" = "#microsoft.graph.ipNamedLocation"
        displayName = "Microsoft - Entra ID"
        ipRanges = $ipRanges
        isTrusted = $false
    }
    New-MgIdentityConditionalAccessNamedLocation -BodyParameter $namedLocation
    Write-Host "Named location created successfully: Microsoft - Entra ID" -ForegroundColor Green
}

# For each regions
ForEach ($Region in $Regions) {
    Write-Host "Processing region: $region" -ForegroundColor Yellow
    
    # Filter by a specific property
    $filteredData = $jsonContent.values | Where-Object { $_.properties.region -eq $Region }

    # Extract the addressPrefixes property
    $addressPrefixes = $filteredData.properties.addressPrefixes
    # Output the addressPrefixes
    Write-Host "    $($addressPrefixes.Count) IP ranges found for region: $Region"

    # Format the addressPrefixes for ipRanges
    $ipRanges = @()
    foreach ($prefix in $addressPrefixes) {
        if ($prefix -match ":") {
            $ipRanges += @{
                "@odata.type" = "#microsoft.graph.iPv6CidrRange"
                CidrAddress = $prefix
            }
        } else {
            $ipRanges += @{
                "@odata.type" = "#microsoft.graph.iPv4CidrRange"
                CidrAddress = $prefix
            }
        }
    }
    # $ipRanges

    # Create a named location in Azure AD Conditional Access
    If (Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq 'Microsoft - $Region'") {
        Write-Host "Named location already exists: Microsoft - $Region" -ForegroundColor Magenta
    } else {
        $namedLocation = @{
            "@odata.type" = "#microsoft.graph.ipNamedLocation"
            displayName = "Microsoft - $Region"
            ipRanges = $ipRanges
            isTrusted = $false
        }
        New-MgIdentityConditionalAccessNamedLocation -BodyParameter $namedLocation
        Write-Host "Named location created successfully: Microsoft - $Region" -ForegroundColor Green
    }
}

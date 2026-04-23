function New-IPv4CidrRange {
    param (
        [string]$cidrAddress
    )
    return @{
        "@odata.type" = "#microsoft.graph.iPv4CidrRange"
        CidrAddress = $cidrAddress
    }
}

$IpRanges = @(
    @{
        "@odata.type" = "#microsoft.graph.iPv4CidrRange"
        CidrAddress = "12.34.221.11/22"
    }
    @{
        "@odata.type" = "#microsoft.graph.iPv6CidrRange"
        CidrAddress = "2001:0:9d38:90d6:0:0:0:0/63"
    }
)

$ImportIpRanges = @()
$IpRanges | ForEach {
    $ImportIpRanges += New-IPv4CidrRange -cidrAddress $($_.CidrAddress)
}

Write-Host "Result: $ImportIpRanges[1]"




<#
  $Location.AdditionalProperties.ipRanges | ForEach {
                    
                    $IpRanges=@{}
                    $IpRanges.add("@odata.type" , "#microsoft.graph.iPv4CidrRange")
                    $IpRanges.add("CidrAddress" , $($_.CidrAddress))
                    $LocationObject.IpRanges+=$IpRanges
                    Write-Host "Result: $IpRanges" -ForegroundColor Yellow
                }
#>
Param (
    [Parameter(Mandatory=$true)]
    [String]$TenantId,
    [Parameter(Mandatory=$true)]
    [String]$SubscriptionId,
    [Parameter(Mandatory=$false)]
    [String]$Identity,
    [Parameter(Mandatory=$false)]
    [Switch]$Start,
    [Parameter(Mandatory=$false)]
    [Switch]$JIT
)

# Import Az module
# Import-Module Az -DisableNameChecking

# Connect to your Azure account
If ($Identity) {
    Connect-AzAccount -Tenant $TenantId -Subscription $SubscriptionId -AccountId $Identity
} Else {
    Connect-AzAccount -Tenant $TenantId -Subscription $SubscriptionId
}

# My public ip
$MyIP = (Invoke-WebRequest -Uri "https://api.ipify.org").Content

# Get all VMs in the subscription
Write-Output "Retrieving list of virtual machines..."
$allVMs = Get-AzVM

if ($allVMs.Count -eq 0) {
    Write-Error "No virtual machines found in the current subscription."
    exit
}

# Display VMs grouped by resource group
Write-Output "`nAvailable Virtual Machines:"
Write-Output "============================"

$vmIndex = 1
$vmList = @()

foreach ($vm in $allVMs) {
    $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
    $powerState = ($vmStatus.Statuses | Where-Object {$_.Code -like "PowerState/*"}).DisplayStatus
    
    Write-Output "$vmIndex. $($vm.Name) (RG: $($vm.ResourceGroupName)) - Status: $powerState"
    
    $vmList += @{
        Index = $vmIndex
        Name = $vm.Name
        ResourceGroupName = $vm.ResourceGroupName
        Location = $vm.Location
        Id = $vm.Id
        PowerState = $powerState
    }
    
    $vmIndex++
}

# Get user selection
Write-Output "`nEnter the number of the VM you want to take action for:"
$selection = Read-Host "VM Number"

try {
    $selectedIndex = [int]$selection
    if ($selectedIndex -lt 1 -or $selectedIndex -gt $vmList.Count) {
        Write-Error "Invalid selection. Please run the script again."
        exit
    }
} catch {
    Write-Error "Invalid input. Please enter a number."
    exit
}

$selectedVM = $vmList[$selectedIndex - 1]

# Set variables for the selected VM
$resourceGroupName = $selectedVM.ResourceGroupName
$vmName = $selectedVM.Name
$portNumber = 3389  # RDP port

Write-Output "`nSelected VM: $vmName in Resource Group: $resourceGroupName"
Write-Output "Current Status: $($selectedVM.PowerState)"

# Get the virtual machine object
$vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName

If ($JIT) {
    # Create JIT policy configuration
    $JitPolicy = @{
        id = $vm.Id
        ports = @(
            @{
                number = $portNumber
                protocol = "*"
                allowedSourceAddressPrefix = @($MyIP)
                maxRequestAccessDuration = "PT4H"
            }
        )
    }

    try {
        # Enable Just-In-Time (JIT) VM Access policy
        Set-AzJitNetworkAccessPolicy `
            -ResourceGroupName $resourceGroupName `
            -Location $vm.Location `
            -Name "default" `
            -Kind "Basic" `
            -VirtualMachine $JitPolicy

        Write-Output "✓ JIT Policy configured successfully for $vmName"

        # Wait a moment for the policy to be fully applied
        Start-Sleep -Seconds 3

        # Try the PowerShell cmdlet first, then fallback to REST API
        try {
            # Request JIT access for the VM using array format
            $JitAccessRequest = @(
                @{
                    id = $vm.Id
                    ports = @(
                        @{
                            number = $portNumber
                            allowedSourceAddressPrefix = $MyIP
                            endTimeUtc = (Get-Date).AddHours(4).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        }
                    )
                }
            )

            # Submit the JIT access request
            Start-AzJitNetworkAccessPolicy `
                -ResourceGroupName $resourceGroupName `
                -Location $vm.Location `
                -Name "default" `
                -VirtualMachine $JitAccessRequest

            Write-Output "✓ JIT Access requested successfully for $vmName"
        } catch {
            Write-Warning "PowerShell cmdlet failed for $vmName. Trying REST API..."
            
            # Alternative approach: Use REST API directly
            try {
                $subscriptionId = (Get-AzContext).Subscription.Id
                $resourceGroupNameUpper = $resourceGroupName.ToUpper()
                
                $requestBody = @{
                    virtualMachines = @(
                        @{
                            id = $vm.Id
                            ports = @(
                                @{
                                    number = $portNumber
                                    allowedSourceAddressPrefix = $MyIP
                                    endTimeUtc = (Get-Date).AddHours(4).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                                }
                            )
                        }
                    )
                } | ConvertTo-Json -Depth 5
                
                $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupNameUpper/providers/Microsoft.Security/locations/$($vm.Location)/jitNetworkAccessPolicies/default/initiate?api-version=2020-01-01"
                
                $result = Invoke-AzRestMethod -Uri $uri -Method POST -Payload $requestBody
                
                if ($result.StatusCode -eq 202) {
                    Write-Output "✓ JIT Access requested successfully for $vmName via REST API"
                } else {
                    Write-Warning "Failed to request JIT access for $vmName. Status: $($result.StatusCode)"
                    Write-Output "Response: $($result.Content)"
                }
            } catch {
                Write-Warning "REST API also failed for $vmName : $($_.Exception.Message)"
            }
        }
    } catch {
        Write-Warning "Failed to configure JIT for $vmName : $($_.Exception.Message)"
        continue
    }
}

If ($Start) {
    # Check VM status and start if needed
    $vmStatus = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Status
    $powerState = ($vmStatus.Statuses | Where-Object {$_.Code -like "PowerState/*"}).DisplayStatus

    Write-Output "Current VM status: $powerState"

    if ($powerState -ne "VM running") {
        Write-Output "Starting VM: $vmName"
        Start-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -NoWait
        Write-Output "VM start command initiated. The VM is starting in the background."
    } else {
        Write-Output "VM is already running."
    }
}


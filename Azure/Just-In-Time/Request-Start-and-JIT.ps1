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

# Import Az module if not already loaded
if (!(Get-Module -Name Az.Accounts -ListAvailable)) {
    Write-Output "Installing Az module..."
    Install-Module -Name Az -Force -AllowClobber -Scope CurrentUser
}

# Connect to your Azure account
Write-Output "Connecting to Azure..."
If ($Identity) {
    Connect-AzAccount -Tenant $TenantId -Subscription $SubscriptionId -AccountId $Identity
} Else {
    Connect-AzAccount -Tenant $TenantId -Subscription $SubscriptionId
}

# Get current public IP
Write-Output "Getting your public IP address..."
$MyIP = (Invoke-WebRequest -Uri "https://api.ipify.org").Content
Write-Output "Your public IP: $MyIP"

# Get all VMs in the subscription
Write-Output "`nRetrieving list of virtual machines..."
$allVMs = Get-AzVM

if ($allVMs.Count -eq 0) {
    Write-Error "No virtual machines found in the current subscription."
    exit
}

# Display VMs with status
Write-Output "`nAvailable Virtual Machines:"
Write-Output "============================"

$vmIndex = 1
$vmList = @()

foreach ($vm in $allVMs) {
    Write-Output "Checking status for VM: $($vm.Name)..."
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

# Get user selection for multiple VMs
Write-Output "`nEnter the number(s) of the VM(s) you want to process:"
Write-Output "(Multiple VMs: use commas like 1,3,5 | Single VM: just the number like 2)"
$selection = Read-Host "VM Number(s)"

# Parse and validate selections
$selectedNumbers = @()
try {
    if ($selection.Contains(",")) {
        # Multiple selections with comma separation
        $selectedNumbers = $selection.Split(",") | ForEach-Object { [int]$_.Trim() }
    } else {
        # Single selection
        $selectedNumbers = @([int]$selection.Trim())
    }
    
    # Validate all selections are within range
    foreach ($num in $selectedNumbers) {
        if ($num -lt 1 -or $num -gt $vmList.Count) {
            Write-Error "Invalid selection: $num. Valid range is 1-$($vmList.Count). Please run the script again."
            exit
        }
    }
} catch {
    Write-Error "Invalid input format. Please enter number(s) separated by commas (e.g., 1,3,5)."
    exit
}

# Build selected VMs array
$selectedVMs = @()
foreach ($num in $selectedNumbers) {
    $selectedVMs += $vmList[$num - 1]
}

# Display selection confirmation
Write-Output "`nSelected VM(s) for processing:"
Write-Output "=============================="
foreach ($selectedVM in $selectedVMs) {
    Write-Output "✓ $($selectedVM.Name) in RG: $($selectedVM.ResourceGroupName) - Current Status: $($selectedVM.PowerState)"
}

# Process START operations
If ($Start) {
    Write-Output "`n" + "="*70
    Write-Output "STARTING VIRTUAL MACHINES"
    Write-Output "="*70
    
    foreach ($selectedVM in $selectedVMs) {
        Write-Output "`n--- Processing VM: $($selectedVM.Name) ---"
        
        $resourceGroupName = $selectedVM.ResourceGroupName
        $vmName = $selectedVM.Name

        # Get fresh VM status
        $vmStatus = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Status
        $powerState = ($vmStatus.Statuses | Where-Object {$_.Code -like "PowerState/*"}).DisplayStatus
        
        Write-Output "Current status: $powerState"

        if ($powerState -ne "VM running") {
            Write-Output "Do you want to start VM '$vmName'? (Y/N)"
            $startChoice = Read-Host
            
            if ($startChoice -match "^[Yy]") {
                try {
                    Write-Output "⏳ Starting VM: $vmName..."
                    Start-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -NoWait
                    Write-Output "✅ VM start command initiated for $vmName (starting in background)"
                } catch {
                    Write-Warning "❌ Failed to start $vmName : $($_.Exception.Message)"
                }
            } else {
                Write-Output "⏭️  VM $vmName will not be started (skipped by user)"
            }
        } else {
            Write-Output "✅ VM $vmName is already running"
        }
    }
}

# Process JIT operations
If ($JIT) {
    Write-Output "`n" + "="*70
    Write-Output "CONFIGURING JUST-IN-TIME ACCESS"
    Write-Output "="*70
    
    foreach ($selectedVM in $selectedVMs) {
        Write-Output "`n--- Processing JIT for VM: $($selectedVM.Name) ---"
        
        $resourceGroupName = $selectedVM.ResourceGroupName
        $vmName = $selectedVM.Name
        $portNumber = 3389  # RDP port

        # Get the virtual machine object
        $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
        
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
            Write-Output "⏳ Configuring JIT policy for $vmName..."
            
            # Enable Just-In-Time (JIT) VM Access policy
            Set-AzJitNetworkAccessPolicy `
                -ResourceGroupName $resourceGroupName `
                -Location $vm.Location `
                -Name "default" `
                -Kind "Basic" `
                -VirtualMachine $JitPolicy

            Write-Output "✅ JIT Policy configured successfully for $vmName"

            # Wait for policy to be applied
            Start-Sleep -Seconds 2

            # Request JIT access - try PowerShell cmdlet first
            try {
                Write-Output "⏳ Requesting JIT access for $vmName..."
                
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

                Write-Output "✅ JIT Access granted successfully for $vmName"
                
            } catch {
                Write-Warning "⚠️  PowerShell cmdlet failed for $vmName. Trying REST API..."
                
                # Fallback: Use REST API directly
                try {
                    $subscriptionId = (Get-AzContext).Subscription.Id
                    
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
                    
                    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Security/locations/$($vm.Location)/jitNetworkAccessPolicies/default/initiate?api-version=2020-01-01"
                    
                    $result = Invoke-AzRestMethod -Uri $uri -Method POST -Payload $requestBody
                    
                    if ($result.StatusCode -eq 202) {
                        Write-Output "✅ JIT Access granted successfully for $vmName (via REST API)"
                    } else {
                        Write-Warning "❌ Failed to request JIT access for $vmName. Status: $($result.StatusCode)"
                        Write-Output "Response: $($result.Content)"
                    }
                } catch {
                    Write-Warning "❌ REST API also failed for $vmName : $($_.Exception.Message)"
                }
            }
        } catch {
            Write-Warning "❌ Failed to configure JIT for $vmName : $($_.Exception.Message)"
            continue
        }
    }
}

# Final summary
Write-Output "`n" + "="*70
Write-Output "SUMMARY - CONNECTION INFORMATION"
Write-Output "="*70
Write-Output "Your Public IP Address: $MyIP"

if ($JIT) {
    Write-Output "JIT Access Duration: 4 hours from now"
    Write-Output "Allowed Port: 3389 (RDP)"
    Write-Output "Access expires at: $((Get-Date).AddHours(4).ToString('yyyy-MM-dd HH:mm:ss'))"
}

Write-Output "`nProcessed Virtual Machine(s):"
foreach ($selectedVM in $selectedVMs) {
    Write-Output "• $($selectedVM.Name) (Resource Group: $($selectedVM.ResourceGroupName))"
}

if ($JIT) {
    Write-Output "`n🔗 You can now connect to the VM(s) using:"
    Write-Output "   - Remote Desktop Connection (mstsc)"
    Write-Output "   - Azure Portal > Virtual Machines > Connect"
    Write-Output "   - Azure Bastion (if configured)"
}

if ($Start) {
    Write-Output "`n⏰ Note: VMs started with -NoWait may take a few minutes to fully boot"
}

Write-Output "`n✅ Script execution completed!"

az account set --subscription "MCAPS-Hybrid-REQ-37778-2022-mdumont"

$SourceResourceGroupName="RG-IdentityMS"
$SourceVMName="CS213AZURE"              
$SourceOSDisk="CS213AZURE_OsDisk_1_5c64a53672f442a184e110972493102c"

$DestinationResourceGroupName="RG-IdentityMS-CA"                    
$DestinationVMName="CS213AZURE"                                     
$DestinationOSDisk="CS213AZURE_OsDisk"                                   
$DestinationNicName="CS213AZURE_CA_NIC"  

$SourceLocation=$(az group show -n $SourceResourceGroupName --query location -o tsv)
$SourceSnapshotName="Snapshot-$SourceOSDisk"                                        
$DestinationLocation=$(az group show -n $DestinationResourceGroupName --query location -o tsv)
$DestinationSnapshotName="Snapshot-$DestinationVMName"                                        

$DestinationComputerName=$(az vm show --resource-group $SourceResourceGroupName --name $SourceVMName --query "osProfile.computerName" -o tsv)
$DestinationVMSize=$(az vm show --resource-group $SourceResourceGroupName --name $SourceVMName --query "hardwareProfile.vmSize" -o tsv)
$DestinationOSType=$(az vm show --resource-group $SourceResourceGroupName --name $SourceVMName --query "storageProfile.osDisk.osType" -o tsv)
$DestinationVMPatchMode=$(az vm show --resource-group $SourceResourceGroupName --name $SourceVMName --query "osProfile.windowsConfiguration.patchSettings.patchMode" -o tsv)

$DestinationVMPatchMode="ImageDefault"

az vm deallocate --resource-group $SourceResourceGroupName --name $SourceVMName

pause

$SourceOSDiskId=$(az disk show --resource-group $SourceResourceGroupName --name $SourceOSDisk --query id --output tsv)
az snapshot create --resource-group $SourceResourceGroupName --name $SourceSnapshotName --source "$SourceOSDiskId" --location $SourceLocation --incremental true --sku "Standard_ZRS"

$SourceSnapshotId=$(az snapshot show --resource-group $SourceResourceGroupName --name $SourceSnapshotName --query "id" --output tsv)
az snapshot create --resource-group $DestinationResourceGroupName --name $DestinationSnapshotName --source $SourceSnapshotId --location $DestinationLocation --incremental --copy-start 

pause

$snapshotStatus=$(az snapshot show --resource-group $DestinationResourceGroupName --name $DestinationSnapshotName --query "provisioningState" --output tsv)
while [ "$snapshotStatus" != "Succeeded" ]; do
    echo "$(date +'%Y-%m-%d %H:%M:%S') - Waiting for snapshot to be ready. Current status: $snapshotStatus"
    sleep 30
    snapshotStatus=$(az snapshot show --resource-group $DestinationResourceGroupName --name $DestinationSnapshotName --query "provisioningState" --output tsv)
done

pause

$DestinationSnapshotId=$(az snapshot show --resource-group $DestinationResourceGroupName --name $DestinationSnapshotName --query "id" --output tsv)
az disk create --resource-group $DestinationResourceGroupName --name $DestinationOSDisk --source $DestinationSnapshotId --location $DestinationLocation

az vm create --resource-group $DestinationResourceGroupName --name $DestinationVMName --attach-os-disk $DestinationOSDisk --os-type $DestinationOSType --size $DestinationVMSize --nics $DestinationNicName --patch-mode $DestinationVMPatchMode --computer-name $DestinationComputerName --nic-delete-option "Detach" --os-disk-delete-option "Detach"

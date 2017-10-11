<#

Move a single VM from one Availability Set to another.

Preconditions:
- The target Availability Set already exists in the same resource group as the VM
- The target Availability Set is enabled for Managed Disks

Warnings:
- Certain VM extensions may need to be reinstalled after this process.

#>

param (
    
    [string] $subscriptionId = 'subidhere',
    [string] $vmResourceGroupName = 'RG-VPN',
    [string] $vmName = 'windowsvpn01',

    [string] $newAvSetName = 'newavset'
)

$ErrorActionPreference = 'Stop'

Select-AzureRmSubscription -SubscriptionId $subscriptionId

# Get VM object
$vmObject = Get-AzureRmVM -ResourceGroupName $vmResourceGroupName -Name $vmName

# Get pre-existing target Availability Set (AvSet)
$targetAvSet = Get-AzureRmAvailabilitySet -ResourceGroupName $vmResourceGroupName -Name $newAvSetName

# Set new availability set for VM object
try{
    $vmObject.AvailabilitySetReference.Id = $targetAvSet.Id
}
catch{
    $vmObject.AvailabilitySetReference = New-Object Microsoft.Azure.Management.Compute.Models.SubResource
    $asRef = New-Object Microsoft.Azure.Management.Compute.Models.SubResource
    $asRef.Id = $targetAvSet.Id
    $vmObject.AvailabilitySetReference = $asRef.Id
}

# Delete old VM
Remove-AzureRmVM -ResourceGroupName $vmResourceGroupName -Name $vmName -Force

# Clear out image reference from VM object
$vmObject.StorageProfile.ImageReference = $null

# Clear out OS Profile from VM object
$vmObject.OSProfile = $null

# Changed the disk property 'CreateOption' from 'FromImage' to 'Attach'
$vmObject.StorageProfile.OsDisk.CreateOption = "Attach" #OS Disk
for($i=0; $i-lt ($VmObject.StorageProfile.DataDisks | Measure).Count; $i++){
    $VmObject.StorageProfile.DataDisks[$i].CreateOption = 'Attach' #For each data disk
}

# Recreate VM from modified VM object
New-AzureRmVM -ResourceGroupName $vmResourceGroupName -Location $vmObject.Location -VM $vmObject





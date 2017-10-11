# Prerequisites for ASM to ARM migration: authenticate to Azure using both Add-AzureRmAccount, and Add-AzureAccount
# Expected time to completion: 30mins (variable depending on OS and data disk size)

#######################################
# Parameter inputs
#######################################

param(

    $originalASMSubscriptionName = "TBR Systems Office Production",
    $targetARMSubscriptionName = "TBR Systems Office Production",

    # Original azure VM parameters
    $cloudServiceName = "tbr-it-p-ban-eis01",
    $vmName = "tbr-it-p-ban-eis01",


    # Target virtual network parameters
    # Must already exist
    $vnetResourceGroupName = "rg-networking",
    $virtualNetworkName = 'VN-TBR-HUB-01',
    $subnetName = 'webTier-Subnet-Prod-01',

    # Target resource group name
    # Must already exist
    $resourceGroupName = 'TBRBanner',

    # Target location
    $location = 'South Central US' ,

    #Target virtual machine size
    $virtualMachineSize = 'Standard_DS2_v2',

    # Target storage account type for OS and data disks
    $diskStorageAccountType = "PremiumLRS",

    # Target availability set. Leave blank or $null if no availabiliy set required.
    $availabilitySetName = "avset-tbr-ban-eis-03",

    # Target destination storage account parameters (for migration between Azure data centers)
    # New storage account is created in target resource group
    # Resource group must already exist
    $targetStorageAccountResourceGroup = "RG-CarlosTestResources",

    # Tags for VM, availability set, disk, and NIC resources
    [hashtable]  $vmTags = @{"Deparment" = "Test";"Owner" = "Test"}

)

#######################################
# Select Subscriptions
#######################################

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

# Explicitly import Azure modules
Import-Module Azure
Import-Module Azure.Storage
Import-Module AzureRM.Profile
Import-Module AzureRM.Storage
Import-Module AzureRM.Compute
Import-Module AzureRM.Network


# Select Azure subscriptions (both ARM and ASM)
Select-AzureRmSubscription -SubscriptionName $targetARMSubscriptionName
Select-AzureSubscription -SubscriptionName $originalASMSubscriptionName

Start-Sleep -Seconds 5

#######################################
# Get original VM
#######################################

$vm = Get-AzureVM -ServiceName $cloudServiceName -Name $vmName
$vmName = $vm.Name
$osType = $vm.GetInstance().OSVirtualHardDisk.OS



#######################################
# Get OS disk details
#######################################

# Get URI of OS Disk
$originalOsVhdUri = $vm.GetInstance().OSVirtualHardDisk.MediaLink

# Create the name of the future Managed Disk resource representing OS disk
$osDiskName = "VD-" + $vm.Name + "-OS-Disk"

# Extract the name of the VHD in which the OS disk is stored
# Method: Match everything after the last "/"
$OsVhdName = [regex]::Match($originalOsVhdUri,"(?<=\/)[^/]*$").Value

# Get the disk object of the original OS disk
$originalOsDisk = Get-AzureDisk | Where-Object {$_.MediaLink -eq $originalOsVhdUri}

# Extract the name of the container in which the OS disk VHD is stored
# Match everything between '.net/' and '/$OsVhdName'
$originalVhdOsContainer = [regex]::Match($originalOsVhdUri,"(?<=\.net\/)(.*?)(?=\/$OsVhdName)").Value

# Extract storage account in which OS disk VHD is located
# Method: extract any string in between "//" and ".blob"
$originalVhdStorageAccountName = [regex]::Match($originalOsVhdUri,"(?<=\/\/)(.*?)(?=\.blob)").Value

# Get the context of the storage account in which the OS disk VHD is located
$originalStorageAccount = Get-AzureStorageAccount -StorageAccountName $originalVhdStorageAccountName
$originalStorageContext = $originalStorageAccount.Context.Context




#######################################
# Get data disk details
#######################################

# Get the data disk configuration from VM object, and get number of data disks
$originalDataDisks = $vm.VM.DataVirtualHardDisks
$numDataDisks = ($originalDataDisks | Measure).Count

# Initializations
$dataDiskNames = @($false) * $numDataDisks
$dataDiskVhdNames = @($false) * $numDataDisks
$dataDiskOriginalUris = @($false) * $numDataDisks
$dataDiskVhdContainers = @($false) * $numDataDisks
$dataDiskVhdStorageAccountNames = @($false) * $numDataDisks
$dataDiskStorageAccountContexts = @($false) * $numDataDisks
$dataDiskLuns = @($false) * $numDataDisks
$dataDiskCachingPreference = @($false) * $numDataDisks

# Get properties for all data disks
for($i = 0; $i -lt $numDataDisks; $i++) {

    # Create the name of the future Managed Disk resource representing this data disk
    $dataDiskNames[$i] = "VD-" + $vm.Name + "-DataDisk" + ($i+1).ToString("00")

    # Get URI of this Data Disk
    $dataDiskOriginalUris[$i] = $originalDataDisks[$i].MediaLink

    # Extract the name of the VHD of this data disk
    $dataDiskVhdNames[$i] = [regex]::Match($($dataDiskOriginalUris[$i]),"(?<=\/)[^/]*$").Value

    # Extract the name of the container of this data disk
    $dataDiskVhdContainers[$i] = [regex]::Match($($dataDiskOriginalUris[$i]),"(?<=\.net\/)(.*?)(?=\/$($dataDiskVhdNames[$i]))").Value

    # Extract the name of the storage account of this data disk
    $dataDiskVhdStorageAccountNames[$i] = [regex]::Match($($dataDiskOriginalUris[$i]),"(?<=\/\/)(.*?)(?=\.blob)").Value

    # Get the context of the storage account in which the OS disk VHD is located
    $dataDiskStorageAccount = Get-AzureStorageAccount -StorageAccountName $dataDiskVhdStorageAccountNames[$i]
    $dataDiskStorageAccountContexts[$i] = $dataDiskStorageAccount.Context.Context

    # Get the LUN associated with the data disk
    $dataDiskLuns[$i] = $originalDataDisks[$i].Lun

    # Get the caching prefere with the data disk
    $dataDiskCachingPreference[$i] = $originalDataDisks[$i].HostCaching
}


#######################################
# Get target storage account details
#######################################

# Form name for new storage account
$date = Get-Date
$destinationStorageAccountName = "h" + ($date.Hour).ToString("00") + "m" + ($date.Minute).ToString("00") + "tempmigra" + ([string][Guid]::NewGuid()).Substring(0,8)

# Container name
$destinationContainer = 'migratedvhds'

# Get the target storage account
$destinationStorage = New-AzureRmStorageAccount -ResourceGroupName $targetStorageAccountResourceGroup `
                                                -Name $destinationStorageAccountName `
                                                -SkuName Standard_LRS `
                                                -Location $location

# Get the context of the current storage account
$pw = Get-AzureRmStorageAccountKey -ResourceGroupName $targetStorageAccountResourceGroup -Name $destinationStorageAccountName
$destinationStorageContext = New-AzureStorageContext -StorageAccountName $destinationStorageAccountName -StorageAccountKey $pw.Value[0] -Protocol Https

# Create new container with its public access permission set to 'Off' (i.e. access to container is Private)
New-AzureStorageContainer -Name $destinationContainer -Permission Off -Context $destinationStorageContext | Out-Null


#######################################
# Stop original VM, start copy operations
#######################################

# Number of copy jobs = OS disk + number of data disks
$numberCopyJobs = 1 + $numDataDisks

# Initialize array to keep track of all blob names being copied
$blobNames = @($false) * $numberCopyJobs

$runbookTime = (Get-Date).ToUniversalTime()
Write-Output "Starting copy operation(s). Time: [$runbookTime]"

$vm | Stop-AzureVM -Force

Remove-Variable -Name 'vm'

# Wait some time just to make absolutely sure VM is in a stopped condition
Start-Sleep -Seconds 20

# Get the VM object, verify that it is in a 'Stopped' condition
$vm = Get-AzureVM -ServiceName $cloudServiceName -Name $vmName
if ($vm.Status -ne "StoppedDeallocated") {
    Write-Output "VM [$($vm.Name)] did not stop successfully. VM state: [$($vm.Status)]"
    throw "VM [$($vm.Name)] did not stop successfully. VM state: [$($vm.Status)]"
}

# Start the copy operation on OS disk
Start-AzureStorageBlobCopy  -Context $originalStorageContext `
                            -SrcContainer $originalVhdOsContainer `
                            -SrcBlob $OsVhdName `
                            -DestContext $destinationStorageContext `
                            -DestContainer $destinationContainer

# Populate blob names with name of blob for OS disk
$blobNames[0] = $OsVhdName

# Start the copy operation for data disks
for($j = 0; $j -lt $numDataDisks; $j++) {

    Start-AzureStorageBlobCopy  -Context $dataDiskStorageAccountContexts[$j] `
                                -SrcContainer $dataDiskVhdContainers[$j] `
                                -SrcBlob $dataDiskVhdNames[$j] `
                                -DestContext $destinationStorageContext `
                                -DestContainer $destinationContainer

    # Populate blob names with the name of each data disk
    $blobNames[$j + 1] = $dataDiskVhdNames[$j]
}

$runningCount = $numberCopyJobs
# Logic waiting for the jobs to complete
while($runningCount -gt 0){
        
    # Reset counter for number of jobs still running
    $runningCount = 0 
 
    # Loop through all jobs
    for ($k=0; $k -lt $numberCopyJobs; $k++) {

        # Get the status of the job
        # Get the context of the current storage account
        $jobStatus = Get-AzureStorageBlob -Container $destinationContainer -Blob $blobNames[$k] -Context $destinationStorageContext `
                                            | Get-AzureStorageBlobCopyState

        if(   $jobStatus.Status -eq "Pending"   )
        { 
            # If the copy operation is still pending, increase the counter for number of jobs still running
            $runningCount++ 
        }
        elseif(   $jobStatus.Status -eq "Failed"   )
        {
            
            Write-Output "Job status on blob [$($blobNames[$k])] and storage account [$($destinationStorage.StorageAccountName)] failed. Copy status description: $($jobStatus.StatusDescription)."
            throw "Job status on blob [$($blobNames[$k])] and storage account [$($destinationStorage.StorageAccountName)] failed. Copy status description: $($jobStatus.StatusDescription)."
        }
    } 

    Write-Output "Number of copy operations still running: $runningCount. Number of total jobs: $numberCopyJobs."
         
    Start-Sleep -Seconds 30
}

$runbookTime = (Get-Date).ToUniversalTime()
Write-Output "Copy operation end. Time: [$runbookTime]"



#######################################
# Create VM operations
#######################################

$runbookTime = (Get-Date).ToUniversalTime()
Write-Output "Creating VM disks (both OS and, if applicable, data disks). Time: [$runbookTime]"

# URI of blob representing OS disk in new storage account
$targetOSDiskUri = "https://$destinationStorageAccountName.blob.core.windows.net/$destinationContainer/$OsVhdName"

# Create Azure OS disk as Managed Disk
New-AzureRmDisk -DiskName $osDiskName -Disk (New-AzureRmDiskConfig `
    -AccountType $diskStorageAccountType -Location $location -CreateOption Import -SourceUri $targetOSDiskUri) `
    -ResourceGroupName $resourceGroupName

$osDisk = Get-AzureRmDisk -ResourceGroupName $resourceGroupName -DiskName $osDiskName


# Create Availability Set, if selected by the user
if ( !([string]::IsNullOrEmpty($availabilitySetName)) ){
    
    $availabilitySet = Get-AzureRmAvailabilitySet -ResourceGroupName $resourceGroupName -Name $availabilitySetName -ErrorAction SilentlyContinue
    if ($vnetResourceGroup -eq $null) {
        $availabilitySet = New-AzureRmAvailabilitySet -ResourceGroupName $resourceGroupName `
                                                      -Name $availabilitySetName `
                                                      -Location $location `
                                                      -Sku "Aligned" `
                                                      -PlatformUpdateDomainCount 5 `
                                                      -PlatformFaultDomainCount 3
                                                          
    }

}

# Create new VM configuration. Add availability set reference only if an availability set name was inputted by user
if ( !([string]::IsNullOrEmpty($availabilitySetName)) ){
    $VirtualMachine = New-AzureRmVMConfig -VMName $vmName -VMSize $virtualMachineSize -AvailabilitySetId $availabilitySet.Id
}
else{
    $VirtualMachine = New-AzureRmVMConfig -VMName $vmName -VMSize $virtualMachineSize
}

# Set the VM configuration's OS disk
if($osType -eq "Windows") {

    $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -ManagedDiskId $osDisk.Id `
                            -DiskSizeInGB $originalOsDisk.DiskSizeInGB -CreateOption Attach -Windows

}
elseif ($osType -eq "Linux") {

    $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -ManagedDiskId $osDisk.Id `
                                          -DiskSizeInGB $originalOsDisk.DiskSizeInGB -CreateOption Attach -Linux
}
else{
   throw "Error: OS Type error"
}

# Loop through all data disks
for($i = 0; $i -lt $numDataDisks; $i++) {

    # Build URI of new data disk VHD
    $targetDataDiskUri = "https://$destinationStorageAccountName.blob.core.windows.net/$destinationContainer/$($dataDiskVhdNames[$i])"

    # Create the data disk resource
    New-AzureRmDisk -DiskName $dataDiskNames[$i] -Disk (New-AzureRmDiskConfig `
        -AccountType $diskStorageAccountType -Location $location -CreateOption Import `
        -SourceUri $targetDataDiskUri ) -ResourceGroupName $resourceGroupName

    $dataDiskResource = Get-AzureRmDisk -ResourceGroupName $resourceGroupName -DiskName $dataDiskNames[$i]

    # Add data disk to VM configuration
    $VirtualMachine = Add-AzureRmVMDataDisk -VM $VirtualMachine -Name $dataDiskNames[$i] `
        -CreateOption Attach -ManagedDiskId $dataDiskResource.Id -Lun $dataDiskLuns[$i] -Caching $dataDiskCachingPreference[$i]

}

# Get target Virtual Network and subnet
$vnet = Get-AzureRmVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $vnetResourceGroupName
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName

$runbookTime = (Get-Date).ToUniversalTime()
Write-Output "Creating VM. Time: [$runbookTime]"

# Create NIC
$nic = New-AzureRmNetworkInterface -Name ($vmName.ToLower()+'-nic1') `
    -ResourceGroupName $resourceGroupName -Location $location -SubnetId $subnet.Id -WarningAction SilentlyContinue

# Add NIC to VM configuration
$VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $nic.Id

# Create VM from VM configuration
New-AzureRmVM -VM $VirtualMachine -ResourceGroupName $resourceGroupName -Location $location -WarningAction SilentlyContinue


#######################################
# Tagging operations
#######################################
<#
# VM tags
Set-AzureRmResource -Tag $vmTags -ResourceName $vmName -ResourceGroupName $resourceGroupName -ResourceType "Microsoft.Compute/virtualMachines" -Force | Out-Null

# NIC tags
Set-AzureRmResource -Tag $vmTags -ResourceName ($vmName.ToLower()+'-nic1') -ResourceGroupName $resourceGroupName -ResourceType "Microsoft.Network/networkInterfaces" -Force | Out-Null

# OS Disk tags
Set-AzureRmResource -Tag $vmTags -ResourceName $osDiskName -ResourceGroupName $resourceGroupName -ResourceType "Microsoft.Compute/disks" -Force | Out-Null

# Data Disk tags
for($i = 0; $i -lt $numDataDisks; $i++){
    Set-AzureRmResource -Tag $vmTags -ResourceName $dataDiskNames[$i] -ResourceGroupName $resourceGroupName -ResourceType "Microsoft.Compute/disks" -Force | Out-Null
}

# Availability Set tags
if ( !([string]::IsNullOrEmpty($availabilitySetName)) ){
    Set-AzureRmResource -Tag $vmTags -ResourceName $availabilitySetName -ResourceGroupName $resourceGroupName -ResourceType "Microsoft.Compute/availabilitySets" -Force | Out-Null
}
#>

$runbookTime = (Get-Date).ToUniversalTime()
Write-Output "End of runbook: [$runbookTime]"
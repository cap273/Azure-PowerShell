<#

.NAME
	Migrate-AzureVMs.ps1
	
.DESCRIPTION 
    Perform the following operations:
    1. Gather information on the ASM VM (specified by $cloudServiceName and $vmName), including its OS and Data Disks
    2. Stop (deallocate) the ASM VM
    3. Create a temporary ARM storage account in resource group $targetStorageAccountResourceGroup
    4. Copy the VHD files associated with the ASM VM's OS and Data Disks to the temporary ARM storage account
    5. Create new Managed Disks (for OS and Data Disks) in ARM from the VHDs in the temporary ARM storage account.
        These Managed Disks will be depoyed in the resource group $resourceGroupName
    6. Create a new NIC and a new ARM VM based on these Managed Disks.
    
    Prerequisites for ASM to ARM migration: authenticate to Azure using both Add-AzureRmAccount, and Add-AzureAccount
    Expected time to completion: 30mins (variable depending on OS and data disk size)

.PARAMETER originalASMSubscriptionName
    The name of the Azure ASM subscription in which the original ASM VM is located.

.PARAMETER targetARMSubscriptionName
    The name of the Azure ARM subscription in which the target ARM VM will be located.

.PARAMETER cloudServiceName
    The name of the cloud service associated with the original ASM VM.

    *NOTE*: Only one operation on a single VM that is part of a cloud service is concurrently allowed.

.PARAMETER vmName
    The name of the the original ASM VM.

.PARAMETER vnetResourceGroupName
    The name of the existing resource group associated with the VNet in which the target ARM VM will be located.

.PARAMETER virtualNetworkName
    The name of the existing VNet in which the target ARM VM will be located.

.PARAMETER subnetName
    The name of the existing subnet (that is part of the VNet specified by $virtualNetworkName) in which the 
    target ARM VM will be located

.PARAMETER vmResourceGroupName
    The name of the resource group in which the VM object, and any associated availability 
    set (if appicable) will be placed. This resource group will not necessarily contain the Managed Disk objects, nor the VM's NICs.
    If this resource group does not already exist, one will be created.

.PARAMETER nicResourceGroupName
    The name of the resource group in which the VM's NICs will be placed. 
    This resource group will not necessarily contain the Managed Disk objects, nor the VM object.
    If this resource group does not already exist, one will be created.

.PARAMETER disksResourceGroupName
    The name of the resource group in which the VM's managed disks will be located. This resource group will 
    not necessarily contain the the VM object, the VM's NICs, and any associated availability set (if appicable).
    If this resource group does not already exist, one will be created.

.PARAMETER staticIpAddress
    If TRUE the DHCP functionality in Azure will
    dynamically assign private IP addresses, and afterwards the assigned private IP addresses will be
    set to 'Static'.

    If FALSE the DHCP functionality in Azure will dynamically assign private IP addresses, an the private IP
    address allocation method will remain unchanged.

.PARAMETER location
    The Azure location (e.g. East US 2) in which the *target* ARM VM will be located.

.PARAMETER virtualMachineSize
    The VM size (e.g. Standard_A2_v2) for the target ARM VM.

.PARAMETER diskStorageAccountType
    The storage type (e.g. StandardLRS) for the target ARM VM disks.

.PARAMETER availabilitySetName
    Name of the availability set for the target ARM VM. Leave blank or $null if no availabiliy set required.
    If an availability set name and it does not already exist, one will be created.

.PARAMETER targetStorageAccountResourceGroup
    Name of the resource group to be used for temporary ARM storage accounts. Copied VHDs will be located here.
    After the target ARM VM is running successfully with no issues, it is safe to delete these temporary
    storage accounts and this resource group, as the disk data would be safely contained in the OS and Data Managed Disks.

.PARAMETER loadBalancerResourceGroup
    The resource group of the load balancer to be associated with this VM's NIC. Leave blank or $null if no 
    load balancer association required.

.PARAMETER loadBalancerName
    The name of the load balancer to be associated with this VM's NIC. Leave blank or $null if no 
    load balancer association required.

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: January 30, 2018
    LEGAL DISCLAIMER:
        This script is not supported under any Microsoft standard program or service. This script is
        provided AS IS without warranty of any kind. Microsoft further disclaims all
        implied warranties including, without limitation, any implied warranties of mechantability or
        of fitness for a particular purpose. The entire risk arising out of the use of performance of
        this script and documentation remains with you. In no event shall Microsoft, its authors, or 
        anyone else involved in the creation, production, or delivery of this script be liable
        for any damages whatsoever (including, without limitation, damages for loss of
        business profits, business interruption, loss of business information, or other
        pecuniary loss) arising out of the use of or inability to use this script or docummentation, 
        even if Microsoft has been advised of the possibility of such damages.
#>

#######################################
# Parameter inputs
#######################################

param(

    $originalASMSubscriptionName,
    $targetARMSubscriptionName,

    # Original azure VM parameters
    $cloudServiceName,
    $vmName,


    # Target virtual network parameters
    # Must already exist
    $vnetResourceGroupName,
    $virtualNetworkName,
    $subnetName,

    # Target resource groups name
    $vmResourceGroupName,
    $nicResourceGroupName,
    $disksResourceGroupName,

    # Target NIC configuration
    [boolean] $staticIpAddress,

    # Target location
    $location,

    #Target virtual machine size
    $virtualMachineSize,

    # Target storage account type for OS and data disks
    $diskStorageAccountType,

    # Target availability set. Leave blank or $null if no availabiliy set required.
    $availabilitySetName,

    # Target destination storage account parameters (for migration between Azure data centers)
    # New storage account is created in target resource group
    $targetStorageAccountResourceGroup,

    # Load Balancer settings ($null or blank if no association with an existing Load Balancer desired)
    $loadBalancerResourceGroup,
    $loadBalancerName,

    # Tags for VM, availability set, disk, and NIC resources
    [hashtable]  $vmTags = @{"Deparment" = "Test";"Owner" = "Test"}

)

#######################################
# Select Subscriptions
#######################################

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

    <#
    ############################
    # Logging initializations (for testing only)
    ############################

    # Ensure folder for deployment logs exists
    $logPath = "C:\Users\Desktop"
    if (!(Test-Path $logPath)) {
        New-Item -ItemType directory -Path $logPath | Out-Null
    }

    # Define function for custom logging logging
    $logFile = "$logPath\$vmName.log"
    Function Write-Output
    {
       Param ([string]$logstring)

       Add-Content $logFile -value $logstring
    }
    #>


# Check for Azure PoweShell version
$modlist = Get-Module -ListAvailable -Name 'AzureRM.Resources' | Where-Object {$_.ModuleType -eq "Script"}
if (($modlist -eq $null) -or ($modlist.Version.Major -lt 5)){
    throw "Please install the Azure Powershell module, version 5.0.0 or above."
}

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
$osDiskName = "VD-" + $vm.Name + "-OsDisk"

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

    # Create the name of the future Managed Disk resource representing this data disk
    $dataDiskNames[$i] = "VD-" + $vm.Name + "-DataDisk-LUN" + ($dataDiskLuns[$i]).ToString("00")
}



######################################
# Check target resource groups
######################################

# Populate list of resource groups to be used, and their related purpose
$resourceGroupsToCheck =  @($disksResourceGroupName,$vmResourceGroupName,$nicResourceGroupName,$targetStorageAccountResourceGroup)
$resourceGroupsPurposes = @("OS and Data Disks","VM and (if applicable) AvSet","Network Interfaces (NICs)","temporary migration storage accounts")

# Create a new resource group for disks, VMs, and temporary storage accounts, if one does not already exist
for ($i=0; $i -lt ($resourceGroupsToCheck | Measure).Count; $i++)
{
    $selectedResourceGroup = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -eq $resourceGroupsToCheck[$i]}
    if ($selectedResourceGroup -eq $null) 
    {
    
        Write-Output "Unable to find resource group [$($resourceGroupsToCheck[$i])] for [$($resourceGroupsPurposes[$i])]."
        Write-Output "Creating resource group [$($resourceGroupsToCheck[$i])]..."

        try
        {
            New-AzureRmResourceGroup -Name $resourceGroupsToCheck[$i] `
                                     -Location $location `
                                     | Out-Null
        } 
    
        catch
        {
            $ErrorMessage = $_.Exception.Message
    
            Write-Output "Creating a new resource group [$($resourceGroupsToCheck[$i])] failed with the following error message:"
            throw "$ErrorMessage"
        }
    }
}

# Additionally, if this VM's NIC is going to be associated with a Load Balancer, check that the Load Balancer and its Resource Group exists
if ( !([string]::IsNullOrEmpty($loadBalancerName)) ){
    $selectedResourceGroup = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -eq $loadBalancerResourceGroup}
    if ($selectedResourceGroup -eq $null) 
    {
        throw "Unable to find resource group [$loadBalancerResourceGroup)] for Azure internal load balancer [$loadBalancerName]."
    }

    # Validate that the Load Balancer already exists
    $existingLoadBalancer = Get-AzureRmLoadBalancer -ResourceGroupName $loadBalancerResourceGroup `
                                           -Name $loadBalancerName `
                                           -ErrorAction SilentlyContinue
    if ($existingLoadBalancer -eq $null) {

        throw "An Azure load balancer with the name [$loadBalancerName] was not found in resource group [$loadBalancerResourceGroup]."
    }
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
    -ResourceGroupName $disksResourceGroupName

$osDisk = Get-AzureRmDisk -ResourceGroupName $disksResourceGroupName -DiskName $osDiskName


# Create Availability Set, if selected by the user
if ( !([string]::IsNullOrEmpty($availabilitySetName)) ){
    
    $availabilitySet = Get-AzureRmAvailabilitySet -ResourceGroupName $vmResourceGroupName -Name $availabilitySetName -ErrorAction SilentlyContinue
    if ($vnetResourceGroup -eq $null) {
        $availabilitySet = New-AzureRmAvailabilitySet -ResourceGroupName $vmResourceGroupName `
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
        -SourceUri $targetDataDiskUri ) -ResourceGroupName $disksResourceGroupName

    $dataDiskResource = Get-AzureRmDisk -ResourceGroupName $disksResourceGroupName -DiskName $dataDiskNames[$i]

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
    -ResourceGroupName $nicResourceGroupName -Location $location -SubnetId $subnet.Id -WarningAction SilentlyContinue

# If IP address allocation needs to be changed to 'Static', do so
if ($staticIpAddress) {

    # Get the NIC object again
    $nic = Get-AzureRmNetworkInterface -Name ($vmName.ToLower()+'-nic1') `
                                       -ResourceGroupName $nicResourceGroupName

    Write-Output "Setting Private IP allocation method to Static..."
    $nic.IpConfigurations[0].PrivateIpAllocationMethod = 'Static'
    $nic | Set-AzureRMNetworkInterface 
}

# Additionally, if this VM's NIC is going to be associated with a Load Balancer, add NIC to the Load Balancer's first backend pool
if ( !([string]::IsNullOrEmpty($loadBalancerName)) ){
    
    # Get the NIC object again
    $nic = Get-AzureRmNetworkInterface -Name ($vmName.ToLower()+'-nic1') `
                                       -ResourceGroupName $nicResourceGroupName

    Write-Output "Adding NIC to load balancer [$loadBalancerName]..."
    $nic.IpConfigurations[0].LoadBalancerBackendAddressPools.Add($existingLoadBalancer.BackendAddressPools[0])
    $nic | Set-AzureRMNetworkInterface 
}

# Add NIC to VM configuration
$VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $nic.Id

# Create VM from VM configuration
New-AzureRmVM -VM $VirtualMachine -ResourceGroupName $vmResourceGroupName -Location $location -WarningAction SilentlyContinue


#######################################
# Tagging operations (currently unused)
#######################################
<#
# VM tags
Set-AzureRmResource -Tag $vmTags -ResourceName $vmName -ResourceGroupName $vmResourceGroupName -ResourceType "Microsoft.Compute/virtualMachines" -Force | Out-Null

# NIC tags
Set-AzureRmResource -Tag $vmTags -ResourceName ($vmName.ToLower()+'-nic1') -ResourceGroupName $vmResourceGroupName -ResourceType "Microsoft.Network/networkInterfaces" -Force | Out-Null

# OS Disk tags
Set-AzureRmResource -Tag $vmTags -ResourceName $osDiskName -ResourceGroupName $disksResourceGroupName -ResourceType "Microsoft.Compute/disks" -Force | Out-Null

# Data Disk tags
for($i = 0; $i -lt $numDataDisks; $i++){
    Set-AzureRmResource -Tag $vmTags -ResourceName $dataDiskNames[$i] -ResourceGroupName $disksResourceGroupName -ResourceType "Microsoft.Compute/disks" -Force | Out-Null
}

# Availability Set tags
if ( !([string]::IsNullOrEmpty($availabilitySetName)) ){
    Set-AzureRmResource -Tag $vmTags -ResourceName $availabilitySetName -ResourceGroupName $vmResourceGroupName -ResourceType "Microsoft.Compute/availabilitySets" -Force | Out-Null
}
#>

$runbookTime = (Get-Date).ToUniversalTime()
Write-Output "End of runbook: [$runbookTime]"
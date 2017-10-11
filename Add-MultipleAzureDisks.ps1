<#

.NAME
	Add-MultipleAzureDisks
	
.DESCRIPTION 
    Attaches new data disks to an Azure VM.

.PARAMETER resourceGroupName
    Name of the resource group where the VM is located

.PARAMETER vmName
    Name of the Virtual Machine.

.PARAMETER diskNames
    An array containing the names of the data disks to be created. E.g. @("$vmName-datadisk1",""$vmName-datadisk2")

.PARAMETER diskSizesInGB
    An array containing the sizes of the data disks to be created, in Gibibytes (GiB).

.PARAMETER startingLUN
    The Logical Unit Number (LUN) to be assigned to the first data disk attached to the VM.
    A new Azure VM will have an OS disk assigned to LUN 0, and a temporary disk (D: drive)
    assigned to LUN 1. Therefore, by default, set $startingLUN to 2.
    For example, if 3 data disks were to be added, and $startingLUN were set to 2, the 3 data
    disks would be assigned LUN 2, LUN 3, and LUN 4.
    Run Get-Disk (as an administrator) on target VM to see the LUNs already assigned to other disks.

.PARAMETER storageAccountName
    The name of the storage account in which to place the new data disks.
    For premium data disks, ensure that the selected storage account is a Premium storage account.

.PARAMETER storageContainerName
    The name of the container within the selected storage account in which to place the new data disks.

.PARAMETER cacheSettings
    An array containing the cache settings for each new data disk.
    Valid settings: 'None','ReadOnly','ReadWrite'
    /


.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: June 17, 2016
#>


param (
    [string]
    $resourceGroupName = 'SCCM-Testing',

    [string]
    $vmName = "domaincontrol01",

    [string[]]
    $diskNames = @("domaincontrol01-datadisk1",
                   "domaincontrol01-datadisk2",
                   "domaincontrol01-datadisk3",
                   "domaincontrol01-datadisk4"
                   ),

    [int[]]
    $diskSizesInGB = @("100",
                       "100",
                       "100",
                       "100"
                       ),

    [int]
    $startingLUN = 2,

    [string]
    $storageAccountName = "sccmstortestcarlos01",

    [string]
    $storageContainerName = "vhds",

    [string[]]
    $cacheSettings = @("None",
                      "None",
                      "None",
                      "None"
                       )

)

# Get VM object
$vm = Get-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName

$numDisks = ($diskNames | Measure).Count

for($i = 0; $i -lt $numDisks; $i++) {

    # Get properties for this specific disk
    $diskname = $diskNames[$i]
    $diskSizeInGB = $diskSizesInGB[$i]
    $cacheSetting = $cacheSettings[$i]
    $LUN = $startingLUN + $i

    # Add disk to VM configuration
    Add-AzureRmVMDataDisk -VM $vm `
                          -Name $diskname `
                          -VhdUri "https://$storageAccountName.blob.core.windows.net/$storageContainerName/$diskname.vhd" `
                          -Caching $cacheSetting `
                          -DiskSizeInGB $diskSizeInGB `
                          -Lun $LUN `
                          -CreateOption empty
}


# Update disk with updated VM configuration
Update-AzureRmVM -VM $vm -ResourceGroupName $resourceGroupName
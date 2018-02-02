<#

.NAME
	Audit-AzureRmVms
	
.DESCRIPTION 
    For a given subscription, this script outputs a CSV file containining information on all ARM VMs.

.PARAMETER SubscriptionName
    The name of the Azure ARM subscription in which the ARM VMs are located.

.PARAMETER outputCsvFile
    The file path (including the name) of the CSV file to where the output will be written.

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: February 2, 2018
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

param(

    # CSV file containing information on Cloud Services and ILBs to migrate
    [String] $subscriptionName = "Visual Studio Enterprise with MSDN",

    # Full file name and path of the CSV file to be created for reporting
    [String] $outputCsvFile = "C:\Users\Desktop\ArmVms.csv"

)

cls
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

###################################################
# region: PowerShell and Azure Dependency Checks
###################################################


# Check for Azure PoweShell version
$modlist = Get-Module -ListAvailable -Name 'AzureRM.Resources' | Where-Object {$_.ModuleType -eq "Script"}
if (($modlist -eq $null) -or ($modlist.Version.Major -lt 5)){
    throw "Please install the Azure Powershell module, version 5.0.0 or above."
}

# Explicitly import Azure modules
Import-Module AzureRM.Profile
Import-Module AzureRM.Compute

# Checking whether user is logged in to Azure
Write-Host "Validating Azure Account..."
try{
    $subscriptionList = Get-AzureRmSubscription | Sort SubscriptionName
}
catch {
    Write-Host "Please authenticate to Azure ARM..."
    Add-AzureRmAccount | Out-Null
    $subscriptionList = Get-AzureRmSubscription | Sort SubscriptionName
}


# Select Azure ASM subscriptions
Select-AzureRmSubscription -SubscriptionName $subscriptionName | Out-Null

#end region


###################################################
# region: Prepare CSV output file
###################################################

Write-Host "Preparing output CSV file in location [$outputCsvFile]..."

# Delete any pre-existing CSV status file
if (Test-Path $outputCsvFile) {
    Remove-Item $outputCsvFile -Force
}

# Add a new CSV file. 
# The first set of headers match with the headers of the input CSV file required for Launch-AzureParallelJobs-AzureILBs.ps1
# The second set of headers is simply extra information, and are unused if fed as the input CSV file required for Launch-AzureParallelJobs-AzureILBs.ps1
$toCSV = "subscriptionName,resourceGroupName,vmName,location,vmSize,osType,licenseType,provisioningState,statusCode,availabilitySetName,numDataDisks,osDiskName,osDiskCreateOption,osDiskStorageType,numNics,primaryNicName,primaryNicPrivateIpAddress,primaryNicPublicIpAddress,primaryNicVnetName,primaryNicSubnetName,loadBalancerBackendAddressPoolAssociations"
Out-File -FilePath $outputCsvFile -Append -InputObject $toCSV -Encoding ascii


###################################################
# region: Main Script
###################################################

# Get all VMs in this subscription
$vms = Get-AzureRmVM

Write-Host "Processing VMs in subscription [$subscriptionName]..."

# Loop through every VM
foreach($vm in $vms) {

    
    
    # Collect information
    $resourceGroupName = $vm.ResourceGroupName
    $vmName = $vm.Name

    Write-Host "`t $vmName"

    $location = $vm.Location
    $vmSize = $vm.HardwareProfile.VmSize
    $osType = $vm.StorageProfile.OsDisk.OsType
    $licenseType = $vm.LicenseType
    $provisioningState = $vm.ProvisioningState
    $statusCode = $vm.StatusCode
    $availabilitySetName = [regex]::Match($($vm.AvailabilitySetReference.Id),"(?<=\/)[^/]*$").Value
    $numDataDisks = ($vm.StorageProfile.DataDisks | Measure).Count
    $osDiskName = $vm.StorageProfile.OsDisk.Name
    $osDiskCreateOption = $vm.StorageProfile.OsDisk.CreateOption

    try{
        $osDiskStorageType = $vm.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
    }
    catch{
        $osDiskStorageType = "NotManagedDisk"
    }

    $numNics = ($vm.NetworkProfile.NetworkInterfaces | Measure).Count

    if ($numNics -lt 2) {
        $primaryNicId = $vm.NetworkProfile.NetworkInterfaces[0].Id
    }
    else{
        $primaryNicId = ($vm.NetworkProfile.NetworkInterfaces | Where-Object {$_.Primary -eq "True"}).Id
    }

    $primaryNicName = [regex]::Match($primaryNicId,"(?<=\/)[^/]*$").Value
    $primaryNicResourceGroup = [regex]::Match($primaryNicId,"(?<=resourceGroups\/)(.*)(?=\/providers)").Value

    # Retrieve the NIC resource
    $primaryNic = Get-AzureRmNetworkInterface -ResourceGroupName $primaryNicResourceGroup -Name $primaryNicName
    
    $primaryNicPrivateIpAddress = $primaryNic.IpConfigurations[0].PrivateIpAddress
    $primaryNicPublicIpAddress = $primaryNic.IpConfigurations[0].PublicIpAddress -ne $null

    $primaryNicSubnetId = $primaryNic.IpConfigurations[0].Subnet.Id

    $primaryNicVnetName = [regex]::Match($primaryNicSubnetId,"(?<=virtualNetworks\/)(.*)(?=\/subnets)").Value
    $primaryNicSubnetName = [regex]::Match($primaryNicSubnetId,"(?<=subnets\/)[^/]*$").Value

    $loadBalancerBackendAddressPoolAssociations = ($primaryNic.IpConfigurations[0].LoadBalancerBackendAddressPools | Measure).Count
    
    $toCSV = "$subscriptionName,$resourceGroupName,$vmName,$location,$vmSize,$osType,$licenseType,$provisioningState,$statusCode,$availabilitySetName,$numDataDisks,$osDiskName,$osDiskCreateOption,$osDiskStorageType,$numNics,$primaryNicName,$primaryNicPrivateIpAddress,$primaryNicPublicIpAddress,$primaryNicVnetName,$primaryNicSubnetName,$loadBalancerBackendAddressPoolAssociations"
    Out-File -FilePath $outputCsvFile -Append -InputObject $toCSV -Encoding ascii
    
}
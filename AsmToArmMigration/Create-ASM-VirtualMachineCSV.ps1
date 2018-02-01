<#

.NAME
	Create-ASM-VirtualMachineCSV
	
.DESCRIPTION 
    For a given subscription, this script outputs a CSV file containining information on all ASM virtual machines.
    The first set of headers of the output CSV has the same headers as the input CSV file required for Launch-AzureParallelJobs-AzureVMs.ps1

.PARAMETER asmSubscriptionName
    The name of the Azure ASM subscription in which the ASM load balancers are located.

.PARAMETER outputCsvFile
    The file path (including the name) of the CSV file to where the output will be written.
    The first set of headers match with the headers of the input CSV file required for Launch-AzureParallelJobs-AzureVMs.ps1
    The second set of headers is simply extra information, and are unused if fed as the input CSV file required for Launch-AzureParallelJobs-AzureVMs.ps1

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: January 31, 2018
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
    [String] $asmSubscriptionName = "Visual Studio Enterprise with MSDN",

    # Full file name and path of the CSV file to be created for reporting
    [String] $outputCsvFile = "C:\Users\Desktop\VmsinAsm.csv"

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
Import-Module Azure

# Checking whether user is logged in to Azure
Write-Host "Validating Azure Account..."
try{
    $subscriptionList = Get-AzureSubscription | Sort SubscriptionName

    # Double check that you're actually logged on:
    if (  ($subscriptionList | Measure).Count -lt 1) {
        throw "Error: no Azure subscriptions available under the current Azure context."
    }
}
catch {
    Write-Host "Please authenticate to Azure ASM..."
    Add-AzureAccount | Out-Null
    $subscriptionList = Get-AzureSubscription | Sort SubscriptionName
}


# Select Azure ASM subscriptions
Select-AzureSubscription -SubscriptionName $asmSubscriptionName | Out-Null

Start-Sleep -Seconds 5
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
$toCSV = "originalASMSubscriptionName,targetARMSubscriptionName,cloudServiceName,vmName,vnetResourceGroupName,virtualNetworkName,subnetName,disksResourceGroupName,nicResourceGroupName,vmResourceGroupName,staticIpAddress,location,virtualMachineSize,diskStorageAccountType,hybridUseBenefit,availabilitySetName,targetStorageAccountResourceGroup,loadBalancerResourceGroup,loadBalancerName,ipAddress,instanceStatus,asmVirtualNetworkName,asmAvailabilitySetName"
Out-File -FilePath $outputCsvFile -Append -InputObject $toCSV -Encoding ascii


###################################################
# region: Main Script
###################################################

Write-Host "Getting information on ASM VMs for subscription [$asmSubscriptionName]..."

# Get all cloud services in the subscription
$cloudServices = Get-AzureService

# Loop through all cloud services
foreach ($cloudService in $cloudServices) {

    Write-Host "Checking cloud service [$($cloudService.ServiceName)]."
    
    # Get the VMs in this cloud service
    $vms = Get-AzureVM -ServiceName $cloudService.ServiceName

    # Loop through all VMs in this cloud service
    foreach ($vm in $vms) {
        Write-Host "`t VM [$($vm.Name)]."

        # Get URI where this VM's disk's VHD is located
        $vhdUri = $vm.vm.OSVirtualHardDisk.MediaLink.AbsoluteUri
            
        # Extract storage account in which OS disk VHD is located
        # Method: extract any string in between "//" and ".blob"
        $asmStorageAccountName = [regex]::Match($vhdUri,"(?<=\/\/)(.*?)(?=\.blob)").Value

        # Get ASM storage account and its type
        $asmStorageAccount = Get-AzureStorageAccount -StorageAccountName $asmStorageAccountName
        $asmStorageAccountType = $asmStorageAccount.AccountType

        <# Valid values for $asmStorageAccountType are:        
            -- Standard_LRS
            -- Standard_ZRS
            -- Standard_GRS
            -- Standard_RAGRS
            -- Premium_LRS
        #>

        # Remove the underscore character from storage account type (for input into ARM APIs)
        $asmDiskType = $asmStorageAccountType -replace '_',''

        # Get any load balancers that are associated witn this VM
        $thisVmLoadBalancedEndpoint = $vm | Get-AzureEndpoint | Where-Object {$_.LBSetName -ne $null}
        if ( !($thisVmLoadBalancedEndpoint -eq $null) ) {
            $loadBalancerName = $thisVmLoadBalancedEndpoint.InternalLoadBalancerName
        }
        else {
            $loadBalancerName = ''
        }
    
        # Build CSV output, leaving certain fields corresponding to the target ARM migration environment blank
        # Assumptions for target ARM migration environment:
        # -targetResourceGroups (for disks, NICs, and VMs) = Cloud Service Name
        # -targetARMSubscriptionName = ASM Subscription Name
        $toCSV = "$asmSubscriptionName,$asmSubscriptionName,$($cloudService.ServiceName),$($vm.Name),,,,$($cloudService.ServiceName),$($cloudService.ServiceName),$($cloudService.ServiceName),,$($cloudService.Location),$($vm.InstanceSize),$asmDiskType,,,,,$loadBalancerName,$($vm.IpAddress),$($vm.InstanceStatus),$($vm.VirtualNetworkName),$($vm.AvailabilitySetName)"

        # Output to CSV file, appending
        Out-File -FilePath $outputCsvFile -Append -InputObject $toCSV -Encoding ascii
    }
}
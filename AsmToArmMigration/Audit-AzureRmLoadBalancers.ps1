<#

.NAME
	Audit-AzureRmLoadBalancers
	
.DESCRIPTION 
    For a given subscription, this script outputs a CSV file containining information on all ARM Load Balancers.

.PARAMETER SubscriptionName
    The name of the Azure ARM subscription in which the ARM Load Balancers are located.

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
    [String] $outputCsvFile = "C:\Users\carpat\Desktop\ArmLbs.csv"

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
$toCSV = "subscriptionName,resourceGroupName,loadBalancerName,location,numFrontendIpConfigurations,firstFrontendPrivateIpAddress,firstFrontendPublicIpAddressResourceGroup,firstFrontendPublicIpAddressName,firstFrontendPublicIpAddress,numbackendAddressPools,firstBackendAddressPoolConfigName,numBackendIpConfigurations,firstBackendIpConfigurationNicResourceGroup,firstBackendIpConfigurationNicName"
Out-File -FilePath $outputCsvFile -Append -InputObject $toCSV -Encoding ascii


###################################################
# region: Main Script
###################################################

# Get all VMs in this subscription
$lbs = Get-AzureRmLoadBalancer

Write-Host "Processing Load Balancers in subscription [$subscriptionName]..."

# Loop through every VM
foreach($lb in $lbs) {


    
    $resourceGroupName = $lb.ResourceGroupName
    $loadBalancerName = $lb.Name
    $location = $lb.Location

    ################################
    # Frontend IP configurations
    ################################

    $frontendIpConfigs = $lb.FrontendIpConfigurations

    $numFrontendIpConfigurations = ($frontendIpConfigs | Measure).Count
    
    # Reset variables
    $firstFrontendPublicIpAddressResourceGroup = $null
    $firstFrontendPublicIpAddressName = $null
    $firstFrontendPrivateIpAddress = $null
    $firstFrontendPublicIpAddress = $null
    $firstFrontendPublicIpAddressObject = $null
    
    # Get private and public IP address information
    if($numFrontendIpConfigurations -gt 0) {

        $ErrorActionPreference = 'SilentlyContinue'

        $firstFrontendPrivateIpAddress = $frontendIpConfigs[0].PrivateIpAddress

        $firstFrontendPublicIpAddressId = $frontendIpConfigs[0].PublicIpAddress.Id
            
        $firstFrontendPublicIpAddressName = [regex]::Match($firstFrontendPublicIpAddressId,"(?<=publicIPAddresses\/)[^/]*$").Value
        $firstFrontendPublicIpAddressResourceGroup = [regex]::Match($firstFrontendPublicIpAddressId,"(?<=resourceGroups\/)(.*)(?=\/providers)").Value
        
        $firstFrontendPublicIpAddressObject = Get-AzureRmPublicIpAddress -ResourceGroupName $firstFrontendPublicIpAddressResourceGroup -Name $firstFrontendPublicIpAddressName
        $firstFrontendPublicIpAddress = $firstFrontendPublicIpAddressObject.IpAddress

        $ErrorActionPreference = 'Stop'
    }

    ################################
    # Backend IP pools
    ################################

    $backendAddressPools = $lb.BackendAddressPools

    $numbackendAddressPools = ($backendAddressPools | Measure).Count

    # Reset variables
    $firstBackendAddressPoolId = $null
    $firstBackendAddressPoolName = $null
    $firstBackendAddressPoolConfig = $null
    $firstBackendAddressPoolConfigName = $null
    $numBackendIpConfigurations = $null
    $firstBackendIpConfigurationId = $null
    $firstBackendIpConfigurationNicResourceGroup = $null
    $firstBackendIpConfigurationNicName = $null

    # Get backend address pool info
    if($numbackendAddressPools -gt 0) {
        
        $firstBackendAddressPoolId = $backendAddressPools[0].Id
        $firstBackendAddressPoolName = [regex]::Match($firstBackendAddressPoolId,"(?<=backendAddressPools\/)[^/]*$").Value

        $firstBackendAddressPoolConfig = Get-AzureRmLoadBalancerBackendAddressPoolConfig -LoadBalancer $lb -Name $firstFrontendPublicIpAddressName
        
        $firstBackendAddressPoolConfigName = "LB-Backend"

        $numBackendIpConfigurations = ($firstBackendAddressPoolConfig.BackendIpConfigurations | Measure).Count

        if ($numBackendIpConfigurations -gt 0) {

            $firstBackendIpConfigurationId = $firstBackendAddressPoolConfig.BackendIpConfigurations[0].Id

            $firstBackendIpConfigurationNicResourceGroup = [regex]::Match($firstBackendIpConfigurationId,"(?<=resourceGroups\/)(.*)(?=\/providers)").Value
            $firstBackendIpConfigurationNicName = [regex]::Match($firstBackendIpConfigurationId,"(?<=networkInterfaces\/)(.*)(?=\/ipConfigurations)").Value

        }
    }

    $toCSV = "$subscriptionName,$resourceGroupName,$loadBalancerName,$location,$numFrontendIpConfigurations,$firstFrontendPrivateIpAddress,$firstFrontendPublicIpAddressResourceGroup,$firstFrontendPublicIpAddressName,$firstFrontendPublicIpAddress,$numbackendAddressPools,$firstBackendAddressPoolConfigName,$numBackendIpConfigurations,$firstBackendIpConfigurationNicResourceGroup,$firstBackendIpConfigurationNicName"
    Out-File -FilePath $outputCsvFile -Append -InputObject $toCSV -Encoding ascii
    
}
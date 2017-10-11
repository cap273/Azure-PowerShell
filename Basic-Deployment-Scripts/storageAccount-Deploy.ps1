<#

.NAME
	storageAccount-Deploy
	
.DESCRIPTION 
    Leverages the ARM Template file titled "storageAccount-Template.json" to deploy one or mote Storage Accounts in Azure.

.PARAMETER subscriptionName
	Name of the subscription in which to deploy the ARM template.

.PARAMETER resourceGroupName
    Name of the resource group in which to deploy the ARM template.

.PARAMETER deploymentName
    Name of the ARM template deployment. This name is only useful for debugging purposes, and can be set to anything.

.PARAMETER location
    The location in which to deploy this storage account.

.PARAMETER templateFilePath
    The path of the ARM template file (e.g. "C:\Users\testuser\Desktop\storageAccount-Template.json"

.PARAMETER storageAccountBaseName
	The base name of the storage account to be deployed, before indexing.

    Example: if $storageAccountBaseName = 'teststorageaccount' and the number
    of VMs to be deployed is 3, and $storageAccountStartIndex = 2, the names of storage accounts to be deployed will be::
    - teststorageaccount02
    - teststorageaccount03
    - teststorageaccount04

    Each of the storage account names to deploy must be globally unique.

.PARAMETER numberOfStorageAccounts
	The number of storage accounts to deploy.

.PARAMETER storageAccountStartIndex
	The starting index of the storage account names.

    Example: if $storageAccountBaseName = 'teststorageaccount' and the number
    of VMs to be deployed is 3, and $storageAccountStartIndex = 2, the names of storage accounts to be deployed will be::
    - teststorageaccount02
    - teststorageaccount03
    - teststorageaccount04

    This script currently only supports two-digit iteration numbers. For this reason, storageAccountStartIndex cannot be greater than 100.

.PARAMETER storageAccountType
	The type of the storage account to be deployed.

.PARAMETER storageAccountTags
    A hashtable specifying the key-value tags to be associated with this Azure resource.
    The creation date of this resource is already automatically added as a tag.

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: September 26, 2017
#>

param (
    
    #######################################
    # Azure and ARM template parameters
    #######################################
    [string] $subscriptionName = 'Visual Studio Enterprise with MSDN',
    [string] $resourceGroupName = 'RG-Test',

    [ValidateSet("Central US", "East US", "East US 2", "West US", "North Central US", "South Central US", "West Central US", "West US 2")]
    [string] $location = 'East US 2',
    
    [string] $deploymentName = 'StorageAccountDeploy',
    [string] $templateFilePath = "C:\Users\carpat\OneDrive - Microsoft\Azure-PowerShell\Basic-Deployment-Scripts\storageAccount-Template.json",


    #######################################
    # Storage Account parameters
    #######################################
    [string] $storageAccountBaseName = 'storcarlostemp',

    [int] $numberOfStorageAccounts = 3,
    
    [int] $storageAccountStartIndex = 2,

    [ValidateSet('Premium_LRS','Standard_GRS','Standard_LRS','Standard_RAGRS','Standard_ZRS')]
    [string] $storageAccountType = 'Standard_LRS',

    [hashtable] $storageAccountTags = @{"Department" = "TestDepartment3";"Owner" = "TestOwner";"TestTag" = "NewTagValue"}

)





###################################################
# region: PowerShell and Azure Dependency Checks
###################################################
cls
$ErrorActionPreference = 'Stop'

Write-Host "Checking Dependencies..."

# Checking for Windows PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "You need to have Windows PowerShell version 5.0 or above installed." -ForegroundColor Red
    Exit -2
}

# Checking for Azure PowerShell module
$modlist = Get-Module -ListAvailable -Name 'AzureRM.Storage'
if (($modlist -eq $null) -or ($modlist.Version.Major -lt 2)){
    Write-Host "Please install the Azure Powershell module, version 2.0.0 (released August 2016) or above." -BackgroundColor Black -ForegroundColor Red
    Write-Host "The standalone MSI file for the latest Azure Powershell versions can be found in the following URL:" -BackgroundColor Black -ForegroundColor Red
    Write-Host "https://github.com/Azure/azure-powershell/releases" -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# Checking whether user is logged in to Azure
Write-Host Validating Azure Accounts...
try{
    $subscriptionList = Get-AzureRmSubscription | Sort Name
}
catch {
    Write-Host "Reauthenticating..."
    Login-AzureRmAccount | Out-Null
    $subscriptionList = Get-AzureRmSubscription | Sort Name
}
#end region





###################################################
# region: User input validation
###################################################

Write-Host "Checking parameter inputs..."

# Get the date in which this deployment is being executed, and add it as a Tag
$creation = Get-Date -Format MM-dd-yyyy
$creationDate = $creation.ToString()
$storageAccountTags.Add("CreationDate", $creationDate)

# Check that template file path is valid
if (!(Test-Path -Path $templateFilePath)) {
    
    Write-Host "The path for the ARM Template file is not valid. Please verify the path." -BackgroundColor Black -ForegroundColor Red
    Exit -2
}


# Check that selected Azure subscription exists.
$selectedSubscription = $subscriptionList | Where-Object {$_.Name -eq $subscriptionName}
if ($selectedSubscription -eq $null) {
    
    Write-Host "Unable to find subscription name $subscriptionName." -BackgroundColor Black -ForegroundColor Red
    Exit -2

} else {

    Select-AzureRmSubscription -SubscriptionName $subscriptionName | Out-Null
}

# Check that selected Resource Group exists in selected subscription.
$selectedResourceGroup = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -eq $resourceGroupName}
if ($selectedResourceGroup -eq $null) {
    
    Write-Host "Unable to find specified resource group. Resource group name: $resourceGroupName. Subscription  name: $subscriptionName."
    Write-Host "Creating resource group..."

    try{

        New-AzureRmResourceGroup -Name $resourceGroupName `
                                 -Location $location `
                                 -Tag $storageAccountTags | Out-Null
    } catch{

        $ErrorMessage = $_.Exception.Message
    

        Write-Host "Creating a new resource group failed with the following error message:" -BackgroundColor Black -ForegroundColor Red
        throw "$ErrorMessage"
    }
    
}

#Basic error checking on starting index and number of storage accounts
if ($numberOfStorageAccounts -lt 1) {
    Write-Host "Number of storage accounts to create must be at least 1" -BackgroundColor Black -ForegroundColor Red
    Exit -2
}
if ($storageAccountStartIndex -lt 0) {
    Write-Host "The storage account starting index cannot be less than 0" -BackgroundColor Black -ForegroundColor Red
    Exit -2
}
if ($storageAccountStartIndex -gt 99) {
    Write-Host "The storage account starting index cannot be greater than 99. This script currently supports only two-digit iteration numbers on storage accounts." -BackgroundColor Black -ForegroundColor Red
    Exit -2
}
if ( ($storageAccountStartIndex + $numberOfStorageAccounts) -gt 100 ) { 
    Write-Host "This script currently supports only two-digit iteration numbers on storage accounts. Any iteration numbers greater than 99 is not supported." -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# Create an array with the names of the storage accounts to create
$storageAccountNames = @($false) * $numberOfStorageAccounts
for ($i = $storageAccountStartIndex; $i -lt ($storageAccountStartIndex + $numberOfStorageAccounts); $i++) {
    
    $storageAccountNames[$i - $storageAccountStartIndex] = $storageAccountBaseName + $i.ToString("00")
}


# Check availability of storage account names
# Name of each storage account must be globally unique.
foreach ($storageAccountName in $storageAccountNames) {
    $storageNameAvailability = Get-AzureRmStorageAccountNameAvailability -Name $storageAccountName
    if ($storageNameAvailability.NameAvailable -eq $false) {
    
        Write-Host "$($storageNameAvailability.Message)" -BackgroundColor Black -ForegroundColor Red
        Exit -2
    }
}

#end region





###################################################
# region: Deploy ARM Template
###################################################

Write-Host "Deploying ARM Template..."

try{
    New-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroupName `
                                       -Name $deploymentName `
                                       -Mode Incremental `
                                       -TemplateFile $templateFilePath `
                                       -location $location `
                                       -storageAccountBaseName $storageAccountBaseName `
                                       -numberStorageAccounts $numberOfStorageAccounts `
                                       -storageAccountStartIndex $storageAccountStartIndex `
                                       -storageAccountType $storageAccountType `
                                       -storageAccountTags $storageAccountTags `
                                       | Out-Null

    Write-Host "ARM Template deployment $deploymentName finished successfully"

}
catch {
    
    $ErrorMessage = $_.Exception.Message
    

    Write-Host "ARM Template deployment $deploymentName failed with the following error message:" -BackgroundColor Black -ForegroundColor Red
    throw "$ErrorMessage"

}
#end region





###################################################
# region: Create default storage container
###################################################

# ARM Templates do not allow storage containers to be defined
# https://feedback.azure.com/forums/281804-azure-resource-manager/suggestions/9306108-let-me-define-preconfigured-blob-containers-table
# Use PowerShell to create a default container (the 'vhds' container) inside the newly-deployed storage account

foreach ($storageAccountName in $storageAccountNames) {
    # Get the context for the storage account
    $pw = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName
    $context = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $pw.Value[0] -Protocol Https


    # If the container 'vhds' does not already exist, create it
    $containerName = 'vhds'
    $existingContainer = Get-AzureStorageContainer -Name $containerName -Context $context -ErrorAction SilentlyContinue
    if ( !($existingContainer) ){
            
        Write-Host "Creating container vhds in storage account $storageAccountName..."

        # Create new container with its public access permission set to 'Off' (i.e. access to container is Private)
        New-AzureStorageContainer -Name $containerName -Permission Off -Context $context | Out-Null
    }

    # Cleanup activities to remove sensitive variables from the current PowerShell session
    Remove-Variable -Name pw
    Remove-Variable -Name context
    #end region
}

Write-Host "Storage account deployment successfully completed."
<#

.NAME
    Create-StorageAccount-SQLBackup

.DESCRIPTION
    Create a storage account for SQL database backups.

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: June 23, 2016
#>

param (

    [string] $subscriptionID,

    [string] $resourceGroupName ,

    [string] $location = "East US 2",
    
    [string] $storageAccountName,

    [ValidateSet('Premium_LRS','Standard_GRS','Standard_LRS','Standard_RAGRS','Standard_ZRS')]
    [string] $storageAccountType,

    [string[]]
    $vmNames = @("vmName1",
                 "vmName2")

)

Select-AzureRmSubscription -SubscriptionId $subscriptionID | Out-Null

$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction SilentlyContinue

if ( !($storageAccount) ) {

    Write-Host "Creating new storage account..."

    New-AzureRmStorageAccount `
                            -ResourceGroupName $resourceGroupName `
                            -Name $storageAccountName `
                            -Type $storageAccountType `
                            -Location $location `
   
}

<# Get password, create storage account context #>
$pw = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName
$context = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $pw.Key1 -Protocol Https


# Declare the types of containers to create
$containerTypes = @("systemdbbkp",
                    "userdbbkp",
                    "userlogbkp")

# Loop through each VM
foreach ($vmName in $vmNames) {

   # Loop through each container type
   foreach ($containerType in $containerTypes) {

        $containerName = "$vmName-$containerType"

        $existingContainer = Get-AzureStorageContainer -Name $containerName -Context $context -ErrorAction SilentlyContinue

        if ( !($existingContainer) ){
            
            Write-Host "Creating container $containerType on VM $vmName..."
            New-AzureStorageContainer -Name $containerName -Permission Off -Context $context | Out-Null
        }

   }

} 

<#
This script copies blobs using user-inputted connection strings for the Source and the
Destination storage accounts. Can be used to copy VHD files across storage accounts.

The container names and the blob names of the SOURCE blobs are stored in a CSV file,
in the following format:
        Container,Blob Name
        ContainerName1,BlobName1
        ContainerName12,BlobName2
        etc.

The name of the DESTINATION container must be specified under user input.

This script has been tested to function correctly in both ASM and ARM.

This script has been tested to function correctly in Azure PowerShell version 1.0.1

.PARAMETER srcStorageAccountName
	Name of the SOURCE storage account

.PARAMETER srcStorageAccountKey
    Account Key of the SOURCE storage account

.PARAMETER csvPath
    Complete path for the CSV file where all the container names and blob names for all the blobs to be copied are stored.

.PARAMETER destStorageAccountName
    Name of the DESTINATION storage account

.PARAMETER destContainerName
    Container name in which the DESTINATION file will be located (container must be inside DESTINATION storage account)

.PARAMETER destStorageAccountKey
    Account Key of the DESTINATION storage account

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: February 26, 2016
#>

param (
    $srcStorageAccountName = "testStorAcctName",

    $srcStorageAccountKey = "testStorAcctKey",

    $csvPath = "C:\testfile.csv",

    $destStorageAccountName = "destinationStorAcctName",

    $destContainerName = "destinationContainer",

    $destStorageAccountKey = "testStorAcctKey"

)


##################################
# Build connection strings
##################################

# Connection String for the SOURCE storage account
$srcConnectionString = "DefaultEndpointsProtocol=https;AccountName=$srcStorageAccountName;AccountKey=$srcStorageAccountKey"

###

# Connection String for the DESTINATION storage account
$destConnectionString = "DefaultEndpointsProtocol=https;AccountName=$destStorageAccountName;AccountKey=$destStorageAccountKey"

##################################
# Start copy operation
##################################

# Make context for SOURCE storage account
$srcContext = New-AzureStorageContext -ConnectionString $srcConnectionString
# Make context for DESTINATION storage account
$destContext = New-AzureStorageContext -ConnectionString $destConnectionString

#Import contents from the CSV file
$blobobjects = Import-Csv -path $csvPath

#Get each blob and copy it individually
foreach ($blob in $blobobjects){

    $srcContainerName = $blob.Container
    $srcBlobName = $blob.'Blob Name'

    # Start copy operation for each blob
    Start-AzureStorageBlobCopy -Context $srcContext -SrcContainer $srcContainerName -SrcBlob $srcBlobName -DestContext $destContext -DestContainer $destContainerName

}


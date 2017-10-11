param(
    $destAccountName = "teststorageaccount",

    $destAccountKey = "testaccountkey",

    # Local path of file to be uploaded
    $fileToUploadPath = "C:\Users\testuser\Desktop\testfile.txt",

    # Container name in which the DESTINATION file will be located (container must be inside DESTINATION storage account)
    $destContainerName = "uploadedresources",

    # Name to give to new blob in Azure storage account
    $blobName = "testblobname"

)

# Connection String for the DESTINATION storage account
$destConnectionString = "DefaultEndpointsProtocol=https;AccountName=$destAccountName;AccountKey=$destAccountKey"

# Make context for DESTINATION storage account
$destContext = New-AzureStorageContext -ConnectionString $destConnectionString

Set-AzureStorageBlobContent -File $fileToUploadPath -Context $destContext -Container $destContainerName -Blob $blobName
<#
 This script downloads all of the contents of a particular container to the specified
 destination folder.
#>


#### USER INPUITS

$container_name = 'uploadedresources'
$destination_path = 'C:\temp'
$accountname,
$accountkey,

#### MAIN FUNCTION

$connection_string = "DefaultEndpointsProtocol=https;AccountName=$accountname;AccountKey=$accountkey"

$storage_account = New-AzureStorageContext -ConnectionString $connection_string


$blobs = Get-AzureStorageBlob -Container $container_name -Context $storage_account

foreach ($blob in $blobs)
    {
        New-Item -ItemType Directory -Force -Path $destination_path

        Get-AzureStorageBlobContent `
        -Container $container_name -Blob $blob.Name -Destination $destination_path `
        -Context $storage_account

    }



<#
Set-AzureStorageBlobContent -Blob "testfilecarlos.txt" -Container $container_name `
                            -File "C:\temp\testfilecarlos.txt" -Context $storage_account
#>
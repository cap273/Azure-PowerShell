<#
Looks for a file in target folder. File search is done recursively. If file does exist, copy file to target storage account.

REQUIRES: Azure PowerShell module installed
#>

param(
    $destAccountName = "testaccount",
    $destContainerName = "containername",
    $destAccountKey = "accountkey",

    # Name to give to new blob in Azure storage account
    $blobName = "testblobname",

    # Local path of the folder in which to look for a file
    $folderPath = "C:\Users\testuser\Desktop",

    # Name of the file to look for
    $fileName = "testfile.txt"
)

# Find file recursively
$file = Get-ChildItem -Path $folderPath -Filter $fileName -Recurse

if ( !([string]::IsNullOrEmpty($file)) ){
    
    Write-Output "File $fileName was found in folder $folderPath!"
    Write-Output "Beginning copy operation..."

    $fullPathOfFile = $file.FullName

    # Connection String for the DESTINATION storage account
    $destConnectionString = "DefaultEndpointsProtocol=https;AccountName=$destAccountName;AccountKey=$destAccountKey"

    # Make context for DESTINATION storage account
    $destContext = New-AzureStorageContext -ConnectionString $destConnectionString

    # Upload blob
    Set-AzureStorageBlobContent -File $fullPathOfFile -Context $destContext -Container $destContainerName -Blob $blobName

    Write-Output "Copy operation finished."

} else {

    Write-Output "File $fileName was not found in folder $folderPath"

}


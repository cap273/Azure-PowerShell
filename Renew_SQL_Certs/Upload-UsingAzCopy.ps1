<#
Upload-UsingAzCopy
Just sharing a quick script to copy files into Azure Blob Storage using PowerShell and AZCopy tool.
If you are not familiar with the AZCopy tool, it’s a command line utility for 
uploading/downloading data to and from blob storage.

http://www.thisdevmind.com/2015/05/20/copying-files-into-azure-blob-storage-using-azcopy-and-powershell/

Upload-UsingAzCopy.
#>

param(
    [string] $Source,
    [string] $Dest,
    [string] $FileToUpload,
    [string] $StorageAccountKey,
    [string] $AzCopyPath
)

if (Test-Path "$Source\$FileToUpload") {

    #use AzCopy to copy files into blob
    # Exclude older files
    & "$AzCopyPath" /Source:""$Source"" /Dest:""$Dest"" /Pattern:""$FileToUpload"" /DestKey:""$StorageAccountKey"" /Y

}

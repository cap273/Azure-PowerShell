param(
    $destAccountName = "teststoragecarlos01",

    $destAccountKey = "storageaccountkeyhere",

    # Local path of folder to be uploaded
    $sourceFolder = "D:\sources\sxs",

    $fileShareName = "testfileshare",

    #Destination Azure directory
    $AzureDirectory = 'sxs'

)

$ErrorActionPreference = 'Stop'

# Connection String for the DESTINATION storage account
$destConnectionString = "DefaultEndpointsProtocol=https;AccountName=$destAccountName;AccountKey=$destAccountKey"

# Make context for DESTINATION storage account
$destContext = New-AzureStorageContext -ConnectionString $destConnectionString 

$storageShare = Get-AzureStorageShare -Context $destContext -Name $fileShareName


#$AzureDirectory = Get-AzureStorageDirectory -Share $storageShare -Path $AzureDirectory


# get all the folders in the source directory and recreate them
$Folders = Get-ChildItem -Path $sourceFolder -Recurse | ?{ $_.PSIsContainer }
foreach($Folder in $Folders)
 {
     $f = ($Folder.FullName).Substring(($sourceFolder.Length))
     $Path = $AzureDirectory + $f

     New-AzureStorageDirectory -Share $storageShare -Path $Path -ErrorAction Continue
 }


# Get all files and upload them
$files = Get-ChildItem -Path $sourceFolder -Recurse -File
foreach($File in $Files)
 {
     $f = ($file.FullName).Substring(($sourceFolder.Length))
     $Path = $AzureDirectory + $f

     #upload the files to the storage
     Set-AzureStorageFileContent -Share $storageShare -Source $File.FullName -Path $Path -Force
 }
<#
This is a test Azure Automation runbook to:
1. Create a file locally in PowerShell
2. Store that file in Azure Automation's local filesystem
3. Upload that file to an Azure storage account

#>

param(

    [String] $connectionName = "AzureRunAsConnection",
    [String] $subscriptionName = "Visual Studio Enterprise with MSDN",

    [String] $storageAccountResourceGroupName = "RG-Storage",
    [String] $storageAccountName = "testcarlosstor5678",
    [String] $containerName = "uploadfiles",

    [String] $testFileNameWithExt = "testfile.txt"
)

$ErrorActionPreference = 'Stop'

####################
# Azure authentication
# References: https://docs.microsoft.com/en-us/azure/automation/automation-create-runas-account
#             https://docs.microsoft.com/en-us/azure/automation/automation-verify-runas-authentication
####################

try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection= Get-AutomationConnection -Name $connectionName         

    Write-Output "Logging in to Azure..."
    Add-AzureRmAccount `
       -ServicePrincipal `
       -TenantId $servicePrincipalConnection.TenantId `
       -ApplicationId $servicePrincipalConnection.ApplicationId `
       -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint | Out-Null

    Write-Output "Login successful."
}
catch 
{
   if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage

    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

try
{
    Write-Output "Selecting subscription [$subscriptionName]..."
    Select-AzureRmSubscription -SubscriptionName $subscriptionName | Out-Null
    Write-Output "Subscription [$subscriptionName] selected successfully.`n"
}
catch
{
    Write-Error -Message $_.Exception
    throw $_.Exception
}

#######

# Output the name of Azure Automation's temporary local filesystem
# Reference: http://www.itprotoday.com/microsoft-azure/where-can-temporary-files-be-created-azure-automation
$thisLocation = $env:TEMP
Write-Output "The local filesystem path is: [$thisLocation]"


####################
# Storage Account
####################


# Get storage context for this Azure storage account
Write-Output "Retrieving the Azure storage account key and context..."
$storageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $storageAccountResourceGroupName -Name $storageAccountName
$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey.Value[0] -Protocol Https
Write-Output "Azure storage account key and context successfully retrieved."


####################
# Container Check
####################

# If the container $containerName does not already exist, create it
$existingContainer = Get-AzureStorageContainer -Name $containerName -Context $storageContext -ErrorAction SilentlyContinue
if ( !($existingContainer) )
{
    
    Write-Output "Container [$containerName] does not exist in storage account [$storageAccountName]."
    Write-Output "Creating container [$containerName] in storage account [$storageAccountName]..."

    # Create new container with its public access permission set to 'Off' (i.e. access to container is Private)
    New-AzureStorageContainer -Name $containerName -Permission Off -Context $storageContext | Out-Null

    Write-Output "Container [$containerName] in storage account [$storageAccountName] successfully created."
}

####################
# New test File
####################

# Create a new file in Azure Automation's local file system
$testFilePath = "$thisLocation\$testFileNameWithExt"
New-Item $testFilePath -ItemType File

Write-Output "Created new file [$testFileNameWithExt] in location [$thisLocation]".

####################
# Upload to storage account
####################

Write-Output "Uploading file [$testFileNameWithExt] to storage account [$storageAccountName]..."
Set-AzureStorageBlobContent -File $testFilePath `
                            -Context $storageContext `
                            -Container $containerName `
                            -Blob $testFileNameWithExt

Write-Output "Finished uploading file [$testFileNameWithExt] to storage account [$storageAccountName]."
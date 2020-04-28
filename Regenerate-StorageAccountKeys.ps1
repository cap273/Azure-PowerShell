<#
    .DESCRIPTION
        Regenerates storage account keys of target Azure storage account.

        This PowerSchell script runs as a runbook in an Azure Automation Account, and authenticates to Azure
        through a Service Principal using certificate 

    .NOTES
        AUTHOR: Carlos Patiño
        LASTEDIT: March 16, 2020
#>

param(
    $resourceGroupName,
    $storageAccountName
)

$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection"
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Login-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

Write-Output "Getting key names from storage account [$storageAccountName] in resource group [$resourceGroupName]..."
$storageAccountKeyNames = (Get-AzStorageAccountKey -ResourceGroupName resourceGroupName -Name $storageAccountName).KeyName
Write-Output "Key names acquired. Key 1 Name: [$($storageAccountKeyNames[0])]. Key 2 Name: [$($storageAccountKeyNames[1])]."

Write-Output "Regenerating first key: [$($storageAccountKeyNames[0])]..."
New-AzStorageAccountKey -ResourceGroupName $resourceGroupName `
    -Name $storageAccountName `
    -KeyName $storageAccountKeyNames[0] | Out-Null
Write-Output "First key: [$($storageAccountKeyNames[0])] regenerated."

Write-Output "Regenerating second key: [$($storageAccountKeyNames[1])]..."
New-AzStorageAccountKey -ResourceGroupName $resourceGroupName `
    -Name $storageAccountName `
    -KeyName $storageAccountKeyNames[1] | Out-Null
Write-Output "Second key [$($storageAccountKeyNames[1])] regenerated."
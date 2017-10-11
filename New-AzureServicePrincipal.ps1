 #Requires -RunAsAdministrator

$ResourceGroup = 'powershelllearning'
$AutomationAccountName = 'testCarlosAutomationAccount2'
$ApplicationDisplayName = 'testCarlosAutomationAccount2'
$SubscriptionId = 'subidgoeshere'
$CertPlainPassword = 'certpwgoeshere'
$NoOfMonthsUntilExpired = 12



$ErrorActionPreference = 'Stop'


Import-Module AzureRM.Resources
#Select-AzureRmSubscription -SubscriptionId $SubscriptionId

$CurrentDate = Get-Date
$EndDate = $CurrentDate.AddMonths($NoOfMonthsUntilExpired)
$KeyId = (New-Guid).Guid
#$CertPath = Join-Path $env:TEMP ($ApplicationDisplayName + ".pfx")
$CertPath = Join-Path "C:\Users\carpat\Desktop" ($ApplicationDisplayName + ".pfx")

$Cert = New-SelfSignedCertificate -DnsName $ApplicationDisplayName `
                                -CertStoreLocation cert:\LocalMachine\My `
                                -KeyExportPolicy Exportable `
                                -Provider "Microsoft Enhanced Cryptographic Provider v1.0" `
                                -HashAlgorithm SHA256

$CertPassword = ConvertTo-SecureString $CertPlainPassword -AsPlainText -Force
Export-PfxCertificate -Cert ("Cert:\localmachine\my\" + $Cert.Thumbprint) -FilePath $CertPath -Password $CertPassword -Force | Write-Verbose

$PFXCert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate -ArgumentList @($CertPath, $CertPlainPassword)
$KeyValue = [System.Convert]::ToBase64String($PFXCert.GetRawCertData())

$KeyCredential = New-Object  Microsoft.Azure.Commands.Resources.Models.ActiveDirectory.PSADKeyCredential
$KeyCredential.StartDate = $CurrentDate
$KeyCredential.EndDate= $EndDate
$KeyCredential.KeyId = $KeyId
#$KeyCredential.Type = "AsymmetricX509Cert"
#$KeyCredential.Usage = "Verify"
#$KeyCredential.Value = $KeyValue
$KeyCredential.CertValue = $KeyValue

Write-Host "here"

# Use Key credentials
$Application = New-AzureRmADApplication -DisplayName $ApplicationDisplayName `
                                        -HomePage ("http://" + $ApplicationDisplayName) `
                                        -IdentifierUris ("http://" + $KeyId) `
                                        -KeyCredentials $keyCredential

New-AzureRMADServicePrincipal -ApplicationId $Application.ApplicationId | Write-Verbose
Get-AzureRmADServicePrincipal | Where {$_.ApplicationId -eq $Application.ApplicationId} | Write-Verbose

Write-Host "now here"

$NewRole = $null
$Retries = 0;
While ($NewRole -eq $null -and $Retries -le 6)
{
    # Sleep here for a few seconds to allow the service principal application to become active (should only take a couple of seconds normally)
    Sleep 5
    New-AzureRMRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $Application.ApplicationId | Write-Verbose -ErrorAction SilentlyContinue
    Sleep 10
    $NewRole = Get-AzureRMRoleAssignment -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
    $Retries++;
}

Write-Host "now here"

# Get the tenant id for this subscription
$SubscriptionInfo = Get-AzureRmSubscription -SubscriptionId $SubscriptionId
$TenantID = $SubscriptionInfo | Select TenantId -First 1

# Create the automation resources
New-AzureRmAutomationCertificate -ResourceGroupName $ResourceGroup `
                                 -AutomationAccountName $AutomationAccountName `
                                 -Path $CertPath `
                                 -Name AzureRunAsCertificate `
                                 -Password $CertPassword `
                                 -Exportable | Write-Verbose

# Create a Automation connection asset named AzureRunAsConnection in the Automation account. This connection uses the service principal.
$ConnectionAssetName = "AzureRunAsConnection"
Remove-AzureRmAutomationConnection -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccountName -Name $ConnectionAssetName -Force -ErrorAction SilentlyContinue
$ConnectionFieldValues = @{"ApplicationId" = $Application.ApplicationId; "TenantId" = $TenantID.TenantId; "CertificateThumbprint" = $Cert.Thumbprint; "SubscriptionId" = $SubscriptionId}
New-AzureRmAutomationConnection -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccountName -Name $ConnectionAssetName -ConnectionTypeName AzureServicePrincipal -ConnectionFieldValues $ConnectionFieldValues

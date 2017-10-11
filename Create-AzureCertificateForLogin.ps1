<#
    This script performs the following:
    - Creates a self-signed certificiate in this computer's local certificate store
    - Registers an application and a service principal in Azure Active Directory.
        Thus application and service principal are associated with the newly-created certificate
    - Assigns the role of 'Owner' to the newly-created service principal

    After all of these actions are complete, Azure PowerShell will be able to authenticate to Azure
    using a management certificate (instead of using any specific user credentials).

#>

param(
    $tenantID = "placeholder",
    $subscriptionName = "placeholder",

    $certName = "CN=CustomAzureMSFTCert",
    $certStoreLocation = "cert:\LocalMachine\My",

    $AppRegistrationDisplayName = "carpat_" + ([guid]::NewGuid()).Guid
)

# Initializations
$ErrorActionPreference = 'Stop'
$identifierUri = "https://0c0669b3d7b430dac3db417af7df128" #The URIs that identify the application. Set here to some random GUID without hyphens

# Checking whether user is logged in to Azure in order to register service principal
Write-Host "Validating Azure Accounts..."
try{
    $subscriptionList = Get-AzureRmSubscription -WarningVariable WarningMessage | Sort SubscriptionName 
    if ($WarningMessage){throw "$WarningMessage"}
}
catch {
    Write-Host "Reauthenticating..."
    Login-AzureRmAccount | Out-Null
    $subscriptionList = Get-AzureRmSubscription | Sort SubscriptionName
}

# Select subscription
Select-AzureRmSubscription -SubscriptionName $subscriptionName -TenantId $tenantID | Out-Null

# Create a new self-signed certificate
Write-Host "Creating new self-signed certificate..."
$cert = New-SelfSignedCertificate -CertStoreLocation $certStoreLocation `
                                  -Subject $certName `
                                  -KeySpec KeyExchange

# Retrieve properties of cerficiate
$keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())

# Create a new Azure Active Directory application
Write-Host "Creating new Azure Active Directory application..."
$azureAdApplication = New-AzureRmADApplication -DisplayName $AppRegistrationDisplayName `
                                               -HomePage "https://management.azure.com/" `
                                               -IdentifierUris $identifierUri `
                                               -CertValue $keyValue `
                                               -EndDate $cert.NotAfter `
                                               -StartDate $cert.NotBefore

Write-Host "The ID of the new AAD application is: $($azureAdApplication.ApplicationId)"

# Create a new Azure Active Directory service principal
Write-Host "Creating new Azure Active Directory service principal..."
New-AzureRmADServicePrincipal -ApplicationId $azureAdApplication.ApplicationId | Out-Null

# Assign the RBAC role 'Owner' to the newly-created service principal
Write-Host "Assigning role 'Owner' to new Azure Active Directory service principal..."
$NewRole = $null
$Retries = 0;
While ($NewRole -eq $null -and $Retries -le 6)
{
    # Sleep here for a few seconds to allow the service principal application to become active (should only take a couple of seconds normally)
    Sleep 5

    New-AzureRmRoleAssignment -RoleDefinitionName Owner `
                              -ServicePrincipalName $azureAdApplication.ApplicationId.Guid `
                              -ErrorAction SilentlyContinue | Out-Null

    Sleep 10
    $NewRole = Get-AzureRMRoleAssignment -ServicePrincipalName $azureAdApplication.ApplicationId.Guid `
                                         -ErrorAction SilentlyContinue
    $Retries++;
}

Write-Host "Operations complete"

<#
################################################
# Authenticate to Azure
################################################

# Get the certificate thumprint, and the application ID 
$certThumbprint = (Get-ChildItem -Path $certStoreLocation | ? { $_.Subject -eq $certName }).Thumbprint
$appId = $azureAdApplication.ApplicationId

# Login to Azure
Add-AzureRmAccount -ServicePrincipal `
                   -TenantId $tenantID `
                   -ApplicationId $appId `
                   -CertificateThumbprint $certThumbprint

#>
<#
    This script performs the following:
    - Logs in to Azure using a service principal and a management certificate (as opposed to using a specific user's credentials)
    - Checks whether any user-defines route tables exist in the specified subscription
    - Logs results of script execution in the file specified by $logFilePath

#>

param(
    $tenantID = "placeholder",
    $subscriptionName = "placeholder",

    $certName = "CN=CustomAzureMSFTCert",
    $certStoreLocation = "cert:\LocalMachine\My",

    # Application ID can be viewed under 'App Registrations' in Azure Active Directory
    $appID = "placeholder",

    # Specify the file type as either .txt or .csv
    $logFilePath = "C:\Users\carpat\Desktop\log.txt"
)

# Initializations
$ErrorActionPreference = 'Stop'

# Define function to save output to CSV file
function Write-Log {
    param($inputLine)
    Out-File -FilePath $logFilePath -Append -InputObject $inputLine -Encoding unicode 
}

# Get current time
$currentTime = (Get-Date).ToUniversalTime()

Write-Log -inputLine "Starting script execution, at UTC time $currentTime"

# Get the thumbprint of the certificate in the certificate store
$certThumbprint = (Get-ChildItem -Path $certStoreLocation | ? { $_.Subject -eq $certName }).Thumbprint

Write-Log -inputLine "Logging into Azure using management certificate..."
try{
    # Login to Azure
    Add-AzureRmAccount -ServicePrincipal `
                   -TenantId $tenantID `
                   -ApplicationId $appId `
                   -CertificateThumbprint $certThumbprint | Out-Null
                    
    Write-Log -inputLine "Selecting subscription $subscriptionName..."
    Select-AzureRmSubscription -SubscriptionName $subscriptionName -TenantId $tenantID | Out-Null
}
catch {
    
    $ErrorMessage = $_.Exception.Message

    Write-Log -inputLine "Logging into Azure using a certificate failed with the following error message:"
    Write-Log -inputLine "$ErrorMessage"
}

Write-Log -inputLine "Successfully logged into Azure"

Write-Log -inputLine "Checking user-defined route tables..."

# Get all Azure route tables in the subscription
$routeTables = Get-AzureRmRouteTable

if ($routeTables) {

    Write-Log -inputLine "WARNING: At least one user-defined route table was found. Route table names:"
    foreach ($routeTable in $routeTables) {
        Write-Log -inputLine "$($routeTable.Name)"
    }

    <#
    # Sample code to send an email using PowerShell

    $SmtpClient = new-object system.net.mail.smtpClient
    $MailMessage = New-Object system.net.mail.mailmessage
    $SmtpClient.Host = "mysmtpserver.mycompany.local"
    $mailmessage.from = ("sender@company.com ")
    $mailmessage.To.add("recipient@company.com")
    $mailmessage.Subject = “Message”
    $mailmessage.Body = “Body”
    $smtpclient.Send($mailmessage) 
    #>

} else{
    Write-Log -inputLine "No route tables were found."
}

Write-Log -inputLine "Azure PowerShell script finished (Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $currentTime))))"
Write-Log -inputLine ""
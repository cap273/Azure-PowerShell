<#

.NAME
	Get-RBAC
	
.DESCRIPTION 
    This script gets:
    (1) custom Role-Based Accesss Control (RBAC) definitions across all available subscriptios in an AAD tenant
    (2) RBAC assignments for all accounts across all available subscriptios in an AAD tenant

    This script outputs this information as several JSON files stored in this script's current working directory:
    - subscriptionList.json: list of available subscriptions in this AAD tenant (as available to the account running this script)
    - roledefs-<subscriptionID>.json: a file per subscription listing the custom RBAC roles
    - roleassign-<subscriptionID>.json: a file per subscription listing the RBAC role assignments


.PARAMETER tenantID
	ID of the Azure Active Directory (AAD) tenant. Can be found in the Azure portal (portal.azure.com) under the 
    tab "Azure Active Directory".

#>

param(
    $tenantID= "d1093b43-aab4-41c7-b407-7556438dfc86"
)

###################################################
# region: PowerShell and Azure Dependency Checks
###################################################
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
$ErrorActionPreference= 'Stop'
$WarningPreference= 'Stop'

Write-Host "Checking Dependencies..."

# Check for the directory in which this script is running.
# Certain files (the ARM template in JSON, and an output CSV file) will be saved in this directory.
if ( [string]::IsNullOrEmpty($PSScriptRoot) ) {
    throw "Please save this script before executing it."
}

# Checking for Windows PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "You need to have Windows PowerShell version 5.0 or above installed." -ForegroundColor Red
    Exit -2
}

# Checking for Azure PowerShell module
$modlist= Get-Module -ListAvailable -Name 'Az.Resources'
if (($modlist -eq $null) -or ($modlist.Version.Major -lt 1)){
    Write-Host "Please install the Azure PowerShell Az module, version 1.0 (released December 2018) or above." -BackgroundColor Black -ForegroundColor Red
    Write-Host "The standalone MSI file for the latest Azure Powershell versions can be found in the following URL:" -BackgroundColor Black -ForegroundColor Red
    Write-Host "https://github.com/Azure/azure-powershell/releases" -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# Checking whether user is logged in to Azure
Write-Host "Validating Azure Accounts..."
try{
    $subscriptionList= Get-AzSubscription | Sort SubscriptionName
}
catch {
    Write-Host "Reauthenticating..."
    Login-AzAccount -Tenant $tenantID | Out-Null
    $subscriptionList= Get-AzSubscription | Sort SubscriptionName
}

Write-Host "`nList of available Azure subscriptions in current Azure AD tenant:" -BackgroundColor Black -ForegroundColor White
foreach ($sub in $subscriptionList) {Write-Host "Name: [$($sub.Name)] ID: [$($sub.ID)]"}
Read-Host -Prompt "`nPress any key to continue or CTRL+C to quit"

Write-Host "`nSaving list of subscriptions to JSON file in current working directory..."
$subscriptionList| ConvertTo-Json | Out-File "$PSScriptRoot\subscriptionList.json" -Force
Write-Host "`List of subscriptions saved to file: [$($PSScriptRoot)\subscriptionList.json]"
#end region


###################################################
# region: Get RBAC definitions & 
###################################################
Write-Host "`n"

# Loop through each subscription, and output a JSON file per subscription with custom RBAC roles
foreach ($sub in $subscriptionList)
{
    Select-AzSubscription $sub | Out-Null
    Write-Host "Current subscription: [$($sub.Name)]..."

    $roleDefOutputFileName= "roledefs-$($sub.ID).json"

    Get-AzRoleDefinition | `
        Where-Object {$_.IsCustom -eq $true} | `
        ConvertTo-Json | `
        Out-File "$PSScriptRoot\$roleDefOutputFileName" -Force

    Write-Host "Custom role definitions saved to file: [$($PSScriptRoot)\$($roleDefOutputFileName)]"
}

Write-Host "`n"

# Loop through each subscription, and output a JSON file per subscription with RBAC assignments
foreach ($sub in $subscriptionList)
{
    Select-AzSubscription $sub | Out-Null
    Write-Host "Current subscription: [$($sub.Name)]..."

    $roleAssignOutputFileName= "roleassign-$($sub.ID).json"

    Get-AzRoleAssignment | `
        ConvertTo-Json | `
        Out-File "$PSScriptRoot\$roleAssignOutputFileName" -Force

    Write-Host "Role assignments saved to file: [$($PSScriptRoot)\$($roleAssignOutputFileName)]"
}

Write-Host "`nScript execution completed." -BackgroundColor Black -ForegroundColor Green
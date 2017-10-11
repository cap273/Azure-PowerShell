#####################
# This script creates and assigns Azure Policies to a selected subscription.
#
# The Azure policies are defined as .json files. These files should be located in the
# folder specified by parameter $folderWithPolicyFiles
#
# This script will first delete any existing policy definitions and assignments from the subscription
#
# Run Login-AzureRmAccount before running this script.
#
####################


param (
    
    # Azure subscription ID
    [string] $subscriptionId = "43955c27-bbb7-4f49-8528-df0163f11a18",

    # Define the folder that contains the .json files that define the ARM policies
    [string] $folderWithPolicyFiles = "C:\Users\carpat\OneDrive - Microsoft\Azure-PowerShell\Policies-Alerts-CustomRBACRole",

    # Set to $true if you want to assign a policy that prohibits the creation of public IP addresses in target subscription
    [bool] $denyPublicIPAddress = $false
)


###################################################
# region: PowerShell and Azure Dependency Checks
###################################################
cls
$ErrorActionPreference = 'Stop'

Write-Host "Checking Dependencies..."

# Checking for Windows PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 4) {
    Write-Host "You need to have Windows PowerShell version 4.0 or above installed." -ForegroundColor Red
    Exit -2
}

# Checking for Azure PowerShell module
$modlist = Get-Module -ListAvailable -Name 'Azure'
if (($modlist -eq $null) -or ($modlist.Version.Major -lt 2)){
    Write-Host "Please install the Azure Powershell module, version 2.0.0 (released August 2016) or above." -BackgroundColor Black -ForegroundColor Red
    Write-Host "The standalone MSI file for the latest Azure Powershell versions can be found in the following URL:" -BackgroundColor Black -ForegroundColor Red
    Write-Host "https://github.com/Azure/azure-powershell/releases" -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# Checking whether user is logged in to Azure
Write-Host "Validating Azure Accounts..."
try{
    $subscriptionList = Get-AzureRmSubscription | Sort SubscriptionName
}
catch {
    Write-Host "Reauthenticating..."
    Login-AzureRmAccount | Out-Null
    $subscriptionList = Get-AzureRmSubscription | Sort SubscriptionName
}

Select-AzureRmSubscription -SubscriptionId $subscriptionId | Out-Null
Write-Host "Operating on subscription with ID: $subscriptionId"
#end region




###################################################
# region: Initializations
###################################################

# Define the policy names and corresponding descriptions
$policies = @(
    @{
        PolicyName = 'Append-AllTags-NonVMResources'; 
        PolicyDescription = 'If a resource that is not a VM is deployed with no tags, append a series of tags with default values.'
    },
    @{
        PolicyName = 'Append-AllTags-VMOnly'; 
        PolicyDescription = 'If a VM is deployed with no tags, append a series of tags with default values.'
    },
    @{
        PolicyName = 'Append-ApplicationName-Tag-to-VM'; 
        PolicyDescription = 'If a VM is deployed with no ApplicationName tag, append the tag.'
    },
    @{
        PolicyName = 'Append-CostCenter-Tag-to-AllResources'; 
        PolicyDescription = 'If any resource is deployed with no CostCenter tag, append the tag.'
    },
    @{
        PolicyName = 'Approved-Azure-Services'; 
        PolicyDescription = 'Policy that defines the list of allowed Azure services. Deny deployments for any other Azure services.'
    },
    @{
        PolicyName = 'Approved-Regions'; 
        PolicyDescription = 'Policy that defines the list of allowed Azure regions. Deny deployments for any other Azure regions.'
    },
    @{
        PolicyName = 'Approved-Storage-SKUs'; 
        PolicyDescription = 'Policy that defines the allowable storage SKUs. Only allow Standard_LRS storage accounts.'
    },
    @{
        PolicyName = 'Audited-Services'; 
        PolicyDescription = 'List of Azure services that will be marked as Audit when deployed.'
    }
)

if ($denyPublicIPAddress) {
    
    $policies += @{
                    PolicyName = 'Deny-Public-IP-Address'; 
                    PolicyDescription = 'Deny the creation of any public IP addresses.'
                  }
    
}

# Define that the scope of the policies to be assigned is the subscription
$subscriptionScope = "/subscriptions/$subscriptionId/"

#endregion


#Delete existing Azure Policy assignments and definitions
Write-Host "Removing existing Azure Policy assignments and definitions..."
Get-AzureRmPolicyAssignment | Remove-AzureRmPolicyAssignment -Scope $subscriptionScope | Out-Null
Get-AzureRmPolicyDefinition | Remove-AzureRmPolicyDefinition -Force | Out-Null



###################################################
# region: Assign Policies
###################################################

#Loop through every policy
for ($i=0; $i -lt $policies.Length; $i++) {

    Write-Host "Creating Azure policy definition & assignment for $($policies[$i].PolicyName)..."
    
    # Get path of JSON file that defines Azure policy
    $policyJsonFile = $policies[$i].PolicyName + '.json'
    $policyJsonFilePath = Join-Path $folderWithPolicyFiles $policyJsonFile

    if ( !(Test-Path $policyJsonFilePath) ) {
        throw "Error: could not find file path for file $policyJsonFilePath."
    }

    try{
        # Define a new Azure Policy Definition
        $policyDefinition = New-AzureRmPolicyDefinition `
                                -Name $policies[$i].PolicyName `
                                -Description $policies[$i].PolicyDescription `
                                -Policy $policyJsonFilePath
    } catch{
        $ErrorMessage = $_.Exception.Message
        Write-Host "New Azure policy definition failed."
        Write-Host "Error message: $ErrorMessage"
    }

    Start-Sleep -Seconds 5

    try{
        # New Azure policy assignment
        New-AzureRmPolicyAssignment `
            -Name $policies[$i].PolicyName `
            -Scope $subscriptionScope `
            -PolicyDefinition $policyDefinition | Out-Null

    }catch{
        $ErrorMessage = $_.Exception.Message
        Write-Host "New Azure policy assignment failed."
        Write-Host "Error message: $ErrorMessage"
    }
}
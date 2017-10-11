#####################
# This script creates Azure log (or event) rules that monitor for certain networking-related actions.
#
# The alert rules currently created by this script are:
# -	When a network security group or route table is associated or disassociated with a subnet
# -	When an alert is deleted. Note that if this alert is deleted, it will not trigger an alert
# -	When a route table is created. Does not infer a route table is associated with a subnet
# -	When a route table is deleted
# -	When a route in a route table is created or modified.
# -	When a route in a route table is deleted
# -	When a network security group is created. Does not infer a network security group is associated with a subnet
# -	When a network security group is deleted
# -	When a rule in an NSG is created or modified
# -	When a rule in an NSG is deleted
#
# Can get the Azure alert rules currently assigned to a resource group by running the following cmdlet:
# Get-AzureRmAlertRule -resourcegroup $resourceGroupName
#
#
# Can delete all Azure alert rules currently assigned to a resource group by running the following:
<#
        $alerts = Get-AzureRmAlertRule -resourcegroup $resourceGroupName
        foreach ($alert in $alerts) {Remove-AzureRmAlertRule -resourcegroup $resourceGroupName -Name $alert.Name -WarningAction SilentlyContinue}
#>
#
# Run Login-AzureRmAccount before running this script.
#
# Author: Jason Beck
#
####################

param (
    
    # Azure subscription ID
    [string] $subscriptionId,

    # Define an array of email addresses that will receive email alerts when the alert rules are triggered
    # Example: $emailAddresses = @("person1@org.com","person2@org.com")
    [string[]] $emailAddresses,

    # Name of the resource group in which this alert rule is going to apply
    # This resource group should contain the networking components to be monitored (e.g. VNets, route tables, NSGs) 
    $resourceGroupName,
    
    # Location of the resource group
    [ValidateSet("Central US", "East US", "East US 2", "West US", "North Central US", "South Central US", "West Central US", "West US 2")]
    [string] $location
)

######

########################################################
# Initializations
########################################################
Select-AzureRmSubscription -SubscriptionId $subscriptionId | Out-Null
$ErrorActionPreference = 'Stop'

function CreateAlert
{
    param(
        $emailAddresses = @("example@myemail.com"), #comma separate emails
        $alertRuleName = "Create NSG",
        $location = "eastus2",
        $resourceGroup = "resourcegroupname", #the resource group where the alert will reside
        $targetResourceGroup = "resourcegroupname", # the targeted resource group where the operation of choice will be monitored 
        $operationName = "Microsoft.Network/networkSecurityGroups/write",
        $description = "description", 
        $status = "Succeeded"
    )

    # Create the email alert
    $emailAlert = New-AzureRmAlertRuleEmail -CustomEmails $emailAddresses

    try{
        # Create the log alert rule with the action being an email alert
        Add-AzureRmLogAlertRule -Name $alertRuleName -Location $location -ResourceGroup $resourceGroup -OperationName $operationName `
                                -status $status -TargetResourceGroup $targetResourceGroup -Actions $emailAlert -Description $description `
                                -WarningAction SilentlyContinue | Out-Null
    }
    catch
    {
        $ErrorMessage = $_.Exception.Message
        Write-Host "Creating log alert named $alertRuleName failed."
        Write-Host "Error message: $ErrorMessage"
    }
}

########################################################
# NSG or RT Subnet Association
########################################################

$emailAddresses = $emailAddresses
$alertRuleName = "NSG or RT Subnet Association"
$location = $location
$resourceGroup = $resourceGroupName #the resource group where the alert will reside
$targetResourceGroup = $resourceGroupName # the targeted resource group where the operation of choice will be monitored 
$operationName = "Microsoft.Network/virtualNetworks/subnets/write"
$description = "Alert when a network security group or route table is associated or disassociated with a subnet"
$status = "Succeeded"

Write-Host "Creating Alert: $alertRuleName..."

CreateAlert -emailAddresses $emailAddresses -alertRuleName $alertRuleName -location $location -resourceGroup $resourceGroup `
            -targetResourceGroup $targetResourceGroup -operationName $operationName -description $description -status $status

Write-Host "Completed: $alertRuleName"

########################################################
# Deleting Log Alerts
########################################################

$emailAddresses = $emailAddresses
$alertRuleName = "Deleting Log Alerts"
$location = $location
$resourceGroup = $resourceGroupName #the resource group where the alert will reside
$targetResourceGroup = $resourceGroupName # the targeted resource group where the operation of choice will be monitored 
$operationName = "Microsoft.Insights/alertrules/delete"
$description = "Alert when a log alert is deleted. If this alert is deleted, it will not trigger an alert."
$status = "Succeeded"

Write-Host ""
Write-Host "Creating Alert: $alertRuleName..."

CreateAlert -emailAddresses $emailAddresses -alertRuleName $alertRuleName -location $location -resourceGroup $resourceGroup `
            -targetResourceGroup $targetResourceGroup -operationName $operationName -description $description -status $status

Write-Host "Completed: $alertRuleName"

########################################################
# Create Route Table
########################################################

$emailAddresses = $emailAddresses
$alertRuleName = "Create Route Table"
$location = $location
$resourceGroup = $resourceGroupName #the resource group where the alert will reside
$targetResourceGroup = $resourceGroupName # the targeted resource group where the operation of choice will be monitored 
$operationName = "Microsoft.Network/routeTables/write"
$description = "Alert when a route table is created. Does not infer a route table is associated with a subnet."
$status = "Succeeded"

Write-Host ""
Write-Host "Creating Alert: $alertRuleName..."

CreateAlert -emailAddresses $emailAddresses -alertRuleName $alertRuleName -location $location -resourceGroup $resourceGroup `
            -targetResourceGroup $targetResourceGroup -operationName $operationName -description $description -status $status

Write-Host "Completed: $alertRuleName"

########################################################
# Delete Route Table
########################################################

$emailAddresses = $emailAddresses
$alertRuleName = "Delete Route Table"
$location = $location
$resourceGroup = $resourceGroupName #the resource group where the alert will reside
$targetResourceGroup = $resourceGroupName # the targeted resource group where the operation of choice will be monitored 
$operationName = "Microsoft.Network/routeTables/delete"
$description = "Alert when a route table is deleted."
$status = "Succeeded"

Write-Host ""
Write-Host "Creating Alert: $alertRuleName..."

CreateAlert -emailAddresses $emailAddresses -alertRuleName $alertRuleName -location $location -resourceGroup $resourceGroup `
            -targetResourceGroup $targetResourceGroup -operationName $operationName -description $description -status $status

Write-Host "Completed: $alertRuleName"

########################################################
# Create or Modify User Defined Routes
########################################################

$emailAddresses = $emailAddresses
$alertRuleName = "Create or Modify User Defined Routes"
$location = $location
$resourceGroup = $resourceGroupName #the resource group where the alert will reside
$targetResourceGroup = $resourceGroupName # the targeted resource group where the operation of choice will be monitored 
$operationName = "Microsoft.Network/routeTables/routes/write"
$description = "Alert when a route in a route table is created or modified."
$status = "Succeeded"

Write-Host ""
Write-Host "Creating Alert: $alertRuleName..."

CreateAlert -emailAddresses $emailAddresses -alertRuleName $alertRuleName -location $location -resourceGroup $resourceGroup `
            -targetResourceGroup $targetResourceGroup -operationName $operationName -description $description -status $status

Write-Host "Completed: $alertRuleName"

########################################################
# Delete User Defined Route
########################################################

$emailAddresses = $emailAddresses
$alertRuleName = "Delete User Defined Route"
$location = $location
$resourceGroup = $resourceGroupName #the resource group where the alert will reside
$targetResourceGroup = $resourceGroupName # the targeted resource group where the operation of choice will be monitored 
$operationName = "Microsoft.Network/routeTables/routes/delete"
$description = "Alert when a user defined route is deleted."
$status = "Accept"

Write-Host ""
Write-Host "Creating Alert: $alertRuleName..."

CreateAlert -emailAddresses $emailAddresses -alertRuleName $alertRuleName -location $location -resourceGroup $resourceGroup `
            -targetResourceGroup $targetResourceGroup -operationName $operationName -description $description -status $status

Write-Host "Completed: $alertRuleName"

########################################################
# Create Network Security Group
########################################################

$emailAddresses = $emailAddresses
$alertRuleName = "Create Network Security Group"
$location = $location
$resourceGroup = $resourceGroupName #the resource group where the alert will reside
$targetResourceGroup = $resourceGroupName # the targeted resource group where the operation of choice will be monitored 
$operationName = "Microsoft.Network/networkSecurityGroups/write"
$description = "Alert when a network security group is created. Does not infer a network security group is associated with a subnet."
$status = "Succeeded"

Write-Host ""
Write-Host "Creating Alert: $alertRuleName..."

CreateAlert -emailAddresses $emailAddresses -alertRuleName $alertRuleName -location $location -resourceGroup $resourceGroup `
            -targetResourceGroup $targetResourceGroup -operationName $operationName -description $description -status $status

Write-Host "Completed: $alertRuleName"

########################################################
# Delete Network Security Group
########################################################

$emailAddresses = $emailAddresses
$alertRuleName = "Delete Network Security Group"
$location = $location
$resourceGroup = $resourceGroupName #the resource group where the alert will reside
$targetResourceGroup = $resourceGroupName # the targeted resource group where the operation of choice will be monitored 
$operationName = "Microsoft.Network/networkSecurityGroups/delete"
$description = "Alert when a network security group is deleted."
$status = "Succeeded"

Write-Host ""
Write-Host "Creating Alert: $alertRuleName..."

CreateAlert -emailAddresses $emailAddresses -alertRuleName $alertRuleName -location $location -resourceGroup $resourceGroup `
            -targetResourceGroup $targetResourceGroup -operationName $operationName -description $description -status $status

Write-Host "Completed: $alertRuleName"

########################################################
# Create or Modify NSG Rules
########################################################

$emailAddresses = $emailAddresses
$alertRuleName = "Create or Modify NSG Rules"
$location = $location
$resourceGroup = $resourceGroupName #the resource group where the alert will reside
$targetResourceGroup = $resourceGroupName # the targeted resource group where the operation of choice will be monitored 
$operationName = "Microsoft.Network/networkSecurityGroups/securityRules/write"
$description = "Alert when a rule in an NSG is created or modified."
$status = "Succeeded"

Write-Host ""
Write-Host "Creating Alert: $alertRuleName..."

CreateAlert -emailAddresses $emailAddresses -alertRuleName $alertRuleName -location $location -resourceGroup $resourceGroup `
            -targetResourceGroup $targetResourceGroup -operationName $operationName -description $description -status $status

Write-Host "Completed: $alertRuleName"

########################################################
# Delete NSG Rules
########################################################

$emailAddresses = $emailAddresses
$alertRuleName = "Delete NSG Rules"
$location = $location
$resourceGroup = $resourceGroupName #the resource group where the alert will reside
$targetResourceGroup = $resourceGroupName # the targeted resource group where the operation of choice will be monitored 
$operationName = "Microsoft.Network/networkSecurityGroups/securityRules/delete"
$description = "Alert when a rule in an NSG is deleted."
$status = "Accept"

Write-Host ""
Write-Host "Creating Alert: $alertRuleName..."

CreateAlert -emailAddresses $emailAddresses -alertRuleName $alertRuleName -location $location -resourceGroup $resourceGroup `
            -targetResourceGroup $targetResourceGroup -operationName $operationName -description $description -status $status

Write-Host "Completed: $alertRuleName"
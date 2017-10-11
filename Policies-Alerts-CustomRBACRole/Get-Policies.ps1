#####
# This script outputs an Azure Resource Manager (ARM) Policy as JSON to the PowerShell console
# This script assumes that the Policy Assignment and the Policy Definition share the same name
#
# To view the names of all current Policy Assignments and Policy Definitions, leave the parameter
# $policyName blank or $null
#
# Run Login-AzureRmAccount before executing this script.
#####

param(
    [string] $subscriptionId,

    [Parameter(Mandatory=$false)] [string] $policyName
)

#Initializations
$ErrorActionPreference = 'Stop'
Select-AzureRmSubscription -SubscriptionId $subscriptionId | Out-Null
$scope = "/subscriptions/$subscriptionId"

# Get all policy definitions and policy assignments
$assignments = Get-AzureRmPolicyAssignment -Scope $scope
$definitions = Get-AzureRmPolicyDefinition

# Output policy definitions and policy assignments to console
Write-Host "`nNames of policy definitions in this subscription:`n--------------------`n"
foreach ($definition in $definitions) {
    Write-Host "$($definition.Name)"
}

Write-Host "`nNames of policy assignments applied at the 'Subscription' scope:`n--------------------`n"
foreach ($assignment in $assignments) {
    Write-Host "$($assignment.Name)"
}

if ( !([string]::IsNullOrEmpty($policyName)) ) {
    
    Write-Host "`n"

    try{

        # Get policy definition
        $policyDefinition = Get-AzureRmPolicyDefinition -Name $policyName

    }catch {
    
        $ErrorMessage = $_.Exception.Message
   
        Write-Host "Retrieving policy definition with name $policyName failed. Error message:" -BackgroundColor Black -ForegroundColor Red
        throw "$ErrorMessage"
    }

    # Convert the policy rule definition into JSON
    $jsonPolicy = ConvertTo-Json $policyDefinition.Properties.policyrule

    # Show policy
    Write-Host "ARM Policy, in JSON format:`n--------------------`n"
    $jsonPolicy

    # Get policy assignment at a SUBSCRIPTION scope
    # Note that a Policy Definition, without a corresponding Policy Assignment at some scope, will have no effect
    $policyAssignment = Get-AzureRmPolicyAssignment -Name $policyName -Scope $scope -ErrorAction SilentlyContinue

    if ($policyAssignment) {

        Write-Host "`nPolicy Assignment with name:'$policyName' was found, and is correctly applied at the subscription level for subscription ID:'$subscriptionId'" -BackgroundColor Black -ForegroundColor Green

    } else {
        Write-Host "`nWARNING: Policy Assignment with name:'$policyName' was NOT found at the subscription level for subscription ID:'$subscriptionId'"  -BackgroundColor Black -ForegroundColor Red
    }
}
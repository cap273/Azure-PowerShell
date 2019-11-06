<#
This script moves all resources from one resource group to another resource group.
Precondition: both resource groups exist in the same Azure subscription
Precondition: user has already authenticated to Azure AD and selected the appropriate subscription

Reference documentation: https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-move-resources
#>

param(
    $sourceRgName = 'Source-MLRG',
    $destRgName = 'Target-MLRG'
)

# Get all resources in source RG
$resources = Get-AzResource -ResourceGroupName $sourceRgName

# Build a array of strings, each string representing a resource ID
# Initialize array
$resourceIDs = New-Object System.String[] $resources.Length

#Loop through each instance of $resources and populate resource ID into $resourceIDs array
for ($i=0; $i -lt $resources.Length; $i++)
{
    $resourceIDs[$i] = $resources[$i].ResourceId
}

# Test move of resources
Move-AzResource -DestinationResourceGroupName $destRgName -ResourceId $resourceIDs
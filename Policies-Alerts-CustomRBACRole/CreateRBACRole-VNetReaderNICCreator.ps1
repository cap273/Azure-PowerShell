<#
.NAME
    CreateRBACRole-VNetReaderNICCreator

.PARAMETER roleName
    Name of the custom RBAC role. 

.PARAMETER roleDescription
    Description of the RBAC definition. This description will be viewable in the Azure portal when selecting the an RBAC
    role

.PARAMETER subscriptionIDsScope
    The subscriptions you want the RBAC role to be available. One or multiple subscriptions can leverage the same RBAC 
    definition. This script expects an array of strings to accomodate one or more subscriptions.

.NOTES
    This script will create an RBAC role that allows a user to view the virtual network and add NICs to the virtual network. 
    The RBAC role does not grant privileges to modify the virtual network other than consume an IP address when a NIC is 
    added to the virtual network. Additional information around RBAC roles can be found here:
    https://azure.microsoft.com/en-us/documentation/articles/role-based-access-control-manage-access-powershell/
    This script assumes you already authenticated to Azure via PowerShell.

    Author: Jason Beck
#>

############################################
# Parameters
############################################

param(
    [string] $roleName = "Network Reader and can add NICs",
    [string] $roleDescription = "User can view the virtual network and can add NICs",
    [string[]] $subscriptionIDsScope = @("subidhere")
)

############################################
# Region: Create RBAC Role Definition
############################################

# Get a role definition object as a framework object to base the custom RBAC definition on
$role = Get-AzureRmRoleDefinition "Network Contributor"
$role.Id = $null
$role.Name = $roleName
$role.Description = $roleDescription
$role.Actions.Clear()
$role.Actions.Add("Microsoft.Network/virtualNetworks/read")
$role.Actions.Add("Microsoft.Network/virtualNetworks/subnets/join/action")
$role.Actions.Add("Microsoft.Network/networkInterfaces/join/action")
$role.Actions.Add("Microsoft.Resources/subscriptions/resourceGroups/read")
$role.AssignableScopes.Clear()

# Adding subscriptions to scope
foreach( $subscriptionID in $subscriptionIDsScope)
{
    $role.AssignableScopes.Add("/subscriptions/" + $subscriptionIDsScope)
}

Write-Host "Creating RBAC role definition..."
try
{
    # create the role definition
    New-AzureRmRoleDefinition -Role $role
}
catch
{
    $ErrorMessage = $_.Exception.Message
    Write-Host "New Azure RBAC definition failed."
    Write-Host "Error message: $ErrorMessage"
}
#end region
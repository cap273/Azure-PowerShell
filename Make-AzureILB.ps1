<#

.NAME
	Make-AzureILB
	
.DESCRIPTION 
    Creates an Internal Load Balancer in Azure.

.PARAMETER subscriptionID
	The ID of the Azure subscription in which to deploy the ILB.

.PARAMETER resourceGroupName
	The name of the resource group in which to deploy the ILB.
   
.PARAMETER location
    The location of the Azure datacenter in which to deploy the ILB.
    E.g. "East US 2", "North Central US", "Southeast Asia"

.PARAMETER ilbName
	Name of the ILB to be deployed.

.PARAMETER ruleName
	The name of the load balancing rule to be configured on the ILB.
	
.PARAMETER vnetResourceGroupName
	The name of the resource group in which the Virtual Network (VNet), in which the ILB
    will be deployed, is located.

.PARAMETER vnetName
    The name of the Virtual Network (VNet) in which the ILB will be deployed.

.PARAMETER subnetName
    The name of the subnet in which the ILB will be deployed. This subnet must be in the VNet
    specified by the $vnetName parameter.

.PARAMETER ilbPort
    The TCP front end and back end port of the ILB.
    Note that this script does not configure the ILB for any NAT.
    For SQL Servers, port 1434 is normally used

.PARAMETER probePort
    The TCP probe port. For SQL Servers, port 59999 is normally used.

.PARAMETER nicNames
    An array of names of NICs to be load balanced by the ILB. These NICs must already exist.

.PARAMETER isLBforSQL
    A boolean. $true if this ILB is for a SQL Server AlwaysOn Availability Group, $false otherwise.
    If this Load Balancer will be used for a SQL Server AlwaysOn Availability Group, the
    load balacing rule will be configured with Floating IP (i.e. Direct Server Return).

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: June 14, 2016
#>

param(

    $subscriptionID,
    $resourceGroupName,
    $location,

    $ilbName,
    $ruleName,

    $vnetResourceGroupName,
    $vnetName,
    $subnetName,

    [int] $ilbPort = 1434,
    [int] $probePort = 59999,

    [string[]]
    $nicNames = @('nicname1',
                  'nicname2'),
    [boolean]
    $isLBforSQL = $false
)

##################################
# Initializations
##################################

$ErrorActionPreference = 'Stop'

Select-AzureRmSubscription -SubscriptionId $subscriptionID | Out-Null

$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $vnetResourceGroupName `
                                  -Name $vnetName

$subnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet `
                                                -Name $subnetName


##################################
# Main Body
##################################

$lbfe = New-AzureRmLoadBalancerFrontendIpConfig -Name "LB-Frontend" `
                                                -Subnet $subnet

# Create an address pool for load balanced servers (later we add addresses to that pool) 
$lbbepool= New-AzureRMLoadBalancerBackendAddressPoolConfig -Name "LB-Backend" 

# Create a Probe Configuration
$healthProbe = New-AzureRmLoadBalancerProbeConfig -Name "HealthProbe-TCP-$probePort"  `
                                                  -Protocol tcp `
                                                  -Port $probePort `
                                                  -IntervalInSeconds 15 `
                                                  -ProbeCount 2

# Create a load balancing rule. If this load balancing rule is for a SQL Server AlwaysOn
# Availability Group, enable Floating IP (i.e. direct server return)
if ($isLBforSQL) {
    $lbrule1 = New-AzureRmLoadBalancerRuleConfig -Name $ruleName `
                                                 -FrontendIpConfiguration $lbfe `
                                                 -BackendAddressPool $lbbepool `
                                                 -Protocol TCP `
                                                 -FrontendPort $ilbPort `
                                                 -BackendPort $ilbPort `
                                                 -Probe $healthProbe `
                                                 -EnableFloatingIP
} 
else {
    $lbrule1 = New-AzureRmLoadBalancerRuleConfig -Name $ruleName `
                                                 -FrontendIpConfiguration $lbfe `
                                                 -BackendAddressPool $lbbepool `
                                                 -Protocol TCP `
                                                 -FrontendPort $ilbPort `
                                                 -BackendPort $ilbPort `
                                                 -Probe $healthProbe
}

 # Create the load balancer resource with all the settings previously defined 
$lb = New-AzureRMLoadBalancer -ResourceGroupName $resourceGroupName `
                              -Name $ilbName `
                              -Location $location `
                              -FrontendIpConfiguration $lbfe `
                              -LoadBalancingRule $lbrule1 `
                              -BackendAddressPool $lbbepool `
                              -Probe $healthProbe

# After the DHCP server in Azure has automatically assigned the ILB a private IP address, set the allocation
# method of the ILB's private IP address to static
$lb = Get-AzureRmLoadBalancer -ResourceGroupName $resourceGroupName -Name $ilbName
$lb.FrontendIpConfigurations[0].PrivateIpAllocationMethod = "Static"
$lb | Set-AzureRmLoadBalancer


# Add to the pool of load balanced addresses.
# These nics was created beforehand and was associated to working servers.
for ($i=0; $i -lt ($nicNames | Measure).Count; $i++) {

    $nic = Get-AzureRMNetworkInterface -ResourceGroupName $resourceGroupName -Name $nicNames[$i]
    $nic.IpConfigurations[0].LoadBalancerBackendAddressPools.Add($lb.BackendAddressPools[0]); 
    $nic | Set-AzureRMNetworkInterface 
}

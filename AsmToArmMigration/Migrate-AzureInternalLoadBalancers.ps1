<#

.NAME
	Migrate-AzureInternalLoadBalancers
	
.DESCRIPTION 
    Creates a new load-balancer ARM resource for an implicit *internal* ASM load balancer for a particular cloud service.
    Additionally, create ARM load-balancer rules corresponding to each ASM load-balanced endpoint.

    Prerequisites for ASM to ARM migration: authenticate to Azure using both Add-AzureRmAccount, and Add-AzureAccount

.PARAMETER originalASMSubscriptionName
    The name of the Azure ASM subscription in which the original ASM load balancer is located.

.PARAMETER targetARMSubscriptionName
    The name of the Azure ARM subscription in which the target ARM load balancer will be located.

.PARAMETER asmCloudServiceName
    The globally-unique name of an ASM cloud service.

.PARAMETER targetResourceGroup
    The name of the resource group in which to place the new ARM load-balancer resource.
    If this resource group does not already exist, one will be created.

.PARAMETER location
    The Azure location (e.g. East US 2) in which the *target* ARM load-balancer resource will be located.

.PARAMETER vnetResourceGroupName
    The resource group name in which the target (and existing) Virtual Network is located.

.PARAMETER virtualNetworkName
    The name of the existing VNet in which the target ARM load-balancer will be located.

.PARAMETER subnetName
    The name of the existing subnet (that is part of the VNet specified by $virtualNetworkName) in which the 
    target ARM load-balancer will be located

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: January 30, 2018
    LEGAL DISCLAIMER:
        This script is not supported under any Microsoft standard program or service. This script is
        provided AS IS without warranty of any kind. Microsoft further disclaims all
        implied warranties including, without limitation, any implied warranties of mechantability or
        of fitness for a particular purpose. The entire risk arising out of the use of performance of
        this script and documentation remains with you. In no event shall Microsoft, its authors, or 
        anyone else involved in the creation, production, or delivery of this script be liable
        for any damages whatsoever (including, without limitation, damages for loss of
        business profits, business interruption, loss of business information, or other
        pecuniary loss) arising out of the use of or inability to use this script or docummentation, 
        even if Microsoft has been advised of the possibility of such damages.
#>

param(

    $originalASMSubscriptionName,
    $targetARMSubscriptionName,

    $asmCloudServiceName,

    $targetResourceGroup,
    $location,

    $vnetResourceGroupName,
    $virtualNetworkName,
    $subnetName

)

#######################################
# Select Subscriptions
#######################################

cls
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

# Explicitly import Azure modules
Import-Module Azure
Import-Module AzureRM.Profile
Import-Module AzureRM.Network


# Select Azure subscriptions (both ARM and ASM)
Select-AzureRmSubscription -SubscriptionName $targetARMSubscriptionName | Out-Null
Select-AzureSubscription -SubscriptionName $originalASMSubscriptionName | Out-Null

Start-Sleep -Seconds 5

#######################################
# Get ASM load balancer details
#######################################

Write-Host "Getting information on original ASM load-balancer..."

# Get the original ASM cloud service
$asmCloudService = Get-AzureService -ServiceName $asmCloudServiceName -ErrorAction SilentlyContinue
if ($asmCloudService -eq $null) {
    
    Write-Host "Unable to find cloud service [$asmCloudServiceName]." -BackgroundColor Black -ForegroundColor Red
    Exit -2

}

# Get the original implicit internal load balancer
$asmLoadBalancer = $asmCloudService | Get-AzureInternalLoadBalancer -ErrorAction SilentlyContinue
if ($asmLoadBalancer -eq $null) {
    
    Write-Host "Unable to find an implicit ASM load balancer in cloud service [$asmCloudServiceName]." -BackgroundColor Black -ForegroundColor Red
    Exit -2

}

# Get the list of VMs in this cloud service
$asmVms = Get-AzureVM -ServiceName $asmCloudServiceName
if ($asmVms -eq $null) {
    
    Write-Host "Unable to find any VMs (and therefore any load-balanced endpoints) in cloud service [$asmCloudServiceName]." -BackgroundColor Black -ForegroundColor Red
    Exit -2

}

#######################################
# Get ASM load balanced endpoint details
#######################################

# Initialize array of list of unique load-balanced sets names
$asmLoadBalancedSetsName = New-Object System.Collections.ArrayList

# Initialize array of list of unique load-balanced set objects
$asmLoadBalancedSetsObject = New-Object System.Collections.ArrayList

# For each VM in the Cloud Service, query that VMs load-balanced endpoints
foreach ($asmVm in $asmVms) {
    
    # Get this VM's load-balanced endpoints
    $thisVmLoadBalancedEndpoints = $asmVm | Get-AzureEndpoint | Where-Object {$_.LBSetName -ne $null}

    # Loop through every load-balanced endpoint in this VM
    foreach ($thisVmLoadBalancedEndpoint in $thisVmLoadBalancedEndpoints) {
        
        # Only consider this endpoint if it is part of a load-balanced set that has not been previously addressed
        if ( !($asmLoadBalancedSetsName.Contains($thisVmLoadBalancedEndpoint.LBSetName)) ) {
            
            # Add this new load-balanced set to the list of load balanced set names
            $asmLoadBalancedSetsName.Add($thisVmLoadBalancedEndpoint.LBSetName) | Out-Null

            # Populate all relevant info for this load balanced set, to then recreate as ARM load-balanced rule
            $asmLoadBalancedSetObject = New-Object PSObject -Property @{      
                                                        InternalLoadBalancerName = $thisVmLoadBalancedEndpoint.InternalLoadBalancerName
                                                        LBSetName                = $thisVmLoadBalancedEndpoint.LBSetName
                                                        LBRuleName               = $thisVmLoadBalancedEndpoint.Name          
                                                        FrontendPort             = $thisVmLoadBalancedEndpoint.Port
                                                        BackendPort              = $thisVmLoadBalancedEndpoint.LocalPort
                                                        Protocol                 = $thisVmLoadBalancedEndpoint.Protocol
                                                        IdleTimeoutInMinutes     = $thisVmLoadBalancedEndpoint.IdleTimeoutInMinutes 
                                                        EnableFloatingIP         = $thisVmLoadBalancedEndpoint.EnableDirectServerReturn
                                                        LoadDistribution         = $thisVmLoadBalancedEndpoint.LoadBalancerDistribution
                                                        ProbeProtocol            = $thisVmLoadBalancedEndpoint.ProbeProtocol
                                                        ProbePort                = $thisVmLoadBalancedEndpoint.ProbePort
                                                        ProbeIntervalInSeconds   = $thisVmLoadBalancedEndpoint.ProbeIntervalInSeconds
                                                        ProbeTimeoutInSeconds    = $thisVmLoadBalancedEndpoint.ProbeTimeoutInSeconds
                                                        ProbePath                = $thisVmLoadBalancedEndpoint.ProbePath         
                                                    }
                                                    
            # Add all relevant info for this load-balanced set to the array of PSObjects for all load-balanced sets    
            $asmLoadBalancedSetsObject.Add($asmLoadBalancedSetObject) | Out-Null
        }

        # If this endpoint is part of a load-balanced set that has already been addressed, double-check to ensure that the private port
        # (aka backend port) of this particular endpoint is the same as all other endpoints in this load-balanced set
        else{
            
            # Find index of this load-balanced set in the array $asmLoadBalancedSetsName (which should also match the index
            # of this load-balanced set in the array $asmLoadBalancedSetObject
            $j = $asmLoadBalancedSetsName.IndexOf($thisVmLoadBalancedEndpoint.LBSetName)

            # Verify that load-balanced set being referenced is indeed the intended one
            if ( $asmLoadBalancedSetObject[$j].LBSetName -ne $thisVmLoadBalancedEndpoint.LBSetName ) {
                throw "[Custom error message] Verifying that all endpoints in the same load-balanced set have the same backend (private) port failed. Indexing failure." 
            }

            # Verify that this endpoint contains the same private (backend) port as the previously-examined endpoint of this load-balanced set
            if ( $asmLoadBalancedSetObject[$j].BackendPort -ne $thisVmLoadBalancedEndpoint.LocalPort ) {

                Write-Host "Error: Mismatch in private (backend) ports in endpoints of the same load-balanced set. VM [$($asmVm.Name)] has 
                                an endpoint with backend port [$($thisVmLoadBalancedEndpoint.LocalPort)] while other VMs in this 
                                same load-balanced set have an endpoint with backend port [$($asmLoadBalancedSetObject[$j].BackendPort)]. 
                                This load balancer should be re-created in ARM manually." -BackgroundColor Black -ForegroundColor Red
                Exit -2
            }
        }
    }
}

# Check for how many Load Balanced sets
if ( ($asmLoadBalancedSetsName | Measure).Count -lt 1 ) {
    throw "[Custom error message] Creating the load balancer probe configuration failed. Unknown probe protocol." 
}


######################################
# Check target resource groups and networks
######################################

Write-Host "Checking target resource groups and networks..."

# Check that selected Virtual Network Resource Group exists in selected subscription.
$vnetResourceGroup = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -eq $vnetResourceGroupName}
if ($vnetResourceGroup -eq $null) {
    
    Write-Host "Unable to find resource group [$vnetResourceGroupName] for Virtual Network in subscription [$subscriptionName]." -BackgroundColor Black -ForegroundColor Red
    Exit -2

}

# Validate that the VNet already exists
$existingVnet = Get-AzureRmVirtualNetwork -ResourceGroupName $vnetResourceGroupName -Name $virtualNetworkName -ErrorAction SilentlyContinue
if ($existingVnet -eq $null) {

    Write-Host "A Virtual Network with the name [$virtualNetworkName] was not found in resource group [$vnetResourceGroupName]." -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# Validate that the subnet already exists
$existingSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $existingVnet -ErrorAction SilentlyContinue
if ($existingSubnet -eq $null) {

    Write-Host "A subnet with the name [$subnetName] was not found in the Virtual Network [$virtualNetworkName]." -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# Check that target resource group exists
$selectedResourceGroup = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -eq $targetResourceGroup}
if ($selectedResourceGroup -eq $null) 
{
    
    Write-Host "Unable to find resource group [$targetResourceGroup]."
    Write-Host "Creating resource group [$targetResourceGroup]..."

    try
    {
        New-AzureRmResourceGroup -Name $targetResourceGroup `
                                    -Location $location `
                                    | Out-Null
    } 
    
    catch
    {
        $ErrorMessage = $_.Exception.Message
    
        Write-Host "Creating a new resource group [$targetResourceGroup] failed with the following error message:" -BackgroundColor Black -ForegroundColor Red
        throw "$ErrorMessage"
    }
}


#######################################
# Create ARM load balancer
#######################################

Write-Host "Creating ARM load balancer..."

# Create internal frontend configuration
$frontend = New-AzureRmLoadBalancerFrontendIpConfig -Name "Frontend01" -Subnet $existingSubnet

# Create an (empty) backend address pool config
$backendAddressPool = New-AzureRmLoadBalancerBackendAddressPoolConfig -Name "BackendAddressPoolConfig01"

# Create probe for load balancer
# ASSUMPTION: existing ASM internal load balancers only have one probe. So simply take probe info from the first load balanced set
if ($asmLoadBalancedSetsObject[0].ProbeProtocol -eq "http") {
    
    # Include request path if the probe protocol is HTTP
    $probe = New-AzureRmLoadBalancerProbeConfig -Name "Probe01-$($asmLoadBalancedSetsObject[0].ProbeProtocol)-$($asmLoadBalancedSetsObject[0].ProbePort)" `
                                                -Protocol $asmLoadBalancedSetsObject[0].ProbeProtocol `
                                                -Port $asmLoadBalancedSetsObject[0].ProbePort `
                                                -IntervalInSeconds $asmLoadBalancedSetsObject[0].ProbeIntervalInSeconds `
                                                -ProbeCount ([math]::floor($asmLoadBalancedSetsObject[0].ProbeTimeoutInSeconds/$asmLoadBalancedSetsObject[0].ProbeIntervalInSeconds)) `
                                                -RequestPath $thisVmLoadBalancedEndpoint.ProbePath

} elseif ($asmLoadBalancedSetsObject[0].ProbeProtocol -eq "tcp") {
    
    # Do not include request path if the probe protocol is not HTTP
    $probe = New-AzureRmLoadBalancerProbeConfig -Name "Probe01-$($asmLoadBalancedSetsObject[0].ProbeProtocol)-$($asmLoadBalancedSetsObject[0].ProbePort)" `
                                                -Protocol $asmLoadBalancedSetsObject[0].ProbeProtocol `
                                                -Port $asmLoadBalancedSetsObject[0].ProbePort `
                                                -IntervalInSeconds $asmLoadBalancedSetsObject[0].ProbeIntervalInSeconds `
                                                -ProbeCount ([math]::floor($asmLoadBalancedSetsObject[0].ProbeTimeoutInSeconds/$asmLoadBalancedSetsObject[0].ProbeIntervalInSeconds))
}
else {

    throw "[Custom error message] Creating the load balancer probe configuration failed. Unknown probe protocol."

}

# Initialize array of list of ARM load balancer rule configs
$armLoadBalancerRuleConfigs = New-Object System.Collections.ArrayList

# Create load balancer rules, one for each load balancer set
for($i = 0; $i -lt ($asmLoadBalancedSetsName | Measure).Count; $i++) {
    
    # Create this rule config
    $thisLbRule = New-AzureRmLoadBalancerRuleConfig -Name $asmLoadBalancedSetsName[$i] `
                                                    -FrontendIpConfiguration $frontend `
                                                    -BackendAddressPool $backendAddressPool `
                                                    -Probe $probe `
                                                    -Protocol $asmLoadBalancedSetsObject[$i].Protocol `
                                                    -FrontendPort $asmLoadBalancedSetsObject[$i].FrontendPort `
                                                    -BackendPort $asmLoadBalancedSetsObject[$i].BackendPort


    # If an Idle Timeout is specified for this rule config, add it to the rule config object
    if ($asmLoadBalancedSetsObject[$i].IdleTimeoutInMinutes -ne $null) {
        $thisLbRule.IdleTimeoutInMinutes = $asmLoadBalancedSetsObject[$i].IdleTimeoutInMinute
    }

    # If a Load Distribution is specified for this rule config, add it to the rule config object
    if ($asmLoadBalancedSetsObject[$i].LoadDistribution -ne $null) {
        $thisLbRule.LoadDistribution = $asmLoadBalancedSetsObject[$i].LoadDistribution
    }

    # If Direct Server return is specified for this rule config, add it to the rule config object
    if ($asmLoadBalancedSetsObject[$i].EnableFloatingIP) {
        $thisLbRule.EnableFloatingIP = $true
    }


    # Add this Lb rule to complete list of all rule configs to be associated with this load balancer
    $armLoadBalancerRuleConfigs.Add($thisLbRule) | Out-Null
}


# Create the load balancer, initially only with the first load balancer rule config
New-AzureRmLoadBalancer -ResourceGroupName $targetResourceGroup `
                                           -Name $asmLoadBalancer.InternalLoadBalancerName `
                                           -Location $location `
                                           -Sku Basic `
                                           -FrontendIpConfiguration $frontend `
                                           -BackendAddressPool $backendAddressPool `
                                           -Probe $probe `
                                           -LoadBalancingRule $armLoadBalancerRuleConfigs[0] | Out-Null

Write-Host "Adding additional configurations to ARM load-balancer..."

$armLoadBalancer = Get-AzureRmLoadBalancer -ResourceGroupName $targetResourceGroup `
                                           -Name $asmLoadBalancer.InternalLoadBalancerName


# After the DHCP server in Azure has automatically assigned the ILB a private IP address, set the allocation
# method of the ILB's private IP address to static
$armLoadBalancer.FrontendIpConfigurations[0].PrivateIpAllocationMethod = "Static"


# If there were more than 1 load balanced rule config, add them to the load balancer object
for($i = 1; $i -lt ($asmLoadBalancedSetsName | Measure).Count; $i++) {
    
    $armLoadBalancer.LoadBalancingRules.Add($armLoadBalancerRuleConfigs[$i])
    
}


# Save load balancer changes to Azure
$armLoadBalancer | Set-AzureRmLoadBalancer | Out-Null


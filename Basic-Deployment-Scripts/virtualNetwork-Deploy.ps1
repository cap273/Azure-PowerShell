<#

.NAME
	virtualNetwork-Deploy
	
.DESCRIPTION 
    Leverages the ARM Template file titled "virtualNetwork-Template.json" to deploy a Virtual Network in Azure.

    This script also points the Virtual Network to a primary (and optionally a secondary) DNS server.
    Additionally, this script creates any number of user-specified subnets. 
    Optionally, this script also creates a Virtual Network Gateway for ExpressRoute.

.PARAMETER subscriptionName
	Name of the subscription in which to deploy the ARM template.

.PARAMETER resourceGroupName
    Name of the resource group in which to deploy the ARM template.

.PARAMETER deploymentName
    Name of the ARM template deployment. This name is only useful for debugging purposes, and can be set to anything.

.PARAMETER location
    The location in which to deploy this storage account.

.PARAMETER templateFilePath
    The path of the ARM template file (e.g. "C:\Users\testuser\Desktop\virtualNetwork-Template.json"

.PARAMETER vnetAddressSpaces
    The IP address space for the subnet to be used for a Virtual Network, in CIDR notation (e.g. 10.0.0.0/8).

.PARAMETER dnsServers
    An array containing the IP addresses of the DNS servers to be used. Maximum number of DNS servers in a single VNet: 9
    If no IP addresses are specified, Azure-provided DNS service will be used by default.

.PARAMETER subnets
    A hashtable containing the names of the subnets to be created, and their respective address spaces, in CIDR form (e.g. 10.0.0.0/24).
    This parameter is intended to EXCLUDE any subnet to be used for a VNet Gateway.
        The Name of the subnet is subject to the following requirements:
            - Up to 80 characters long. 
            - It must begin with a word character
            - It must end with a word character or with '_'.
            - May contain word characters or '.', '-', '_'.

.PARAMETER virtualNetworkTags
    A hashtable specifying the key-value tags to be associated with this Azure resource.
    The creation date of this resource is already automatically added as a tag.

.PARAMETER createVnetGateway
    Boolean parameter. If $true, a Virtual Network Gateway for ExpressRoute will be created using user-specified parameters.

.PARAMETER vnetGatewaySubnetSpace
    The IP address space for the subnet to be used for a Virtual Network Gateway, in CIDR notation (e.g. 192.168.200.0/26).
    The minimum size of a subnet for an ExpressRoute gateway is /28 (although a /27 is required for an ExpressRoute & Site-to-SiteVPN coexistence)
    See: https://azure.microsoft.com/en-us/documentation/articles/expressroute-howto-add-gateway-resource-manager/

.NOTES

    AUTHOR: Carlos Patiño
    LASTEDIT: September 26, 2017
#>

param (
    
    #######################################
    # Azure and ARM template parameters
    #######################################
    [string] $subscriptionName = 'Visual Studio Enterprise with MSDN',
    [string] $resourceGroupName = 'RG-Networking',
    
    [ValidateSet("Central US", "East US", "East US 2", "West US", "North Central US", "South Central US", "West Central US", "West US 2")]
    [string]$location = 'West Europe',
    
    [string] $deploymentName = 'VNet-Deployment',
    [string] $templateFilePath = "C:\Users\carpat\OneDrive - Microsoft\Azure-PowerShell\Basic-Deployment-Scripts\virtualNetwork-Template.json",

    #######################################
    # Virtual Network parameters
    #######################################
    [string] $virtualNetworkName = 'Personal-Network-WestEurope',
    [string] $vnetAddressSpaces = '10.10.0.0/16',

    [Parameter(Mandatory=$false)]
    [string[]] $dnsServers,

    [hashtable] $subnets = @{"default" = '10.10.0.0/16'},

    [hashtable] $virtualNetworkTags = @{"Department" = "TestDepartment3";"Owner" = "TestOwner"},

    #######################################
    # Virtual Network Gateway parameters for EXPRESSROUTE ONLY - VPN *NOT* CURRENTLY SUPPORTED
    #######################################

    [bool] $createVnetGateway = $false,

    [string] $vnetGatewaySubnetSpace = '10.80.2.0/27',
    [string] $GatewayName = "VN-Gateway",
    [string] $GatewayIPName = "VN-Gateway-PIP",
    [string] $GatewayIPConfigName = "VN-Gatewa-IP-Config-01",

    # 'Basic' gateway SKU is not supported for ExpressRoute
    [ValidateSet("Standard", "HighPerformance", "UltraPerformance")]
    [string] $gatewaySku = 'Standard'
)





###################################################
# region: PowerShell and Azure Dependency Checks
###################################################
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
$ErrorActionPreference = 'Stop'

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
$modlist = Get-Module -ListAvailable -Name 'AzureRM.Resources'
if (($modlist -eq $null) -or ($modlist.Version.Major -lt 4)){
    Write-Host "Please install the Azure Powershell module, version 4.0.0 (released May 2017) or above." -BackgroundColor Black -ForegroundColor Red
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
#end region



###################################################
# region: User input validation
###################################################

Write-Host "Checking parameter inputs..."

# Check that template file path is valid
if (!(Test-Path -Path $templateFilePath)) {
    
    Write-Host "The path for the ARM Template file is not valid. Please verify the path." -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# Check that selected Azure subscription exists.
$selectedSubscription = $subscriptionList | Where-Object {$_.Name -eq $subscriptionName}
if ($selectedSubscription -eq $null) {
    
    Write-Host "Unable to find subscription name $subscriptionName." -BackgroundColor Black -ForegroundColor Red
    Exit -2

} else {

    Select-AzureRmSubscription -SubscriptionName $subscriptionName | Out-Null
}
$subscriptionID = $selectedSubscription.SubscriptionId

# Check that selected Resource Group exists in selected subscription.
$selectedResourceGroup = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -eq $resourceGroupName}
if ($selectedResourceGroup -eq $null) {
    
    Write-Host "Unable to find specified resource group. Resource group name: $resourceGroupName. Subscription  name: $subscriptionName."
    Write-Host "Creating resource group..."

    try{

        New-AzureRmResourceGroup -Name $resourceGroupName `
                                 -Location $location `
                                  | Out-Null
    } catch{

        $ErrorMessage = $_.Exception.Message
    

        Write-Host "Creating a new resource group failed with the following error message:" -BackgroundColor Black -ForegroundColor Red
        throw "$ErrorMessage"
    }

}

#Check the name of the Virtual Network to deploy
If ($virtualNetworkName -like "* *"){
    
    Write-Host "The name of the Virtual Network cannot contain a space." -BackgroundColor Black -ForegroundColor Red
    Exit -2
}

# Validate that none of the subnets to be created which were specified with a custom name contain the reserved name 'GatewaySubnet'
# Iterate through each subnet to be created
foreach ($subnetRow in $subnets.GetEnumerator()) {
    
    if ($subnetRow.Name -eq "GatewaySubnet") {

        Write-Host "Do not specify the name and address space of the Gateway Subet in the `$subnets parameter." -BackgroundColor Black -ForegroundColor Red
        Write-Host "Instead, please simply specify the IP address space of the desired Gateway Subnet in the parameter `$vnetGatewaySubnetSpace." -BackgroundColor Black -ForegroundColor Red

        Exit -2
    }

}

# Validate that the VNet to be created does not exist yet
$existingVnet = Get-AzureRmVirtualNetwork -ResourceGroupName $resourceGroupName -Name $virtualNetworkName -ErrorAction SilentlyContinue
if ($existingVnet) {

    Write-Host "A Virtual Network with the name $virtualNetworkName already exists in resource group $resourceGroupName." -BackgroundColor Black -ForegroundColor Red

    Exit -2
}


# Get the date in which this deployment is being executed, and add it as a Tag
$creation = Get-Date -Format MM-dd-yyyy
$creationDate = $creation.ToString()
$virtualNetworkTags.Add("CreationDate", $creationDate)
#end region




###################################################
# region: Deploy ARM Template
###################################################

Write-Host "Deploying ARM Template..."

try{
    New-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroupName `
                                       -Name $deploymentName `
                                       -Mode Incremental `
                                       -TemplateFile $templateFilePath `
                                       -location $location `
                                       -virtualNetworkName $virtualNetworkName `
                                       -vNetAddressSpaces $vnetAddressSpaces `
                                       -virtualNetworkTags $virtualNetworkTags `
                                       | Out-Null
                                       

    Write-Host "ARM Template deployment $deploymentName finished successfully."

}
catch {
    
    $ErrorMessage = $_.Exception.Message
    

    Write-Host "ARM Template deployment $deploymentName failed with the following error message:" -BackgroundColor Black -ForegroundColor Red
    throw "$ErrorMessage"

}
#end region




###################################################
# region: Create subnets and add secondary DNS server
###################################################
# The creation of subnets is significantly more flexible
# (in particular with regards to the number of subnets to be created)
# if performed with PowerShell rather than with ARM templates

Write-Host "Creating subnets in Virtual Network $virtualNetworkName..."

# Get the object of the VNet that was just created
$vNet = Get-AzureRmVirtualNetwork -ResourceGroupName $resourceGroupName -Name $virtualNetworkName 

# Iterate through each subnet to be created
foreach ($subnetRow in $subnets.GetEnumerator()) {
    
    # Add the subnet to the VNet object
    Add-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vNet `
                                          -Name $subnetRow.Name `
                                          -AddressPrefix $subnetRow.Value `
                                          | Out-Null

}


# If the user has defined a DNS servers, add them to VNet config
if ($dnsServers.Count -gt 0) {
    $vnet.DhcpOptions = @{dnsServers = @()}
}
foreach ($dnsIP in $dnsServers)  {

    Write-Host "Adding DNS server to VNet with IP address $dnsIP..."
    $vnet.DhcpOptions.DnsServers.Add($dnsIP);
}

# Save the changes on Azure
Set-AzureRmVirtualNetwork -VirtualNetwork $vNet | Out-Null
#end region


###################################################
# region: Create Virtual Network (VNet) Gateway for ExpressRoute
###################################################
# Following documentation: https://azure.microsoft.com/en-us/documentation/articles/expressroute-howto-add-gateway-resource-manager/

# Define function for creating a VNet Gateway, in case retry logic is necessary
Function Make-VNetGateway {
    param(
        $resourceGroupName,
        $virtualNetworkName,
        $vnetGatewaySubnetSpace,
        $GatewayIPName,
        $GatewayIPConfigName,
        $GatewayName,
        $gatewaySku,
        $location
    )

    Write-Host "Creating Virtual Network Gateway, type 'ExpressRoute', and Sku $gatewaySku..."
    Write-Host "This operation may take up to 40 minutes..."
    Write-Host "Creating gateway subnet..."

    # Get the object of the VNet again
    $vNet = Get-AzureRmVirtualNetwork -ResourceGroupName $resourceGroupName -Name $virtualNetworkName

    # Add a new subnet for the Gateway
    # Note the following restrictions:
    # - The name of the Gateway subnet must be 'GatewaySubnet'
    # - The minimum size of a subnet for an ExpressRoute gateway is /28 (although a /27 is required for an ExpressRoute & Site-to-SiteVPN coexistence)
    Add-AzureRmVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -VirtualNetwork $vnet -AddressPrefix $vnetGatewaySubnetSpace -ErrorAction SilentlyContinue | Out-Null

    # Save subnet changes to Azure
    Set-AzureRmVirtualNetwork -VirtualNetwork $vnet | Out-Null

    # Get gateway subnet
    $gatewaySubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -VirtualNetwork $vnet

    Write-Host "Creating public IP address for the gateway..."

    # Request a public IP address for the gateway
    # The IP address must be dynamically allocated
    $pip = New-AzureRmPublicIpAddress -Name $GatewayIPName `
                                      -ResourceGroupName $resourceGroupName `
                                      -Location $location `
                                      -AllocationMethod Dynamic `
                                      -WarningAction SilentlyContinue `
                                      -Force

    Write-Host "Creating IP configuration for gateway..."

    # Create the gateway configuration, which specifies public IP and subnet to use
    $GatewayIPConfig = New-AzureRmVirtualNetworkGatewayIpConfig -Name $GatewayIPConfigName -Subnet $gatewaySubnet -PublicIpAddress $pip

    Write-Host "Creating VNet gateway...."

    # Create the gateway
    New-AzureRmVirtualNetworkGateway -Name $GatewayName `
                                        -ResourceGroupName $resourceGroupName `
                                        -Location $location `
                                        -IpConfigurations $GatewayIPConfig `
                                        -GatewayType ExpressRoute `
                                        -GatewaySku $gatewaySku `
                                        -WarningAction SilentlyContinue `
                                        | Out-Null
}

# If the user has selected for a VNet Gateway to be created
if ($createVnetGateway) {
    
    # Initialize retry counter limit
    $retryLimit = 2

    # Initialize current number of retries
    $retry = 0

    # Initialize while-loop condition
    $inProgress = $true

    while ($inProgress) {
        
        # Attempt to create VNet Gateway
        try{
        
            Make-VNetGateway -resourceGroupName $resourceGroupName `
                             -virtualNetworkName $virtualNetworkName `
                             -vnetGatewaySubnetSpace $vnetGatewaySubnetSpace `
                             -GatewayIPName $GatewayIPName `
                             -GatewayIPConfigName $GatewayIPConfigName `
                             -GatewayName $GatewayName `
                             -gatewaySku $gatewaySku `
                             -location $location

            # If making a VNet Gateway did not return any errors, signal the while loop to finish
            Write-Host "VNet Gateway creation finished successfully."
            $inProgress = $false

        } catch {

            # If there was an error during the VNet Gateway creation, update retry counter
            $retry++

            # If the retry counter does not exceed retry limit, retry VNet Gateway creation. Otherwise, throw an error.
            if ($retry -le $retryLimit) {

                Write-Host "VNet Gateway creation failed. Retrying... Current retry: $retry. Retry limit: $retryLimit"
                Continue

            } else {
                $ErrorMessage = $_.Exception.Message
   
                Write-Host "Creating Virtual Network Gateway failed with the following error messaage:" -BackgroundColor Black -ForegroundColor Red
                throw "$ErrorMessage"
            }
        }
    } 
 }
#end region

Write-Host "Virtual Network deployment has finished successfully."
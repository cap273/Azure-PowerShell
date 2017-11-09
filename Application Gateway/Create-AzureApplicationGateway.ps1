param(
    
    $location,

    $appGwResourceGroupName,
    $appGwName,

    $vnetResourceGroupName,
    $vnetName,
    $subnetName,

    $publicIpResourceGroupName,
    $publicIpName
)

$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $vnetResourceGroupName `
                                  -Name $vnetName

# Find index for desired subnet in VNet object
$subnetIndex = 0
foreach ($subnetTemp in $vnet.Subnets) {
    
    if ($subnetTemp.Name -eq $subnetName) {

        # End search for index for desired HTTP Listener
        break
    }

    # Update HTTP index
    $subnetIndex++
}

# Retrieve the newly created subnet
$subnet=$vnet.Subnets[$subnetIndex]

$publicIp = Get-AzureRmPublicIpAddress -ResourceGroupName $publicIpResourceGroupName `
                                       -Name $publicIpName


# Create a gateway IP configuration. The gateway picks up an IP addressfrom the configured subnet and 
# routes network traffic to the IP addresses in the backend IP pool. Keep in mind that each instance takes one IP address.
$gipconfig = New-AzureRmApplicationGatewayIPConfiguration -Name "AppGatewayIPConfig-Prod" -Subnet $subnet

# Configure a frontend port that is used to connect to the application gateway through the public IP address
$fp443 = New-AzureRmApplicationGatewayFrontendPort -Name "FrontEndPort-AllSSL-Prod"  -Port 443

# Configure a frontend port that is used to connect to the application gateway through the public IP address
$fp80 = New-AzureRmApplicationGatewayFrontendPort -Name "FrontEndPort-HTTP-Prod"  -Port 80

# Configure the frontend IP configuration with the public IP address retrieved earlier
$fipconfig = New-AzureRmApplicationGatewayFrontendIPConfig -Name "Public-FrontendIPConfig" -PublicIPAddress $publicIp

# Configure the SKU for the application gateway, this determines the size and whether or not WAF is used.
$sku = New-AzureRmApplicationGatewaySku -Name WAF_Medium -Tier WAF -Capacity 1

###################################
# DUMMY RESOURCES
##################################

# Configure a backend pool with the addresses of your web servers. These backend pool members are all validated to be healthy by probes, whether they are basic probes or custom probes.  Traffic is then routed to them when requests come into the application gateway. Backend pools can be used by multiple rules within the application gateway, which means one backend pool could be used for multiple web applications that reside on the same host.
$pool = New-AzureRmApplicationGatewayBackendAddressPool -Name "dummy-pool" -BackendIPAddresses 10.110.0.0

# Configure backend http settings to determine the protocol and port that is used when sending traffic to the backend servers. Cookie-based sessions are also determined by the backend HTTP settings.  If enabled, cookie-based session affinity sends traffic to the same backend as previous requests for each packet.
$poolSetting = New-AzureRmApplicationGatewayBackendHttpSettings -Name "dummy-httpsetting" -Port 80 -Protocol Http -CookieBasedAffinity Disabled -RequestTimeout 120

# Configure the listener.  The listener is a combination of the front end IP configuration, protocol, and port and is used to receive incoming network traffic. 
$listener = New-AzureRmApplicationGatewayHttpListener -Name "dummy-listener" -Protocol Http -FrontendIPConfiguration $fipconfig -FrontendPort $fp80

# Configure a basic rule that is used to route traffic to the backend servers. The backend pool settings, listener, and backend pool created in the previous steps make up the rule. Based on the criteria defined traffic is routed to the appropriate backend.
$rule = New-AzureRmApplicationGatewayRequestRoutingRule -Name "dummy-rule" -RuleType Basic -BackendHttpSettings $poolSetting -HttpListener $listener -BackendAddressPool $pool


###################################
# END OF DUMMY RESOURCES
##################################

# Create the application gateway
$appGw = New-AzureRmApplicationGateway -ResourceGroupName $appGwResourceGroupName `
                                       -Name $appGwName `
                                       -Location $location `
                                       -FrontendIpConfigurations $fipconfig `
                                       -GatewayIpConfigurations $gipconfig `
                                       -FrontendPorts $fp443,$fp80 `
                                       -Sku $sku `
                                       -BackendAddressPools $pool `
                                       -BackendHttpSettingsCollection $poolSetting `
                                       -HttpListeners $listener `
                                       -RequestRoutingRules $rule

###################################
# REMOVING DUMMY RESOURCES
##################################

Get-AzureRmApplicationGateway -ResourceGroupName $appGwResourceGroupName -Name $appGwName

Remove-AzureRmApplicationGatewayBackendAddressPool -ApplicationGateway $appGw -Name "dummy-pool"
Remove-AzureRmApplicationGatewayBackendHttpSettings -ApplicationGateway $appGw -Name "dummy-httpsetting"
Remove-AzureRmApplicationGatewayHttpListener -ApplicationGateway $appGw -Name "dummy-listener"
Remove-AzureRmApplicationGatewayRequestRoutingRule -ApplicationGateway $appGw -Name "dummy-rule"

Set-AzureRmApplicationGateway -ApplicationGateway $appGw


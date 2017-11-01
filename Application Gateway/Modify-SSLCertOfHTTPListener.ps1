param(
    
    $subscriptionId = "sub id here",
    
    $applicationGatewayRG = "RG-Networking",

    $applicationGatewayName = "AppGateway-Hub-Prod",

    # Name of HTTP listener to associate SSL certificate
    $httpListenerName = "listener name here",

    # Name of the desired SSL certificate to associate with HTTP listener
    $sslCertificateName = "ssl cert name here"

)

$ErrorActionPreference = 'Stop'

Select-AzureRmSubscription -SubscriptionId $subscriptionId | Out-Null

$appGw = Get-AzureRmApplicationGateway -ResourceGroupName $applicationGatewayRG `
                                       -Name $applicationGatewayName


# Find index for desired HTTP listener in Application Gateway object
$httpIndex = 0
foreach ($httpListener in $appGw.HttpListeners) {
    
    if ($httpListener.Name -eq $httpListenerName) {

        # Verify that this is an HTTP listener that uses 'HTTPS' protocol. If not, throw error.
        if ($httpListener.Protocol -ne "HTTPS") {
            throw "Error: this HTTP Listener is not associated with HTTPS protocol, and therefore cannot be associated with SSL Cert."
        }

        # End search for index for desired HTTP Listener
        break
    }

    # Update HTTP index
    $httpIndex++
}

# Find SSL certificate
$sslCert = Get-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $appGw `
                                                       -Name $sslCertificateName


###################
# Actually modify HTTP Listener of Application Gateway object to associate it with new SSL Certificate
# Save changes to Application Gateway object to Azure
###################
$appGw.HttpListeners[$httpIndex].SslCertificate.Id = $sslCert.Id
Set-AzureRmApplicationGateway -ApplicationGateway $appGw

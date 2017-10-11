###############
# PARAMETER INPUTS
##############

$subscriptionName = "mySubscriptionName"
$rgName = "myResourceGroupName"
$appGWName = "myAppGatewayName"

$frontendCertificateName = 'Certificate01'
$frontendCertificateFilePath = "C:\Downloads\Certificate.pfx" # file type: .pfx
$frontendCertificatePassword = "Password123$"


$backendAuthorizationCertificate = 'WhitelistBackendCertificate01'
$backendAuthorizationCertificateFilePath = "C:\Downloads\Certificate.cer" # file type: base 64 encoded .cer

###############
# END OF PARAMETER INPUTS
##############


Select-AzureRmSubscription -SubscriptionName $subscriptionName | Out-Null

$appGW = Get-AzureRmApplicationGateway -ResourceGroupName $rgName -Name $appGWName
$cert1 = Add-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $appGW `
                    -Name $frontendCertificateName `
                    -CertificateFile $frontendCertificateFilePath `
                    -Password $frontendCertificatePassword

$authcert1 = Add-AzureRmApplicationGatewayAuthenticationCertificate -ApplicationGateway $appGW `
                    -Name $backendAuthorizationCertificate -CertificateFile $backendAuthorizationCertificateFilePath

Set-AzureRmApplicationGateway -ApplicationGateway $appGW




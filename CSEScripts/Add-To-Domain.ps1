param(
	$domain,
	$domainUsername,
	$domainPassword
)

$secpasswd = ConvertTo-SecureString 'testpassword' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ('charliedomain\admin', $secpasswd)

Add-Computer -DomainName 'charliedomain.local' `
             -Credential $cred `
             -Force

Ipconfig /release

Ipconfig /renew

Ipconfig /flushdns

Restart-Computer -Force

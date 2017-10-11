param(

    $svcAcctUserName,
    $passwd

)

$secpasswd = ConvertTo-SecureString $passwd -AsPlainText -Force

$cred = New-Object System.Management.Automation.PSCredential ($svcAcctUserName, $secpasswd)

Add-Computer -DomainName 'contoso.com' `
             -Credential $cred `
             -Force

Ipconfig /release

Ipconfig /renew

Ipconfig /flushdns

Restart-Computer -Force
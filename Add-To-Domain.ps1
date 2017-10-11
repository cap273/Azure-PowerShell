$secpasswd = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ('CLOUD\userid', $secpasswd)

Add-Computer -DomainName 'domain.com' `
             -Credential $cred `
             -Force

Ipconfig /release
Wait 2

Ipconfig /renew
Wait 2

Ipconfig /flushdns
Wait 2

$computerName = $env:computername
([ADSI]"WinNT://$computerName/Administrators,group").Add("WinNT://domain/user one") 
([ADSI]"WinNT://$computerName/Administrators,group").Add("WinNT://domain/user two") 

Restart-Computer -Force

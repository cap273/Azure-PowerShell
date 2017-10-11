$computerName = $env:computername
([ADSI]"WinNT://$computerName/Administrators,group").Add("WinNT://root/name 0") 
([ADSI]"WinNT://$computerName/Administrators,group").Add("WinNT://root/name one") 
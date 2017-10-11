$secpasswd = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ('svcacctcldad', $secpasswd)

Remove-Computer $cred `
             -Force

if ((gwmi win32_computersystem).partofdomain -eq $true) {
    write-host "I am domain joined!"
} else {
    write-host "Ooops, workgroup!"
}
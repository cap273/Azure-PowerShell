<#

.NAME
    MasterScript-Install-SQL-Server

.DESCRIPTION
    Remotely executes a number of PowerShell scripts on a specified target VM to configure and install SQL Server.

    PREREQUISITES: The following PowerShell scripts must exist in the same folder as MasterScript-Install-SQL-Server.ps1:
        - Pre-SQL-Installation-Config.ps1
        - Install-SQLServer.psq1
        - Post-SQL-Installation-Config.ps1

    See the individual PowerShell scripts listed above for detailed documentation.

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: April 26, 2016
#>

param (

    # FQDN of target VM
    $vm,

    #######################################
    <# Pre-SQL-Installation-Config.ps1 parameters #>
    #######################################
    [String] $DotNet35SourcePath = "\\testVM.com\Source\dotnet35source\sxs\",
    [int] $SQLServerPort = 14481,
    [int] $SQLListenerPort = 14482,
    [int] $ILBProbePort = 59999,


    #######################################
    <# Install-SQLServer.ps1 parameters #>
    #######################################

    [String] $sqlInstallationPath = "\\testVM.com\Source\SQLServer2014SP1\Setup.exe",
    [string] $LocalAdmin,
    [String] $sqlServerSAPwd, # Password for the SQL sa account for SQL authentication

    <# Array of Windows user accounts or Windows group accounts that will be added as sysadmins 
        of SQL Server instance #>  
    [string[]]
    $sqlAdminsArray = @("domain\user 1",
                        "domain\user 2"),

    [int] $sizeTempDBDataFileMB = 5000,
    [int] $autogrowTempDBinMB = 500,

    <# Boolean to indicate whether to use Local service accounts (e.g. NT Service\MSSQLSERVER) 
        or Domain service accounts (e.g. MyCompanyDomain\SqlServiceAccount) for SQL Server and SQL Agent #>  
    [bool]
    $UseDefaultLocalServiceAccounts = $true,

    <# Parameters only applicable if using Domain Service Accounts for SQL Server and SQL Agent #>

    [String] $sqlServerSvcAcct = "CLOUD\SVCsqlserver", # SQL Server service account name
    [String] $sqlServerSvcAcctPwd = "testpassword", # SQL Server service account password
    [String] $sqlAgentSvcAcct = "CLOUD\SVCsqlagent", # SQL Agent service account name
    [String] $sqlAgentSvcAcctPwd = 'testpassword', # SQL Agent service account password


    #######################################
    <# Post-SQL-Installation-Config.ps1 parameters #>
    #######################################

     # Path of the T-SQL files
    [string] $tSQLPath = "C:\Users\myuser\Desktop\SQLScripts",

    [string] $SMTPServerName,
    [string] $OperatorEmailAddress,

    [string] $TargetDataFilesLocation = 'T:\TempDB\',
    [string] $TargetDataSizeMB = '10000MB',
    [string] $TargetDataFilegrowthMB = '5000MB',
    [string] $TargetTlogFilesLocation = 'J:\TempDBLog\',
    [string] $TargetTlogSizeMB = '5000MB',
    [string] $TargetTlogFilegrowthMB = '1000MB',

    [string] $storageAccountName = "azurestorageaccountname1",
    [string] $storageAccountKey
)

################################################
# Initializations
###############################################

$ErrorActionPreference = 'Stop'

# Prompt the user for a domain credential that will have access to all of the VMs
$cred = Get-Credential

echo "`n Processing $vm"


<#
Function to disable CredSSP authentication
This will be run either as a clean-up activity at the end of the script,
or will be run if any errors are thrown during the script execution.
#>
function Disable-CredSSP {
    
    param(
        [string] $vm,
        $cred
    )

    # Disable Util server as the CredSSP Client
    Write-Host "Disabling current VM as CredSSP client...."
    Disable-WSManCredSSP -Role Client

    # Disable the target VM as the CredSSP Server
    Write-Host "Disabling target VM as CredSSP server..."
    Invoke-Command -ComputerName $vm `
                   -Credential $cred `
                   -SessionOption (New-PSSessionOption -IdleTimeout 120000) `
                   -ScriptBlock { Disable-WSManCredSSP -Role Server }
}



################################################
# Connection settings and verifications
###############################################

# Testing WinRM service to target VM
try {
    
    Write-Host "Testing WinRM service on target VM..."
    Test-WSMan -ComputerName $vm | Out-Null

    Write-Host "Test successful: WinRM service is running on target VM"

} catch {

    $ErrorMessage = $_.Exception.Message
    

    Write-Host "Cannot verify that the WinRM service is running on target VM."
    Write-Host "Run the ""Enable-PSRemoting"" cmdlet on target VM to enture PowerShell remoting is enabled." 
    Write-Host "Cmdlet ""Test-WSMan"" failed with following error message:"
    throw "$ErrorMessage"

}

<#
Configuring current and target VM for CredSSP authentication

The SQL Server installation will retrieve the SQL Server installation bits from a remote file-share server
This will involve a double-hop authentication, which is by default not allowed using Kerberos authentication.
Use CredSSP authentication so that the user's credentials are passed to a remote computer to be authenticated.
    
#>
try {

    # Enable Util server as the CredSSP Client
    Write-Host "Setting current VM as CredSSP Client..."
    Enable-WSManCredSSP -Role Client -DelegateComputer $vm -Force | Out-Null

    # Enable the target VM as the CredSSP Server
    # Use IdleTimeout of 120,000 milliseconds (2 mins)
    Write-Host "Setting target VM as CredSSP Server..."
    Invoke-Command -ComputerName $vm `
                   -Credential $cred `
                   -SessionOption (New-PSSessionOption -IdleTimeout 120000) `
                   -ScriptBlock { Enable-WSManCredSSP -Role Server -Force | Out-Null }

} catch {

    $ErrorMessage = $_.Exception.Message
    
    Write-Host "Configuring CredSSP authentication between current and target VM failed with error message:"
    throw "$ErrorMessage"

}

# Verifying access to the file share VM with the installation bits for .NET Framework and SQL Server
$codeBlock = {

    param(

        [string]$sqlInstallationPath,
        [string]$DotNet35SourcePath
    )

    try {
        if ( !(Test-Path -Path $sqlInstallationPath) ) {        
            throw "Error: The location of SQL Server installation bits is not accessible from target VM."
        }

        if ( !(Test-Path -Path $DotNet35SourcePath) ) {        
            throw "Error: The location of .NET Framework 3.5 installation bits is not accessible from target VM."
        }
    } catch {
        $ErrorMessage = $_.Exception.Message
    
        Write-Host "Verifying access to file share locations on target VM failed with error message:"
        throw "$ErrorMessage"
    }
}

try{

    Write-Host "Verifying access to file share paths for software installation bits..."

    Invoke-Command -ComputerName $vm `
                   -Credential $cred `
                   -Authentication Credssp `
                   -SessionOption (New-PSSessionOption -IdleTimeout 120000) `
                   -ScriptBlock $codeBlock `
                   -ArgumentList $sqlInstallationPath, $DotNet35SourcePath

    Write-Host "Test successful: all file share paths are accessible from target VM using CredSSP authentcation."

} catch {

    $ErrorMessage = $_.Exception.Message
    
    Write-Host "Verifying access to file share locations on target VM failed."

    # Cleanup activity
    Disable-CredSSP -vm $vm -cred $cred

    Write-Host "Error message:"
    throw "$ErrorMessage"
}




################################################
# Run Pre-SQL-Installation-Config.ps1 remotely
###############################################

try {

    Write-Host "Running Pre-SQL-Installation-Config.ps1..."

    # Use IdleTimeout of 7,200,000 milliseconds (2 hours)
    Invoke-Command -ComputerName $vm `
                   -Credential $cred `
                   -SessionOption (New-PSSessionOption -IdleTimeout 7200000) `
                   -FilePath "$PSScriptRoot\Pre-SQL-Installation-Config.ps1" `
                   -ArgumentList $DotNet35SourcePath,`
                                 $SQLServerPort,`
                                 $SQLListenerPort,`
                                 $ILBProbePort

    Write-Host "Finished execution of Pre-SQL-Installation-Config.ps1"

} catch {

    $ErrorMessage = $_.Exception.Message
    
    Write-Host "Pre-SQL-Installation-Config.ps1 failed."

    # Cleanup activity
    Disable-CredSSP -vm $vm -cred $cred

    Write-Host "Error message:"
    throw "$ErrorMessage"

}




################################################
# Run Install-SQLServer.ps1 remotely
###############################################

try{

    Write-Host "Running Install-SQLServer.ps1..."

    # Use IdleTimeout of 7,200,000 milliseconds (2 hours)
    Invoke-Command -ComputerName $vm `
                   -Credential $cred `
                   -Authentication Credssp `
                   -SessionOption (New-PSSessionOption -IdleTimeout 7200000) `
                   -FilePath "$PSScriptRoot\Install-SQLServer.ps1" `
                   -ArgumentList $sqlInstallationPath,`
                                 $LocalAdmin,`
                                 $sqlServerSAPwd,`
                                 $sqlAdminsArray,`
                                 $sizeTempDBDataFileMB,`
                                 $autogrowTempDBinMB,`
                                 $UseDefaultLocalServiceAccounts,`
                                 $sqlServerSvcAcct,`
                                 $sqlServerSvcAcctPwd,`
                                 $sqlAgentSvcAcct,`
                                 $sqlAgentSvcAcctPwd
                                    
    Write-Host "Finished execution of Install-SQLServer.ps1"

} catch {

    $ErrorMessage = $_.Exception.Message
    
    Write-Host "Install-SQLServer.ps1 failed."

    # Cleanup activity
    Disable-CredSSP -vm $vm -cred $cred

    Write-Host "Error message:"
    throw "$ErrorMessage"

}




################################################
# Run Post-SQL-Installation-Config.ps1 remotely
###############################################


<#
Copies the contents of the $tSQLPath directory to the C:\MicrosoftScripts directory of the target VM. 
It creates the \MicrosoftScripts subdirectory if it does not already exist.
#>
Copy-Item $tSQLPath -Destination "\\$vm\C$\MicrosoftScripts" -Recurse

try{

    Write-Host "Running Post-SQL-Installation-Config.ps1..."

    # Use IdleTimeout of 240,000 milliseconds (4 minutes)
    Invoke-Command -ComputerName $vm `
                   -Credential $cred `
                   -SessionOption (New-PSSessionOption -IdleTimeout 240000) `
                   -FilePath "$PSScriptRoot\Post-SQL-Installation-Config.ps1" `
                   -ArgumentList $SMTPServerName,`
                                 $OperatorEmailAddress,`
                                 $TargetDataFilesLocation,`
                                 $TargetDataSizeMB,`
                                 $TargetDataFilegrowthMB,`
                                 $TargetTlogFilesLocation,`
                                 $TargetTlogSizeMB,`
                                 $TargetTlogFilegrowthMB,`
                                 $storageAccountName,`
                                 $storageAccountKey

                                    
    Write-Host "Finished execution of Post-SQL-Installation-Config.ps1"

} catch {

    $ErrorMessage = $_.Exception.Message
    
    Write-Host "Post-SQL-Installation-Config.ps1 failed."

    # Cleanup activity
    Disable-CredSSP -vm $vm -cred $cred

    Write-Host "Error message:"
    throw "$ErrorMessage"

}



################################################
# Clean-Up activities
###############################################

try {

    # Disable CredSSP on both target and current VM
    Disable-CredSSP -vm $vm -cred $cred

} catch {

    $ErrorMessage = $_.Exception.Message
    
    Write-Host "Disabling CredSSP on target and/or current VM failed with the following error message:"
    throw "$ErrorMessage"

}

Write-Host "SQL Server installation and configuration completed."
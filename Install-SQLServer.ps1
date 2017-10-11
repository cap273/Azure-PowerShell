<#

.NAME
	Install-SQLServer.
	
.SYNOPSIS 
    InstallS SQL Server 2012 or 2014 on a Windows Server 2012 R2 host machine.

.DESCRIPTION
	
	This script performs the following operations:
        - Install SQL Server from a source file.
            - A SQL Server service account is used as the Log On As account for the SQL Server instance.
            - A SQL Server Agent service account is used as the Log On As account for the SQL Server Agent instance.
            - Nondefault locations are used for User databases, Backups, System databases, and Log files, according to
                a company standard and SQL Server best practices.
        - Performs certain post-installation SQL Server configurations through a SQL query:
            - Set the number of TempDB files to the number of cores of this VM, or to 8 (whichever is least) [currently disabled]
            - Set the size and autogrow sizes of the TempDB files [currently disabled]
            - Enable certain flags

    PRECONDITION: The script Pre-SQL-Installation-Config.ps1 has already been successfully executed on the host machine.

    WARNING: Service account passwords that contain single quotes (') and/or double quotes (") will cause the SQL Server installation to fail.
         If any passwords contain single or double quotes, please install SQL Server with default local service accounts by
         setting the variable $UseDefaultLocalServiceAccounts to true.
            

.PARAMETER sqlInstallationPath
	Path of the SQL Server installation file (i.e. Setup.exe). This can be either SQL Server 2012 or 2014.

.PARAMETER LocalAdmin
    Name of the local administrator of the target machine.

.PARAMETER sqlServerSAPwd
    The password of the SQL sa account used to connect to the instance of SQL Server using SQL authentication (as opposed to Windows authentication)

.PARAMETER sqlAdminsArray
    An array of strings. Each element of this array is the name of an account to be added as a SQL sysadmin.

.PARAMETER sqlServerSvcAcct
    The SQL Server service account to be configured to run the SQL Server service. 

.PARAMETER sizeTempDBDataFileMB
	The initial configured size of the TempDB data files, in MB.
	
.PARAMETER autogrowTempDBinMB
	The file growth of the TempDB data files, in MB.

.PARAMETER UseDefaultLocalServiceAccounts
    Boolean to indicate whether to use Local service accounts if $true (e.g. NT Service\MSSQLSERVER) 
    or Domain service accounts if $false (e.g. MyCompanyDomain\SqlServiceAccount) for SQL Server and SQL Agent

.PARAMETER sqlServerSvcAcct
    The name of the SQL Server service account.

.PARAMETER sqlServerSvcAcctPwd
    The password of the SQL Server service account.

.PARAMETER sqlAgentSvcAcct
    The name of the SQL Agent service account.

.PARAMETER sqlAgentSvcAcctPwd
    The password of the SQL Agent service account.

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: April 26, 2016

#>

param (

    <# Shared Parameters #>

    [String]
    $sqlInstallationPath = "\\targetVM\Source\SQLServer2014\Setup.exe",

    [string]
    $LocalAdmin = "AzrRootAdminUser",

    [String]
    $sqlServerSAPwd = "testpassword",

    [string[]]
    $sqlAdminsArray = @("domain\username1",
                        "domain\username2"),

    [int]
    $sizeTempDBDataFileMB = 5000,

    [int]
    $autogrowTempDBinMB = 500,



    <# Boolean to indicate whether to use Local service accounts (e.g. NT Service\MSSQLSERVER) 
        or Domain service accounts (e.g. MyCompanyDomain\SqlServiceAccount) for SQL Server and SQL Agent #>
    
    [bool]
    $UseDefaultLocalServiceAccounts = $false,



    <# Parameters only applicable if using Domain Service Accounts for SQL Server and SQL Agent #>

    [String]
    $sqlServerSvcAcct = "CLOUD\SVCsqlserver",

    [String]
    $sqlServerSvcAcctPwd = "testpassword",

    [String]
    $sqlAgentSvcAcct = "CLOUD\SVCsqlagent",

    [String]
    $sqlAgentSvcAcctPwd = 'testpassword'

    )

########################################
# Initialize variables
########################################
$ServerName = $env:COMPUTERNAME # Name of the local computer.

# It appears that Try/Catch/Finally and Trap in PowerShell only works with terminating errors.
# Make all errors terminating
$ErrorActionPreference = "Stop";

<#
For each element of the array $sqlAdminsArray, prepare the string to be inputted as an argument of the SQL Server installation
This is accomplished by:
1. Adding a space at the end of the string (which is the delimiter for SQL Server installation parameters)
2. Wrapping the entire account in double quotes (") so as to prevent any spaces in the account name from being interpreted
    as delimiters.

Note that, in PowerShell, the escape character for a double quote is a double quote.
#>

# Initialize array to hold process account names for SQL Server sysadmins
$processedSqlAdminsArray = @($false) * ($sqlAdminsArray | Measure).Count 

# Loop through each account name to be added as a SQL Server sysadmin and process it
for ($i=0; $i -lt ($sqlAdminsArray | Measure).Count; $i ++) {
    
    $processedSqlAdminsArray[$i] = """$($sqlAdminsArray[$i])"" "

}


########################################
# Install and configure SQL Server
########################################
# Using the following document as a reference for list of parameters:
# https://msdn.microsoft.com/en-us/library/ms144259(v=sql.120).aspx

<#
 The following features are being installed:
 - Database Engine
    - Replication component of Database Engine
    - Full Text component of Database Engine
- Integration Services
- Management Tools - Complete
- Client Tools Backward Compatibility
- Client Tools Connectivity 
- SDK for SQL Server Native Client
- Software development kit
#>

# Specify installation parameters
$myArgList =  '/Q '                                                # Fully quiet installation
$myArgList += '/ACTION=INSTALL '
$myArgList += '/IAcceptSQLServerLicenseTerms=1 '                   # Accept the SQL Server license agreement
$myArgList += '/UPDATEENABLED=0 '                                  # Specify to NOT include product updates.
$myArgList += '/ERRORREPORTING=0 '                                 # Specify that errors CANNOT be reported to Microsoft.
$myArgList += '/SQMREPORTING=0 '                                   # Specify that SQL Server feature usage data CANNOT be collected and sent to Microsoft.                                     

$myArgList += '/FEATURES=SQLENGINE,REPLICATION,FULLTEXT,IS,ADV_SSMS,BC,CONN,SNAC_SDK,SDK '  # Specifies the Features to install        

$myArgList += '/INSTALLSHAREDDIR="E:\SQLSys\Program Files\Microsoft SQL Server" '            # Specifies a nondefault installation directory for 64-bit shared components.
$myArgList += '/INSTALLSHAREDWOWDIR="E:\SQLSys\Program Files(x86)\Microsoft SQL Server" '    # Specifies a nondefault installation directory for 32-bit shared components. 
$myArgList += '/INSTANCEDIR="E:\SQLSys\Program Files\Microsoft SQL Server" '                 # Specifies a nondefault installation directory for instance-specific components.
$myArgList += '/INSTALLSQLDATADIR="E:\SQLSys\Program Files\Microsoft SQL Server" '           # Specifies the data directory for SQL Server data files.

$myArgList += '/INSTANCENAME=MSSQLSERVER '                         # Specifies a SQL Server instance name.

if ( $UseDefaultLocalServiceAccounts ) {

    $myArgList += '/AGTSVCACCOUNT="NT Service\SQLSERVERAGENT" '    # Name of local service account for SQL Agent
    $myArgList += "/AGTSVCPASSWORD=testpassword "                  # (Dummy) Password of local service account for SQL Agent servie

}else {

    $myArgList += "/AGTSVCACCOUNT=$sqlAgentSvcAcct "               # Name of domain service account for SQL Agent
    $myArgList += "/AGTSVCPASSWORD=$sqlAgentSvcAcctPwd "           # Password of domain service account for SQL Agent
}

$myArgList += '/AGTSVCSTARTUPTYPE=Automatic '                      # Startup type of the SQL Server Agent service

$myArgList += '/SQLTEMPDBDIR="T:\TempDB" '                         # Specifies the directory for the data files for tempdb.
$myArgList += '/SQLTEMPDBLOGDIR="J:\TempDBLog" '                   # Specifies the directory for the log files for tempdb.

$myArgList += '/SQLUSERDBDIR="F:\SQLData" '                        # Specifies the directory for the data files for user databases.
$myArgList += '/SQLBACKUPDIR="E:\SQLBackup" '                      # Specifies the directory for backup files.
$myArgList += '/SQLUSERDBLOGDIR="J:\SQLLog" '                      # Specifies the directory for the log files for user databases.

$myArgList += '/ISSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE" '      # Specifies the account for Integration Services.
$myArgList += "/ISSVCPASSWORD=testpassword "                       # Specifies the Integration Services password. Since we are always using the default local service account, use dummy password.

if ( $UseDefaultLocalServiceAccounts ) {

    $myArgList += '/SQLSVCACCOUNT="NT Service\MSSQLSERVER" '       # Name of local service account for SQL Server
    $myArgList += "/SQLSVCPASSWORD=testpassword "                  # (Dummy) Password of local service account for SQL Server service

}else {
    
    $myArgList += "/SQLSVCACCOUNT=$sqlServerSvcAcct "              # Name of domain service account for SQL Server
    $myArgList += "/SQLSVCPASSWORD=$sqlServerSvcAcctPwd "          # Password of domain service account for SQL Agent
}

$myArgList += '/SQLSVCSTARTUPTYPE=Automatic '                      # Startup type for the SQL Server service
$myArgList += "/SQLSYSADMINACCOUNTS=$ServerName\$LocalAdmin "      # Add the local administrator of the machine as SQL Server system administrators.


# Add other Windows users or groups as SQL Server system administrators (the delimiter for /SQLSYSADMINACCOUNTS is simply a space)
for ($i=0; $i -lt ($processedSqlAdminsArray | Measure).Count; $i ++) {   
   
     $myArgList += $processedSqlAdminsArray[$i]
}                

$myArgList += '/SECURITYMODE=SQL '                                 # Use SQL for Mixed Mode authentication
$myArgList += "/SAPWD=$sqlServerSAPwd "                            # Specifies the password for the SQL Server sa account.

$myArgList += '/TCPENABLED=1'                                      # Enable TCP/IP Protocol

# Display the list of arguments to the user
Write-Host "`n `n $myArgList"

Write-Host "`n `n Installing SQL Server..."

try {

    # Start the installation process with the specified parameters.
    Start-Process -Verb runas -FilePath $sqlInstallationPath -ArgumentList $myArgList -Wait

    Write-Host "Installation of SQL Server exited. Installation status will be determined by the success or failure of running a query on the SQL Server instance."

} catch {
    
    throw "Error: Something went wrong with the SQL Server installation. Check the path of the SQL Server installation bits, and check the argument list."

}


########################################
# SQL Server Post-Installation
########################################
<#
    Build a multi-line string to be used as a SQL query.
    This query will:
        - Configure the flags to be enabled
        - Set the number of TempDB file
        - Set the initial size and autogrow size of the TempDB files

    Reference for the number of TempDB files to create according to SQL best practices:
    http://www.brentozar.com/sql/tempdb-performance-and-configuration/
    
#>

Write-Host "Running a SQL Query to configure TempDB files and enable SQL Server flags..."

# Enable certain trace flags.
$Query = "DBCC TRACEON (1117, 1118, 1204, 3226, 3605, -1);"

<#
# Continue building the SQL query string. Two new lines.
$Query += "`n `n"

# Set the first TempDB file according to user-selected initial size and autogrow size
$Query += "ALTER DATABASE tempdb `n"
$Query += "MODIFY FILE (name = tempdev, FILENAME = 'T:\TempDB\tempdb.mdf', SIZE = $($sizeTempDBDataFileMB)MB, FILEGROWTH = $($autogrowTempDBinMB)MB);"

# Set the number of TempDB files to the number of cores of this VM, or to 8 (whichever is less)
$numCores = (Get-WmiObject Win32_Processor).NumberOfCores

if ($numCores -le 8) {
    $numTempDBFiles = $numCores
} else {
    $numTempDBFiles = 8
}

# Continue building the SQL query to be executed for setting the number and autogrow settings of TempDB files
if (   $numTempDBFiles -gt 1   ) {
    
    for ($i=2; $i -le $numTempDBFiles; $i++) {
        
        $Query += "`n `n"
        $Query += "ALTER DATABASE tempdb `n"
        $Query += "ADD FILE (NAME = tempdev$i, FILENAME = 'T:\TempDB\tempdb$i.mdf', SIZE = $($sizeTempDBDataFileMB)MB, FILEGROWTH = $($autogrowTempDBinMB)MB);"
    }
}
#>

# Database name on which to perform query
$DatabaseName = "master"

# Timeout parameters (in seconds)
$QueryTimeout = 600
$ConnectionTimeout = 120

try{

    # Create the connection string and open the connection with the SQL Server instance
    $conn=New-Object System.Data.SqlClient.SQLConnection
    $ConnectionString = "Server={0};Database={1};Integrated Security=True;Connect Timeout={2}" -f $ServerName,$DatabaseName,$ConnectionTimeout
    $conn.ConnectionString=$ConnectionString
    $conn.Open()

    # Create a new SQL Command with the Query and run the Command
    $cmd=New-Object System.Data.SqlClient.SqlCommand($Query,$conn)
    $cmd.CommandTimeout=$QueryTimeout
    $ds=New-Object System.Data.DataSet
    $da=New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    [void]$da.fill($ds)

    <#
    # Change the default location of the Data, Log, and Backup databases
    # To add Microsoft.SqlServer.Smo objects, following the instructions on the following website: 
    # http://sqlmag.com/powershell/using-sql-server-management-objects-powershell
    Add-Type -path "C:\Windows\assembly\GAC_MSIL\Microsoft.SqlServer.Smo\10.0.0.0__89845dcd8080cc91\Microsoft.SqlServer.Smo.dll"
    $SQLServer = New-Object Microsoft.SqlServer.Management.Smo.Server($ServerName)
    $SQLServer.DefaultFile = "F:\SQL_Data"                        # Change the default location of data files
    $SQLServer.DefaultLog = "F:\SQL_Logs"                         # Change the default location of log files
    $SQLServer.BackupDirectory = "F:\SQL_Backup"                  # Change the default location of backup files
    $SQLServer.Alter()                                            # Updates any Server object property changes on the instance of SQL Server. 
    #>

    # Close the connection and output any results.
    $conn.Close()
    $ds.Tables

    Write-Host "Restarting the SQL Server instance..."
    Restart-Service -Name 'MSSQLSERVER' -Force

    <# 
    Wait some time before executing anything on SQL Server after SQL Server restart to prevent "Lock Request Time Out Period Exceeded" error
    #>
    Start-Sleep 60

    Write-Host "SQL Server successfully installed and configured."

} catch {

    throw "Running a query on the SQL Server instance failed. This is probably because SQL Server installation failed. Please check the SQL Server error logs."

}
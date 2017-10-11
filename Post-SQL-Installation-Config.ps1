<#

.NAME
	Post-SQL-Installation-Config
	
.DESCRIPTION 
    Configures the SQL Server instance, configures TempDB files, sets up optimization tasks, and sets up backup jobs to an Azure storage account.
    
    PRECONDITION: The scripts Pre-SQL-Installation-COnfig.ps1 and 
        Install-SQLServer.ps1 have been executed successfully on this machine.


.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: April 26, 2016
#>

param (
        #########################################
        # 10_SQL_Instance_2014_Config.sql params
        #########################################
        [string] $SMTPServerName,
        [string] $OperatorEmailAddress,

        #########################################
        # 15_SQL_TempDB_Configuration.sql params
        #########################################
        [string] $TargetDataFilesLocation = 'T:\TempDB\',
        [string] $TargetDataSizeMB = '10000MB',
        [string] $TargetDataFilegrowthMB = '5000MB',
        [string] $TargetTlogFilesLocation = 'J:\TempDBLog\',
        [string] $TargetTlogSizeMB = '5000MB',
        [string] $TargetTlogFilegrowthMB = '1000MB',

        #########################################
        # Backups and Custom Jobs
        #########################################
        [string] $storageAccountName,
        [string] $storageAccountKey


    )

########################################
# Initialize variables
########################################
$ServerName = $env:COMPUTERNAME # Name of the local computer.

# It appears that Try/Catch/Finally and Trap in PowerShell only works with terminating errors.
# Make all errors terminating
$ErrorActionPreference = "Stop";

# The SQL Server instance. For default instances, only specify the computer name
$DBServer = "$ServerName" 

# Execute scripts against the master database
$database = "master"

# Base folder with all TSQL scripts
$rootFolder = "C:\MicrosoftScripts"

# Import Invoke-SqlCMD cmdlet
if (Test-Path -Path "E:\SQLSys\Program Files(x86)\Microsoft SQL Server\120\Tools\PowerShell\Modules\SQLPS") {
    
    $env:PSModulePath = $env:PSModulePath + ";E:\SQLSys\Program Files(x86)\Microsoft SQL Server\120\Tools\PowerShell\Modules"

    Import-Module SQLPS -DisableNameChecking

} else {

    throw "Manually finding the module path for SQLPS has failed. This module is necessary to execute Invoke-SqlCmd."

} 



########################################
# 10_SQL_Instance_2014_Config.sql
########################################

# Location of script
$DBScriptFile = "$rootFolder\10_SQL_Instance_2014_Config.sql"          

# Build the list of parameters names and parameter values to be passed to the TSQL script
$Param1 = "SMTPServerName=" + "$SMTPServerName"
$Param2 = "OperatorEmailAddress=" + "$OperatorEmailAddress"
$Params = $Param1, $Param2

Write-Host "Executing 10_SQL_Instance_2014_Config.sql..."

Invoke-Sqlcmd -InputFile $DBScriptFile -ServerInstance $DBServer -Database $database -Variable $Params -QueryTimeout 120

Write-Host "Execution of 10_SQL_Instance_2014_Config.sql completed."


########################################
# 15_SQL_TempDB_Configuration.sql
########################################

# Location of script
$DBScriptFile = "$rootFolder\15_SQL_TempDB_Configuration.sql"          


# Build the list of parameters names and parameter values to be passed to the TSQL script
$Param1 = "TargetDataFilesLocation=" + "$TargetDataFilesLocation"
$Param2 = "TargetDataSizeMB=" + "$TargetDataSizeMB"
$Param3 = "TargetDataFilegrowthMB=" + "$TargetDataFilegrowthMB"
$Param4 = "TargetTlogFilesLocation=" + "$TargetTlogFilesLocation"
$Param5 = "TargetTlogSizeMB=" + "$TargetTlogSizeMB"
$Param6 = "TargetTlogFilegrowthMB=" + "$TargetTlogFilegrowthMB"
$Params = $Param1, $Param2, $Param3, $Param4, $Param5, $Param6

Write-Host "Executing 15_SQL_TempDB_Configuration.sql..."

Invoke-Sqlcmd -InputFile $DBScriptFile -ServerInstance $DBServer -Database $database -Variable $Params -QueryTimeout 900

Write-Host "Execution of 15_SQL_TempDB_Configuration.sql completed."


########################################
# 0_Create_Credential_For_Backup.sql
########################################

# Location of script
$DBScriptFile = "$rootFolder\CustomJobs\0_Create_Credential_For_Backup.sql"       

<#
 HACK: All storage account keys in Azure end with two equal signs (==)
 It appears that equal signs cannot appear in the value of parameters passed using Invoke-SQLcmd: 
 http://stackoverflow.com/questions/35157090/escape-variable-in-sqlcmd-invoke-sqlcmd

 So, the hack is to remove the two equal signs here, and append them back in the T-SQL script.
#>
$storageAccountKey_edited = $storageAccountKey -replace '=',''

# Build the list of parameters names and parameter values to be passed to the TSQL script
$Param1 = "storageAccountName=" + "$storageAccountName"
$Param2 = "storageAccountKey=" + "$storageAccountKey_edited"
$Params = $Param1, $Param2

Write-Host "Executing 0_Create_Credential_For_Backup.sql..."

Invoke-Sqlcmd -InputFile $DBScriptFile -ServerInstance $DBServer -Database $database -Variable $Params -QueryTimeout 60

Write-Host "Execution of 0_Create_Credential_For_Backup.sql completed."


########################################
# 1_Ola_MaintenanceSolution_20160108_GZ.sql
########################################

# Location of script
$DBScriptFile = "$rootFolder\CustomJobs\1_Ola_MaintenanceSolution_20160108_GZ.sql"       

Write-Host "Executing 1_Ola_MaintenanceSolution_20160108_GZ.sql..."

# This script does not require any parameters
Invoke-Sqlcmd -InputFile $DBScriptFile -ServerInstance $DBServer -Database $database -QueryTimeout 60

Write-Host "Execution of 1_Ola_MaintenanceSolution_20160108_GZ.sql completed."

#######################################
# Set environment variables to pass paramaters to SQL Server
#######################################

# Set environment variables to store the storage account name and key
[Environment]::SetEnvironmentVariable("StorageAccount","$storageAccountName","Machine")
[Environment]::SetEnvironmentVariable("StorageAccountKey","$storageAccountKey","Machine")

Restart-Service -Name 'MSSQLSERVER' -Force

# Waiting only at most 30 seconds after MSSQLSERVER restart before using Invoke-Sqlcmd restart causes 
# the error "Lock Request Time Out Period Exceeded" to be returned.
Write-Host "Waiting for SQL Server service to restart..."
Start-Sleep 180


########################################
# SQL Server Agent jobs 2-9
########################################

$jobFiles = @(
                "2_Create DatabaseBackup - SYSTEM_DATABASES - FULL Job.sql",
                "3_Create DatabaseBackup - USER_DATABASES - FULL Job.sql",
                "4_Create DatabaseBackup - USER_DATABASES - LOG Job.sql",
                "5_Create DatabaseIntegrityCheck - SYSTEM_DATABASES Job.sql",
                "6_Create DatabaseIntegrityCheck - USER_DATABASES Job.sql",
                "7_Create IndexOptimize - USER_DATABASES Job.sql",
                "8_Create CommandLog Cleanup Job.sql",
                "9_Create Output File Cleanup Job.sql"
             )

foreach( $jobFile in $jobFiles ) {

    # Location of script
    $DBScriptFile = "$rootFolder\CustomJobs\$jobFile"       

    Write-Host "Executing $jobFile..."

    # Do NOT pass parameters to T-SQL script through PowerShell. The T-SQL script will read environment variables instead.
    Invoke-Sqlcmd -InputFile $DBScriptFile -ServerInstance $DBServer -Database $database -DisableVariables

    Write-Host "Execution of $jobFile completed."
}


########################################
# Delete old backup jobs
########################################

$jobFiles = @(
                "Create_Delete_Old_Full_Backups_From_BLOB_SystemDB_Job.sql",
                "Create_Delete_Old_Full_Backups_From_BLOB_UserDB_Job.sql",
                "Create_Delete_Old_TLog_Backups_From_BLOB_Job.sql"
             )

foreach( $jobFile in $jobFiles ) {

    # Location of script
    $DBScriptFile = "$rootFolder\DeleteOldBackupsScripts\$jobFile"       

    Write-Host "Executing $jobFile..."

    # Do NOT pass parameters to T-SQL script through PowerShell. The T-SQL script will read environment variables instead.
    Invoke-Sqlcmd -InputFile $DBScriptFile -ServerInstance $DBServer -Database $database -DisableVariables

    Write-Host "Execution of $jobFile completed."
}


#######################################
# Clean-up activities: remove environment variables
#######################################

# Remove environment variabls
[Environment]::SetEnvironmentVariable("StorageAccount",$null,"Machine")
[Environment]::SetEnvironmentVariable("StorageAccountKey",$null,"Machine")
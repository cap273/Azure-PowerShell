<#

.NAME
	Add-SQLAdmin
	
.SYNOPSIS 
    Adds a domain user as a SQL Server sysadmin.

.PARAMETER DomainUser
    The domain user to add as sysadmin, in the form Domain\User

.NOTES
    AUTHOR: Carlos Patiño
    LASTEDIT: March 16, 2016

#>

param (
    [String]
    $DomainUser

    )

Write-Host "Configuring SQL Server..."

# Get server name
$ServerName = $env:COMPUTERNAME # Name of the local computer.

# Enable certain trace flags.
$Query = "EXEC master..sp_addsrvrolemember @loginame = N'$DomainUser', @rolename = N'sysadmin'"

# Database name on which to perform query
$DatabaseName = "master"

# Timeout parameters
$QueryTimeout = 120
$ConnectionTimeout = 60

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

# Close the connection and output any results.
$conn.Close()
$ds.Tables

# Restart the SQL Server instance
Restart-Service -Name 'MSSQLSERVER' -Force

Write-Host "SQL Server configuration finished."
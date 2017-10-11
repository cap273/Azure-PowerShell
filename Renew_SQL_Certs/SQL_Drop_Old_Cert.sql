--SQL_Drop_Old_Cert
/*
This script drops the existing backup certificate
on this SQL Sevrer


Execute script in SQL CMD mode
*/

/*
Variables passed from PowerShell:
- certificateName
*/


SET NOCOUNT ON
USE master;

IF (SELECT CONVERT(int,PARSENAME(CONVERT(varchar(32), SERVERPROPERTY('ProductVersion')),4))) > 11	
--Do it only for SQL 2014
BEGIN
	--Step3. Creating Backup certificate in master database
	PRINT 'Creating backup encryption certificate...';
	IF EXISTS (
			  SELECT *
			  FROM sys.certificates
			  WHERE name = '$(certificateName)'
			  )
		DROP CERTIFICATE Autobackup_Certificate;
	ELSE
		PRINT 'No backup certificate by the inputted name exists.'
END
ELSE
	PRINT 'SQL Server Version is less than SQL 2014...No encrypted backup'
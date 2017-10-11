--SQL_Drop_Old_Cert
/*
This script creates the existing backup certificate
on this SQL Server.

This script also backs up the certificate locally, with its
private key, so that it may be distributed to other VMs in the
same Availability Group.


Execute script in SQL CMD mode
*/

/*
Variables passed from PowerShell:
- certificateFolder
- certificatePassword
*/


SET NOCOUNT ON
USE master;

DECLARE @CertFolder sysname = '$(certificateFolder)'
DECLARE @CertPassword sysname = '$(certificatePassword)'

IF (SELECT CONVERT(int,PARSENAME(CONVERT(varchar(32), SERVERPROPERTY('ProductVersion')),4))) > 11	
--Do it only for SQL 2014
BEGIN
	--Step3. Creating Backup certificate in master database
	PRINT 'Dropping old backup encryption certificate...';
	IF NOT EXISTS (
					SELECT *
					FROM sys.certificates
					WHERE name = 'Autobackup_Certificate'
					)
		CREATE CERTIFICATE Autobackup_Certificate 
			WITH SUBJECT = 'Automatic Backup Certificate',
			EXPIRY_DATE = '12/31/2099';
	ELSE
		PRINT 'Backup Encryption Certificate already exists...'
END
ELSE
	PRINT 'SQL Server Version is less than SQL 2014...No encrypted backup'


DECLARE @mysql      varchar(max)
-- Backup the certificate to remove the nag that would otherwise appear in the output of every backup
SET @mysql = '
BACKUP CERTIFICATE AutoBackup_Certificate
TO FILE = ''' + @CertFolder + '\AutoBackup_Certificate.cer''
WITH PRIVATE KEY (
                 FILE = ''' + @CertFolder + '\AutoBackup_Certificate_private_key.key'',
                 ENCRYPTION BY PASSWORD = ''' + @CertPassword + '''
                 );
'
print @mysql
EXEC (@mysql)
print 'Certificate is backed up'
GO
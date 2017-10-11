--SQL_Drop_Old_Cert
/*
This script uses an existing certificate to set
up the backup certificate for this SQL Server instance


Execute script in SQL CMD mode
*/

/*
Variables passed from PowerShell:
- certificateFolder
- certificatePassword
*/


SET NOCOUNT ON
USE master;

DECLARE @mysql      varchar(max)
DECLARE @mysql2      varchar(max)

DECLARE @CertFolder sysname = '$(certificateFolder)'
DECLARE @CertPassword sysname = '$(certificatePassword)'

IF (SELECT CONVERT(int,PARSENAME(CONVERT(varchar(32), SERVERPROPERTY('ProductVersion')),4))) > 11	
--Do it only for SQL 2014
BEGIN
	SET @mysql = '
	CREATE CERTIFICATE Autobackup_Certificate
	FROM FILE = ''' + @CertFolder + '\Autobackup_Certificate.cer''
	WITH PRIVATE KEY (
					 FILE = ''' + @CertFolder + '\Autobackup_Certificate_private_key.key'',
					 DECRYPTION BY PASSWORD = ''' + @CertPassword + '''
					 );
	'
	print @mysql
	EXEC (@mysql)
	print 'Certificate is Re-Created from the local file'


	-- Backup the certificate to remove the nag that would otherwise appear in the output of every backup
	SET @mysql2 = '
	BACKUP CERTIFICATE AutoBackup_Certificate
	TO FILE = ''' + @CertFolder + '\AutoBackup_Certificate_dummy.cer''
	WITH PRIVATE KEY (
					 FILE = ''' + @CertFolder + '\AutoBackup_Certificate_private_key_dummy.key'',
					 ENCRYPTION BY PASSWORD = ''' + @CertPassword + '''
					 );
	'
	print @mysql2
	EXEC (@mysql2)
	print 'Certificate is backed up'
	
END
ELSE
	PRINT 'SQL Server Version is less than SQL 2014...No encrypted backup'
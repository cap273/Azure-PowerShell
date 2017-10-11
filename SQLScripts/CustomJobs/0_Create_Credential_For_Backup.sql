--Create_Credential_For_Backup

/*
1. Put proper name of standard storage account for IDENTITY element
2. Put name of Primary key for this account in SECRET
*/

DECLARE @storageAccountName varchar(max)
DECLARE @storageAccountKey varchar(max)

SELECT @storageAccountName = '$(storageAccountName)'
SELECT @storageAccountKey = '$(storageAccountKey)'

/*
 HACK: All storage account keys in Azure end with two equal signs (==)
 It appears that equal signs cannot appear in the value of parameters passed using Invoke-SQLcmd: 
 http://stackoverflow.com/questions/35157090/escape-variable-in-sqlcmd-invoke-sqlcmd

 So, the hack is to remove the two equal signs here, and append them back in the T-SQL script.
*/
SELECT @storageAccountKey = @storageAccountKey + '=='

IF NOT EXISTS
(SELECT * FROM sys.credentials 
WHERE credential_identity = 'AutoBackup_Credential')

/*
CREATE CREDENTIAL AutoBackup_Credential WITH IDENTITY = 'name_of_storage_acct'
,SECRET = 'Storage_acct_Primary_Key' ;
*/

EXEC('CREATE CREDENTIAL AutoBackup_Credential WITH IDENTITY = ''' + @storageAccountName + ''',SECRET = ''' + @storageAccountKey + ''';')


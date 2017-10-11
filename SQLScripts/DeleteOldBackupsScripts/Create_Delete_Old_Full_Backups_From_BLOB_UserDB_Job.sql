--Create_Delete_Old_Full_Backups_From_BLOB_UserDB_Job

/*
Before execution, edit:
1. Location of the PowerShell script
2. # of days to keeps files (1st parameter)
3. BLOB container (3rd parameter)
4. Name of Storage account (4th parameter)
5. Account Key (5th parameter)
6. Job Schedule
*/


DECLARE @StorageAccountName varchar(max)
DECLARE @StorageAccountKey varchar(max)

--Get the server name
DECLARE @servername varchar(max) 
SELECT @servername = LOWER(@@SERVERNAME)

/*
Use sp_configure to allow xp_cmdshell to run. Necessary to extract environment variables passed from PowerShell
*/
declare @prevAdvancedOptions int
declare @prevXpCmdshell int

select @prevAdvancedOptions = cast(value_in_use as int) from sys.configurations where name = 'show advanced options'
select @prevXpCmdshell = cast(value_in_use as int) from sys.configurations where name = 'xp_cmdshell'

if (@prevAdvancedOptions = 0)
begin
    exec sp_configure 'show advanced options', 1
    reconfigure
end

if (@prevXpCmdshell = 0)
begin
    exec sp_configure 'xp_cmdshell', 1
    reconfigure
end

/*
Retrieve environment variables (set by PowerShell) that store the storage account name and key
*/
CREATE TABLE #Tmp
(
EnvVar nvarchar(max)
)
INSERT INTO #Tmp exec xp_cmdshell 'echo %StorageAccount%'
SET @StorageAccountName = (SELECT TOP 1 EnvVar from #Tmp)

--SELECT @StorageAccountName as 'Storage Account Name'
DROP TABLE #Tmp

CREATE TABLE #Tmp2
(
EnvVar2 nvarchar(max)
)
INSERT INTO #Tmp2 exec xp_cmdshell 'echo %StorageAccountKey%'
SET @StorageAccountKey = (SELECT TOP 1 EnvVar2 from #Tmp2)

--SELECT @StorageAccountKey as 'Storage Account Key'
DROP TABLE #Tmp2

/*
Return the sys.configurations settings to their previous state
*/
if (@prevXpCmdshell = 0)
begin
    exec sp_configure 'xp_cmdshell', 0
    reconfigure
end

if (@prevAdvancedOptions = 0)
begin
    exec sp_configure 'show advanced options', 0
    reconfigure
end

DECLARE @Command nvarchar(max)
SET @Command = N'C:\Windows\System32\WindowsPowerShell\v1.0\powershell -Command "C:\MicrosoftScripts\DeleteOldBackupsScripts\Delete_Old_Files.ps1" 15 ''bak'' ''' + @servername +  '-userdbbkp'' ''' + @StorageAccountName + ''' ''' + @StorageAccountKey + '''"'

BEGIN TRANSACTION

USE [msdb]

IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'Delete_Old_Full_Backups_From_BLOB_UserDB')
	EXEC msdb.dbo.sp_delete_job @job_name=N'Delete_Old_Full_Backups_From_BLOB_UserDB', @delete_unused_schedule=1


COMMIT TRANSACTION
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Delete_Old_Full_Backups_From_BLOB_UserDB', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Set Execution Policy Unrestricted', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=4, 
		@on_success_step_id=2, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'C:\Windows\System32\WindowsPowerShell\v1.0\powershell -command "set-executionpolicy unrestricted -scope process -force"', 
		@flags=32
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Run PowerShell Script', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=4, 
		@on_success_step_id=3, 
		@on_fail_action=4, 
		@on_fail_step_id=4, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=@Command, 
		@flags=32
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Set Execution Policy RemoteSigned', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'C:\Windows\System32\WindowsPowerShell\v1.0\powershell -command "set-executionpolicy remotesigned -scope process -force"', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Set Execution Policy After Failure', 
		@step_id=4, 
		@cmdexec_success_code=0, 
		@on_success_action=2, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'C:\Windows\System32\WindowsPowerShell\v1.0\powershell -command "set-executionpolicy remotesigned -scope process -force"', 
		@flags=32
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Delete_Old_Full_Backups_From_BLOB_UserDB_Sch', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20160103, 
		@active_end_date=99991231, 
		@active_start_time=10000, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO

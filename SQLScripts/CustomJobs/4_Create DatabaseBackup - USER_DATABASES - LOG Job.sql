--Create DatabaseBackup - USER_DATABASES - LOG Job

/*
1. Change the value of @URL parameter (name of storage account and container)
2. Verify correct folder in parameter @output_file_name
*/
DECLARE @URLPath varchar(max)
DECLARE @Outpath varchar(max) = 'E:\DBA_Logs\'

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
Retrieve environment variables (set by PowerShell) that store the storage account name
*/
DECLARE @storname nvarchar(255)
CREATE TABLE #Tmp
(
EnvVar nvarchar(max)
)
INSERT INTO #Tmp exec xp_cmdshell 'echo %StorageAccount%'
SET @storname = (SELECT TOP 1 EnvVar from #Tmp)

SELECT @storname as 'Storage Account Name'
DROP TABLE #Tmp

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

--Get the server name
DECLARE @servername varchar(max) 
SELECT @servername = LOWER(@@SERVERNAME)


SELECT @URLPath = 'https://' + @storname + '.blob.core.windows.net/' + @servername + '-userlogbkp'

USE [msdb]
 
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = 'DatabaseBackup - USER_DATABASES - LOG')
        EXEC msdb.dbo.sp_delete_job @job_name=N'DatabaseBackup - USER_DATABASES - LOG', @delete_unused_schedule=1

DECLARE @StepCommand nvarchar(max), @OutputCommand nvarchar(max)
SET @OutputCommand = @Outpath + N'DatabaseBackup_$(ESCAPE_SQUOTE(JOBID))_$(ESCAPE_SQUOTE(STEPID))_$(ESCAPE_SQUOTE(STRTDT))_$(ESCAPE_SQUOTE(STRTTM)).txt' 
SET @StepCommand = N'sqlcmd -E -S $(ESCAPE_SQUOTE(SRVR)) -d DBA_Local -Q "EXECUTE [dbo].[DatabaseBackup] @Databases = ''USER_DATABASES'', @URL = N''' + @URLPath + ''', @Credential = ''AutoBackup_Credential'', @BackupType = ''LOG'', @Verify = ''Y'', @Compress = ''Y'', @CheckSum = ''Y'', @ChangeBackupType = ''Y'', @LogToTable = ''Y''" -b'

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DatabaseBackup - USER_DATABASES - LOG', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Source: https://ola.hallengren.com', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'DatabaseBackup - USER_DATABASES - LOG', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=@StepCommand, 
		@output_file_name=@OutputCommand, 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'TLogBackup_User_Sch', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=1, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20160111, 
		@active_end_date=99991231, 
		@active_start_time=100, 
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
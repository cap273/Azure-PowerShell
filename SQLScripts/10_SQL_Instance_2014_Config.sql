--10_SQL_Instance_2014_Config
/* 
This scripts configures a new SQL instance on an Azure OLTP .
Default SQL instance is assumed.

Execute on every SQL instance.

Variables passed from PowerShell:
- SMTPServerName
- OperatorEmailAddress
*/
USE master;
SET NOCOUNT ON;

DECLARE @SMTPServerName sysname = '$(SMTPServerName)'               
DECLARE @OperatorEmailAddress sysname = '$(OperatorEmailAddress)'

DECLARE @servername varchar(128)
SELECT	@servername = CONVERT(varchar(128),SERVERPROPERTY('servername'))
--SELECT	@servername


PRINT 'Setting instance options on server  ' + @servername;

DECLARE @total_physical_memory_MB int, @max_server_memory_MB int, @min_server_memory_MB int
SELECT	@total_physical_memory_MB = total_physical_memory_kb/1024 from sys.dm_os_sys_memory 
SELECT  @max_server_memory_MB = CASE 
			WHEN @total_physical_memory_MB > 60000 THEN @total_physical_memory_MB * 0.9
			ELSE @total_physical_memory_MB * 0.9 End,
		@min_server_memory_MB = CASE
			WHEN @total_physical_memory_MB > 14000 THEN 10000
			ELSE 2000 End
--SELECT	@max_server_memory_MB, 	@min_server_memory_MB	

DECLARE @Logical_CPU_Count int, @Hyperthread_Ratio int, @Physical_CPU_Count int, @MAXDOP int
SELECT	@Logical_CPU_Count = cpu_count, 
		@Hyperthread_Ratio = hyperthread_ratio,
		@Physical_CPU_Count= cpu_count/hyperthread_ratio
FROM sys.dm_os_sys_info

SELECT  @MAXDOP = @Logical_CPU_Count / @Physical_CPU_Count / 2

exec sp_configure 'show advanced options', 1;
reconfigure

DECLARE @mystr varchar(max)
SET		@mystr = 'exec sp_configure ''max server memory (MB)'', ' + LTRIM(STR(@max_server_memory_MB))
--SELECT	@mystr
EXEC	(@mystr)

SET		@mystr = 'exec sp_configure ''min server memory (MB)'', ' + LTRIM(STR(@min_server_memory_MB))
--SELECT	@mystr
EXEC	(@mystr)

SET		@mystr = 'exec sp_configure ''max degree of parallelism'', ' + LTRIM(STR(@MAXDOP))
--SELECT	@mystr
EXEC	(@mystr)

--exec sp_configure 'max server memory (MB)', 25000;
--exec sp_configure 'min server memory (MB)', 10000;
--exec sp_configure 'max degree of parallelism', 4;
exec sp_configure 'cost threshold for parallelism', 30;
exec sp_configure 'backup compression default', 1;
exec sp_configure 'backup checksum default', 1;
exec sp_configure 'optimize for Ad hoc Workloads', 1;
exec sp_configure 'remote admin connections', 1;
exec sp_configure 'Database Mail XPs', 1;
exec sp_configure 'Agent XPs', 1;
exec sp_configure 'contained database authentication', 1; -- Only needed for WAP databases
reconfigure;

--PRINT 'Current Server Settings are:'
--exec sp_configure 

PRINT 'Enabling SQL Authentication...';

-- Enable SQL auth
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2

PRINT 'Configuring Database Mail...';

-- Configure DB Mail
USE msdb;

DECLARE @display_name nvarchar(100)= 'SQL Server in Azure IaaS ' + @servername;
DECLARE @EmailNotificationFromAddress nvarchar(128)
SET	@EmailNotificationFromAddress = @servername + '@emailaddress.com'

IF EXISTS (SELECT * FROM msdb.dbo.sysmail_profileaccount pa 
	INNER JOIN msdb.dbo.sysmail_account ac ON pa.account_id = ac.account_id
	INNER JOIN msdb.dbo.sysmail_profile pr ON pa.profile_id = pr.profile_id
	WHERE ac.name = 'SQL Server Mail' AND pr.name = 'DBA Mail Profile')
	EXECUTE msdb.dbo.sysmail_delete_profileaccount_sp @account_name = 'SQL Server Mail', @profile_name = 'DBA Mail Profile'

IF EXISTS (SELECT * FROM msdb.dbo.sysmail_account WHERE name = 'SQL Server Mail')
	EXECUTE msdb.dbo.sysmail_delete_account_sp @account_name = 'SQL Server Mail'
EXECUTE msdb.dbo.sysmail_add_account_sp
    @account_name = 'SQL Server Mail',
    @email_address = @EmailNotificationFromAddress,
    @display_name = @display_name,
    @mailserver_name = @SMTPServerName;

IF EXISTS (SELECT * FROM msdb.dbo.sysmail_profile WHERE name = 'DBA Mail Profile')
	EXECUTE msdb.dbo.sysmail_delete_profile_sp @profile_name = 'DBA Mail Profile'
EXECUTE msdb.dbo.sysmail_add_profile_sp
    @profile_name = 'DBA Mail Profile';

EXECUTE msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name = 'DBA Mail Profile',
    @account_name = 'SQL Server Mail',
    @sequence_number = 1;

EXEC msdb.dbo.sp_set_sqlagent_properties @email_save_in_sent_folder=1, 
		@databasemail_profile=N'DBA Mail Profile', 
		@use_databasemail=1;

PRINT 'Creating the Operations operator...';

IF NOT EXISTS (select 1 from msdb.dbo.sysoperators WHERE name = 'AzureOps')
	EXEC msdb.dbo.sp_add_operator @name=N'AzureOps', 
			@enabled=1, 
			@weekday_pager_start_time=90000, 
			@weekday_pager_end_time=180000, 
			@saturday_pager_start_time=90000, 
			@saturday_pager_end_time=180000, 
			@sunday_pager_start_time=90000, 
			@sunday_pager_end_time=180000, 
			@pager_days=0, 
			@email_address=@OperatorEmailAddress, 
			@category_name=N'[Uncategorized]'

PRINT 'Configuring the model database...';

USE master;

-- Configure model
ALTER DATABASE [model] SET RECOVERY SIMPLE WITH NO_WAIT;
IF (SELECT (size * 8) FROM sys.master_files WHERE DB_NAME(database_id) = 'model' AND Name = 'modeldev') < 65536
	ALTER DATABASE [model] MODIFY FILE ( NAME = N'modeldev', SIZE = 65536KB, FILEGROWTH = 65536KB);
IF (SELECT (size * 8) FROM sys.master_files WHERE DB_NAME(database_id) = 'model' AND Name = 'modellog') < 65536
	ALTER DATABASE [model] MODIFY FILE ( NAME = N'modellog', SIZE = 65536KB, FILEGROWTH = 65536KB);

PRINT 'Creating DBA_Local database...';

-- Create DBA_Local
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DBA_Local')
BEGIN
	CREATE DATABASE DBA_Local;
	ALTER AUTHORIZATION ON DATABASE::DBA_Local TO sa;

	ALTER DATABASE DBA_Local MODIFY FILE (NAME = N'DBA_Local', FILEGROWTH = 65536KB );
	ALTER DATABASE DBA_Local MODIFY FILE (NAME = N'DBA_Local_log', SIZE = 65536KB , FILEGROWTH = 65536KB );
END
PRINT 'Configuring error log retention...';

EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'NumErrorLogs', REG_DWORD, 30

PRINT 'Creating a job to cycle error logs...';

-- Create a job to cycle error log

USE msdb;

IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = 'Cycle error log')
	EXEC msdb.dbo.sp_delete_job @job_name=N'Cycle error log', @delete_unused_schedule=1;
EXEC  msdb.dbo.sp_add_job @job_name=N'Cycle error log', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=2, 
		@notify_level_page=2, 
		@delete_level=0, 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa';

EXEC msdb.dbo.sp_add_jobserver @job_name=N'Cycle error log', @server_name = N'(local)';

EXEC msdb.dbo.sp_add_jobstep @job_name=N'Cycle error log', @step_name=N'Execute sp_cycle_errorlog', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_fail_action=2, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0,
        @subsystem=N'TSQL', 
		@command=N'EXEC sp_cycle_errorlog;', 
		@database_name=N'master', 
		@flags=0;

EXEC msdb.dbo.sp_add_jobschedule @job_name=N'Cycle error log', @name=N'Daily at 23:55', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20150622, 
		@active_end_date=99991231, 
		@active_start_time=235500, 
		@active_end_time=235959;

PRINT 'Creating alerts...';

IF EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE name = 'Error 823')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 823'
EXEC msdb.dbo.sp_add_alert @name=N'Error 823', 
		@message_id=823, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=600, 
		@include_event_description_in=1, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000';

IF EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE name = 'Error 824')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 824'
EXEC msdb.dbo.sp_add_alert @name=N'Error 824', 
		@message_id=824, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=600, 
		@include_event_description_in=1, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000';

IF EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE name = 'Error 825')
	EXEC msdb.dbo.sp_delete_alert @name=N'Error 825'
EXEC msdb.dbo.sp_add_alert @name=N'Error 825', 
		@message_id=825, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=600, 
		@include_event_description_in=1, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000';

IF EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE name = 'Severity 22+')
	EXEC msdb.dbo.sp_delete_alert @name=N'Severity 22+'
EXEC msdb.dbo.sp_add_alert @name=N'Severity 22+', 
		@message_id=0, 
		@severity=22, 
		@enabled=1, 
		@delay_between_responses=600, 
		@include_event_description_in=1, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000';

EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 823', @operator_name=N'AzureOps', @notification_method = 1;
EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 824', @operator_name=N'AzureOps', @notification_method = 1;
EXEC msdb.dbo.sp_add_notification @alert_name=N'Error 825', @operator_name=N'AzureOps', @notification_method = 1;
EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity 22+', @operator_name=N'AzureOps', @notification_method = 1;

PRINT 'Configure SQL Agent properties...';

EXEC msdb.dbo.sp_set_sqlagent_properties @jobhistory_max_rows=100000, @jobhistory_max_rows_per_job=1000;

GO

USE DBA_Local;

PRINT 'Creating GetActiveRequests stored procedure...';
GO
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'GetActiveRequests' AND type = 'P')
	DROP PROCEDURE dbo.GetActiveRequests;
GO
CREATE PROCEDURE dbo.GetActiveRequests
AS
SET NOCOUNT ON;

SELECT r.session_id,
       s.login_time,
       r.start_time,
       r.total_elapsed_time / 1000 AS elapsed_time_seconds,
       r.status,
       r.command,
       CAST(st.stmt AS xml) AS statement,
       NULLIF(r.blocking_session_id, 0) AS blocking_session_id,
       r.wait_type,
       r.wait_time,
       r.wait_resource,
       qp.query_plan,
       qp.plan_object_name,
       r.open_transaction_count,
       r.percent_complete,
       r.cpu_time,
       r.logical_reads,
       r.reads,
       r.writes,
       CASE r.transaction_isolation_level
            WHEN 0 THEN 'Unspecified'
            WHEN 1 THEN 'Read uncommitted'
            WHEN 2 THEN 'Read committed'
            WHEN 3 THEN 'Repeatable read'
            WHEN 4 THEN 'Serializable'
            WHEN 5 THEN 'Snapshot'
       END
       AS transaction_isolation_level,
       r.row_count,
       s.program_name,
       r.granted_query_memory * 8 AS memory_grant_kb,
       mg.requested_memory_kb,
       mg.max_used_memory_kb,
       t.task_count
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
ON r.session_id = s.session_id
OUTER APPLY (
            SELECT SUBSTRING(
                            text, r.statement_start_offset / 2 + 1,
                            (
                            CASE WHEN r.statement_end_offset = -1
                                 THEN LEN(CONVERT(nvarchar(max), text)) * 2
                                 ELSE r.statement_end_offset
                            END 
                            - r.statement_start_offset
                            ) / 2
                            ) AS [processing-instruction(stmt)]
            FROM sys.dm_exec_sql_text(r.sql_handle)
            FOR XML PATH('')
            ) AS st (stmt)
OUTER APPLY (
            SELECT query_plan,
                   OBJECT_NAME(objectid, dbid) AS plan_object_name
            FROM sys.dm_exec_query_plan(r.plan_handle)
            ) AS qp
OUTER APPLY (
            SELECT COUNT(1) AS task_count
            FROM sys.dm_os_tasks AS t
            WHERE t.session_id = s.session_id
                  AND
                  t.request_id = r.request_id
            ) AS t
LEFT JOIN sys.dm_exec_query_memory_grants AS mg
ON mg.session_id = r.session_id
   AND
   mg.request_id = r.request_id
WHERE r.session_id <> @@SPID
      AND
      s.is_user_process = 1
ORDER BY start_time
;
GO


PRINT 'Configuration complete. Restart SQL Server service to enable.'
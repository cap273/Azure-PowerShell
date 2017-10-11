--15_SQL_TempDB_Configuration
USE master
SET NOCOUNT ON
GO

-- Edit Values of variables file

DECLARE	@TargetDataFilesLocation	varchar(100)
DECLARE	@TargetDataSizeMB			varchar(100)
DECLARE	@TargetDataFilegrowthMB		varchar(100)
DECLARE	@TargetTlogFilesLocation	varchar(100)
DECLARE	@TargetTlogSizeMB			varchar(100)
DECLARE	@TargetTlogFilegrowthMB		varchar(100)
DECLARE @VerifyOnly					char(1) = 'N'	-- 'Y' - only needed commands will be displayed, no action taken; 'N' - neccessary commands will be executed

SELECT @TargetDataFilesLocation = '$(TargetDataFilesLocation)'
SELECT @TargetDataSizeMB = '$(TargetDataSizeMB)'
SELECT @TargetDataFilegrowthMB = '$(TargetDataFilegrowthMB)'
SELECT @TargetTlogFilesLocation = '$(TargetTlogFilesLocation)'
SELECT @TargetTlogSizeMB = '$(TargetTlogSizeMB)'
SELECT @TargetTlogFilegrowthMB = '$(TargetTlogFilegrowthMB)'


--DO NOT MODIFY BELOW THIS LINE !!!
-----------------------------------------------------------------------------------

IF RIGHT(@TargetDataFilesLocation,1) <> '\'
	SET @TargetDataFilesLocation =  @TargetDataFilesLocation + '\'
IF RIGHT(@TargetTlogFilesLocation,1) <> '\'
	SET @TargetTlogFilesLocation =  @TargetTlogFilesLocation + '\'

DECLARE @iTargetDataSizeMB	int
DECLARE @iTargetTlogSizeMB  int
DECLARE @iTargetDataFilegrowthMB	int
DECLARE @iTargetTlogFilegrowthMB	int
SELECT	@iTargetDataSizeMB = CONVERT(int,REPLACE(REPLACE(@TargetDataSizeMB,'MB',''),',',''))
SELECT	@iTargetTlogSizeMB = CONVERT(int,REPLACE(REPLACE(@TargetTlogSizeMB,'MB',''),',',''))
SELECT	@iTargetDataFilegrowthMB = CONVERT(int,REPLACE(REPLACE(@TargetDataFilegrowthMB,'MB',''),',',''))
SELECT	@iTargetTlogFilegrowthMB = CONVERT(int,REPLACE(REPLACE(@TargetTlogFilegrowthMB,'MB',''),',',''))



--Get initial size of model database
DECLARE	@modelDataFileSizeMB	int
SELECT @modelDataFileSizeMB = 
	CEILING((size*8)/1024.0) -- as modelDataFileSizeMB
FROM sys.master_files 
WHERE database_id = DB_ID('model') AND type_desc = 'ROWS'


/*
IF EXISTS (SELECT * from tempdb..sysobjects WHERE name like '%TempDBCurrentConfig%' AND type = 'U')
	DROP TABLE #TempDBCurrentConfig;


CREATE TABLE #TempDBCurrentConfig (		*/
DECLARE @TempDBCurrentConfig TABLE (
	file_id			int,
	type			int,
	type_desc		varchar(10),
	name			varchar(50),
	physical_name	varchar(200),
	sizeMB			int,
	max_size		int,
	growth			int,
	is_percent_growth	bit,
	rownumber		int 
)			
--INSERT #TempDBCurrentConfig (file_id,type,type_desc,name,physical_name,sizeMB,max_size,growth,is_percent_growth,rownumber)
INSERT @TempDBCurrentConfig (file_id,type,type_desc,name,physical_name,sizeMB,max_size,growth,is_percent_growth,rownumber)
SELECT file_id,type,type_desc,name,physical_name,
	CEILING((size*8)/1024.0) as sizeMB,
	max_size,growth,is_percent_growth
	,row_number() over(partition by type order by file_id) as rownumber
FROM sys.master_files 
WHERE database_id = DB_ID('tempdb') 
ORDER BY type asc,file_id asc

--select * from @TempDBCurrentConfig

DECLARE @restartNeeded				bit = 0
DECLARE @tempdbDataFileCount		int;
DECLARE @suggestedDataFilecount		int;

SELECT @tempdbDataFileCount = COUNT(*) FROM sys.master_files 
WHERE database_id = DB_ID('tempdb') AND type_desc = 'ROWS';
PRINT N'Count of tempdb data files = ' + CONVERT(nvarchar(10), @tempdbDataFileCount);

-- suggests ideal number of tempdb data files (subject to testing)

SELECT @suggestedDataFilecount = CASE 
	WHEN cpu_count <= 8 THEN cpu_count 
	WHEN cpu_count BETWEEN 9 AND 16 THEN 8
	ELSE cpu_count / 2 END  
FROM sys.dm_os_sys_info;

--SELECT @suggestedDataFilecount = 1

DECLARE	@DataFilesOperation	int
SET	@DataFilesOperation = @suggestedDataFilecount - @tempdbDataFileCount
IF @DataFilesOperation = 0 
BEGIN
	PRINT N'Server has correct number of tempdb data files (' + CONVERT(varchar(10), @suggestedDataFilecount) + ')'
END 
IF @DataFilesOperation < 0 
BEGIN
	PRINT N'Server has too many tempdb data files (' + CONVERT(varchar(10), @tempdbDataFileCount) + '). Recommended value are ' + CONVERT(varchar(10), @suggestedDataFilecount)
END 
IF @DataFilesOperation > 0 
BEGIN
	PRINT N'Server has insufficient number of tempdb data files (' + CONVERT(varchar(10), @tempdbDataFileCount) + '). Recommended value are ' + CONVERT(varchar(10), @suggestedDataFilecount)
END 


DECLARE @rowcnt int
DECLARE @curr int = 1
DECLARE	@DataFilesLocation	varchar(100)
DECLARE @sizeMB				int
DECLARE @filename			varchar(50)
DECLARE @is_percent_growth	bit
DECLARE @DataFilegrowthMB	int

DECLARE @curr_String	varchar(max)
--DECLARE @bContinue		bit = 1
DECLARE @errmsg				varchar(max)


WHILE @curr <= (CASE WHEN @DataFilesOperation >= 0 THEN @tempdbDataFileCount ELSE @suggestedDataFilecount End)
BEGIN
	SELECT	@DataFilesLocation = LEFT(physical_name,LEN(physical_name)+1-CHARINDEX('\',REVERSE(physical_name))) 
			,@sizeMB		= sizeMB
			,@filename		= name
			,@is_percent_growth = is_percent_growth
			,@DataFilegrowthMB	= CASE WHEN is_percent_growth = 1 THEN growth ELSE CEILING((growth*8)/1024.0) End
	FROM @TempDBCurrentConfig WHERE rownumber = @curr AND type = 0
--	FROM #TempDBCurrentConfig WHERE rownumber = @curr AND type = 0
	IF (@modelDataFileSizeMB > @iTargetDataSizeMB) AND (@curr = 1)
	BEGIN
		PRINT 'Size of 1st data file for TempDB (' + @filename + ') is ' + LTRIM(STR(@iTargetDataSizeMB)) + 'MB and cannot be less than size of data file for model database (' + LTRIM(STR(@modelDataFileSizeMB)) + 'MB). Either change size of model database or increase initial size for data files for TempDB'
		IF @suggestedDataFilecount > 1
			PRINT 'Microsoft recommends that all data files for TempDB have the same size'
		GOTO Endd
	END

	IF (@DataFilesLocation <> @TargetDataFilesLocation) OR (@sizeMB <> @iTargetDataSizeMB) OR (@is_percent_growth = 1) OR (@is_percent_growth = 0 AND @DataFilegrowthMB <> @iTargetDataFilegrowthMB) 
	BEGIN	
		SET @curr_String = 'USE master; 
ALTER DATABASE tempdb MODIFY FILE (NAME=N''' + @filename + ''', FILENAME = N''' + @TargetDataFilesLocation + @filename + CASE WHEN @curr = 1 THEN '.mdf' ELSE '.ndf' END + ''', SIZE = ' + @TargetDataSizeMB + ', FILEGROWTH = ' + @TargetDataFilegrowthMB + ')'
		PRINT 'Executes Command: ' + @curr_String
		BEGIN TRY
			IF @VerifyOnly = 'N'
				EXEC (@curr_String)
			SET @restartNeeded = 1
		END TRY
		BEGIN CATCH
			SELECT @errmsg = (SELECT ERROR_MESSAGE())
			PRINT  'There was an error executing command: ' + @errmsg     
			GOTO Endd 
		END CATCH
	END
	SET @curr = @curr + 1
END

IF @DataFilesOperation > 0 
BEGIN
	SET @curr = @tempdbDataFileCount + 1
	WHILE @curr <= @suggestedDataFilecount
	BEGIN
		SET @filename = 'tempdev_' + LTRIM(STR(@curr))
		SET @curr_String = 'USE master; 
ALTER DATABASE tempdb ADD FILE (NAME=N''' + @filename + ''', FILENAME = N''' + @TargetDataFilesLocation + @filename + '.ndf'', SIZE = ' + @TargetDataSizeMB + ', FILEGROWTH = ' + @TargetDataFilegrowthMB + ')'
		PRINT 'Executes Command: ' + @curr_String
		BEGIN TRY
			IF @VerifyOnly = 'N'
				EXEC (@curr_String)
			SET @restartNeeded = 1
		END TRY
		BEGIN CATCH
			SELECT @errmsg = (SELECT ERROR_MESSAGE())
			PRINT  'There was an error executing command: ' + @errmsg    
			GOTO Endd 
		END CATCH
		SET @curr = @curr + 1
	END
END

IF @DataFilesOperation < 0 
BEGIN
	SET @curr = @suggestedDataFilecount  + 1
	WHILE @curr <= @tempdbDataFileCount
	BEGIN
		SELECT	@filename		= name
		FROM @TempDBCurrentConfig WHERE rownumber = @curr AND type = 0
--		FROM #TempDBCurrentConfig WHERE rownumber = @curr AND type = 0

		SET @curr_String = 'USE tempdb; 
DBCC SHRINKFILE(''' + @filename + ''', EMPTYFILE)'
		BEGIN TRY
			PRINT 'Executes Command: ' + @curr_String
			IF @VerifyOnly = 'N'
				EXEC (@curr_String)
--			SET @restartNeeded = 1
			SET @curr_String = 'USE master; 
ALTER DATABASE tempdb REMOVE FILE ' + @filename 
			PRINT 'Executes Command: ' + @curr_String
			IF @VerifyOnly = 'N'
				EXEC (@curr_String)
		END TRY
		BEGIN CATCH
			SELECT @errmsg = (SELECT ERROR_MESSAGE())
			PRINT  'There was an error executing command: ' + @errmsg  
			PRINT  'You may try to restart SQL Server and remove extra data files manually'
			SET @restartNeeded = 1
			GOTO Endd 
		END CATCH
		SET @curr = @curr + 1
	END
END

DECLARE @tempdbTlogFileCount int
SELECT @tempdbTlogFileCount = COUNT(*) FROM sys.master_files 
WHERE database_id = DB_ID('tempdb') AND type_desc = 'LOG';

PRINT N'Count of tempdb log files = ' + CONVERT(nvarchar(10), @tempdbTlogFileCount);

SET @curr = 1
WHILE @curr <= @tempdbTlogFileCount
BEGIN
	SELECT	@DataFilesLocation = LEFT(physical_name,LEN(physical_name)+1-CHARINDEX('\',REVERSE(physical_name))) 
			,@sizeMB		= sizeMB
			,@filename		= name
			,@is_percent_growth = is_percent_growth
			,@DataFilegrowthMB	= CASE WHEN is_percent_growth = 1 THEN growth ELSE CEILING((growth*8)/1024.0) End
	FROM @TempDBCurrentConfig WHERE rownumber = @curr AND type = 1	
--	FROM #TempDBCurrentConfig WHERE rownumber = @curr AND type = 1	
	IF (@DataFilesLocation <> @TargetTlogFilesLocation) OR (@sizeMB <> @iTargetTlogSizeMB) OR (@is_percent_growth = 1) OR (@is_percent_growth = 0 AND @DataFilegrowthMB <> @iTargetTlogFilegrowthMB) 
	BEGIN
		SET @curr_String = 'USE master; 
ALTER DATABASE tempdb MODIFY FILE (NAME=N''' + @filename + ''', FILENAME = N''' + @TargetTlogFilesLocation + @filename + '.ldf'', SIZE = ' + @TargetTlogSizeMB + ', FILEGROWTH = ' + @TargetTlogFilegrowthMB + ')'
		PRINT 'Executes Command: ' + @curr_String
		BEGIN TRY
			IF @VerifyOnly = 'N'
				EXEC (@curr_String)
			SET @restartNeeded = 1
		END TRY
		BEGIN CATCH
			SELECT @errmsg = (SELECT ERROR_MESSAGE())
			PRINT  'There was an error executing command: ' + @errmsg    
			GOTO Endd 
		END CATCH
	END
	SET @curr = @curr + 1
END

Endd:
PRINT 'Completed...'	
IF @restartNeeded = 1
BEGIN
	IF @VerifyOnly = 'N'	
		PRINT 'Please restart the server for changes took effect'
	ELSE
		PRINT 'Restarting the server will be needed (if executed) for changes take effect'
END

--select * from sys.master_files WHERE database_id = DB_ID('tempdb') AND type_desc = 'ROWS';

/*
database_id file_id     file_guid                            type type_desc                                                    data_space_id name                                                                                                                             physical_name                                                                                                                                                                                                                                                    state state_desc                                                   size        max_size    growth      is_media_read_only is_read_only is_sparse is_percent_growth is_name_reserved create_lsn                              drop_lsn                                read_only_lsn                           read_write_lsn                          differential_base_lsn                   differential_base_guid               differential_base_time  redo_start_lsn                          redo_start_fork_guid                 redo_target_lsn                         redo_target_fork_guid                backup_lsn                              credential_id
----------- ----------- ------------------------------------ ---- ------------------------------------------------------------ ------------- -------------------------------------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- ----- ------------------------------------------------------------ ----------- ----------- ----------- ------------------ ------------ --------- ----------------- ---------------- --------------------------------------- --------------------------------------- --------------------------------------- --------------------------------------- --------------------------------------- ------------------------------------ ----------------------- --------------------------------------- ------------------------------------ --------------------------------------- ------------------------------------ --------------------------------------- -------------
2           1           NULL                                 0    ROWS                                                         1             tempdev                                                                                                                          F:\TempDB\tempdb.mdf                                                                                                                                                                                                                                             0     ONLINE                                                       1024        -1          10          0                  0            0         1                 0                NULL                                    NULL                                    NULL                                    NULL                                    NULL                                    NULL                                 NULL                    NULL                                    NULL                                 NULL                                    NULL                                 NULL                                    NULL
2           2           NULL                                 1    LOG                                                          0             templog                                                                                                                          J:\TempDBLog\templog.ldf                                                                                                                                                                                                                                         0     ONLINE                                                       64          -1          10          0                  0            0         1                 0                NULL                                    NULL                                    NULL                                    NULL                                    NULL                                    NULL                                 NULL                    NULL                                    NULL                                 NULL                                    NULL                                 NULL                                    NULL
*/

-- Run as an authorized operator. The SQL Server service account needs access
-- to the instance backup directory. Select FULL or DIFF when scheduling separately.
USE [EV_B_TEST];
GO

SET NOCOUNT ON;
DECLARE @mode VARCHAR(4) = 'BOTH';
DECLARE @directory NVARCHAR(4000) = CONVERT(NVARCHAR(4000), SERVERPROPERTY('InstanceDefaultBackupPath'));
IF NULLIF(@directory, N'') IS NULL
    THROW 52720, N'Configure a SQL Server backup directory before running this script.', 1;
IF RIGHT(@directory, 1) NOT IN (N'\', N'/')
    SET @directory += N'\';

DECLARE @suffix NVARCHAR(36) = CONVERT(NVARCHAR(36), NEWID());
DECLARE @full_file NVARCHAR(4000) = CONCAT(@directory, N'EV_B_TEST_full_', @suffix, N'.bak');
DECLARE @diff_file NVARCHAR(4000) = CONCAT(@directory, N'EV_B_TEST_diff_', @suffix, N'.bak');
IF @mode NOT IN ('FULL', 'DIFF', 'BOTH')
    THROW 52721, N'Backup mode must be FULL, DIFF or BOTH.', 1;

IF @mode IN ('FULL', 'BOTH')
BEGIN
    -- A regular full backup establishes the base for subsequent differentials.
    BACKUP DATABASE [EV_B_TEST] TO DISK = @full_file WITH CHECKSUM;
    RESTORE VERIFYONLY FROM DISK = @full_file WITH CHECKSUM;
    SELECT @full_file AS full_backup;
END;

IF @mode IN ('DIFF', 'BOTH')
BEGIN
    BACKUP DATABASE [EV_B_TEST] TO DISK = @diff_file WITH DIFFERENTIAL, CHECKSUM;
    RESTORE VERIFYONLY FROM DISK = @diff_file WITH CHECKSUM;
    SELECT @diff_file AS differential_backup;
END;
GO

/*
仅在隔离实例和专用演练库执行。先用 RESTORE FILELISTONLY 核对逻辑文件名，
用 RESTORE HEADERONLY 核对差异备份对应的全量基线，替换以下路径和逻辑名。
USE [master];
RESTORE DATABASE [EV_B_RESTORE_DRILL]
FROM DISK = N'<完整备份路径>'
WITH REPLACE, NORECOVERY, CHECKSUM,
     MOVE N'<逻辑数据文件名>' TO N'<独立演练数据文件路径>',
     MOVE N'<逻辑日志文件名>' TO N'<独立演练日志文件路径>';
RESTORE DATABASE [EV_B_RESTORE_DRILL]
FROM DISK = N'<匹配的差异备份路径>'
WITH RECOVERY, CHECKSUM;
DBCC CHECKDB (N'EV_B_RESTORE_DRILL') WITH NO_INFOMSGS;
*/

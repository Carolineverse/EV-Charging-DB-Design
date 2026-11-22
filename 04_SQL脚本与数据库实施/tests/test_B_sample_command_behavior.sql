SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51000, 'This test must run in EV_B_TEST.', 1;

DECLARE @Token VARCHAR(32) = REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '');
DECLARE @OperatorId VARCHAR(20) = 'BMOP' + LEFT(@Token, 16);
DECLARE @StationId VARCHAR(20) = 'BMST' + LEFT(@Token, 16);
DECLARE @PileId VARCHAR(20) = 'BMPL' + LEFT(@Token, 16);
DECLARE @GunId VARCHAR(20) = 'BMGN' + LEFT(@Token, 16);
DECLARE @UserId VARCHAR(20) = 'BTUSER' + LEFT(@Token, 14);
DECLARE @NoticeAccountId BIGINT = 1;
DECLARE @OrderId BIGINT;
DECLARE @SecondOrderId BIGINT;
DECLARE @Passed INT = 0;
DECLARE @Failed INT = 0;
DECLARE @CleanupOk BIT = 0;
DECLARE @CaughtError INT;
DECLARE @ReportPeriodic1 VARCHAR(50) = 'BMR-' + @Token + '-P1';
DECLARE @ReportPeriodic2 VARCHAR(50) = 'BMR-' + @Token + '-P2';
DECLARE @ReportStart1 VARCHAR(50) = 'BMR-' + @Token + '-S1';
DECLARE @ReportStart2 VARCHAR(50) = 'BMR-' + @Token + '-S2';
DECLARE @ReportStart3 VARCHAR(50) = 'BMR-' + @Token + '-S3';
DECLARE @ReportEnd1 VARCHAR(50) = 'BMR-' + @Token + '-E1';
DECLARE @ReportEnd2 VARCHAR(50) = 'BMR-' + @Token + '-E2';
DECLARE @EventId VARCHAR(64) = 'BME-' + @Token;
DECLARE @Hash CHAR(64) = REPLICATE('a', 64);
DECLARE @Now DATETIME2(3) = SYSDATETIME();
DECLARE @NoticeFkExists BIT = 0;
DECLARE @UserFkExists BIT = 0;
DECLARE @ReportFkExists BIT = 0;

IF OBJECT_ID(N'dbo.ChargingOrder', N'U') IS NULL
   OR OBJECT_ID(N'dbo.ChargingMeterSample', N'U') IS NULL
   OR OBJECT_ID(N'dbo.OrderCommand', N'U') IS NULL
    THROW 51001, 'Required B tables are missing from EV_B_TEST.', 1;

IF EXISTS (
    SELECT 1
    FROM sys.foreign_key_columns AS fkc
    JOIN sys.columns AS c
      ON c.object_id = fkc.parent_object_id
     AND c.column_id = fkc.parent_column_id
    JOIN sys.tables AS rt
      ON rt.object_id = fkc.referenced_object_id
    WHERE fkc.parent_object_id = OBJECT_ID(N'dbo.ChargingStation')
      AND c.name = N'workorder_notice_account_id'
      AND rt.name = N'SysAccount'
)
    SET @NoticeFkExists = 1;

IF @NoticeFkExists = 1
BEGIN
    SET @NoticeAccountId = NULL;
    EXEC sys.sp_executesql
        N'SELECT TOP (1) @value = account_id FROM dbo.SysAccount ORDER BY account_id;',
        N'@value BIGINT OUTPUT',
        @value = @NoticeAccountId OUTPUT;

    IF @NoticeAccountId IS NULL
        THROW 51002, 'Seed a shared SysAccount before running this B test.', 1;
END;

IF EXISTS (
    SELECT 1
    FROM sys.foreign_key_columns AS fkc
    JOIN sys.columns AS c
      ON c.object_id = fkc.parent_object_id
     AND c.column_id = fkc.parent_column_id
    JOIN sys.tables AS rt
      ON rt.object_id = fkc.referenced_object_id
    WHERE fkc.parent_object_id = OBJECT_ID(N'dbo.ChargingOrder')
      AND c.name = N'user_id'
      AND rt.name = N'UserProfile'
)
    SET @UserFkExists = 1;

IF @UserFkExists = 1
BEGIN
    SET @UserId = NULL;
    EXEC sys.sp_executesql
        N'SELECT TOP (1) @value = user_id FROM dbo.UserProfile ORDER BY user_id;',
        N'@value VARCHAR(20) OUTPUT',
        @value = @UserId OUTPUT;

    IF @UserId IS NULL
        THROW 51003, 'Seed a shared UserProfile before running this B test.', 1;
END;

CREATE TABLE #Reports
(
    report_no TINYINT IDENTITY(1,1) PRIMARY KEY,
    report_id VARCHAR(50) NOT NULL UNIQUE
);

IF EXISTS (
    SELECT 1
    FROM sys.foreign_key_columns AS fkc
    JOIN sys.columns AS c
      ON c.object_id = fkc.parent_object_id
     AND c.column_id = fkc.parent_column_id
    JOIN sys.tables AS rt
      ON rt.object_id = fkc.referenced_object_id
    WHERE fkc.parent_object_id = OBJECT_ID(N'dbo.ChargingMeterSample')
      AND c.name = N'report_id'
      AND rt.name = N'DeviceReport'
)
    SET @ReportFkExists = 1;

IF @ReportFkExists = 1
BEGIN
    IF OBJECT_ID(N'dbo.DeviceReport', N'U') IS NULL
        THROW 51004, 'The DeviceReport table required by an active FK is missing.', 1;

    INSERT INTO #Reports (report_id)
    EXEC sys.sp_executesql
        N'SELECT DISTINCT TOP (7) report_id FROM dbo.DeviceReport ORDER BY report_id;';

    IF (SELECT COUNT(*) FROM #Reports) < 7
        THROW 51005, 'Seed at least seven DeviceReport rows before running this B test.', 1;
END
ELSE
    INSERT INTO #Reports (report_id)
    VALUES
        (@ReportPeriodic1), (@ReportPeriodic2), (@ReportStart1),
        (@ReportStart2), (@ReportStart3), (@ReportEnd1), (@ReportEnd2);

SELECT @ReportPeriodic1 = report_id FROM #Reports WHERE report_no = 1;
SELECT @ReportPeriodic2 = report_id FROM #Reports WHERE report_no = 2;
SELECT @ReportStart1 = report_id FROM #Reports WHERE report_no = 3;
SELECT @ReportStart2 = report_id FROM #Reports WHERE report_no = 4;
SELECT @ReportStart3 = report_id FROM #Reports WHERE report_no = 5;
SELECT @ReportEnd1 = report_id FROM #Reports WHERE report_no = 6;
SELECT @ReportEnd2 = report_id FROM #Reports WHERE report_no = 7;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'B 采样与命令测试临时运营商');

    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'B 采样与命令测试临时场站', N'事务内测试数据',
         0, 0, @OperatorId, 1, N'00:00-24:00', N'测试', @NoticeAccountId);

    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw,
         communication_protocol, commissioned_date, warranty_end_date)
    VALUES
        (@PileId, @StationId, N'B-test', 60, N'OCPP', CONVERT(date, @Now),
         DATEADD(year, 1, CONVERT(date, @Now)));

    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard, max_output_power_kw)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 60);

    IF @UserFkExists = 0
        SET @UserId = 'BTUSER' + LEFT(@Token, 14);

    INSERT INTO dbo.ChargingOrder (user_id, gun_id, opening_station_id)
    VALUES (@UserId, @GunId, @StationId);
    SET @OrderId = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.ChargingOrder (user_id, gun_id, opening_station_id)
    VALUES (@UserId, @GunId, @StationId);
    SET @SecondOrderId = CONVERT(BIGINT, SCOPE_IDENTITY());

    -- A duplicate delivery must not replace the first sample.
    INSERT INTO dbo.ChargingMeterSample
        (order_id, device_session_no, report_id, collected_at, cumulative_kwh,
         sample_type, validation_status)
    VALUES
        (@OrderId, 'SESSION-' + @Token, @ReportPeriodic1, @Now, 1.000,
         'PERIODIC', 'VALID');
    SET @Passed += 1;

    BEGIN TRY
        INSERT INTO dbo.ChargingMeterSample
            (order_id, device_session_no, report_id, collected_at, cumulative_kwh,
             sample_type, validation_status, invalid_reason)
        VALUES
            (@OrderId, 'SESSION-' + @Token, @ReportPeriodic1, DATEADD(second, 1, @Now),
             NULL, 'PERIODIC', 'INVALID', N'重复报文');
        SET @Failed += 1;
        PRINT N'失败：同一报文重复投递未被拒绝';
    END TRY
    BEGIN CATCH
        SET @CaughtError = ERROR_NUMBER();
        IF @CaughtError IN (2601, 2627)
            SET @Passed += 1;
        ELSE
        BEGIN
            SET @Failed += 1;
            PRINT N'失败：重复报文返回意外错误 ' + ERROR_MESSAGE();
        END;
    END CATCH;

    IF EXISTS (
        SELECT 1 FROM dbo.ChargingMeterSample
        WHERE order_id = @OrderId
          AND report_id = @ReportPeriodic1
          AND sample_type = 'PERIODIC'
          AND validation_status = 'VALID'
          AND cumulative_kwh = 1.000
    )
        SET @Passed += 1;
    ELSE
    BEGIN
        SET @Failed += 1;
        PRINT N'失败：重复投递改变了原样本';
    END;

    -- A different invalid report is retained independently.
    INSERT INTO dbo.ChargingMeterSample
        (order_id, device_session_no, report_id, collected_at, cumulative_kwh,
         sample_type, validation_status, invalid_reason)
    VALUES
        (@OrderId, 'SESSION-' + @Token, @ReportPeriodic2, DATEADD(second, 2, @Now),
         NULL, 'PERIODIC', 'INVALID', N'缺少累计读数');
    SET @Passed += 1;

    BEGIN TRY
        INSERT INTO dbo.ChargingMeterSample
            (order_id, device_session_no, report_id, collected_at, cumulative_kwh,
             sample_type, validation_status, invalid_reason)
        VALUES
            (@OrderId, 'SESSION-' + @Token, 'BMR-' + @Token + '-BAD', DATEADD(second, 3, @Now),
             NULL, 'PERIODIC', 'INVALID', N'   ');
        SET @Failed += 1;
        PRINT N'失败：空白无效原因未被拒绝';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547
            SET @Passed += 1;
        ELSE
        BEGIN
            SET @Failed += 1;
            PRINT N'失败：空白无效原因返回意外错误 ' + ERROR_MESSAGE();
        END;
    END CATCH;

    -- Each order may have one valid START and END; invalid points do not occupy them.
    INSERT INTO dbo.ChargingMeterSample
        (order_id, device_session_no, report_id, collected_at, cumulative_kwh,
         sample_type, validation_status)
    VALUES
        (@OrderId, 'SESSION-' + @Token, @ReportStart1, @Now, 0, 'START', 'VALID');
    SET @Passed += 1;

    INSERT INTO dbo.ChargingMeterSample
        (order_id, device_session_no, report_id, collected_at, cumulative_kwh,
         sample_type, validation_status, invalid_reason)
    VALUES
        (@OrderId, 'SESSION-' + @Token, @ReportStart2, DATEADD(second, 1, @Now),
         NULL, 'START', 'INVALID', N'实测枪号=TEST-OTHER-GUN；与订单不匹配');
    SET @Passed += 1;

    IF EXISTS (
        SELECT 1 FROM dbo.ChargingMeterSample
        WHERE order_id = @OrderId
          AND report_id = @ReportStart2
          AND invalid_reason LIKE N'%TEST-OTHER-GUN%'
    )
        SET @Passed += 1;
    ELSE
    BEGIN
        SET @Failed += 1;
        PRINT N'失败：无效样本未保留实测枪号和原因';
    END;

    BEGIN TRY
        INSERT INTO dbo.ChargingMeterSample
            (order_id, device_session_no, report_id, collected_at, cumulative_kwh,
             sample_type, validation_status)
        VALUES
            (@OrderId, 'SESSION-' + @Token, @ReportStart3, DATEADD(second, 2, @Now),
             0, 'START', 'VALID');
        SET @Failed += 1;
        PRINT N'失败：同一订单出现第二条有效 START';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            SET @Passed += 1;
        ELSE
        BEGIN
            SET @Failed += 1;
            PRINT N'失败：重复有效 START 返回意外错误 ' + ERROR_MESSAGE();
        END;
    END CATCH;

    INSERT INTO dbo.ChargingMeterSample
        (order_id, device_session_no, report_id, collected_at, cumulative_kwh,
         sample_type, validation_status)
    VALUES
        (@OrderId, 'SESSION-' + @Token, @ReportEnd1, DATEADD(second, 3, @Now),
         1.000, 'END', 'VALID');
    SET @Passed += 1;

    BEGIN TRY
        INSERT INTO dbo.ChargingMeterSample
            (order_id, device_session_no, report_id, collected_at, cumulative_kwh,
             sample_type, validation_status)
        VALUES
            (@OrderId, 'SESSION-' + @Token, @ReportEnd2, DATEADD(second, 4, @Now),
             1.100, 'END', 'VALID');
        SET @Failed += 1;
        PRINT N'失败：同一订单出现第二条有效 END';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            SET @Passed += 1;
        ELSE
        BEGIN
            SET @Failed += 1;
            PRINT N'失败：重复有效 END 返回意外错误 ' + ERROR_MESSAGE();
        END;
    END CATCH;

    -- A pending command has no result fields; final commands require a complete result.
    INSERT INTO dbo.OrderCommand (order_id, command_type, status, created_at, deadline_at)
    VALUES (@OrderId, 'START', 'PENDING', @Now, DATEADD(minute, 5, @Now));
    SET @Passed += 1;

    BEGIN TRY
        INSERT INTO dbo.OrderCommand (order_id, command_type, status, created_at, deadline_at)
        VALUES (@OrderId, 'START', 'PENDING', @Now, DATEADD(minute, 5, @Now));
        SET @Failed += 1;
        PRINT N'失败：同一订单重复创建 START 命令';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            SET @Passed += 1;
        ELSE
        BEGIN
            SET @Failed += 1;
            PRINT N'失败：重复 START 命令返回意外错误 ' + ERROR_MESSAGE();
        END;
    END CATCH;

    BEGIN TRY
        INSERT INTO dbo.OrderCommand (order_id, command_type, status, created_at, deadline_at)
        VALUES (@OrderId, 'STOP', 'CONFIRMED', @Now, DATEADD(minute, 5, @Now));
        SET @Failed += 1;
        PRINT N'失败：结果字段缺失的 CONFIRMED 命令被接受';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547
            SET @Passed += 1;
        ELSE
        BEGIN
            SET @Failed += 1;
            PRINT N'失败：不完整命令返回意外错误 ' + ERROR_MESSAGE();
        END;
    END CATCH;

    BEGIN TRY
        INSERT INTO dbo.OrderCommand
            (order_id, command_type, status, created_at, deadline_at,
             processed_event_id, result_hash, result_snapshot)
        VALUES
            (@OrderId, 'STOP', 'CONFIRMED', @Now, DATEADD(minute, 5, @Now),
             @EventId, @Hash, N'{"result":"ok"}');
        SET @Failed += 1;
        PRINT N'失败：缺少 confirmed_at 的 CONFIRMED 命令被接受';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547
            SET @Passed += 1;
        ELSE
        BEGIN
            SET @Failed += 1;
            PRINT N'失败：缺少确认时间返回意外错误 ' + ERROR_MESSAGE();
        END;
    END CATCH;

    BEGIN TRY
        INSERT INTO dbo.OrderCommand
            (order_id, command_type, status, created_at, deadline_at,
             processed_event_id, result_hash, result_snapshot)
        VALUES
            (@OrderId, 'STOP', 'FAILED', @Now, DATEADD(minute, 5, @Now),
             @EventId, @Hash, N'{bad json');
        SET @Failed += 1;
        PRINT N'失败：非法 JSON 结果快照被接受';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547
            SET @Passed += 1;
        ELSE
        BEGIN
            SET @Failed += 1;
            PRINT N'失败：非法 JSON 返回意外错误 ' + ERROR_MESSAGE();
        END;
    END CATCH;

    BEGIN TRY
        INSERT INTO dbo.OrderCommand
            (order_id, command_type, status, created_at, deadline_at,
             processed_event_id, result_hash, result_snapshot)
        VALUES
            (@OrderId, 'STOP', 'FAILED', @Now, DATEADD(minute, 5, @Now),
             @EventId, REPLICATE('A', 64), N'{"result":"ok"}');
        SET @Failed += 1;
        PRINT N'失败：大写摘要被接受';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547
            SET @Passed += 1;
        ELSE
        BEGIN
            SET @Failed += 1;
            PRINT N'失败：非法摘要返回意外错误 ' + ERROR_MESSAGE();
        END;
    END CATCH;

    INSERT INTO dbo.OrderCommand
        (order_id, command_type, status, created_at, deadline_at, confirmed_at,
         processed_event_id, result_hash, result_snapshot)
    VALUES
        (@OrderId, 'STOP', 'CONFIRMED', @Now, DATEADD(minute, 5, @Now), @Now,
         @EventId, @Hash, N'{"result":"ok"}');
    SET @Passed += 1;

    BEGIN TRY
        INSERT INTO dbo.OrderCommand
            (order_id, command_type, status, created_at, deadline_at,
             processed_event_id, result_hash, result_snapshot)
        VALUES
            (@SecondOrderId, 'START', 'FAILED', @Now, DATEADD(minute, 5, @Now),
             @EventId, @Hash, N'{"result":"ok"}');
        SET @Failed += 1;
        PRINT N'失败：已处理事件编号重复';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            SET @Passed += 1;
        ELSE
        BEGIN
            SET @Failed += 1;
            PRINT N'失败：重复事件编号返回意外错误 ' + ERROR_MESSAGE();
        END;
    END CATCH;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    SET @Failed += 1;
    PRINT N'测试准备或执行失败：' + ERROR_MESSAGE();
END CATCH;

SET @CleanupOk = CASE
    WHEN NOT EXISTS (SELECT 1 FROM dbo.Operator WHERE operator_id = @OperatorId)
     AND NOT EXISTS (SELECT 1 FROM dbo.ChargingStation WHERE station_id = @StationId)
     AND NOT EXISTS (SELECT 1 FROM dbo.ChargingPile WHERE pile_id = @PileId)
     AND NOT EXISTS (SELECT 1 FROM dbo.ChargingGun WHERE gun_id = @GunId)
     AND NOT EXISTS (SELECT 1 FROM dbo.ChargingOrder WHERE order_id IN (@OrderId, @SecondOrderId))
     AND NOT EXISTS (SELECT 1 FROM dbo.ChargingMeterSample WHERE order_id = @OrderId)
     AND NOT EXISTS (SELECT 1 FROM dbo.OrderCommand WHERE order_id IN (@OrderId, @SecondOrderId))
    THEN 1 ELSE 0 END;

IF @CleanupOk = 1
    SET @Passed += 1;
ELSE
    SET @Failed += 1;

SELECT @Passed AS passed_tests,
       @Failed AS failed_tests,
       @CleanupOk AS rollback_cleanup_ok,
       CASE WHEN @Failed = 0 AND @CleanupOk = 1 THEN N'全部通过'
            ELSE N'存在失败' END AS test_result;

IF @Failed > 0 OR @CleanupOk = 0
    THROW 51006, 'B sample/command behavior tests failed.', 1;

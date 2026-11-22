-- P-A1 回归测试：设备状态与历史原子更新、重复状态不重复记历史。
-- 测试夹具及失败注入触发器均在 EV_B_TEST 的事务中回滚。

SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 52310, 'This test must run in EV_B_TEST.', 1;
IF OBJECT_ID(N'dbo.usp_A1_UpdateDeviceStatus', N'P') IS NULL
    THROW 52311, 'Install dbo.usp_A1_UpdateDeviceStatus before this test.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @OperatorId VARCHAR(20) = 'PA1OP' + @Token;
DECLARE @StationId VARCHAR(20) = 'PA1ST' + @Token;
DECLARE @PileId VARCHAR(20) = 'PA1PL' + @Token;
DECLARE @GunId VARCHAR(20) = 'PA1GN' + @Token;
DECLARE @OtherGunId VARCHAR(20) = 'PA1GX' + @Token;
DECLARE @BeforeHistory BIGINT;
DECLARE @AfterHistory BIGINT;
DECLARE @ActualStatus VARCHAR(20);
DECLARE @PassCount INT = 0;
DECLARE @ExpectedCount INT = 10;
DECLARE @ErrorNumber INT;

BEGIN TRY
    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'P-A1测试运营商');
    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'P-A1测试场站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         1, N'00:00-24:00', N'测试', 1);
    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileId, @StationId, N'P-A1-MODEL', 60.00, N'OCPP',
         '2026-01-01', '2028-01-01', 'UNKNOWN');
    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 60.00, 'UNKNOWN'),
        (@OtherGunId, @PileId, 2, 'DC_FAST', N'GB/T', 60.00, 'UNKNOWN');

    SELECT @BeforeHistory = COUNT_BIG(*) FROM dbo.DeviceStatusHistory;
    BEGIN TRANSACTION;

    BEGIN TRY
        EXEC dbo.usp_A1_UpdateDeviceStatus
            @new_status = 'IDLE', @change_reason = N'非法双空目标',
            @change_source = 'MANUAL';
        THROW 52312, 'P-A1 accepted both device targets as NULL.', 1;
    END TRY
    BEGIN CATCH
        SET @ErrorNumber = ERROR_NUMBER();
        IF @ErrorNumber <> 52300 THROW;
        SET @PassCount += 1;
    END CATCH;

    BEGIN TRY
        EXEC dbo.usp_A1_UpdateDeviceStatus
            @pile_id = @PileId, @gun_id = @GunId, @new_status = 'IDLE',
            @change_reason = N'非法双目标', @change_source = 'MANUAL';
        THROW 52313, 'P-A1 accepted both device targets.', 1;
    END TRY
    BEGIN CATCH
        SET @ErrorNumber = ERROR_NUMBER();
        IF @ErrorNumber <> 52300 THROW;
        SET @PassCount += 1;
    END CATCH;

    BEGIN TRY
        EXEC dbo.usp_A1_UpdateDeviceStatus
            @pile_id = @PileId, @new_status = 'BROKEN',
            @change_reason = N'非法状态', @change_source = 'MANUAL';
        THROW 52314, 'P-A1 accepted an invalid device status.', 1;
    END TRY
    BEGIN CATCH
        SET @ErrorNumber = ERROR_NUMBER();
        IF @ErrorNumber <> 52301 THROW;
        SET @PassCount += 1;
    END CATCH;

    BEGIN TRY
        EXEC dbo.usp_A1_UpdateDeviceStatus
            @pile_id = @PileId, @new_status = 'IDLE',
            @change_reason = N'非法来源', @change_source = 'UNTRUSTED';
        THROW 52315, 'P-A1 accepted an invalid change source.', 1;
    END TRY
    BEGIN CATCH
        SET @ErrorNumber = ERROR_NUMBER();
        IF @ErrorNumber <> 52302 THROW;
        SET @PassCount += 1;
    END CATCH;

    EXEC dbo.usp_A1_UpdateDeviceStatus
        @pile_id = @PileId, @new_status = 'IDLE',
        @change_reason = N'测试桩状态初始化', @change_source = 'MANUAL',
        @changed_at = '2026-10-15T10:00:00';

    SELECT @ActualStatus = status FROM dbo.ChargingPile WHERE pile_id = @PileId;
    SELECT @AfterHistory = COUNT_BIG(*) FROM dbo.DeviceStatusHistory;
    IF @ActualStatus <> 'IDLE' OR @AfterHistory <> @BeforeHistory + 1
       OR NOT EXISTS
          (SELECT 1 FROM dbo.DeviceStatusHistory
           WHERE pile_id = @PileId AND gun_id IS NULL
             AND old_status = 'UNKNOWN' AND new_status = 'IDLE'
             AND changed_at = '2026-10-15T10:00:00')
        THROW 52316, 'P-A1 pile update/history assertions failed.', 1;
    SET @PassCount += 1;

    EXEC dbo.usp_A1_UpdateDeviceStatus
        @pile_id = @PileId, @new_status = 'IDLE',
        @change_reason = N'重复状态不应增加历史', @change_source = 'MANUAL';
    SELECT @AfterHistory = COUNT_BIG(*) FROM dbo.DeviceStatusHistory;
    IF @AfterHistory <> @BeforeHistory + 1
        THROW 52317, 'P-A1 wrote a history row for an unchanged status.', 1;
    SET @PassCount += 1;

    EXEC dbo.usp_A1_UpdateDeviceStatus
        @gun_id = @GunId, @new_status = 'FAULT',
        @change_reason = N'测试枪状态变化', @change_source = 'REPAIR_REVIEW';
    IF NOT EXISTS
       (SELECT 1 FROM dbo.ChargingGun WHERE gun_id = @GunId AND status = 'FAULT')
       OR NOT EXISTS
       (SELECT 1 FROM dbo.DeviceStatusHistory
        WHERE gun_id = @GunId AND pile_id IS NULL
          AND old_status = 'UNKNOWN' AND new_status = 'FAULT'
          AND change_source = 'REPAIR_REVIEW')
        THROW 52318, 'P-A1 gun update/history assertions failed.', 1;
    SET @PassCount += 1;

    EXEC(N'
        CREATE TRIGGER dbo.TR_test_A1_history_failure
        ON dbo.DeviceStatusHistory
        AFTER INSERT
        AS
        BEGIN
            SET NOCOUNT ON;
            IF EXISTS (SELECT 1 FROM inserted WHERE change_reason = N''P-A1_FORCE_HISTORY_FAILURE'')
                RAISERROR (''Injected A1 history write failure.'', 16, 1);
        END;
    ');

    BEGIN TRY
        EXEC dbo.usp_A1_UpdateDeviceStatus
            @gun_id = @OtherGunId, @new_status = 'OFFLINE',
            @change_reason = N'P-A1_FORCE_HISTORY_FAILURE', @change_source = 'MANUAL';
        THROW 52319, 'P-A1 did not propagate a history insert failure.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 52319 THROW;
        SET @PassCount += 1;
    END CATCH;

    IF @PassCount <> @ExpectedCount - 2
        THROW 52321, 'One or more P-A1 checks did not run.', 1;

    ROLLBACK TRANSACTION;

    SET @ActualStatus = NULL;
    SELECT @ActualStatus = status FROM dbo.ChargingGun WHERE gun_id = @OtherGunId;
    SELECT @AfterHistory = COUNT_BIG(*) FROM dbo.DeviceStatusHistory;
    IF @ActualStatus <> 'UNKNOWN' OR @AfterHistory <> @BeforeHistory
        THROW 52320, 'Caller rollback did not restore the device/history baseline.', 1;

    SET @PassCount += 1;

    EXEC dbo.usp_A1_UpdateDeviceStatus
        @gun_id = @OtherGunId, @new_status = 'OFFLINE',
        @change_reason = N'过程自有事务提交测试', @change_source = 'SYSTEM_RULE';
    SELECT @ActualStatus = status FROM dbo.ChargingGun WHERE gun_id = @OtherGunId;
    SELECT @AfterHistory = COUNT_BIG(*) FROM dbo.DeviceStatusHistory;
    IF @ActualStatus <> 'OFFLINE' OR @AfterHistory <> @BeforeHistory + 1
       OR NOT EXISTS
          (SELECT 1 FROM dbo.DeviceStatusHistory
           WHERE gun_id = @OtherGunId AND new_status = 'OFFLINE'
             AND change_reason = N'过程自有事务提交测试')
        THROW 52322, 'P-A1 failed to commit when it owns the transaction.', 1;
    SET @PassCount += 1;

    IF @PassCount <> @ExpectedCount
        THROW 52323, 'P-A1 final pass count did not match the expected count.', 1;

    DELETE FROM dbo.DeviceStatusHistory WHERE pile_id = @PileId OR gun_id IN (@GunId, @OtherGunId);
    DELETE FROM dbo.ChargingGun WHERE gun_id IN (@GunId, @OtherGunId);
    DELETE FROM dbo.ChargingPile WHERE pile_id = @PileId;
    DELETE FROM dbo.ChargingStation WHERE station_id = @StationId;
    DELETE FROM dbo.Operator WHERE operator_id = @OperatorId;

    SELECT @PassCount AS passed_tests, @ExpectedCount AS expected_tests,
           N'全部通过' AS test_result;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID(N'dbo.TR_test_A1_history_failure', N'TR') IS NOT NULL
        DROP TRIGGER dbo.TR_test_A1_history_failure;
    DELETE FROM dbo.DeviceStatusHistory WHERE pile_id = @PileId OR gun_id IN (@GunId, @OtherGunId);
    DELETE FROM dbo.ChargingGun WHERE gun_id IN (@GunId, @OtherGunId);
    DELETE FROM dbo.ChargingPile WHERE pile_id = @PileId;
    DELETE FROM dbo.ChargingStation WHERE station_id = @StationId;
    DELETE FROM dbo.Operator WHERE operator_id = @OperatorId;
    THROW;
END CATCH;

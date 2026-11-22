-- V01 回归测试：空站保留，枪数不会倍增桩数，设备状态分别计数。
-- 所有夹具在 EV_B_TEST 的事务中回滚。

SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51300, 'This test must run in EV_B_TEST.', 1;

IF OBJECT_ID(N'dbo.v_A1StationDeviceOverview', N'V') IS NULL
    THROW 51301, 'Install dbo.v_A1StationDeviceOverview before this test.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @OperatorId VARCHAR(20) = 'V01OP' + @Token;
DECLARE @EmptyStationId VARCHAR(20) = 'V01SE' + @Token;
DECLARE @FullStationId VARCHAR(20) = 'V01SF' + @Token;
DECLARE @PileOneId VARCHAR(20) = 'V01P1' + @Token;
DECLARE @PileTwoId VARCHAR(20) = 'V01P2' + @Token;
DECLARE @GunOneId VARCHAR(20) = 'V01G1' + @Token;
DECLARE @GunTwoId VARCHAR(20) = 'V01G2' + @Token;
DECLARE @GunThreeId VARCHAR(20) = 'V01G3' + @Token;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'V01测试运营商');

    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@EmptyStationId, N'V01空站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         0, N'00:00-24:00', N'测试', 1),
        (@FullStationId, N'V01多枪站', N'测试地址', 116.410000, 39.910000, @OperatorId,
         2, N'00:00-24:00', N'测试', 1);

    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileOneId, @FullStationId, N'V01-MODEL', 60.00, N'OCPP', '2026-01-01', '2028-01-01', 'IDLE'),
        (@PileTwoId, @FullStationId, N'V01-MODEL', 60.00, N'OCPP', '2026-01-01', '2028-01-01', 'FAULT');

    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunOneId, @PileOneId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE'),
        (@GunTwoId, @PileOneId, 2, 'DC_FAST', N'GB/T', 60.00, 'OCCUPIED'),
        (@GunThreeId, @PileTwoId, 1, 'DC_FAST', N'GB/T', 60.00, 'OFFLINE');

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A1StationDeviceOverview
        WHERE station_id = @EmptyStationId AND pile_count = 0 AND gun_count = 0)
        THROW 51302, 'V01 did not preserve the empty station.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A1StationDeviceOverview
        WHERE station_id = @FullStationId
          AND pile_count = 2 AND idle_pile_count = 1 AND fault_pile_count = 1
          AND gun_count = 3 AND idle_gun_count = 1 AND occupied_gun_count = 1
          AND offline_gun_count = 1)
        THROW 51303, 'V01 returned incorrect device totals or status counts.', 1;

    SELECT station_id, pile_count, idle_pile_count, fault_pile_count,
           gun_count, idle_gun_count, occupied_gun_count, offline_gun_count
    FROM dbo.v_A1StationDeviceOverview
    WHERE station_id IN (@EmptyStationId, @FullStationId)
    ORDER BY station_id;
    SELECT N'V01 空站保留、桩枪计数与状态汇总' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

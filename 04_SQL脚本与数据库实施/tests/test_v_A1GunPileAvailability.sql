-- V02 回归测试：当前状态与设备上报状态分离，且无枪桩仍可见。
-- 所有夹具在 EV_B_TEST 的事务中回滚。

SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51400, 'This test must run in EV_B_TEST.', 1;

IF OBJECT_ID(N'dbo.v_A1GunPileAvailability', N'V') IS NULL
    THROW 51401, 'Install dbo.v_A1GunPileAvailability before this test.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @OperatorId VARCHAR(20) = 'V02OP' + @Token;
DECLARE @StationId VARCHAR(20) = 'V02ST' + @Token;
DECLARE @PileWithGunsId VARCHAR(20) = 'V02PG' + @Token;
DECLARE @PileWithoutGunId VARCHAR(20) = 'V02PN' + @Token;
DECLARE @GunOneId VARCHAR(20) = 'V02G1' + @Token;
DECLARE @GunTwoId VARCHAR(20) = 'V02G2' + @Token;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'V02测试运营商');

    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'V02测试场站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         2, N'00:00-24:00', N'测试', 1);

    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status, reported_status, last_heartbeat_at)
    VALUES
        (@PileWithGunsId, @StationId, N'V02-MODEL', 60.00, N'OCPP',
         '2026-01-01', '2028-01-01', 'OFFLINE', 'IDLE', '2026-10-15T10:00:00'),
        (@PileWithoutGunId, @StationId, N'V02-MODEL', 60.00, N'OCPP',
         '2026-01-01', '2028-01-01', 'FAULT', 'FAULT', '2026-10-15T10:01:00');

    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status, reported_status, last_reported_at)
    VALUES
        (@GunOneId, @PileWithGunsId, 1, 'DC_FAST', N'GB/T', 60.00,
         'UNKNOWN', 'FAULT', '2026-10-15T10:02:00'),
        (@GunTwoId, @PileWithGunsId, 2, 'DC_FAST', N'GB/T', 60.00,
         'IDLE', 'OCCUPIED', '2026-10-15T10:03:00');

    IF (SELECT COUNT(*) FROM dbo.v_A1GunPileAvailability
        WHERE pile_id = @PileWithGunsId) <> 2
        THROW 51402, 'V02 did not return one row per gun.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A1GunPileAvailability
        WHERE pile_id = @PileWithGunsId AND gun_id = @GunOneId
          AND pile_status = 'OFFLINE' AND pile_reported_status = 'IDLE'
          AND gun_status = 'UNKNOWN' AND gun_reported_status = 'FAULT'
          AND last_heartbeat_at = '2026-10-15T10:00:00'
          AND gun_last_reported_at = '2026-10-15T10:02:00')
        THROW 51403, 'V02 conflated current and reported device states.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A1GunPileAvailability
        WHERE pile_id = @PileWithoutGunId AND gun_id IS NULL
          AND pile_status = 'FAULT' AND pile_reported_status = 'FAULT')
        THROW 51404, 'V02 did not preserve the pile without a gun.', 1;

    SELECT pile_id, pile_status, pile_reported_status, last_heartbeat_at,
           gun_id, gun_status, gun_reported_status, gun_last_reported_at
    FROM dbo.v_A1GunPileAvailability
    WHERE pile_id IN (@PileWithGunsId, @PileWithoutGunId)
    ORDER BY pile_id, gun_id;
    SELECT N'V02 状态分离与无枪桩保留' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

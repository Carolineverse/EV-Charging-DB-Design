-- V03 回归测试：事项身份、提交/审核字段及当前场站映射准确。
-- 所有夹具在 EV_B_TEST 的事务中回滚。

SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51500, 'This test must run in EV_B_TEST.', 1;

IF OBJECT_ID(N'dbo.v_A1AssetCaseTrace', N'V') IS NULL
    THROW 51501, 'Install dbo.v_A1AssetCaseTrace before this test.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @OperatorId VARCHAR(20) = 'V03OP' + @Token;
DECLARE @StationId VARCHAR(20) = 'V03ST' + @Token;
DECLARE @PileId VARCHAR(20) = 'V03PL' + @Token;
DECLARE @GunId VARCHAR(20) = 'V03GN' + @Token;
DECLARE @AssetCaseId BIGINT;
DECLARE @SubmittedAt DATETIME2(3) = '2026-10-15T09:30:00';
DECLARE @ReviewedAt DATETIME2(3) = '2026-10-15T10:00:00';

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'V03测试运营商');

    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'V03当前场站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         1, N'00:00-24:00', N'测试', 1);

    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileId, @StationId, N'V03-MODEL', 60.00, N'OCPP',
         '2026-01-01', '2028-01-01', 'IDLE');

    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE');

    INSERT INTO dbo.DeviceAssetCase
        (pile_id, gun_id, case_type, submitted_by, submitted_at, details,
         status, reviewed_by, reviewed_at, decision)
    VALUES
        (@PileId, @GunId, 'INSPECTION', 101, @SubmittedAt, N'V03测试设备事项',
         'APPROVED', 202, @ReviewedAt, N'V03测试审核意见');
    SET @AssetCaseId = CONVERT(BIGINT, SCOPE_IDENTITY());

    IF (SELECT COUNT(*) FROM dbo.v_A1AssetCaseTrace
        WHERE asset_case_id = @AssetCaseId) <> 1
        THROW 51502, 'V03 did not return exactly one row per asset case.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A1AssetCaseTrace
        WHERE asset_case_id = @AssetCaseId
          AND pile_id = @PileId AND gun_id = @GunId
          AND current_station_id = @StationId
          AND current_station_name = N'V03当前场站'
          AND submitted_by = 101 AND submitted_at = @SubmittedAt
          AND case_status = 'APPROVED' AND reviewed_by = 202
          AND reviewed_at = @ReviewedAt AND decision = N'V03测试审核意见')
        THROW 51503, 'V03 lost or changed the asset case trace fields.', 1;

    SELECT asset_case_id, pile_id, current_station_id, current_station_name,
           gun_id, case_type, submitted_by, submitted_at, case_status,
           reviewed_by, reviewed_at, decision
    FROM dbo.v_A1AssetCaseTrace
    WHERE asset_case_id = @AssetCaseId;
    SELECT N'V03 资产事项追溯字段' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

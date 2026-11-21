-- V09 回归测试：企业账期按订单 end_time 月份核对，明细快照与订单事实对照。
-- 所有夹具在 EV_B_TEST 的事务中回滚；企业订单金额为明确标记的测试快照。

SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 52100, 'This test must run in EV_B_TEST.', 1;
IF OBJECT_ID(N'dbo.v_A2EnterpriseMonthlyDetail', N'V') IS NULL
    THROW 52101, 'Install dbo.v_A2EnterpriseMonthlyDetail before this test.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @OperatorId VARCHAR(20) = 'V09OP' + @Token;
DECLARE @StationId VARCHAR(20) = 'V09ST' + @Token;
DECLARE @PileId VARCHAR(20) = 'V09PL' + @Token;
DECLARE @GunId VARCHAR(20) = 'V09GN' + @Token;
DECLARE @EnterpriseId VARCHAR(20) = 'V09E' + @Token;
DECLARE @FleetMemberId VARCHAR(20) = 'V09FM' + @Token;
DECLARE @VehicleId VARCHAR(20) = 'V09VE' + @Token;
DECLARE @CardId VARCHAR(20) = 'V09CA' + @Token;
DECLARE @QuotaId VARCHAR(20) = 'V09QU' + @Token;
DECLARE @OctSettlementId VARCHAR(20) = 'V09OCT' + @Token;
DECLARE @NovSettlementId VARCHAR(20) = 'V09NOV' + @Token;
DECLARE @BindingId BIGINT;
DECLARE @OctOrderId BIGINT;
DECLARE @NovOrderId BIGINT;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'V09测试运营商');
    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'V09测试场站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         1, N'00:00-24:00', N'测试', 1);
    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileId, @StationId, N'V09-MODEL', 60.00, N'OCPP', '2026-01-01', '2028-01-01', 'IDLE');
    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE');

    INSERT INTO dbo.FleetMember (fleet_member_id, enterprise_id, user_id, member_no)
    VALUES (@FleetMemberId, @EnterpriseId, 'V09U' + @Token, 'V09-MEMBER');
    INSERT INTO dbo.Vehicle
        (vehicle_id, user_id, enterprise_id, plate_ciphertext, plate_hash,
         vehicle_model, battery_capacity_kwh, max_charging_power_kw)
    VALUES
        (@VehicleId, NULL, @EnterpriseId, 0x01,
         CONVERT(CHAR(64), HASHBYTES('SHA2_256', @VehicleId), 2),
         N'V09测试车辆', 70.00, 100.00);
    INSERT INTO dbo.EnterpriseCard (enterprise_card_id, enterprise_id, card_no)
    VALUES (@CardId, @EnterpriseId, 'V09-CARD-' + @Token);
    INSERT INTO dbo.EnterpriseCardBinding
        (enterprise_card_id, vehicle_id, fleet_member_id, effective_start_at)
    VALUES
        (@CardId, @VehicleId, @FleetMemberId, '2026-10-01T00:00:00');
    SET @BindingId = CONVERT(BIGINT, SCOPE_IDENTITY());
    INSERT INTO dbo.EnterpriseQuota
        (enterprise_quota_id, fleet_member_id, quota_month, quota_amount, reserved_amount)
    VALUES
        (@QuotaId, @FleetMemberId, '2026-10-01', 100.00, 0.00);

    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, binding_id, enterprise_quota_id,
         start_time, end_time, energy_kwh, status, gross_amount,
         opening_station_id, settled_at, priced_at)
    VALUES
        ('ENTERPRISE', 'V09U' + @Token, @GunId, @BindingId, @QuotaId,
         '2026-10-15T10:00:00', '2026-10-15T11:00:00', 1.000, 'PAID', 5.00,
         @StationId, '2026-10-15T11:05:00', '2026-10-15T11:04:00');
    SET @OctOrderId = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, binding_id, enterprise_quota_id,
         start_time, end_time, energy_kwh, status, gross_amount,
         opening_station_id, settled_at, priced_at)
    VALUES
        ('ENTERPRISE', 'V09U' + @Token, @GunId, @BindingId, @QuotaId,
         '2026-10-31T23:00:00', '2026-10-31T23:59:00', 1.000, 'PAID', 5.00,
         @StationId, '2026-10-31T23:59:00', '2026-10-31T23:58:00');
    SET @NovOrderId = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.EnterpriseSettlement
        (enterprise_settlement_id, enterprise_id, billing_period_start,
         total_order_count, total_energy_kwh, total_amount, generated_at)
    VALUES
        (@OctSettlementId, @EnterpriseId, '2026-10-01', 1, 1.000, 5.00, '2026-11-01T09:00:00'),
        (@NovSettlementId, @EnterpriseId, '2026-11-01', 1, 1.000, 5.00, '2026-11-02T09:00:00');

    INSERT INTO dbo.EnterpriseSettlementDetail
        (enterprise_settlement_id, order_id, fleet_member_id, vehicle_id,
         payable_amount, energy_kwh)
    VALUES
        (@OctSettlementId, @OctOrderId, @FleetMemberId, @VehicleId, 5.00, 1.000),
        (@NovSettlementId, @NovOrderId, @FleetMemberId, @VehicleId, 5.00, 1.000);

    IF (SELECT COUNT(*) FROM dbo.v_A2EnterpriseMonthlyDetail
        WHERE order_id IN (@OctOrderId, @NovOrderId)) <> 2
        THROW 52102, 'V09 did not return one row per enterprise order detail.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A2EnterpriseMonthlyDetail
        WHERE order_id = @OctOrderId AND period_matches_order_end_month = 1
          AND detail_energy_matches_order = 1 AND detail_amount_matches_order = 1
          AND order_payable_amount = 5.00 AND settlement_state = 'GENERATED')
        THROW 52103, 'V09 did not validate the in-month enterprise detail.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A2EnterpriseMonthlyDetail
        WHERE order_id = @NovOrderId AND period_matches_order_end_month = 0
          AND detail_energy_matches_order = 1 AND detail_amount_matches_order = 1)
        THROW 52104, 'V09 failed to flag an order assigned to the wrong end month.', 1;

    SELECT enterprise_settlement_id, enterprise_id, billing_period_start,
           order_id, order_end_time, detail_energy_kwh, order_energy_kwh,
           detail_payable_amount, order_payable_amount, settlement_state,
           period_matches_order_end_month, detail_energy_matches_order,
           detail_amount_matches_order
    FROM dbo.v_A2EnterpriseMonthlyDetail
    WHERE order_id IN (@OctOrderId, @NovOrderId)
    ORDER BY order_id;
    SELECT N'V09 企业月结明细与实际结束月核对' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

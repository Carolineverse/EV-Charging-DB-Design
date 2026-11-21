USE [EV_B_TEST];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51130, 'B enterprise demo seed must run in EV_B_TEST.', 1;

IF OBJECT_ID(N'dbo.EnterpriseProfile', N'U') IS NULL
   OR OBJECT_ID(N'dbo.EnterpriseCard', N'U') IS NULL
   OR OBJECT_ID(N'dbo.EnterpriseCardBinding', N'U') IS NULL
   OR OBJECT_ID(N'dbo.EnterpriseQuota', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FleetMember', N'U') IS NULL
   OR OBJECT_ID(N'dbo.Vehicle', N'U') IS NULL
   OR OBJECT_ID(N'dbo.EnterpriseSettlement', N'U') IS NULL
   OR OBJECT_ID(N'dbo.EnterpriseSettlementDetail', N'U') IS NULL
   OR OBJECT_ID(N'dbo.usp_A2_GenerateEnterpriseSettlement', N'P') IS NULL
    THROW 51131, 'Install R, A2 tables and the A2 settlement procedure after seed 50.', 1;

DECLARE @EnterpriseId VARCHAR(20) = 'B_DEMO_ENT01';
DECLARE @UserId VARCHAR(20) = 'B_DEMO_USER01';
DECLARE @StationId VARCHAR(20) = 'B_DEMO_ST01';
DECLARE @GunId VARCHAR(20) = 'B_DEMO_GUN01';
DECLARE @FleetMemberId VARCHAR(20) = 'B_DEMO_FM01';
DECLARE @VehicleId VARCHAR(20) = 'B_DEMO_VE01';
DECLARE @CardId VARCHAR(20) = 'B_DEMO_CARD01';
DECLARE @QuotaId VARCHAR(20) = 'B_DEMO_QUOTA01';
DECLARE @EnterpriseRuleVersionId BIGINT = 920260103;
DECLARE @EnterpriseSettlementId VARCHAR(20) = 'B_DEMO_ES01';
DECLARE @BillingRuleId BIGINT;
DECLARE @BindingId BIGINT;
DECLARE @OrderId BIGINT;
DECLARE @ExistingSettlementId VARCHAR(20);

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.FleetMember WHERE fleet_member_id = @FleetMemberId)
        INSERT INTO dbo.FleetMember
            (fleet_member_id, enterprise_id, user_id, member_no, joined_at)
        VALUES
            (@FleetMemberId, @EnterpriseId, @UserId, 'B-DEMO-MEMBER-01', '2026-01-01T00:00:00');

    IF NOT EXISTS (SELECT 1 FROM dbo.Vehicle WHERE vehicle_id = @VehicleId)
        INSERT INTO dbo.Vehicle
            (vehicle_id, user_id, enterprise_id, plate_ciphertext, plate_hash,
             vehicle_model, battery_capacity_kwh, max_charging_power_kw, status)
        VALUES
            (@VehicleId, NULL, @EnterpriseId, 0x01,
             CONVERT(CHAR(64), HASHBYTES('SHA2_256', @VehicleId), 2),
             N'B 企业演示车辆', 70.00, 100.00, 'ACTIVE');

    IF NOT EXISTS (SELECT 1 FROM dbo.EnterpriseCard WHERE enterprise_card_id = @CardId)
        INSERT INTO dbo.EnterpriseCard
            (enterprise_card_id, enterprise_id, card_no, status, issued_at)
        VALUES (@CardId, @EnterpriseId, 'B-DEMO-CARD-01', 'ACTIVE', '2026-01-01T00:00:00');

    IF NOT EXISTS
       (SELECT 1 FROM dbo.EnterpriseCardBinding
        WHERE enterprise_card_id = @CardId AND vehicle_id = @VehicleId
          AND fleet_member_id = @FleetMemberId AND effective_end_at IS NULL)
        INSERT INTO dbo.EnterpriseCardBinding
            (enterprise_card_id, vehicle_id, fleet_member_id, effective_start_at)
        VALUES (@CardId, @VehicleId, @FleetMemberId, '2026-01-01T00:00:00');

    SELECT @BindingId = binding_id
    FROM dbo.EnterpriseCardBinding
    WHERE enterprise_card_id = @CardId AND vehicle_id = @VehicleId
      AND fleet_member_id = @FleetMemberId AND effective_end_at IS NULL;

    IF @BindingId IS NULL
        THROW 51132, 'Could not resolve the B enterprise demo card binding.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.EnterpriseQuota WHERE enterprise_quota_id = @QuotaId)
        INSERT INTO dbo.EnterpriseQuota
            (enterprise_quota_id, fleet_member_id, quota_month, quota_amount, reserved_amount)
        VALUES (@QuotaId, @FleetMemberId, '2026-10-01', 100.00, 0.00);

    IF NOT EXISTS (SELECT 1 FROM dbo.BillingRuleVersion WHERE rule_version_id = @EnterpriseRuleVersionId)
        INSERT INTO dbo.BillingRuleVersion
            (rule_version_id, station_id, enterprise_id, free_minutes, minimum_amount,
             effective_from, effective_to, status)
        VALUES
            (@EnterpriseRuleVersionId, @StationId, @EnterpriseId, 0, 5.00,
             '2026-01-01T00:00:00', NULL, 'ACTIVE');

    IF EXISTS
       (SELECT 1 FROM dbo.BillingRuleVersion
        WHERE rule_version_id = @EnterpriseRuleVersionId
          AND (station_id <> @StationId OR enterprise_id <> @EnterpriseId
               OR minimum_amount <> 5.00 OR effective_from <> '2026-01-01T00:00:00'
               OR effective_to IS NOT NULL OR status <> 'ACTIVE'))
        THROW 51133, 'B enterprise demo rule version has unexpected facts.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.BillingRule
        WHERE rule_version_id = @EnterpriseRuleVersionId AND period_start_time = '00:00:00')
        INSERT INTO dbo.BillingRule
            (rule_version_id, period_type, period_start_time, period_end_time,
             electricity_price, service_price)
        VALUES
            (@EnterpriseRuleVersionId, N'平', '00:00:00', '23:59:00', 2.0000, 1.0000);

    SELECT @BillingRuleId = billing_rule_id
    FROM dbo.BillingRule
    WHERE rule_version_id = @EnterpriseRuleVersionId AND period_start_time = '00:00:00';

    IF @BillingRuleId IS NULL
        THROW 51134, 'Could not resolve the B enterprise demo billing rule.', 1;

    IF (SELECT COUNT(*) FROM dbo.ChargingOrder
        WHERE user_id = @UserId AND gun_id = @GunId
          AND created_at = '2026-10-01T00:00:04') > 1
        THROW 51135, 'Duplicate B enterprise demo order marker; rebuild EV_B_TEST.', 1;

    SELECT @OrderId = order_id
    FROM dbo.ChargingOrder
    WHERE user_id = @UserId AND gun_id = @GunId
      AND created_at = '2026-10-01T00:00:04';

    IF @OrderId IS NULL
    BEGIN
        -- Imported upstream-paid fixture for D integration; this does not implement
        -- or decide the production enterprise pricing/payment lifecycle.
        INSERT INTO dbo.ChargingOrder
            (order_type, user_id, gun_id, binding_id, enterprise_quota_id,
             start_time, end_time, energy_kwh, status, gross_amount,
             minimum_adjustment, discount_amount, paid_amount, refund_amount,
             created_at, updated_at, opening_station_id, settled_at,
             startup_rule_version_id, priced_at, device_released_at)
        VALUES
            ('ENTERPRISE', @UserId, @GunId, @BindingId, @QuotaId,
             '2026-10-15T09:00:00', '2026-10-15T10:00:00', 1.000, 'PAID',
             5.00, 2.00, 0.00, 5.00, 0.00,
             '2026-10-01T00:00:04', '2026-11-04T10:00:00', @StationId,
             '2026-10-15T10:05:00', @EnterpriseRuleVersionId,
             '2026-10-15T10:04:00', '2026-10-15T10:03:00');
        SET @OrderId = CONVERT(BIGINT, SCOPE_IDENTITY());
    END;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.OrderFeeDetail
        WHERE order_id = @OrderId AND segment_start = '2026-10-15T09:00:00')
        INSERT INTO dbo.OrderFeeDetail
            (order_id, billing_rule_id, segment_start, segment_end,
             segment_energy_kwh, free_service_fee)
        VALUES
            (@OrderId, @BillingRuleId, '2026-10-15T09:00:00',
             '2026-10-15T10:00:00', 1.000, 0.00);

    SELECT @ExistingSettlementId = enterprise_settlement_id
    FROM dbo.EnterpriseSettlement
    WHERE enterprise_id = @EnterpriseId AND billing_period_start = '2026-10-01';

    IF @ExistingSettlementId IS NOT NULL AND @ExistingSettlementId <> @EnterpriseSettlementId
        THROW 51136, 'Another enterprise settlement already occupies the B demo period.', 1;

    IF @ExistingSettlementId IS NULL
        EXEC dbo.usp_A2_GenerateEnterpriseSettlement
            @enterprise_settlement_id = @EnterpriseSettlementId,
            @enterprise_id = @EnterpriseId,
            @billing_period_start = '2026-10-01',
            @generated_at = '2026-11-02T09:00:00';

    UPDATE dbo.EnterpriseSettlement
    SET confirmed_at = COALESCE(confirmed_at, '2026-11-03T10:00:00'),
        paid_at = COALESCE(paid_at, '2026-11-04T10:00:00'),
        payment_reference = COALESCE(payment_reference, 'B-DEMO-ENTERPRISE-202610'),
        updated_at = SYSDATETIME()
    WHERE enterprise_settlement_id = @EnterpriseSettlementId;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.EnterpriseSettlementDetail
        WHERE enterprise_settlement_id = @EnterpriseSettlementId AND order_id = @OrderId)
        THROW 51137, 'A2 demo settlement did not include the B enterprise demo order.', 1;

    COMMIT TRANSACTION;

    SELECT @EnterpriseId AS enterprise_id, @OrderId AS order_id,
           @EnterpriseSettlementId AS enterprise_settlement_id,
           CAST(2.00 AS DECIMAL(12,2)) AS electricity_base,
           CAST(1.00 AS DECIMAL(12,2)) AS service_base,
           CAST(2.00 AS DECIMAL(12,2)) AS minimum_adjustment,
           CAST(5.00 AS DECIMAL(12,2)) AS payable_amount,
           CAST('REVIEW_REQUIRED' AS VARCHAR(20)) AS expected_source_status;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

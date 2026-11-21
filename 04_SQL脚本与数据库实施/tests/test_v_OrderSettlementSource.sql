-- V04 回归测试：SettlementDetail 快照契约、退款状态及 A2 企业收款凭据。
-- 所有数据在 EV_B_TEST 事务中回滚；本脚本不创建 D 表或占位对象。

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
    THROW 51800, 'This test must run in EV_B_TEST.', 1;
IF OBJECT_ID(N'dbo.v_OrderSettlementSource', N'V') IS NULL
    THROW 51801, 'Install dbo.v_OrderSettlementSource before this test.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @OperatorId VARCHAR(20) = 'V04OP' + @Token;
DECLARE @StationId VARCHAR(20) = 'V04ST' + @Token;
DECLARE @PileId VARCHAR(20) = 'V04PL' + @Token;
DECLARE @GunId VARCHAR(20) = 'V04GN' + @Token;
DECLARE @EnterpriseId VARCHAR(20) = 'V04E' + @Token;
DECLARE @FleetMemberId VARCHAR(20) = 'V04FM' + @Token;
DECLARE @VehicleId VARCHAR(20) = 'V04VE' + @Token;
DECLARE @CardId VARCHAR(20) = 'V04CA' + @Token;
DECLARE @QuotaId VARCHAR(20) = 'V04QU' + @Token;
DECLARE @EnterpriseSettlementId VARCHAR(20) = 'V04ES' + @Token;
DECLARE @PersonalVersionId BIGINT = 930000000000000000
    + ABS(CAST(CHECKSUM(NEWID()) AS BIGINT));
DECLARE @EnterpriseVersionId BIGINT = 940000000000000000
    + ABS(CAST(CHECKSUM(NEWID()) AS BIGINT));
DECLARE @PersonalRuleId BIGINT;
DECLARE @EnterpriseRuleId BIGINT;
DECLARE @EligibleOrderId BIGINT;
DECLARE @FailedRefundOrderId BIGINT;
DECLARE @SuccessfulRefundOrderId BIGINT;
DECLARE @UnpricedOrderId BIGINT;
DECLARE @EnterpriseMissingReceiptOrderId BIGINT;
DECLARE @EnterpriseVerifiedReceiptOrderId BIGINT;
DECLARE @BindingId BIGINT;
DECLARE @PaymentId BIGINT;
DECLARE @ExpectedCount INT = 6;
DECLARE @MissingContractColumns INT;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @RequiredDColumns TABLE (column_name SYSNAME PRIMARY KEY);
    INSERT INTO @RequiredDColumns (column_name)
    VALUES
        (N'order_id'), (N'station_id'), (N'settlement_source'), (N'ended_at'),
        (N'settled_at'), (N'energy_kwh'), (N'electricity_base'), (N'service_base'),
        (N'minimum_adjustment'), (N'refund_state_snapshot'), (N'is_settleable'),
        (N'unsettleable_reason');
    SELECT @MissingContractColumns = COUNT(*)
    FROM @RequiredDColumns AS required_column
    LEFT JOIN sys.columns AS actual_column
      ON actual_column.object_id = OBJECT_ID(N'dbo.v_OrderSettlementSource')
     AND actual_column.name = required_column.column_name
    WHERE actual_column.column_id IS NULL;
    IF @MissingContractColumns <> 0
        THROW 51809, 'V04 does not expose the required D settlement source columns.', 1;

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'V04测试运营商');
    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'V04测试场站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         1, N'00:00-24:00', N'测试', 1);
    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileId, @StationId, N'V04-MODEL', 60.00, N'OCPP', '2026-01-01', '2028-01-01', 'IDLE');
    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE');

    INSERT INTO dbo.BillingRuleVersion
        (rule_version_id, station_id, enterprise_id, free_minutes, minimum_amount,
         effective_from, status)
    VALUES
        (@PersonalVersionId, @StationId, NULL, 0, 5.00, '2026-10-01T00:00:00', 'ACTIVE'),
        (@EnterpriseVersionId, @StationId, @EnterpriseId, 0, 5.00,
         '2026-10-01T00:00:00', 'ACTIVE');
    INSERT INTO dbo.BillingRule
        (rule_version_id, period_type, period_start_time, period_end_time,
         electricity_price, service_price)
    VALUES
        (@PersonalVersionId, N'平', '00:00:00', '23:59:00', 2.0000, 1.0000),
        (@EnterpriseVersionId, N'平', '00:00:00', '23:59:00', 2.0000, 1.0000);
    SELECT @PersonalRuleId = billing_rule_id
    FROM dbo.BillingRule WHERE rule_version_id = @PersonalVersionId;
    SELECT @EnterpriseRuleId = billing_rule_id
    FROM dbo.BillingRule WHERE rule_version_id = @EnterpriseVersionId;

    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, start_time, end_time, energy_kwh, status,
         gross_amount, minimum_adjustment, discount_amount,
         opening_station_id, startup_rule_version_id)
    VALUES
        ('PERSONAL', 'V04U' + @Token, @GunId, '2026-10-15T10:00:00', '2026-10-15T11:00:00',
         1.000, 'PENDING_PAYMENT', 5.00, 2.00, 3.00, @StationId, @PersonalVersionId),
        ('PERSONAL', 'V04U' + @Token, @GunId, '2026-10-15T12:00:00', '2026-10-15T13:00:00',
         1.000, 'PENDING_PAYMENT', 5.00, 2.00, 0.00, @StationId, @PersonalVersionId),
        ('PERSONAL', 'V04U' + @Token, @GunId, '2026-10-16T10:00:00', '2026-10-16T11:00:00',
         1.000, 'PENDING_PAYMENT', 5.00, 2.00, 0.00, @StationId, @PersonalVersionId),
        ('PERSONAL', 'V04U' + @Token, @GunId, '2026-10-17T10:00:00', '2026-10-17T11:00:00',
         1.000, 'PENDING_PAYMENT', 5.00, 2.00, 0.00, @StationId, @PersonalVersionId);
    SELECT @EligibleOrderId = MIN(order_id) FROM dbo.ChargingOrder WHERE user_id = 'V04U' + @Token;
    SELECT @UnpricedOrderId = MAX(order_id) FROM dbo.ChargingOrder WHERE user_id = 'V04U' + @Token;
    SELECT @FailedRefundOrderId = MIN(order_id) FROM dbo.ChargingOrder
    WHERE user_id = 'V04U' + @Token AND start_time = '2026-10-15T12:00:00';
    SELECT @SuccessfulRefundOrderId = MIN(order_id) FROM dbo.ChargingOrder
    WHERE user_id = 'V04U' + @Token AND start_time = '2026-10-16T10:00:00';
    UPDATE dbo.ChargingOrder SET gross_amount = 0, minimum_adjustment = 0
    WHERE order_id = @UnpricedOrderId;

    INSERT INTO dbo.OrderFeeDetail
        (order_id, billing_rule_id, segment_start, segment_end,
         segment_energy_kwh, free_service_fee)
    SELECT o.order_id, @PersonalRuleId, o.start_time, o.end_time, 1.000, 0.00
    FROM dbo.ChargingOrder AS o
    WHERE o.user_id = 'V04U' + @Token AND o.order_id <> @UnpricedOrderId;

    EXEC dbo.usp_PriceChargingOrder @order_id = @EligibleOrderId, @discount_amount = 3.00;
    EXEC dbo.usp_PriceChargingOrder @order_id = @FailedRefundOrderId, @discount_amount = 0.00;
    EXEC dbo.usp_PriceChargingOrder @order_id = @SuccessfulRefundOrderId, @discount_amount = 0.00;

    UPDATE dbo.ChargingOrder
    SET status = 'PAID', paid_amount = 2.00, settled_at = '2026-10-15T11:05:00'
    WHERE order_id = @EligibleOrderId;
    UPDATE dbo.ChargingOrder
    SET status = 'PAID', paid_amount = 5.00, settled_at = '2026-10-15T13:05:00'
    WHERE order_id = @FailedRefundOrderId;
    UPDATE dbo.ChargingOrder
    SET status = 'PAID', paid_amount = 5.00, settled_at = '2026-10-16T11:05:00'
    WHERE order_id = @SuccessfulRefundOrderId;

    INSERT INTO dbo.PaymentRecord
        (order_id, pay_channel, transaction_no, pay_amount, refund_amount, pay_time)
    VALUES
        (@EligibleOrderId, 'WECHAT', 'V04-' + @Token + '-P1', 2.00, 0.00, '2026-10-15T11:04:00'),
        (@FailedRefundOrderId, 'WECHAT', 'V04-' + @Token + '-P2', 5.00, 0.00, '2026-10-15T13:04:00'),
        (@SuccessfulRefundOrderId, 'WECHAT', 'V04-' + @Token + '-P3', 5.00, 1.00, '2026-10-16T11:04:00');

    SELECT @PaymentId = payment_id FROM dbo.PaymentRecord WHERE order_id = @FailedRefundOrderId;
    INSERT INTO dbo.RefundRecord (payment_id, refund_no, refund_amount, status, refunded_at)
    VALUES (@PaymentId, 'V04-' + @Token + '-R1', 1.00, 'FAILED', NULL);
    SELECT @PaymentId = payment_id FROM dbo.PaymentRecord WHERE order_id = @SuccessfulRefundOrderId;
    INSERT INTO dbo.RefundRecord (payment_id, refund_no, refund_amount, status, refunded_at)
    VALUES (@PaymentId, 'V04-' + @Token + '-R2', 1.00, 'SUCCESS', '2026-10-16T12:00:00');
    UPDATE dbo.ChargingOrder SET refund_amount = 1.00 WHERE order_id = @SuccessfulRefundOrderId;

    INSERT INTO dbo.FleetMember (fleet_member_id, enterprise_id, user_id, member_no)
    VALUES (@FleetMemberId, @EnterpriseId, 'V04U' + @Token, 'V04-MEMBER');
    INSERT INTO dbo.Vehicle
        (vehicle_id, user_id, enterprise_id, plate_ciphertext, plate_hash,
         vehicle_model, battery_capacity_kwh, max_charging_power_kw)
    VALUES
        (@VehicleId, NULL, @EnterpriseId, 0x01,
         CONVERT(CHAR(64), HASHBYTES('SHA2_256', @VehicleId), 2),
         N'V04测试车辆', 70.00, 100.00);
    INSERT INTO dbo.EnterpriseCard (enterprise_card_id, enterprise_id, card_no)
    VALUES (@CardId, @EnterpriseId, 'V04-CARD-' + @Token);
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
         start_time, end_time, energy_kwh, status, gross_amount, minimum_adjustment,
         paid_amount, opening_station_id, settled_at, startup_rule_version_id, priced_at)
    VALUES
        ('ENTERPRISE', 'V04U' + @Token, @GunId, @BindingId, @QuotaId,
         '2026-10-18T10:00:00', '2026-10-18T11:00:00', 1.000, 'PAID', 5.00, 2.00,
         0.00, @StationId, '2026-10-18T11:05:00', @EnterpriseVersionId, SYSDATETIME()),
        ('ENTERPRISE', 'V04U' + @Token, @GunId, @BindingId, @QuotaId,
         '2026-10-19T10:00:00', '2026-10-19T11:00:00', 1.000, 'PAID', 5.00, 2.00,
         0.00, @StationId, '2026-10-19T11:05:00', @EnterpriseVersionId, SYSDATETIME());
    SELECT @EnterpriseMissingReceiptOrderId = MIN(order_id) FROM dbo.ChargingOrder
    WHERE order_type = 'ENTERPRISE';
    SELECT @EnterpriseVerifiedReceiptOrderId = MAX(order_id) FROM dbo.ChargingOrder
    WHERE order_type = 'ENTERPRISE';

    INSERT INTO dbo.OrderFeeDetail
        (order_id, billing_rule_id, segment_start, segment_end,
         segment_energy_kwh, free_service_fee)
    SELECT @EnterpriseMissingReceiptOrderId, @EnterpriseRuleId,
           '2026-10-18T10:00:00', '2026-10-18T11:00:00', 1.000, 0.00
    UNION ALL
    SELECT @EnterpriseVerifiedReceiptOrderId, @EnterpriseRuleId,
           '2026-10-19T10:00:00', '2026-10-19T11:00:00', 1.000, 0.00;

    INSERT INTO dbo.EnterpriseSettlement
        (enterprise_settlement_id, enterprise_id, billing_period_start,
         total_order_count, total_energy_kwh, total_amount, generated_at,
         confirmed_at, paid_at, payment_reference)
    VALUES
        (@EnterpriseSettlementId, @EnterpriseId, '2026-10-01', 1, 1.000, 5.00,
         '2026-10-31T09:00:00', '2026-10-31T10:00:00', '2026-11-01T10:00:00',
         'V04-ENTERPRISE-RECEIPT-' + @Token);
    INSERT INTO dbo.EnterpriseSettlementDetail
        (enterprise_settlement_id, order_id, fleet_member_id, vehicle_id,
         payable_amount, energy_kwh)
    VALUES
        (@EnterpriseSettlementId, @EnterpriseVerifiedReceiptOrderId,
         @FleetMemberId, @VehicleId, 5.00, 1.000);

    IF (SELECT COUNT(*) FROM dbo.v_OrderSettlementSource
        WHERE order_id IN (@EligibleOrderId, @FailedRefundOrderId, @SuccessfulRefundOrderId,
                           @UnpricedOrderId, @EnterpriseMissingReceiptOrderId,
                           @EnterpriseVerifiedReceiptOrderId)) <> @ExpectedCount
        THROW 51802, 'V04 must return exactly one row for each fixture order.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_OrderSettlementSource
        WHERE order_id = @EligibleOrderId AND eligibility_status = 'ELIGIBLE'
          AND opening_station_id = @StationId AND ended_at_snapshot = '2026-10-15T11:00:00'
          AND energy_snapshot = 1.000 AND electricity_base = 2.00
          AND service_base = 1.00 AND minimum_adjustment = 2.00
          AND settled_at_snapshot = '2026-10-15T11:05:00'
          AND settlement_source = 'PERSONAL' AND refund_state_snapshot = 'NONE'
          AND payable_amount = 2.00 AND payment_amount = 2.00
          AND station_id = @StationId AND ended_at = '2026-10-15T11:00:00'
          AND settled_at = '2026-10-15T11:05:00' AND energy_kwh = 1.000
          AND is_settleable = 1 AND unsettleable_reason IS NULL)
        THROW 51803, 'V04 did not produce the required personal SettlementDetail snapshots.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_OrderSettlementSource
        WHERE order_id = @FailedRefundOrderId AND eligibility_status = 'ELIGIBLE'
          AND refund_state_snapshot = 'FAILED_CANCELLED'
          AND is_settleable = 1 AND unsettleable_reason IS NULL)
        THROW 51804, 'Failed refunds should map to the permitted FAILED_CANCELLED snapshot.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_OrderSettlementSource
        WHERE order_id = @SuccessfulRefundOrderId AND eligibility_status = 'INELIGIBLE'
          AND eligibility_reason = 'PRE_SETTLE_REFUND'
          AND refund_state_snapshot IS NULL AND successful_refund_amount = 1.00
          AND is_settleable = 0 AND unsettleable_reason = 'PRE_SETTLE_REFUND')
        THROW 51805, 'Successful refunds must remain visible and cannot produce an eligible snapshot.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_OrderSettlementSource
        WHERE order_id = @UnpricedOrderId AND eligibility_status = 'INELIGIBLE'
          AND eligibility_reason = 'NOT_PRICED'
          AND electricity_base IS NULL AND service_base IS NULL
          AND minimum_adjustment IS NULL AND payable_amount IS NULL
          AND is_settleable = 0 AND unsettleable_reason = 'NOT_PRICED')
        THROW 51806, 'Unpriced defaults must not be exposed as settlement amounts.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_OrderSettlementSource
        WHERE order_id = @EnterpriseMissingReceiptOrderId AND eligibility_status = 'INELIGIBLE'
          AND eligibility_reason = 'ENTERPRISE_RECEIPT_MISSING'
          AND settlement_source = 'ENTERPRISE' AND enterprise_refund_check_required = 1
          AND is_settleable = 0 AND unsettleable_reason = 'ENTERPRISE_RECEIPT_MISSING')
        THROW 51807, 'Enterprise orders without a paid A2 receipt must be excluded.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_OrderSettlementSource
        WHERE order_id = @EnterpriseVerifiedReceiptOrderId
          AND eligibility_status = 'REVIEW_REQUIRED'
          AND eligibility_reason = 'ENTERPRISE_REFUND_CHECK_REQUIRED'
          AND enterprise_receipt_verified = 1
          AND enterprise_receipt_billing_period_start = '2026-10-01'
          AND refund_state_snapshot = 'NONE'
          AND is_settleable = 1 AND unsettleable_reason IS NULL)
        THROW 51808, 'Enterprise receipt and separate refund review state were not exposed.', 1;

    SELECT order_id, station_id, opening_station_id, ended_at, ended_at_snapshot,
           energy_kwh, energy_snapshot, settled_at, settled_at_snapshot,
           electricity_base, service_base, minimum_adjustment, settled_at_snapshot,
           settlement_source, refund_state_snapshot, is_settleable, unsettleable_reason,
           eligibility_status, eligibility_reason,
           enterprise_receipt_verified
    FROM dbo.v_OrderSettlementSource
    WHERE order_id IN (@EligibleOrderId, @FailedRefundOrderId, @SuccessfulRefundOrderId,
                       @UnpricedOrderId, @EnterpriseMissingReceiptOrderId,
                       @EnterpriseVerifiedReceiptOrderId)
    ORDER BY order_id;
    SELECT N'V04 SettlementDetail 快照及资格/退款审阅' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

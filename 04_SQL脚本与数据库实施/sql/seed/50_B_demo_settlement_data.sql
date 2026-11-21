USE [EV_B_TEST];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51100, 'B demo seed must run in EV_B_TEST.', 1;

IF OBJECT_ID(N'dbo.SysRole', N'U') IS NULL
   OR OBJECT_ID(N'dbo.SysAccount', N'U') IS NULL
   OR OBJECT_ID(N'dbo.UserProfile', N'U') IS NULL
   OR OBJECT_ID(N'dbo.EnterpriseProfile', N'U') IS NULL
    THROW 51101, 'Install the official R core tables and role seed before loading B demo data.', 1;

IF OBJECT_ID(N'dbo.Operator', N'U') IS NULL
   OR OBJECT_ID(N'dbo.ChargingStation', N'U') IS NULL
   OR OBJECT_ID(N'dbo.ChargingPile', N'U') IS NULL
   OR OBJECT_ID(N'dbo.ChargingGun', N'U') IS NULL
   OR OBJECT_ID(N'dbo.BillingRuleVersion', N'U') IS NULL
   OR OBJECT_ID(N'dbo.BillingRule', N'U') IS NULL
   OR OBJECT_ID(N'dbo.ChargingOrder', N'U') IS NULL
   OR OBJECT_ID(N'dbo.OrderFeeDetail', N'U') IS NULL
   OR OBJECT_ID(N'dbo.PaymentRecord', N'U') IS NULL
   OR OBJECT_ID(N'dbo.RefundRecord', N'U') IS NULL
    THROW 51102, 'Install A1 and B tables before loading demo data.', 1;

DECLARE @OperatorId VARCHAR(20) = 'B_DEMO_OP01';
DECLARE @StationId VARCHAR(20) = 'B_DEMO_ST01';
DECLARE @PileId VARCHAR(20) = 'B_DEMO_PILE01';
DECLARE @GunId VARCHAR(20) = 'B_DEMO_GUN01';
DECLARE @UserId VARCHAR(20) = 'B_DEMO_USER01';
DECLARE @EnterpriseId VARCHAR(20) = 'B_DEMO_ENT01';
DECLARE @RuleVersionId BIGINT = 920260101;
DECLARE @RefundRuleVersionId BIGINT = 920260102;
DECLARE @R01RoleId TINYINT;
DECLARE @PersonalRoleId TINYINT;
DECLARE @EnterpriseRoleId TINYINT;
DECLARE @NoticeAccountId BIGINT;
DECLARE @UserAccountId BIGINT;
DECLARE @EnterpriseAccountId BIGINT;
DECLARE @BillingRuleId BIGINT;
DECLARE @RefundBillingRuleId BIGINT;
DECLARE @NormalOrderId BIGINT;
DECLARE @OutsideOrderId BIGINT;
DECLARE @RefundOrderId BIGINT;
DECLARE @NormalPaymentId BIGINT;
DECLARE @OutsidePaymentId BIGINT;
DECLARE @RefundPaymentId BIGINT;

SELECT @R01RoleId = role_id FROM dbo.SysRole WHERE role_code = 'R01';
SELECT @PersonalRoleId = role_id FROM dbo.SysRole WHERE role_code = 'R04';
SELECT @EnterpriseRoleId = role_id FROM dbo.SysRole WHERE role_code = 'R05';

IF @R01RoleId IS NULL OR @PersonalRoleId IS NULL OR @EnterpriseRoleId IS NULL
    THROW 51103, 'Seed the agreed R01, R04 and R05 roles before loading B demo data.', 1;

BEGIN TRANSACTION;

-- These B-owned scenario identities use the official R role IDs. The hashes are
-- unusable test markers; these records are not login credentials.
IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE username = 'B_DEMO_R01')
    INSERT INTO dbo.SysAccount (username, password_hash, role_id, status)
    VALUES ('B_DEMO_R01', 'TEST_ONLY_NO_LOGIN', @R01RoleId, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE username = @UserId)
    INSERT INTO dbo.SysAccount (username, password_hash, role_id, status)
    VALUES (@UserId, 'TEST_ONLY_NO_LOGIN', @PersonalRoleId, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE username = @EnterpriseId)
    INSERT INTO dbo.SysAccount (username, password_hash, role_id, status)
    VALUES (@EnterpriseId, 'TEST_ONLY_NO_LOGIN', @EnterpriseRoleId, 1);

SELECT @NoticeAccountId = account_id FROM dbo.SysAccount
WHERE username = 'B_DEMO_R01' AND role_id = @R01RoleId AND status = 1;
SELECT @UserAccountId = account_id FROM dbo.SysAccount
WHERE username = @UserId AND role_id = @PersonalRoleId AND status = 1;
SELECT @EnterpriseAccountId = account_id FROM dbo.SysAccount
WHERE username = @EnterpriseId AND role_id = @EnterpriseRoleId AND status = 1;

IF @NoticeAccountId IS NULL OR @UserAccountId IS NULL OR @EnterpriseAccountId IS NULL
    THROW 51104, 'A B demo account exists with an unexpected role or disabled status.', 1;

IF NOT EXISTS (SELECT 1 FROM dbo.UserProfile WHERE user_id = @UserId)
    INSERT INTO dbo.UserProfile
        (user_id, account_id, phone_ciphertext, phone_hash, real_name_status,
         register_channel, registered_at, status)
    VALUES
        (@UserId, @UserAccountId, HASHBYTES('SHA2_256', @UserId),
         CONVERT(CHAR(64), HASHBYTES('SHA2_256', @UserId), 2), 'UNVERIFIED',
         'B_DEMO', '2026-01-01T00:00:00', 'ACTIVE');

IF EXISTS (SELECT 1 FROM dbo.UserProfile WHERE user_id = @UserId AND account_id <> @UserAccountId)
    THROW 51113, 'B_DEMO_USER01 is already linked to a different R account.', 1;

IF NOT EXISTS (SELECT 1 FROM dbo.EnterpriseProfile WHERE enterprise_id = @EnterpriseId)
    INSERT INTO dbo.EnterpriseProfile
        (enterprise_id, account_id, enterprise_name, credit_code, contact_name,
         contact_phone_ciphertext, status)
    VALUES
        (@EnterpriseId, @EnterpriseAccountId, N'B 演示企业', 'BDEMO0000000000001',
         N'演示联系人', HASHBYTES('SHA2_256', @EnterpriseId), 'ACTIVE');

IF EXISTS (SELECT 1 FROM dbo.EnterpriseProfile
           WHERE enterprise_id = @EnterpriseId AND account_id <> @EnterpriseAccountId)
    THROW 51114, 'B_DEMO_ENT01 is already linked to a different R account.', 1;

IF NOT EXISTS (SELECT 1 FROM dbo.Operator WHERE operator_id = @OperatorId)
    INSERT INTO dbo.Operator (operator_id, operator_name, status)
    VALUES (@OperatorId, N'B 样例运营商', 'ACTIVE');

IF NOT EXISTS (SELECT 1 FROM dbo.ChargingStation WHERE station_id = @StationId)
    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, status,
         workorder_notice_account_id)
    VALUES
        (@StationId, N'B 样例场站', N'测试数据', 116.400000, 39.900000,
         @OperatorId, 2, N'00:00-24:00', N'测试期间免费', 'OPERATING',
         @NoticeAccountId);

IF NOT EXISTS (SELECT 1 FROM dbo.ChargingPile WHERE pile_id = @PileId)
    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw,
         communication_protocol, commissioned_date, warranty_end_date,
         status, reported_status)
    VALUES
        (@PileId, @StationId, N'B-DEMO-DC120', 120.00, N'OCPP-1.6',
         '2026-01-01', '2028-01-01', 'IDLE', 'IDLE');

IF NOT EXISTS (SELECT 1 FROM dbo.ChargingGun WHERE gun_id = @GunId)
    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status, reported_status)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 120.00, 'IDLE', 'IDLE');

IF NOT EXISTS (
    SELECT 1 FROM dbo.BillingRuleVersion
    WHERE rule_version_id = @RuleVersionId
)
    INSERT INTO dbo.BillingRuleVersion
        (rule_version_id, station_id, enterprise_id, free_minutes,
         minimum_amount, effective_from, effective_to, status)
    VALUES
        (@RuleVersionId, @StationId, NULL, 0, 5.00,
         '2026-01-01T00:00:00', '2026-10-20T00:00:00', 'ACTIVE');

IF EXISTS
(
    SELECT 1 FROM dbo.BillingRuleVersion
    WHERE rule_version_id = @RuleVersionId
      AND (station_id <> @StationId OR enterprise_id IS NOT NULL
           OR minimum_amount <> 5.00 OR effective_from <> '2026-01-01T00:00:00'
           OR effective_to <> '2026-10-20T00:00:00' OR status <> 'ACTIVE')
)
    THROW 51110, 'B demo rule version 920260101 has unexpected facts; rebuild EV_B_TEST.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM dbo.BillingRuleVersion
    WHERE rule_version_id = @RefundRuleVersionId
)
    INSERT INTO dbo.BillingRuleVersion
        (rule_version_id, station_id, enterprise_id, free_minutes,
         minimum_amount, effective_from, effective_to, status)
    VALUES
        (@RefundRuleVersionId, @StationId, NULL, 0, 8.00,
         '2026-10-20T00:00:00', NULL, 'ACTIVE');

IF EXISTS
(
    SELECT 1 FROM dbo.BillingRuleVersion
    WHERE rule_version_id = @RefundRuleVersionId
      AND (station_id <> @StationId OR enterprise_id IS NOT NULL
           OR minimum_amount <> 8.00 OR effective_from <> '2026-10-20T00:00:00'
           OR effective_to IS NOT NULL OR status <> 'ACTIVE')
)
    THROW 51111, 'B demo rule version 920260102 has unexpected facts; rebuild EV_B_TEST.', 1;

IF NOT EXISTS (
    SELECT 1 FROM dbo.BillingRule
    WHERE rule_version_id = @RuleVersionId
      AND period_start_time = '00:00:00'
)
    INSERT INTO dbo.BillingRule
        (rule_version_id, period_type, period_start_time, period_end_time,
         electricity_price, service_price)
    VALUES
        (@RuleVersionId, N'平', '00:00:00', '23:59:00', 2.0000, 1.0000);

IF NOT EXISTS
(
    SELECT 1 FROM dbo.BillingRule
    WHERE rule_version_id = @RefundRuleVersionId
      AND period_start_time = '00:00:00'
)
    INSERT INTO dbo.BillingRule
        (rule_version_id, period_type, period_start_time, period_end_time,
         electricity_price, service_price)
    VALUES
        (@RefundRuleVersionId, N'平', '00:00:00', '23:59:00', 2.0000, 1.0000);

SELECT @BillingRuleId = billing_rule_id
FROM dbo.BillingRule
WHERE rule_version_id = @RuleVersionId
  AND period_start_time = '00:00:00';

IF @BillingRuleId IS NULL
    THROW 51105, 'Could not resolve the B demo billing rule.', 1;

SELECT @RefundBillingRuleId = billing_rule_id
FROM dbo.BillingRule
WHERE rule_version_id = @RefundRuleVersionId
  AND period_start_time = '00:00:00';

IF @RefundBillingRuleId IS NULL
    THROW 51112, 'Could not resolve the B demo refund billing rule.', 1;

IF (SELECT COUNT(*) FROM dbo.ChargingOrder WHERE user_id = @UserId AND gun_id = @GunId
    AND created_at = '2026-10-01T00:00:01') > 1
    THROW 51106, 'Duplicate normal demo order marker; rebuild EV_B_TEST.', 1;

SELECT @NormalOrderId = order_id FROM dbo.ChargingOrder
WHERE user_id = @UserId AND gun_id = @GunId
  AND created_at = '2026-10-01T00:00:01';
IF @NormalOrderId IS NULL
BEGIN
    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, binding_id, enterprise_quota_id,
         start_time, end_time, energy_kwh, status, gross_amount,
         minimum_adjustment, discount_amount, paid_amount, refund_amount,
         created_at, updated_at, opening_station_id, settled_at,
         startup_rule_version_id, priced_at, device_released_at)
    VALUES
        ('PERSONAL', @UserId, @GunId, NULL, NULL,
         '2026-10-15T09:00:00', '2026-10-15T10:00:00', 1.000, 'PAID',
         5.00, 2.00, 3.00, 2.00, 0.00,
         '2026-10-01T00:00:01', '2026-10-15T10:00:00', @StationId,
         '2026-10-15T10:00:05', @RuleVersionId,
         '2026-10-15T10:00:04', '2026-10-15T10:00:03');
    SET @NormalOrderId = CONVERT(BIGINT, SCOPE_IDENTITY());
END;

IF (SELECT COUNT(*) FROM dbo.ChargingOrder WHERE user_id = @UserId AND gun_id = @GunId
    AND created_at = '2026-10-01T00:00:02') > 1
    THROW 51107, 'Duplicate outside-period demo order marker; rebuild EV_B_TEST.', 1;

SELECT @OutsideOrderId = order_id FROM dbo.ChargingOrder
WHERE user_id = @UserId AND gun_id = @GunId
  AND created_at = '2026-10-01T00:00:02';
IF @OutsideOrderId IS NULL
BEGIN
    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, binding_id, enterprise_quota_id,
         start_time, end_time, energy_kwh, status, gross_amount,
         minimum_adjustment, discount_amount, paid_amount, refund_amount,
         created_at, updated_at, opening_station_id, settled_at,
         startup_rule_version_id, priced_at, device_released_at)
    VALUES
        ('PERSONAL', @UserId, @GunId, NULL, NULL,
         '2026-09-30T22:00:00', '2026-09-30T23:00:00', 1.000, 'PAID',
         5.00, 2.00, 0.00, 5.00, 0.00,
         '2026-10-01T00:00:02', '2026-09-30T23:00:00', @StationId,
         '2026-09-30T23:00:05', @RuleVersionId,
         '2026-09-30T23:00:04', '2026-09-30T23:00:03');
    SET @OutsideOrderId = CONVERT(BIGINT, SCOPE_IDENTITY());
END;

IF (SELECT COUNT(*) FROM dbo.ChargingOrder WHERE user_id = @UserId AND gun_id = @GunId
    AND created_at = '2026-10-01T00:00:03') > 1
    THROW 51108, 'Duplicate refund demo order marker; rebuild EV_B_TEST.', 1;

SELECT @RefundOrderId = order_id FROM dbo.ChargingOrder
WHERE user_id = @UserId AND gun_id = @GunId
  AND created_at = '2026-10-01T00:00:03';
IF @RefundOrderId IS NULL
BEGIN
    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, binding_id, enterprise_quota_id,
         start_time, end_time, energy_kwh, status, gross_amount,
         minimum_adjustment, discount_amount, paid_amount, refund_amount,
         created_at, updated_at, opening_station_id, settled_at,
         startup_rule_version_id, priced_at, device_released_at)
    VALUES
        ('PERSONAL', @UserId, @GunId, NULL, NULL,
         '2026-10-20T11:00:00', '2026-10-20T12:00:00', 2.000, 'PAID',
         8.00, 2.00, 0.00, 8.00, 1.00,
         '2026-10-01T00:00:03', '2026-10-25T12:00:00', @StationId,
         '2026-10-20T12:00:05', @RefundRuleVersionId,
         '2026-10-20T12:00:04', '2026-10-20T12:00:03');
    SET @RefundOrderId = CONVERT(BIGINT, SCOPE_IDENTITY());
END;

IF NOT EXISTS (SELECT 1 FROM dbo.OrderFeeDetail WHERE order_id = @NormalOrderId
               AND segment_start = '2026-10-15T09:00:00')
    INSERT INTO dbo.OrderFeeDetail
        (order_id, billing_rule_id, segment_start, segment_end,
         segment_energy_kwh, free_service_fee)
    VALUES (@NormalOrderId, @BillingRuleId, '2026-10-15T09:00:00',
            '2026-10-15T10:00:00', 1.000, 0.00);

IF NOT EXISTS (SELECT 1 FROM dbo.OrderFeeDetail WHERE order_id = @OutsideOrderId
               AND segment_start = '2026-09-30T22:00:00')
    INSERT INTO dbo.OrderFeeDetail
        (order_id, billing_rule_id, segment_start, segment_end,
         segment_energy_kwh, free_service_fee)
    VALUES (@OutsideOrderId, @BillingRuleId, '2026-09-30T22:00:00',
            '2026-09-30T23:00:00', 1.000, 0.00);

IF NOT EXISTS (SELECT 1 FROM dbo.OrderFeeDetail WHERE order_id = @RefundOrderId
               AND segment_start = '2026-10-20T11:00:00')
    INSERT INTO dbo.OrderFeeDetail
        (order_id, billing_rule_id, segment_start, segment_end,
         segment_energy_kwh, free_service_fee)
    VALUES (@RefundOrderId, @RefundBillingRuleId, '2026-10-20T11:00:00',
            '2026-10-20T12:00:00', 2.000, 0.00);

IF NOT EXISTS (SELECT 1 FROM dbo.PaymentRecord WHERE pay_channel = 'OTHER'
               AND transaction_no = 'B-DEMO-PAY-NORMAL')
    INSERT INTO dbo.PaymentRecord (order_id, pay_channel, transaction_no, pay_amount, pay_time)
    VALUES (@NormalOrderId, 'OTHER', 'B-DEMO-PAY-NORMAL', 2.00, '2026-10-15T10:00:05');

IF NOT EXISTS (SELECT 1 FROM dbo.PaymentRecord WHERE pay_channel = 'OTHER'
               AND transaction_no = 'B-DEMO-PAY-OUTSIDE')
    INSERT INTO dbo.PaymentRecord (order_id, pay_channel, transaction_no, pay_amount, pay_time)
    VALUES (@OutsideOrderId, 'OTHER', 'B-DEMO-PAY-OUTSIDE', 5.00, '2026-09-30T23:00:05');

SELECT @RefundPaymentId = payment_id FROM dbo.PaymentRecord
WHERE pay_channel = 'OTHER' AND transaction_no = 'B-DEMO-PAY-REFUND';
IF @RefundPaymentId IS NULL
BEGIN
    INSERT INTO dbo.PaymentRecord
        (order_id, pay_channel, transaction_no, pay_amount, pay_time, refund_amount)
    VALUES (@RefundOrderId, 'OTHER', 'B-DEMO-PAY-REFUND', 8.00,
            '2026-10-20T12:00:05', 1.00);
    SET @RefundPaymentId = CONVERT(BIGINT, SCOPE_IDENTITY());
END;

SELECT @NormalPaymentId = payment_id FROM dbo.PaymentRecord
WHERE pay_channel = 'OTHER' AND transaction_no = 'B-DEMO-PAY-NORMAL';
SELECT @OutsidePaymentId = payment_id FROM dbo.PaymentRecord
WHERE pay_channel = 'OTHER' AND transaction_no = 'B-DEMO-PAY-OUTSIDE';

IF @NormalPaymentId IS NULL OR @OutsidePaymentId IS NULL OR @RefundPaymentId IS NULL
    THROW 51109, 'Could not resolve all B demo payment records.', 1;

IF NOT EXISTS (SELECT 1 FROM dbo.RefundRecord WHERE refund_no = 'B-DEMO-REFUND-001')
    INSERT INTO dbo.RefundRecord
        (payment_id, refund_no, refund_amount, status, reason, refunded_at)
    VALUES (@RefundPaymentId, 'B-DEMO-REFUND-001', 1.00, 'SUCCESS',
            N'B 到 D 退款联调样例', '2026-10-25T12:00:00');

COMMIT TRANSACTION;

SELECT N'正常可结算' AS sample_name, @NormalOrderId AS order_id,
       @StationId AS station_id, CONVERT(CHAR(6), '202610') AS billing_period,
       CAST(5.00 AS DECIMAL(12,2)) AS gross_amount,
       CAST(3.00 AS DECIMAL(12,2)) AS discount_amount,
       CAST(2.00 AS DECIMAL(12,2)) AS paid_amount,
       CAST(0.00 AS DECIMAL(12,2)) AS refund_amount
UNION ALL
SELECT N'账期外排除', @OutsideOrderId, @StationId, '202610',
       5.00, 0.00, 5.00, 0.00
UNION ALL
SELECT N'成功退款凭据', @RefundOrderId, @StationId, '202610',
       8.00, 0.00, 8.00, 1.00;
GO

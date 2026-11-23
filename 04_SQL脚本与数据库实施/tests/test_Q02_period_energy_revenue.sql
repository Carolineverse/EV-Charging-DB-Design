-- Q02 回归测试：日期范围、冻结费率关联、逐段舍入与服务费折抵。
-- 测试创建已核价订单，所有夹具在 EV_B_TEST 的事务中回滚。

SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51200, 'This test must run in EV_B_TEST.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @UserId VARCHAR(20) = 'TST_Q02_U' + @Token;
DECLARE @OperatorId VARCHAR(20) = 'Q02OP' + @Token;
DECLARE @StationId VARCHAR(20) = 'Q02ST' + @Token;
DECLARE @PileId VARCHAR(20) = 'Q02PL' + @Token;
DECLARE @GunId VARCHAR(20) = 'Q02GN' + @Token;
DECLARE @RuleVersionId BIGINT = 910000000000000000
    + ABS(CAST(CHECKSUM(NEWID()) AS BIGINT));
DECLARE @ValleyRuleId BIGINT;
DECLARE @PeakRuleId BIGINT;
DECLARE @OrderId BIGINT;
DECLARE @OutsideOrderId BIGINT;
DECLARE @StartInclusive DATETIME2(3) = '2026-10-15T00:00:00';
DECLARE @EndExclusive DATETIME2(3) = '2026-10-16T00:00:00';
DECLARE @Actual TABLE
(
    period_type NCHAR(1) PRIMARY KEY,
    energy_kwh DECIMAL(10,3),
    electricity_amount DECIMAL(12,2),
    service_amount_before_free DECIMAL(12,2),
    free_service_fee DECIMAL(12,2),
    service_amount_after_free DECIMAL(12,2)
);

BEGIN TRY
    BEGIN TRANSACTION;

    -- Complete the R-domain parents using the installed roles and this test's own identities.
    DECLARE @FixtureAccounts TABLE (username VARCHAR(50) PRIMARY KEY, account_id BIGINT NOT NULL);
    INSERT INTO dbo.SysAccount (username, password_hash, role_id)
    OUTPUT INSERTED.username, INSERTED.account_id INTO @FixtureAccounts (username, account_id)
    SELECT f.username, 'REPLACE_WITH_REAL_PASSWORD_HASH', r.role_id
    FROM (VALUES
        ('TST_Q02_A' + @Token, 'R01'),
        (@UserId, 'R04')
    ) f(username, role_code)
    JOIN dbo.SysRole r ON r.role_code = f.role_code;
    IF @@ROWCOUNT <> 2
        THROW 52990, 'Install the required R roles before running this fixture.', 1;
    DECLARE @NoticeAccountId BIGINT = (SELECT account_id FROM @FixtureAccounts WHERE username = 'TST_Q02_A' + @Token);

    INSERT INTO dbo.UserProfile
        (user_id, account_id, phone_ciphertext, phone_hash, real_name_status, registered_at, status)
    SELECT f.username, f.account_id, 0x00, CONVERT(CHAR(64), HASHBYTES('SHA2_256', f.username), 2),
           'UNVERIFIED', '2026-01-01', 'ACTIVE'
    FROM @FixtureAccounts f
    WHERE f.username IN (@UserId);

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'Q02测试运营商');

    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'Q02测试场站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         1, N'00:00-24:00', N'测试', @NoticeAccountId);

    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileId, @StationId, N'Q02-MODEL', 60.00, N'OCPP',
         '2026-01-01', '2028-01-01', 'IDLE');

    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE');

    INSERT INTO dbo.BillingRuleVersion
        (rule_version_id, station_id, enterprise_id, free_minutes, minimum_amount,
         effective_from, status)
    VALUES
        (@RuleVersionId, @StationId, NULL, 0, 0.00,
         '2026-10-01T00:00:00', 'ACTIVE');

    INSERT INTO dbo.BillingRule
        (rule_version_id, period_type, period_start_time, period_end_time,
         electricity_price, service_price)
    VALUES
        (@RuleVersionId, N'谷', '00:00:00', '12:00:00', 1.0000, 1.0000),
        (@RuleVersionId, N'峰', '12:00:00', '23:59:00', 2.0000, 1.0000);

    SELECT @ValleyRuleId = billing_rule_id
    FROM dbo.BillingRule
    WHERE rule_version_id = @RuleVersionId AND period_type = N'谷';

    SELECT @PeakRuleId = billing_rule_id
    FROM dbo.BillingRule
    WHERE rule_version_id = @RuleVersionId AND period_type = N'峰';

    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, start_time, end_time, energy_kwh, status,
         opening_station_id, startup_rule_version_id)
    VALUES
        ('PERSONAL', @UserId, @GunId, '2026-10-15T11:58:00',
         '2026-10-15T12:01:00', 0.015, 'PENDING_PAYMENT', @StationId, @RuleVersionId);
    SET @OrderId = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.OrderFeeDetail
        (order_id, billing_rule_id, segment_start, segment_end,
         segment_energy_kwh, free_service_fee)
    VALUES
        (@OrderId, @ValleyRuleId, '2026-10-15T11:58:00', '2026-10-15T11:59:00', 0.005, 0.01),
        (@OrderId, @ValleyRuleId, '2026-10-15T11:59:00', '2026-10-15T12:00:00', 0.005, 0.00),
        (@OrderId, @PeakRuleId, '2026-10-15T12:00:00', '2026-10-15T12:01:00', 0.005, 0.00);

    EXEC dbo.usp_PriceChargingOrder @order_id = @OrderId, @discount_amount = 0.00;

    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, start_time, end_time, energy_kwh, status,
         opening_station_id, startup_rule_version_id)
    VALUES
        ('PERSONAL', @UserId, @GunId, '2026-10-14T11:58:00',
         '2026-10-14T11:59:00', 0.005, 'PENDING_PAYMENT', @StationId, @RuleVersionId);
    SET @OutsideOrderId = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.OrderFeeDetail
        (order_id, billing_rule_id, segment_start, segment_end,
         segment_energy_kwh, free_service_fee)
    VALUES
        (@OutsideOrderId, @ValleyRuleId, '2026-10-14T11:58:00', '2026-10-14T11:59:00', 0.005, 0.00);

    EXEC dbo.usp_PriceChargingOrder @order_id = @OutsideOrderId, @discount_amount = 0.00;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.ChargingOrder WHERE order_id = @OrderId AND priced_at IS NOT NULL)
        THROW 51201, 'The Q02 fixture order was not priced successfully.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.ChargingOrder WHERE order_id = @OutsideOrderId AND priced_at IS NOT NULL)
        THROW 51205, 'The out-of-range fixture order was not priced successfully.', 1;

    WITH priced_segments AS
    (
        SELECT s.station_id,
               s.station_name,
               r.period_type,
               d.segment_energy_kwh,
               r.electricity_price,
               r.service_price,
               d.free_service_fee
        FROM dbo.ChargingOrder AS o
        INNER JOIN dbo.ChargingStation AS s
            ON s.station_id = o.opening_station_id
        INNER JOIN dbo.BillingRuleVersion AS v
            ON v.rule_version_id = o.startup_rule_version_id
           AND v.station_id = o.opening_station_id
        INNER JOIN dbo.OrderFeeDetail AS d
            ON d.order_id = o.order_id
           AND d.segment_start >= @StartInclusive
           AND d.segment_start < @EndExclusive
        INNER JOIN dbo.BillingRule AS r
            ON r.billing_rule_id = d.billing_rule_id
           AND r.rule_version_id = v.rule_version_id
        WHERE o.priced_at IS NOT NULL
          AND o.opening_station_id = @StationId
    )
    INSERT INTO @Actual
        (period_type, energy_kwh, electricity_amount,
         service_amount_before_free, free_service_fee, service_amount_after_free)
    SELECT period_type,
           SUM(segment_energy_kwh),
           SUM(ROUND(segment_energy_kwh * electricity_price, 2)),
           SUM(ROUND(segment_energy_kwh * service_price, 2)),
           SUM(free_service_fee),
           SUM(ROUND(segment_energy_kwh * service_price, 2) - free_service_fee)
    FROM priced_segments
    GROUP BY period_type;

    IF (SELECT COUNT(*) FROM @Actual) <> 2
        THROW 51202, 'Q02 did not return both fixture tariff periods.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM @Actual WHERE period_type = N'谷' AND energy_kwh = 0.010
        AND electricity_amount = 0.02 AND service_amount_before_free = 0.02
        AND free_service_fee = 0.01 AND service_amount_after_free = 0.01)
        THROW 51203, 'Q02 valley totals are incorrect or were rounded after aggregation.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM @Actual WHERE period_type = N'峰' AND energy_kwh = 0.005
        AND electricity_amount = 0.01 AND service_amount_before_free = 0.01
        AND free_service_fee = 0.00 AND service_amount_after_free = 0.01)
        THROW 51204, 'Q02 peak totals are incorrect.', 1;

    SELECT @OrderId AS order_id, gross_amount, priced_at
    FROM dbo.ChargingOrder
    WHERE order_id = @OrderId;
    SELECT period_type, energy_kwh, electricity_amount,
           service_amount_before_free, free_service_fee, service_amount_after_free
    FROM @Actual
    ORDER BY period_type;
    SELECT N'Q02 分段舍入与时段聚合' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

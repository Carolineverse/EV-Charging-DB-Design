-- V05 回归测试：按每条费用段派生金额并显示冻结版本是否匹配。
-- 所有夹具与核价写入在 EV_B_TEST 的事务中回滚。

SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51600, 'This test must run in EV_B_TEST.', 1;
IF OBJECT_ID(N'dbo.v_BOrderFeeSegments', N'V') IS NULL
    THROW 51601, 'Install dbo.v_BOrderFeeSegments before this test.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @UserId VARCHAR(20) = 'TST_V05_U' + @Token;
DECLARE @OperatorId VARCHAR(20) = 'V05OP' + @Token;
DECLARE @StationId VARCHAR(20) = 'V05ST' + @Token;
DECLARE @PileId VARCHAR(20) = 'V05PL' + @Token;
DECLARE @GunId VARCHAR(20) = 'V05GN' + @Token;
DECLARE @RuleVersionId BIGINT = 920000000000000000
    + ABS(CAST(CHECKSUM(NEWID()) AS BIGINT));
DECLARE @RuleId BIGINT;
DECLARE @OrderId BIGINT;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Complete the R-domain parents using the installed roles and this test's own identities.
    DECLARE @FixtureAccounts TABLE (username VARCHAR(50) PRIMARY KEY, account_id BIGINT NOT NULL);
    INSERT INTO dbo.SysAccount (username, password_hash, role_id)
    OUTPUT INSERTED.username, INSERTED.account_id INTO @FixtureAccounts (username, account_id)
    SELECT f.username, 'REPLACE_WITH_REAL_PASSWORD_HASH', r.role_id
    FROM (VALUES
        ('TST_V05_A' + @Token, 'R01'),
        (@UserId, 'R04')
    ) f(username, role_code)
    JOIN dbo.SysRole r ON r.role_code = f.role_code;
    IF @@ROWCOUNT <> 2
        THROW 52990, 'Install the required R roles before running this fixture.', 1;
    DECLARE @NoticeAccountId BIGINT = (SELECT account_id FROM @FixtureAccounts WHERE username = 'TST_V05_A' + @Token);

    INSERT INTO dbo.UserProfile
        (user_id, account_id, phone_ciphertext, phone_hash, real_name_status, registered_at, status)
    SELECT f.username, f.account_id, 0x00, CONVERT(CHAR(64), HASHBYTES('SHA2_256', f.username), 2),
           'UNVERIFIED', '2026-01-01', 'ACTIVE'
    FROM @FixtureAccounts f
    WHERE f.username IN (@UserId);

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'V05测试运营商');
    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'V05测试场站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         1, N'00:00-24:00', N'测试', @NoticeAccountId);
    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileId, @StationId, N'V05-MODEL', 60.00, N'OCPP', '2026-01-01', '2028-01-01', 'IDLE');
    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE');
    INSERT INTO dbo.BillingRuleVersion
        (rule_version_id, station_id, enterprise_id, free_minutes, minimum_amount,
         effective_from, status)
    VALUES
        (@RuleVersionId, @StationId, NULL, 0, 0.00, '2026-10-01T00:00:00', 'ACTIVE');
    INSERT INTO dbo.BillingRule
        (rule_version_id, period_type, period_start_time, period_end_time,
         electricity_price, service_price)
    VALUES
        (@RuleVersionId, N'谷', '00:00:00', '12:00:00', 1.0000, 1.0000);
    SET @RuleId = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, start_time, end_time, energy_kwh, status,
         opening_station_id, startup_rule_version_id)
    VALUES
        ('PERSONAL', @UserId, @GunId, '2026-10-15T10:00:00',
         '2026-10-15T10:02:00', 0.010, 'PENDING_PAYMENT', @StationId, @RuleVersionId);
    SET @OrderId = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.OrderFeeDetail
        (order_id, billing_rule_id, segment_start, segment_end,
         segment_energy_kwh, free_service_fee)
    VALUES
        (@OrderId, @RuleId, '2026-10-15T10:00:00', '2026-10-15T10:01:00', 0.005, 0.01),
        (@OrderId, @RuleId, '2026-10-15T10:01:00', '2026-10-15T10:02:00', 0.005, 0.00);

    EXEC dbo.usp_PriceChargingOrder @order_id = @OrderId, @discount_amount = 0.00;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.ChargingOrder WHERE order_id = @OrderId AND priced_at IS NOT NULL)
        THROW 51602, 'The V05 fixture order was not priced successfully.', 1;

    IF (SELECT COUNT(*) FROM dbo.v_BOrderFeeSegments WHERE order_id = @OrderId) <> 2
        THROW 51603, 'V05 did not return one row per fee segment.', 1;

    IF (SELECT SUM(electricity_amount) FROM dbo.v_BOrderFeeSegments WHERE order_id = @OrderId) <> 0.02
       OR (SELECT SUM(service_amount_before_free) FROM dbo.v_BOrderFeeSegments WHERE order_id = @OrderId) <> 0.02
       OR (SELECT SUM(free_service_fee) FROM dbo.v_BOrderFeeSegments WHERE order_id = @OrderId) <> 0.01
       OR (SELECT SUM(service_amount_after_free) FROM dbo.v_BOrderFeeSegments WHERE order_id = @OrderId) <> 0.01
       OR EXISTS (SELECT 1 FROM dbo.v_BOrderFeeSegments WHERE order_id = @OrderId AND rule_version_matches = 0)
        THROW 51604, 'V05 derived segment amounts or version match are incorrect.', 1;

    SELECT order_id, order_fee_detail_id, period_type, segment_energy_kwh,
           electricity_amount, service_amount_before_free, free_service_fee,
           service_amount_after_free, rule_version_matches
    FROM dbo.v_BOrderFeeSegments
    WHERE order_id = @OrderId
    ORDER BY segment_start;
    SELECT N'V05 费用段金额与冻结版本' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

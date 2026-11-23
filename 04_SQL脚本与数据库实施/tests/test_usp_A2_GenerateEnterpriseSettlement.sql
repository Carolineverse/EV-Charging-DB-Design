-- P-A2 回归测试：结束月入账、启动月额度、幂等/唯一保护及调用方回滚。
-- 明确使用测试业务数据；测试完成后删除全部夹具。

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
    THROW 52500, 'This test must run in EV_B_TEST.', 1;
IF OBJECT_ID(N'dbo.usp_A2_GenerateEnterpriseSettlement', N'P') IS NULL
    THROW 52501, 'Install dbo.usp_A2_GenerateEnterpriseSettlement before this test.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @UserId VARCHAR(20) = 'TST_PA2_U' + @Token;
DECLARE @OperatorId VARCHAR(20) = 'PA2OP' + @Token;
DECLARE @StationId VARCHAR(20) = 'PA2ST' + @Token;
DECLARE @PileId VARCHAR(20) = 'PA2PL' + @Token;
DECLARE @GunId VARCHAR(20) = 'PA2GN' + @Token;
DECLARE @EnterpriseId VARCHAR(20) = 'TST_PA2_E' + @Token;
DECLARE @FleetMemberId VARCHAR(20) = 'PA2FM' + @Token;
DECLARE @VehicleId VARCHAR(20) = 'PA2VE' + @Token;
DECLARE @CardId VARCHAR(20) = 'PA2CA' + @Token;
DECLARE @SeptemberQuotaId VARCHAR(20) = 'PA2QS' + @Token;
DECLARE @OctoberQuotaId VARCHAR(20) = 'PA2QO' + @Token;
DECLARE @WrongMonthQuotaId VARCHAR(20) = 'PA2QW' + @Token;
DECLARE @RuleVersionId BIGINT = 950000000000000000
    + ABS(CAST(CHECKSUM(NEWID()) AS BIGINT));
DECLARE @BindingId BIGINT;
DECLARE @SeptemberStartOrderId BIGINT;
DECLARE @OctoberStartOrderId BIGINT;
DECLARE @WrongQuotaOrderId BIGINT;
DECLARE @OctoberSettlementId VARCHAR(20) = 'PA2OCT' + @Token;
DECLARE @NovemberSettlementId VARCHAR(20) = 'PA2NOV' + @Token;
DECLARE @DecemberSettlementId VARCHAR(20) = 'PA2DEC' + @Token;
DECLARE @RollbackSettlementId VARCHAR(20) = 'PA2RBK' + @Token;
DECLARE @DuplicateSettlementId VARCHAR(20) = 'PA2DUP' + @Token;
DECLARE @Output TABLE
(
    enterprise_settlement_id VARCHAR(20),
    order_count INT,
    total_energy_kwh DECIMAL(38,3),
    total_amount DECIMAL(38,2)
);
DECLARE @ErrorNumber INT;
DECLARE @PassCount INT = 0;
DECLARE @ExpectedCount INT = 6;
DECLARE @FixtureAccounts TABLE (username VARCHAR(50) PRIMARY KEY, account_id BIGINT NOT NULL);

BEGIN TRY
    BEGIN TRANSACTION;

    -- Complete the R-domain parents using the installed roles and this test's own identities.
    INSERT INTO dbo.SysAccount (username, password_hash, role_id)
    OUTPUT INSERTED.username, INSERTED.account_id INTO @FixtureAccounts (username, account_id)
    SELECT f.username, 'REPLACE_WITH_REAL_PASSWORD_HASH', r.role_id
    FROM (VALUES
        ('TST_PA2_A' + @Token, 'R01'),
        (@UserId, 'R04'),
        (@EnterpriseId, 'R05')
    ) f(username, role_code)
    JOIN dbo.SysRole r ON r.role_code = f.role_code;
    IF @@ROWCOUNT <> 3
        THROW 52990, 'Install the required R roles before running this fixture.', 1;
    DECLARE @NoticeAccountId BIGINT = (SELECT account_id FROM @FixtureAccounts WHERE username = 'TST_PA2_A' + @Token);

    INSERT INTO dbo.UserProfile
        (user_id, account_id, phone_ciphertext, phone_hash, real_name_status, registered_at, status)
    SELECT f.username, f.account_id, 0x00, CONVERT(CHAR(64), HASHBYTES('SHA2_256', f.username), 2),
           'UNVERIFIED', '2026-01-01', 'ACTIVE'
    FROM @FixtureAccounts f
    WHERE f.username IN (@UserId);

    INSERT INTO dbo.EnterpriseProfile
        (enterprise_id, account_id, enterprise_name, credit_code, contact_name, contact_phone_ciphertext, status)
    SELECT v.enterprise_id, f.account_id, N'Test enterprise', v.credit_code, N'Test contact', 0x00, 'ACTIVE'
    FROM (VALUES
        (@EnterpriseId, 'TST_PA2E' + @Token)
    ) v(enterprise_id, credit_code)
    JOIN @FixtureAccounts f ON f.username = v.enterprise_id;

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'P-A2测试运营商');
    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'P-A2测试场站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         1, N'00:00-24:00', N'测试', @NoticeAccountId);
    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileId, @StationId, N'P-A2-MODEL', 60.00, N'OCPP',
         '2026-01-01', '2028-01-01', 'IDLE');
    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE');

    INSERT INTO dbo.FleetMember
        (fleet_member_id, enterprise_id, user_id, member_no, joined_at)
    VALUES
        (@FleetMemberId, @EnterpriseId, @UserId, 'PA2-MEMBER', '2026-09-01');
    INSERT INTO dbo.Vehicle
        (vehicle_id, user_id, enterprise_id, plate_ciphertext, plate_hash,
         vehicle_model, battery_capacity_kwh, max_charging_power_kw)
    VALUES
        (@VehicleId, NULL, @EnterpriseId, 0x01,
         CONVERT(CHAR(64), HASHBYTES('SHA2_256', @VehicleId), 2),
         N'P-A2测试车辆', 70.00, 100.00);
    INSERT INTO dbo.EnterpriseCard (enterprise_card_id, enterprise_id, card_no)
    VALUES (@CardId, @EnterpriseId, 'PA2-CARD-' + @Token);
    INSERT INTO dbo.EnterpriseCardBinding
        (enterprise_card_id, vehicle_id, fleet_member_id, effective_start_at)
    VALUES
        (@CardId, @VehicleId, @FleetMemberId, '2026-09-01T00:00:00');
    SET @BindingId = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.EnterpriseQuota
        (enterprise_quota_id, fleet_member_id, quota_month, quota_amount, reserved_amount, status)
    VALUES
        (@SeptemberQuotaId, @FleetMemberId, '2026-09-01', 100.00, 0.00, 'INACTIVE'),
        (@OctoberQuotaId, @FleetMemberId, '2026-10-01', 100.00, 0.00, 'ACTIVE'),
        (@WrongMonthQuotaId, @FleetMemberId, '2026-11-01', 100.00, 0.00, 'ACTIVE');

    INSERT INTO dbo.BillingRuleVersion
        (rule_version_id, station_id, enterprise_id, free_minutes, minimum_amount,
         effective_from, status)
    VALUES
        (@RuleVersionId, @StationId, @EnterpriseId, 0, 0.00,
         '2026-09-01T00:00:00', 'ACTIVE');

    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, binding_id, enterprise_quota_id,
         start_time, end_time, energy_kwh, status, gross_amount, discount_amount,
         opening_station_id, settled_at, startup_rule_version_id, priced_at)
    VALUES
        ('ENTERPRISE', @UserId, @GunId, @BindingId, @SeptemberQuotaId,
         '2026-09-30T23:00:00', '2026-10-01T00:30:00', 1.000, 'PAID', 6.00, 2.00,
         @StationId, '2026-10-01T00:31:00', @RuleVersionId, '2026-10-01T00:30:30'),
        ('ENTERPRISE', @UserId, @GunId, @BindingId, @OctoberQuotaId,
         '2026-10-31T23:00:00', '2026-11-01T00:30:00', 1.000, 'PAID', 8.00, 1.00,
         @StationId, '2026-11-01T00:31:00', @RuleVersionId, '2026-11-01T00:30:30'),
        ('ENTERPRISE', @UserId, @GunId, @BindingId, @WrongMonthQuotaId,
         '2026-10-05T10:00:00', '2026-10-05T11:00:00', 1.000, 'PAID', 3.00, 0.00,
         @StationId, '2026-10-05T11:01:00', @RuleVersionId, '2026-10-05T11:00:30');

    SELECT @SeptemberStartOrderId = MIN(order_id) FROM dbo.ChargingOrder
    WHERE enterprise_quota_id = @SeptemberQuotaId;
    SELECT @OctoberStartOrderId = MIN(order_id) FROM dbo.ChargingOrder
    WHERE enterprise_quota_id = @OctoberQuotaId;
    SELECT @WrongQuotaOrderId = MIN(order_id) FROM dbo.ChargingOrder
    WHERE enterprise_quota_id = @WrongMonthQuotaId;

    COMMIT TRANSACTION;

    EXEC dbo.usp_A2_GenerateEnterpriseSettlement
        @enterprise_settlement_id = @OctoberSettlementId,
        @enterprise_id = @EnterpriseId,
        @billing_period_start = '2026-10-01',
        @generated_at = '2026-11-02T09:00:00';

    IF NOT EXISTS
       (SELECT 1 FROM dbo.EnterpriseSettlement
        WHERE enterprise_settlement_id = @OctoberSettlementId
          AND total_order_count = 1 AND total_energy_kwh = 1.000 AND total_amount = 4.00)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.EnterpriseSettlementDetail
        WHERE enterprise_settlement_id = @OctoberSettlementId
          AND order_id = @SeptemberStartOrderId AND payable_amount = 4.00
          AND energy_kwh = 1.000 AND fleet_member_id = @FleetMemberId
          AND vehicle_id = @VehicleId)
       OR EXISTS
       (SELECT 1 FROM dbo.EnterpriseSettlementDetail
        WHERE enterprise_settlement_id = @OctoberSettlementId
          AND order_id IN (@OctoberStartOrderId, @WrongQuotaOrderId))
        THROW 52502, 'October settlement did not use end month and startup-month quota correctly.', 1;
    SET @PassCount += 1;

    EXEC dbo.usp_A2_GenerateEnterpriseSettlement
        @enterprise_settlement_id = @NovemberSettlementId,
        @enterprise_id = @EnterpriseId,
        @billing_period_start = '2026-11-01',
        @generated_at = '2026-12-02T09:00:00';

    IF NOT EXISTS
       (SELECT 1 FROM dbo.EnterpriseSettlement
        WHERE enterprise_settlement_id = @NovemberSettlementId
          AND total_order_count = 1 AND total_energy_kwh = 1.000 AND total_amount = 7.00)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.EnterpriseSettlementDetail
        WHERE enterprise_settlement_id = @NovemberSettlementId
          AND order_id = @OctoberStartOrderId AND payable_amount = 7.00
          AND energy_kwh = 1.000)
        THROW 52503, 'November settlement did not include the order ended in November.', 1;
    SET @PassCount += 1;

    EXEC dbo.usp_A2_GenerateEnterpriseSettlement
        @enterprise_settlement_id = @DecemberSettlementId,
        @enterprise_id = @EnterpriseId,
        @billing_period_start = '2026-12-01',
        @generated_at = '2027-01-02T09:00:00';
    IF NOT EXISTS
       (SELECT 1 FROM dbo.EnterpriseSettlement
        WHERE enterprise_settlement_id = @DecemberSettlementId
          AND total_order_count = 0 AND total_energy_kwh = 0 AND total_amount = 0)
        THROW 52504, 'An empty settlement period should create a zero-total header.', 1;
    SET @PassCount += 1;

    BEGIN TRY
        EXEC dbo.usp_A2_GenerateEnterpriseSettlement
            @enterprise_settlement_id = @DuplicateSettlementId,
            @enterprise_id = @EnterpriseId,
            @billing_period_start = '2026-10-01';
        THROW 52505, 'P-A2 allowed duplicate generation for the enterprise month.', 1;
    END TRY
    BEGIN CATCH
        SET @ErrorNumber = ERROR_NUMBER();
        IF @ErrorNumber <> 52403 THROW;
        SET @PassCount += 1;
    END CATCH;

    BEGIN TRANSACTION;
    EXEC dbo.usp_A2_GenerateEnterpriseSettlement
        @enterprise_settlement_id = @RollbackSettlementId,
        @enterprise_id = @EnterpriseId,
        @billing_period_start = '2027-03-01';
    ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.EnterpriseSettlement
               WHERE enterprise_settlement_id = @RollbackSettlementId)
        THROW 52506, 'P-A2 did not participate in the caller rollback.', 1;
    SET @PassCount += 1;

    IF (SELECT COUNT(*) FROM dbo.EnterpriseSettlementDetail
        WHERE order_id IN (@SeptemberStartOrderId, @OctoberStartOrderId)) <> 2
        THROW 52507, 'An enterprise order was duplicated or omitted across billing months.', 1;
    SET @PassCount += 1;

    IF @PassCount <> @ExpectedCount
        THROW 52508, 'One or more P-A2 checks did not run.', 1;

    SELECT @PassCount AS passed_tests, @ExpectedCount AS expected_tests,
           N'全部通过' AS test_result;

    DELETE FROM dbo.EnterpriseSettlementDetail
    WHERE enterprise_settlement_id IN
        (@OctoberSettlementId, @NovemberSettlementId, @DecemberSettlementId);
    DELETE FROM dbo.EnterpriseSettlement
    WHERE enterprise_settlement_id IN
        (@OctoberSettlementId, @NovemberSettlementId, @DecemberSettlementId);
    DELETE FROM dbo.ChargingOrder
    WHERE order_id IN (@SeptemberStartOrderId, @OctoberStartOrderId, @WrongQuotaOrderId);
    DELETE FROM dbo.EnterpriseQuota
    WHERE enterprise_quota_id IN (@SeptemberQuotaId, @OctoberQuotaId, @WrongMonthQuotaId);
    DELETE FROM dbo.EnterpriseCardBinding WHERE binding_id = @BindingId;
    DELETE FROM dbo.EnterpriseCard WHERE enterprise_card_id = @CardId;
    DELETE FROM dbo.Vehicle WHERE vehicle_id = @VehicleId;
    DELETE FROM dbo.FleetMember WHERE fleet_member_id = @FleetMemberId;
    DELETE FROM dbo.BillingRuleVersion WHERE rule_version_id = @RuleVersionId;
    DELETE FROM dbo.ChargingGun WHERE gun_id = @GunId;
    DELETE FROM dbo.ChargingPile WHERE pile_id = @PileId;
    DELETE FROM dbo.ChargingStation WHERE station_id = @StationId;
    DELETE FROM dbo.Operator WHERE operator_id = @OperatorId;
    DELETE FROM dbo.UserProfile WHERE user_id = @UserId;
    DELETE FROM dbo.EnterpriseProfile WHERE enterprise_id = @EnterpriseId;
    DELETE a FROM dbo.SysAccount a
    JOIN @FixtureAccounts f ON f.account_id = a.account_id AND f.username = a.username;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    DELETE FROM dbo.EnterpriseSettlementDetail
    WHERE enterprise_settlement_id IN
        (@OctoberSettlementId, @NovemberSettlementId, @DecemberSettlementId, @RollbackSettlementId);
    DELETE FROM dbo.EnterpriseSettlement
    WHERE enterprise_settlement_id IN
        (@OctoberSettlementId, @NovemberSettlementId, @DecemberSettlementId, @RollbackSettlementId);
    DELETE FROM dbo.ChargingOrder
    WHERE order_id IN (@SeptemberStartOrderId, @OctoberStartOrderId, @WrongQuotaOrderId);
    DELETE FROM dbo.EnterpriseQuota
    WHERE enterprise_quota_id IN (@SeptemberQuotaId, @OctoberQuotaId, @WrongMonthQuotaId);
    DELETE FROM dbo.EnterpriseCardBinding WHERE binding_id = @BindingId;
    DELETE FROM dbo.EnterpriseCard WHERE enterprise_card_id = @CardId;
    DELETE FROM dbo.Vehicle WHERE vehicle_id = @VehicleId;
    DELETE FROM dbo.FleetMember WHERE fleet_member_id = @FleetMemberId;
    DELETE FROM dbo.BillingRuleVersion WHERE rule_version_id = @RuleVersionId;
    DELETE FROM dbo.ChargingGun WHERE gun_id = @GunId;
    DELETE FROM dbo.ChargingPile WHERE pile_id = @PileId;
    DELETE FROM dbo.ChargingStation WHERE station_id = @StationId;
    DELETE FROM dbo.Operator WHERE operator_id = @OperatorId;
    DELETE FROM dbo.UserProfile WHERE user_id = @UserId;
    DELETE FROM dbo.EnterpriseProfile WHERE enterprise_id = @EnterpriseId;
    DELETE a FROM dbo.SysAccount a
    JOIN @FixtureAccounts f ON f.account_id = a.account_id AND f.username = a.username;
    THROW;
END CATCH;

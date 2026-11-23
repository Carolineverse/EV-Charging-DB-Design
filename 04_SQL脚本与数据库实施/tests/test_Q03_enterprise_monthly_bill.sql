-- Q03 回归测试：三表月结汇总、父子快照一致及 end_time 月份归属。
-- 所有夹具在 EV_B_TEST 的事务中回滚；R EnterpriseProfile 不作占位。

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
    THROW 52200, 'This test must run in EV_B_TEST.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @UserId VARCHAR(20) = 'TST_Q03_U' + @Token;
DECLARE @OperatorId VARCHAR(20) = 'Q03OP' + @Token;
DECLARE @StationId VARCHAR(20) = 'Q03ST' + @Token;
DECLARE @PileId VARCHAR(20) = 'Q03PL' + @Token;
DECLARE @GunId VARCHAR(20) = 'Q03GN' + @Token;
DECLARE @EnterpriseId VARCHAR(20) = 'TST_Q03_E' + @Token;
DECLARE @ZeroEnterpriseId VARCHAR(20) = 'TST_Q03_Z' + @Token;
DECLARE @FleetMemberId VARCHAR(20) = 'Q03FM' + @Token;
DECLARE @VehicleId VARCHAR(20) = 'Q03VE' + @Token;
DECLARE @CardId VARCHAR(20) = 'Q03CA' + @Token;
DECLARE @QuotaId VARCHAR(20) = 'Q03QU' + @Token;
DECLARE @SettlementId VARCHAR(20) = 'Q03ES' + @Token;
DECLARE @ZeroSettlementId VARCHAR(20) = 'Q03ZS' + @Token;
DECLARE @BindingId BIGINT;
DECLARE @InMonthOrderId BIGINT;
DECLARE @WrongMonthOrderId BIGINT;
DECLARE @Actual TABLE
(
    enterprise_settlement_id VARCHAR(20) PRIMARY KEY,
    enterprise_id VARCHAR(20),
    billing_period_start DATE,
    header_order_count INT,
    detail_order_count BIGINT,
    header_energy_kwh DECIMAL(12,3),
    detail_energy_kwh DECIMAL(38,3),
    header_amount DECIMAL(12,2),
    detail_amount DECIMAL(38,2),
    order_end_in_period_count BIGINT,
    paid_order_count BIGINT,
    settlement_state VARCHAR(20)
);

BEGIN TRY
    BEGIN TRANSACTION;

    -- Complete the R-domain parents using the installed roles and this test's own identities.
    DECLARE @FixtureAccounts TABLE (username VARCHAR(50) PRIMARY KEY, account_id BIGINT NOT NULL);
    INSERT INTO dbo.SysAccount (username, password_hash, role_id)
    OUTPUT INSERTED.username, INSERTED.account_id INTO @FixtureAccounts (username, account_id)
    SELECT f.username, 'REPLACE_WITH_REAL_PASSWORD_HASH', r.role_id
    FROM (VALUES
        ('TST_Q03_A' + @Token, 'R01'),
        (@UserId, 'R04'),
        (@EnterpriseId, 'R05'),
        (@ZeroEnterpriseId, 'R05')
    ) f(username, role_code)
    JOIN dbo.SysRole r ON r.role_code = f.role_code;
    IF @@ROWCOUNT <> 4
        THROW 52990, 'Install the required R roles before running this fixture.', 1;
    DECLARE @NoticeAccountId BIGINT = (SELECT account_id FROM @FixtureAccounts WHERE username = 'TST_Q03_A' + @Token);

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
        (@EnterpriseId, 'TST_Q03E' + @Token),
        (@ZeroEnterpriseId, 'TST_Q03Z' + @Token)
    ) v(enterprise_id, credit_code)
    JOIN @FixtureAccounts f ON f.username = v.enterprise_id;

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'Q03测试运营商');
    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'Q03测试场站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         1, N'00:00-24:00', N'测试', @NoticeAccountId);
    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileId, @StationId, N'Q03-MODEL', 60.00, N'OCPP', '2026-01-01', '2028-01-01', 'IDLE');
    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE');

    INSERT INTO dbo.FleetMember (fleet_member_id, enterprise_id, user_id, member_no)
    VALUES (@FleetMemberId, @EnterpriseId, @UserId, 'Q03-MEMBER');
    INSERT INTO dbo.Vehicle
        (vehicle_id, user_id, enterprise_id, plate_ciphertext, plate_hash,
         vehicle_model, battery_capacity_kwh, max_charging_power_kw)
    VALUES
        (@VehicleId, NULL, @EnterpriseId, 0x01,
         CONVERT(CHAR(64), HASHBYTES('SHA2_256', @VehicleId), 2),
         N'Q03测试车辆', 70.00, 100.00);
    INSERT INTO dbo.EnterpriseCard (enterprise_card_id, enterprise_id, card_no)
    VALUES (@CardId, @EnterpriseId, 'Q03-CARD-' + @Token);
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
        ('ENTERPRISE', @UserId, @GunId, @BindingId, @QuotaId,
         '2026-10-15T10:00:00', '2026-10-15T11:00:00', 1.000, 'PAID', 5.00,
         @StationId, '2026-10-15T11:05:00', '2026-10-15T11:04:00');
    SET @InMonthOrderId = CONVERT(BIGINT, SCOPE_IDENTITY());
    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, binding_id, enterprise_quota_id,
         start_time, end_time, energy_kwh, status, gross_amount,
         opening_station_id, settled_at, priced_at)
    VALUES
        ('ENTERPRISE', @UserId, @GunId, @BindingId, @QuotaId,
         '2026-10-31T23:00:00', '2026-11-01T00:01:00', 1.000, 'PAID', 5.00,
         @StationId, '2026-11-01T00:05:00', '2026-11-01T00:04:00');
    SET @WrongMonthOrderId = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.EnterpriseSettlement
        (enterprise_settlement_id, enterprise_id, billing_period_start,
         total_order_count, total_energy_kwh, total_amount, generated_at,
         confirmed_at, paid_at, payment_reference)
    VALUES
        (@SettlementId, @EnterpriseId, '2026-10-01', 2, 2.000, 10.00,
         '2026-11-02T09:00:00', '2026-11-02T10:00:00', '2026-11-03T10:00:00',
         'Q03-RECEIPT-' + @Token),
        (@ZeroSettlementId, @ZeroEnterpriseId, '2026-10-01', 0, 0.000, 0.00,
         '2026-11-02T09:00:00', NULL, NULL, NULL);

    INSERT INTO dbo.EnterpriseSettlementDetail
        (enterprise_settlement_id, order_id, fleet_member_id, vehicle_id,
         payable_amount, energy_kwh)
    VALUES
        (@SettlementId, @InMonthOrderId, @FleetMemberId, @VehicleId, 5.00, 1.000),
        (@SettlementId, @WrongMonthOrderId, @FleetMemberId, @VehicleId, 5.00, 1.000);

    ;WITH detail_summary AS
    (
        SELECT e.enterprise_settlement_id,
               COUNT_BIG(*) AS detail_order_count,
               SUM(d.energy_kwh) AS detail_energy_kwh,
               SUM(d.payable_amount) AS detail_amount,
               SUM(CASE WHEN o.end_time >= e.billing_period_start
                         AND o.end_time < DATEADD(MONTH, 1, e.billing_period_start)
                        THEN 1 ELSE 0 END) AS order_end_in_period_count,
               SUM(CASE WHEN o.status = 'PAID' AND o.settled_at IS NOT NULL
                        THEN 1 ELSE 0 END) AS paid_order_count
        FROM dbo.EnterpriseSettlement AS e
        INNER JOIN dbo.EnterpriseSettlementDetail AS d
            ON d.enterprise_settlement_id = e.enterprise_settlement_id
        INNER JOIN dbo.ChargingOrder AS o ON o.order_id = d.order_id
        WHERE e.enterprise_settlement_id = @SettlementId
        GROUP BY e.enterprise_settlement_id
    )
    INSERT INTO @Actual
        (enterprise_settlement_id, enterprise_id, billing_period_start,
         header_order_count, detail_order_count, header_energy_kwh, detail_energy_kwh,
         header_amount, detail_amount, order_end_in_period_count, paid_order_count,
         settlement_state)
    SELECT e.enterprise_settlement_id,
           e.enterprise_id,
           e.billing_period_start,
           e.total_order_count,
           COALESCE(ds.detail_order_count, 0),
           e.total_energy_kwh,
           COALESCE(ds.detail_energy_kwh, 0),
           e.total_amount,
           COALESCE(ds.detail_amount, 0),
           COALESCE(ds.order_end_in_period_count, 0),
           COALESCE(ds.paid_order_count, 0),
           CASE WHEN e.paid_at IS NOT NULL THEN 'PAID'
                WHEN e.confirmed_at IS NOT NULL THEN 'CONFIRMED'
                ELSE 'GENERATED' END
    FROM dbo.EnterpriseSettlement AS e
    LEFT JOIN detail_summary AS ds
        ON ds.enterprise_settlement_id = e.enterprise_settlement_id
    WHERE e.enterprise_settlement_id IN (@SettlementId, @ZeroSettlementId);

    IF NOT EXISTS
       (SELECT 1 FROM @Actual
        WHERE enterprise_settlement_id = @SettlementId
          AND header_order_count = 2 AND detail_order_count = 2
          AND header_energy_kwh = 2.000 AND detail_energy_kwh = 2.000
          AND header_amount = 10.00 AND detail_amount = 10.00
          AND order_end_in_period_count = 1 AND paid_order_count = 2
          AND settlement_state = 'PAID')
        THROW 52201, 'Q03 monthly aggregate or period check is incorrect.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM @Actual
        WHERE enterprise_settlement_id = @ZeroSettlementId
          AND header_order_count = 0 AND detail_order_count = 0
          AND header_energy_kwh = 0 AND detail_energy_kwh = 0
          AND header_amount = 0 AND detail_amount = 0
          AND order_end_in_period_count = 0 AND paid_order_count = 0
          AND settlement_state = 'GENERATED')
        THROW 52202, 'Q03 omitted the zero-detail settlement or returned nonzero detail totals.', 1;

    SELECT enterprise_id, billing_period_start,
           header_order_count, detail_order_count,
           header_energy_kwh, detail_energy_kwh,
           header_amount, detail_amount,
           order_end_in_period_count, paid_order_count, settlement_state
    FROM @Actual;
    SELECT N'Q03 企业月结三表汇总与结束月核对' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

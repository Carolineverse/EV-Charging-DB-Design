-- =============================================================
-- D 维护的联调演示数据
-- 前置：r_base.sql、50_B_demo_settlement_data.sql 已执行
-- 产出：4 个新站 + 每站一套计费版本；5 站 × 5 账期(202606~202610)
--       = 25 笔无退款 PAID 订单 + 25 条支付（用于生成 25 张结算单）
-- 电费 2、服务费 1、优惠 3。B 站五期订单均在每月 10 日，使用普通计费版本。
-- =============================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRY
BEGIN TRANSACTION;

DECLARE @op   VARCHAR(20) = 'B_DEMO_OP01';
DECLARE @user VARCHAR(20) = 'B_DEMO_USER01';
DECLARE @notice BIGINT = (SELECT account_id FROM dbo.SysAccount WHERE username='demo_admin_r01');

DECLARE @stations TABLE (idx INT, station_id VARCHAR(20), pile_id VARCHAR(20), gun_id VARCHAR(20), rule_version_id BIGINT);
INSERT INTO @stations VALUES
 (1,'B_DEMO_ST01','B_DEMO_PILE01','B_DEMO_GUN01',920260101),
 (2,'D_DEMO_ST02','D_DEMO_PILE02','D_DEMO_GUN02',920260201),
 (3,'D_DEMO_ST03','D_DEMO_PILE03','D_DEMO_GUN03',920260301),
 (4,'D_DEMO_ST04','D_DEMO_PILE04','D_DEMO_GUN04',920260401),
 (5,'D_DEMO_ST05','D_DEMO_PILE05','D_DEMO_GUN05',920260501);

-- 4 个新站 + 桩 + 枪 + 计费版本 + 计费规则
DECLARE @i INT = 2;
WHILE @i <= 5
BEGIN
    DECLARE @sid VARCHAR(20) = 'D_DEMO_ST0' + CAST(@i AS VARCHAR(1));
    DECLARE @pid VARCHAR(20) = 'D_DEMO_PILE0' + CAST(@i AS VARCHAR(1));
    DECLARE @gid VARCHAR(20) = 'D_DEMO_GUN0' + CAST(@i AS VARCHAR(1));
    DECLARE @rv  BIGINT = 920260000 + @i * 100 + 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.ChargingStation WHERE station_id = @sid)
        INSERT INTO dbo.ChargingStation
            (station_id, station_name, address, longitude, latitude, operator_id,
             total_spaces, business_hours, parking_fee_standard, status, workorder_notice_account_id)
        VALUES (@sid, N'D 联调场站' + CAST(@i AS NVARCHAR), N'测试数据', 116.400000, 39.900000,
                @op, 2, N'00:00-24:00', N'测试期间免费', 'OPERATING', @notice);

    IF NOT EXISTS (SELECT 1 FROM dbo.ChargingPile WHERE pile_id = @pid)
        INSERT INTO dbo.ChargingPile
            (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
             commissioned_date, warranty_end_date, status, reported_status)
        VALUES (@pid, @sid, N'D-DEMO-DC120', 120.00, N'OCPP-1.6', '2026-01-01', '2028-01-01', 'IDLE', 'IDLE');

    IF NOT EXISTS (SELECT 1 FROM dbo.ChargingGun WHERE gun_id = @gid)
        INSERT INTO dbo.ChargingGun
            (gun_id, pile_id, gun_sequence, gun_type, interface_standard, max_output_power_kw, status, reported_status)
        VALUES (@gid, @pid, 1, 'DC_FAST', N'GB/T', 120.00, 'IDLE', 'IDLE');

    IF NOT EXISTS (SELECT 1 FROM dbo.BillingRuleVersion WHERE rule_version_id = @rv)
        INSERT INTO dbo.BillingRuleVersion
            (rule_version_id, station_id, enterprise_id, free_minutes, minimum_amount, effective_from, effective_to, status)
        VALUES (@rv, @sid, NULL, 0, 5.00, '2026-01-01T00:00:00', NULL, 'ACTIVE');

    IF NOT EXISTS (SELECT 1 FROM dbo.BillingRule WHERE rule_version_id = @rv AND period_start_time = '00:00:00')
        INSERT INTO dbo.BillingRule
            (rule_version_id, period_type, period_start_time, period_end_time, electricity_price, service_price)
        VALUES (@rv, N'平', '00:00:00', '23:59:00', 2.0000, 1.0000);

    SET @i = @i + 1;
END;

-- 每站每账期 1 笔干净订单（25 笔）
DECLARE @new_order TABLE (order_id BIGINT);
DECLARE @s INT = 1;
WHILE @s <= 5
BEGIN
    DECLARE @st VARCHAR(20), @gun VARCHAR(20), @rv2 BIGINT;
    SELECT @st = station_id, @gun = gun_id, @rv2 = rule_version_id FROM @stations WHERE idx = @s;

    DECLARE @m INT = 6;
    WHILE @m <= 10
    BEGIN
        DECLARE @ym CHAR(6) = '2026' + RIGHT('0' + CAST(@m AS VARCHAR), 2);
        DECLARE @end DATETIME2(3) = DATETIME2FROMPARTS(2026, @m, 10, 10, 0, 0, 0, 3);
        DECLARE @minimum DECIMAL(12,2) = (SELECT minimum_amount FROM dbo.BillingRuleVersion WHERE rule_version_id = @rv2);
        DECLARE @created DATETIME2(3) = DATEADD(second, -1, DATEADD(hour, -1, @end));
        DECLARE @txn VARCHAR(64) = 'D-DEMO-PAY-' + @st + '-' + @ym;
        DECLARE @oid BIGINT;

        IF NOT EXISTS (SELECT 1 FROM dbo.PaymentRecord WHERE pay_channel = 'OTHER' AND transaction_no = @txn)
        BEGIN
            DELETE FROM @new_order;
            INSERT INTO dbo.ChargingOrder
                (order_type, user_id, gun_id, binding_id, enterprise_quota_id,
                 start_time, end_time, energy_kwh, status, gross_amount,
                 minimum_adjustment, discount_amount, paid_amount, refund_amount,
                 created_at, updated_at, opening_station_id, settled_at,
                 startup_rule_version_id, priced_at, device_released_at)
            OUTPUT inserted.order_id INTO @new_order
            VALUES ('PERSONAL', @user, @gun, NULL, NULL,
                    DATEADD(hour, -1, @end), @end, 1.000, 'PAID', @minimum, @minimum - 3.00, 3.00, @minimum - 3.00, 0.00,
                    @created, @end, @st, DATEADD(second, 5, @end), @rv2,
                    DATEADD(second, 4, @end), DATEADD(second, 3, @end));
            SELECT @oid = order_id FROM @new_order;

            INSERT INTO dbo.OrderFeeDetail
                (order_id, billing_rule_id, segment_start, segment_end, segment_energy_kwh, free_service_fee)
            SELECT @oid, billing_rule_id, DATEADD(hour, -1, @end), @end, 1.000, 0.00
            FROM dbo.BillingRule WHERE rule_version_id = @rv2 AND period_start_time = '00:00:00';

            INSERT INTO dbo.PaymentRecord (order_id, pay_channel, transaction_no, pay_amount, pay_time)
            VALUES (@oid, 'OTHER', @txn, @minimum - 3.00, DATEADD(second, 5, @end));
        END;

        SET @m = @m + 1;
    END;
    SET @s = @s + 1;
END;

COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

SELECT COUNT(*) AS d_demo_orders FROM dbo.PaymentRecord
WHERE pay_channel = 'OTHER' AND transaction_no LIKE 'D-DEMO-PAY-%';

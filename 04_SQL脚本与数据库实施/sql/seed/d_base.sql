-- =============================================================
-- D 线种子（数据驱动版）：费率 → 分派 → 生成 25 单 → 确认 → 退款 → 结转链
--                      → 202610 差异 → 开票 → 核对事项
-- 前置：r_base、50_B_demo_settlement_data、60_D_demo_bulk_data 已执行；
--       d_generate / d_flows / d_register_carryover 已建。
-- 依赖 B_DEMO_* / D_DEMO_* 的真实编号，不再使用 ST-*/OP-* 夹具编号。
-- =============================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRY
BEGIN TRANSACTION;

DECLARE @r01 BIGINT = (SELECT account_id FROM dbo.SysAccount WHERE username='demo_admin_r01');
DECLARE @r03 BIGINT = (SELECT account_id FROM dbo.SysAccount WHERE username='demo_settlement_r03');

DECLARE @s INT, @m INT, @st VARCHAR(20), @ym CHAR(6), @next_ym CHAR(6);
DECLARE @settle BIGINT, @oid BIGINT, @pay BIGINT, @ref BIGINT, @carry BIGINT, @target BIGINT;
DECLARE @payment_key VARCHAR(64), @refund_no VARCHAR(64), @invoice_no VARCHAR(50);
DECLARE @new_refund TABLE (refund_id BIGINT);
DECLARE @final_settlement BIGINT, @final_order BIGINT, @d INT, @dt TINYINT, @damt DECIMAL(12,2), @did BIGINT, @settleInv BIGINT;

-- 四个 D 场站各五个连续月度区间。B 样例站使用运营商默认率。
INSERT INTO dbo.OperatorSettlementRate (operator_id, station_id, platform_rate, effective_from, effective_to, status)
SELECT NULL, s.station_id, 0.200000, p.starts_at, p.ends_at, 'ACTIVE'
FROM (VALUES ('D_DEMO_ST02'),('D_DEMO_ST03'),('D_DEMO_ST04'),('D_DEMO_ST05')) s(station_id)
CROSS JOIN (VALUES (6),(7),(8),(9),(10)) m(month_number)
CROSS APPLY (
    SELECT DATEFROMPARTS(2026, m.month_number, 1) AS starts_at,
           DATEADD(MONTH, 1, DATEFROMPARTS(2026, m.month_number, 1)) AS ends_at
) p
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.OperatorSettlementRate r
    WHERE r.station_id = s.station_id AND r.effective_from = p.starts_at AND r.status = 'ACTIVE'
);
IF NOT EXISTS (SELECT 1 FROM dbo.OperatorSettlementRate WHERE operator_id='B_DEMO_OP01' AND status='ACTIVE')
    INSERT INTO dbo.OperatorSettlementRate (operator_id, station_id, platform_rate, effective_from, status)
    VALUES ('B_DEMO_OP01', NULL, 0.200000, '2026-06-01T00:00:00', 'ACTIVE');

-- 2) 分派 + 3) 生成 25 张结算单
SET @s = 1;
WHILE @s <= 5
BEGIN
    SET @st = CASE @s WHEN 1 THEN 'B_DEMO_ST01' ELSE 'D_DEMO_ST0' + CAST(@s AS VARCHAR(1)) END;
    SET @m = 6;
    WHILE @m <= 10
    BEGIN
        SET @ym = '2026' + RIGHT('0' + CAST(@m AS VARCHAR), 2);
        IF NOT EXISTS (SELECT 1 FROM dbo.ServiceCaseAssignment WHERE case_type='SETTLEMENT_GENERATE' AND case_id=@st+'|'+@ym)
            INSERT INTO dbo.ServiceCaseAssignment (case_type, case_id, assigned_account_id, assigned_by, effective_from)
            VALUES ('SETTLEMENT_GENERATE', @st+'|'+@ym, @r03, @r01, '2026-06-01T00:00:00');
        IF NOT EXISTS (SELECT 1 FROM dbo.SettlementStatement WHERE station_id=@st AND period_month=@ym)
            EXEC dbo.usp_GenerateSettlement @st, @ym, @r03, @r03;
        SET @m = @m + 1;
    END;
    SET @s = @s + 1;
END;

-- 4) 逐站逐月：确认 06~09 → 锁定后退款 → 登记/审批/应用结转到下一期
SET @s = 1;
WHILE @s <= 5
BEGIN
    SET @st = CASE @s WHEN 1 THEN 'B_DEMO_ST01' ELSE 'D_DEMO_ST0' + CAST(@s AS VARCHAR(1)) END;
    SET @m = 6;
    WHILE @m <= 9
    BEGIN
        SET @ym = '2026' + RIGHT('0' + CAST(@m AS VARCHAR), 2);
        SET @next_ym = '2026' + RIGHT('0' + CAST(@m + 1 AS VARCHAR), 2);
        SET @settle = (SELECT settlement_id FROM dbo.SettlementStatement WHERE station_id=@st AND period_month=@ym);

        EXEC dbo.usp_ConfirmSettlement @settle, @r01, N'联调确认';

        SET @payment_key = 'D-DEMO-PAY-' + @st + '-' + @ym;
        SET @refund_no = 'D-DEMO-REF-' + @st + '-' + @ym;
        SET @pay = NULL;
        SELECT @pay = p.payment_id, @oid = p.order_id
        FROM dbo.PaymentRecord p
        JOIN dbo.SettlementDetail d ON d.order_id = p.order_id AND d.settlement_id = @settle
        WHERE p.pay_channel = 'OTHER' AND p.transaction_no = @payment_key;
        IF @pay IS NULL THROW 50160, N'联调支付未关联到指定原单明细', 1;

        -- 等到服务器时钟跨过确认时间的 DATETIME2(3) 精度。
        WAITFOR DELAY '00:00:00.010';
        DELETE FROM @new_refund;
        INSERT INTO dbo.RefundRecord (payment_id, refund_no, refund_amount, status, reason, refunded_at)
        OUTPUT inserted.refund_id INTO @new_refund
        VALUES (@pay, @refund_no, 1.00, 'SUCCESS', N'锁定后退款联调', SYSDATETIME());
        SELECT @ref = refund_id FROM @new_refund;
        UPDATE dbo.ChargingOrder SET refund_amount = refund_amount + 1.00 WHERE order_id = @oid;
        UPDATE dbo.PaymentRecord SET refund_amount = refund_amount + 1.00 WHERE payment_id = @pay;

        SELECT @target = settlement_id FROM dbo.SettlementStatement WHERE station_id=@st AND period_month=@next_ym;
        EXEC dbo.usp_RegisterCarryover @settle, @ref, @target, -0.80,
             N'联调核验：用户退 1 元，按原快照核定运营商承担 0.80 元', @r03, @carry OUTPUT;
        EXEC dbo.usp_ApproveCarryover @carry, @r01;
        EXEC dbo.usp_ApplyCarryover @carry, @target, @r03;
        SET @m = @m + 1;
    END;
    SET @s = @s + 1;
END;

-- 5) 差异：202610 每站 4 条（类型 1/2/3），登记并关闭 → 20 条 status=2
SET @s = 1;
WHILE @s <= 5
BEGIN
    SET @st = CASE @s WHEN 1 THEN 'B_DEMO_ST01' ELSE 'D_DEMO_ST0' + CAST(@s AS VARCHAR(1)) END;
    SET @final_settlement = (SELECT settlement_id FROM dbo.SettlementStatement WHERE station_id=@st AND period_month='202610');
    SET @payment_key = 'D-DEMO-PAY-' + @st + '-202610';
    SET @final_order = (
        SELECT p.order_id FROM dbo.PaymentRecord p
        JOIN dbo.SettlementDetail d ON d.order_id = p.order_id AND d.settlement_id = @final_settlement
        WHERE p.pay_channel = 'OTHER' AND p.transaction_no = @payment_key
    );
    IF @final_order IS NULL THROW 50161, N'联调最后一期缺少指定订单的明细', 1;
    SET @d = 1;
    WHILE @d <= 4
    BEGIN
        SET @dt = ((@d - 1) % 3) + 1;
        SET @damt = CASE WHEN @d % 2 = 1 THEN 0.50 ELSE -0.50 END;
        EXEC dbo.usp_RegisterDifference @final_settlement, @final_order, @dt, @damt, NULL, @r03, @did OUTPUT;
        EXEC dbo.usp_CloseDifference @did, @r01, N'联调确认', N'联调关闭';
        SET @d = @d + 1;
    END;
    SET @s = @s + 1;
END;

-- 6) 开票：06~09 的 20 张已确认单，每张 1.00 蓝票
SET @s = 1;
WHILE @s <= 5
BEGIN
    SET @st = CASE @s WHEN 1 THEN 'B_DEMO_ST01' ELSE 'D_DEMO_ST0' + CAST(@s AS VARCHAR(1)) END;
    SET @m = 6;
    WHILE @m <= 9
    BEGIN
        SET @ym = '2026' + RIGHT('0' + CAST(@m AS VARCHAR), 2);
        SET @settleInv = (SELECT settlement_id FROM dbo.SettlementStatement WHERE station_id=@st AND period_month=@ym);
        SET @invoice_no = 'D-DEMO-INV-' + @st + '-' + @ym;
        EXEC dbo.usp_RegisterInvoice @settleInv, @invoice_no, N'平台运营公司', '91110000MA0000000X', 1.00, @r03;
        SET @m = @m + 1;
    END;
    SET @s = @s + 1;
END;

-- 7) 核对事项：20 条 POST_LOCK_REFUND（每条对应一笔 D 联调退款）
INSERT INTO dbo.SettlementReviewCase (order_id, period_month, reason_code, refund_id, assigned_account_id, status, created_at)
SELECT p.order_id, s.period_month, 'POST_LOCK_REFUND', r.refund_id, @r03, 'PENDING', SYSDATETIME()
FROM dbo.RefundRecord r
JOIN dbo.PaymentRecord p ON p.payment_id = r.payment_id
JOIN dbo.SettlementCarryoverAdjustment a ON a.refund_id = r.refund_id AND a.status = 'APPLIED'
JOIN dbo.SettlementStatement s ON s.settlement_id = a.original_settlement_id
JOIN dbo.SettlementDetail d ON d.settlement_id = s.settlement_id AND d.order_id = p.order_id
WHERE r.refund_no = 'D-DEMO-REF-' + s.station_id + '-' + s.period_month
  AND p.pay_channel = 'OTHER' AND p.transaction_no = 'D-DEMO-PAY-' + s.station_id + '-' + s.period_month
  AND s.status IN (1,2) AND r.status = 'SUCCESS' AND r.refunded_at > s.confirmed_at
  AND NOT EXISTS (SELECT 1 FROM dbo.SettlementReviewCase c WHERE c.refund_id = r.refund_id AND c.reason_code='POST_LOCK_REFUND');

COMMIT TRANSACTION;

SELECT 'SettlementStatement' t, COUNT(*) n FROM dbo.SettlementStatement
UNION ALL SELECT 'SettlementDetail', COUNT(*) FROM dbo.SettlementDetail
UNION ALL SELECT 'SettlementCarryoverAdjustment(APPLIED)', COUNT(*) FROM dbo.SettlementCarryoverAdjustment WHERE status='APPLIED'
UNION ALL SELECT 'ReconciliationDifference', COUNT(*) FROM dbo.ReconciliationDifference
UNION ALL SELECT 'SettlementInvoice', COUNT(*) FROM dbo.SettlementInvoice
UNION ALL SELECT 'SettlementReviewCase', COUNT(*) FROM dbo.SettlementReviewCase
UNION ALL SELECT 'RefundRecord(D-DEMO)', COUNT(*) FROM dbo.RefundRecord WHERE refund_no LIKE 'D-DEMO-REF-%';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

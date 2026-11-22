-- =============================================================
-- D 线种子：费率、分派、结算单与明细、差异、发票、结转、人工核对、日志
-- 前置：r_base（账号）、00_b_fixture（订单 40 笔跨 4 账期、退款 20 笔）
-- 产出：20 结算单 + 40 明细 + 20 差异 + 20 发票（挂在已确认账单上）
--       + 20 结转 + 20 核对事项 + 20 操作日志
-- =============================================================
SET NOCOUNT ON;

-- 站级费率（3）+ 运营商默认费率（3）
INSERT INTO dbo.OperatorSettlementRate (operator_id, station_id, platform_rate, effective_from, status) VALUES
(NULL, 'ST-001', 0.200000, '2026-08-01T00:00:00', 'ACTIVE'),
(NULL, 'ST-003', 0.180000, '2026-08-01T00:00:00', 'ACTIVE'),
(NULL, 'ST-005', 0.220000, '2026-08-01T00:00:00', 'ACTIVE'),
('OP-001', NULL, 0.200000, '2026-08-01T00:00:00', 'ACTIVE'),
('OP-002', NULL, 0.180000, '2026-08-01T00:00:00', 'ACTIVE'),
('OP-003', NULL, 0.220000, '2026-08-01T00:00:00', 'ACTIVE');

-- 结算生成事项分派：5 站 × 4 账期 = 20 条
DECLARE @sa_st INT = 1;
WHILE @sa_st <= 5
BEGIN
    DECLARE @sa_mm INT = 1;
    WHILE @sa_mm <= 5
    BEGIN
        DECLARE @sa_sid VARCHAR(20) = 'ST-' + RIGHT('00' + CAST(@sa_st AS VARCHAR), 3);
        DECLARE @sa_pm CHAR(6) = CASE @sa_mm WHEN 1 THEN '202608' WHEN 2 THEN '202609' WHEN 3 THEN '202610' WHEN 4 THEN '202611' ELSE '202612' END;
        INSERT INTO dbo.ServiceCaseAssignment (case_type, case_id, assigned_account_id, assigned_by, effective_from)
        SELECT 'SETTLEMENT_GENERATE', @sa_sid + '|' + @sa_pm,
               (SELECT account_id FROM dbo.SysAccount WHERE username='demo_settlement_r03'),
               (SELECT account_id FROM dbo.SysAccount WHERE username='demo_admin_r01'),
               '2026-08-01T00:00:00'
        WHERE NOT EXISTS (SELECT 1 FROM dbo.ServiceCaseAssignment WHERE case_type='SETTLEMENT_GENERATE' AND case_id=@sa_sid + '|' + @sa_pm);
        SET @sa_mm = @sa_mm + 1;
    END;
    SET @sa_st = @sa_st + 1;
END;

-- 结算单 + 明细：5 站 × 4 账期
DECLARE @ss_st INT = 1;
WHILE @ss_st <= 5
BEGIN
    DECLARE @ss_mm INT = 1;
    WHILE @ss_mm <= 5
    BEGIN
        DECLARE @ss_sid VARCHAR(20) = 'ST-' + RIGHT('00' + CAST(@ss_st AS VARCHAR), 3);
        DECLARE @ss_pm CHAR(6) = CASE @ss_mm WHEN 1 THEN '202608' WHEN 2 THEN '202609' WHEN 3 THEN '202610' WHEN 4 THEN '202611' ELSE '202612' END;
        DECLARE @r03 BIGINT = (SELECT account_id FROM dbo.SysAccount WHERE username='demo_settlement_r03');
        DECLARE @ss_ps DATE = CONVERT(date, @ss_pm + '01', 112);
        DECLARE @ss_pe DATE = DATEADD(month, 1, @ss_ps);
        DECLARE @settlement_id BIGINT;

        INSERT INTO dbo.SettlementStatement (station_id, period_month, platform_rate, status, assigned_account_id, created_by, created_at)
        VALUES (@ss_sid, @ss_pm, 0.200000, 0, @r03, @r03, SYSDATETIME());
        SET @settlement_id = SCOPE_IDENTITY();

        INSERT INTO dbo.SettlementDetail (settlement_id, order_id, ended_at_snapshot, energy_snapshot, electricity_base, service_base, minimum_adjustment, created_at, settled_at_snapshot, settlement_source, eligibility_checked_at, refund_state_snapshot)
        SELECT @settlement_id, o.order_id, o.end_time, o.energy_kwh, o.electricity_base, o.service_base, o.minimum_adjustment, SYSDATETIME(), o.settled_at, o.order_type, SYSDATETIME(), 'NONE'
        FROM dbo.ChargingOrder o
        WHERE o.opening_station_id = @ss_sid AND o.end_time >= @ss_ps AND o.end_time < @ss_pe AND o.status = 'PAID';

        SET @ss_mm = @ss_mm + 1;
    END;
    SET @ss_st = @ss_st + 1;
END;

-- 差异：20 条（挂在 1~10 号待对账结算单，每单 2 条）
DECLARE @df INT = 1;
WHILE @df <= 20
BEGIN
    DECLARE @sn INT = ((@df - 1) / 2) + 1;   -- 1..10
    DECLARE @df_oid BIGINT;
    SELECT @df_oid = MIN(order_id) FROM dbo.SettlementDetail WHERE settlement_id = @sn;
    IF @df % 2 = 0
        SELECT @df_oid = MAX(order_id) FROM dbo.SettlementDetail WHERE settlement_id = @sn;
    IF @df_oid IS NOT NULL
        INSERT INTO dbo.ReconciliationDifference (settlement_id, order_id, difference_type, difference_amount, status, created_by, created_at)
        VALUES (@sn, @df_oid, (@df % 4) + 1, CASE WHEN @df % 2 = 0 THEN 0.50 ELSE -0.50 END, 0,
                (SELECT account_id FROM dbo.SysAccount WHERE username='demo_settlement_r03'), SYSDATETIME());
    SET @df = @df + 1;
END;

-- 确认 11~20 号结算单（无差异，直接已确认待补票）
UPDATE dbo.SettlementStatement
SET status = 1,
    confirmed_by = (SELECT account_id FROM dbo.SysAccount WHERE username='demo_admin_r01'),
    confirmed_at = SYSDATETIME(),
    confirmation_evidence = N'运营商已确认（种子）'
WHERE settlement_id BETWEEN 11 AND 20;

-- 发票：20 条（挂在 11~20 号已确认账单，每单 2 张、合计全额 8.80）
DECLARE @inv INT = 1;
WHILE @inv <= 20
BEGIN
    DECLARE @inv_sn INT = 10 + ((@inv - 1) / 2) + 1;   -- 11..20
    INSERT INTO dbo.SettlementInvoice (settlement_id, invoice_no, invoice_title, tax_number, amount, status, created_by, created_at, issued_at)
    VALUES (@inv_sn, 'INV-2026-' + RIGHT('0000' + CAST(@inv AS VARCHAR), 4), N'平台运营公司', '91110000MA0000000X', 4.40, 1,
            (SELECT account_id FROM dbo.SysAccount WHERE username='demo_settlement_r03'), SYSDATETIME(), SYSDATETIME());
    SET @inv = @inv + 1;
END;

-- 退款结转：20 条（一半已审批，一半待审批）
DECLARE @cv INT = 1;
WHILE @cv <= 20
BEGIN
    INSERT INTO dbo.SettlementCarryoverAdjustment (original_settlement_id, refund_id, target_period_month, adjustment_amount, status, created_by, assessment_evidence, created_at)
    VALUES (@cv, @cv, '202612', -1.00, CASE WHEN @cv % 2 = 0 THEN 'APPROVED' ELSE 'PENDING' END,
            (SELECT account_id FROM dbo.SysAccount WHERE username='demo_settlement_r03'), N'跨期退款扣回-演示', SYSDATETIME());
    SET @cv = @cv + 1;
END;

-- 人工核对事项：20 条
DECLARE @rc INT = 1;
WHILE @rc <= 20
BEGIN
    INSERT INTO dbo.SettlementReviewCase (order_id, period_month, reason_code, assigned_account_id, status, created_at)
    VALUES (@rc, '202611',
            CASE @rc % 3 WHEN 0 THEN 'LATE_PAID' WHEN 1 THEN 'PRE_SETTLE_REFUND' ELSE 'PAYMENT_FAILED' END,
            (SELECT account_id FROM dbo.SysAccount WHERE username='demo_settlement_r03'), 'PENDING', SYSDATETIME());
    SET @rc = @rc + 1;
END;

-- 操作日志：20 条
DECLARE @log INT = 1;
WHILE @log <= 20
BEGIN
    INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, before_data, after_data)
    VALUES (CASE @log % 5 WHEN 0 THEN 'A1' WHEN 1 THEN 'BILLING' WHEN 2 THEN 'C' WHEN 3 THEN 'A2' ELSE 'D' END,
            'OBJ' + CAST(@log AS VARCHAR), CAST(@log AS VARCHAR), 'ACTION' + CAST(@log AS VARCHAR),
            CASE WHEN @log % 2 = 0 THEN 'SYSTEM' ELSE 'HUMAN' END,
            CASE WHEN @log % 2 = 0 THEN NULL ELSE (SELECT account_id FROM dbo.SysAccount WHERE username='demo_admin_r01') END,
            DATEADD(minute, @log, '2026-11-01T08:00:00'), N'{}', N'{}');
    SET @log = @log + 1;
END;
GO

-- 校验行数
SELECT 'OperatorSettlementRate' t, COUNT(*) n FROM dbo.OperatorSettlementRate
UNION ALL SELECT 'ServiceCaseAssignment', COUNT(*) FROM dbo.ServiceCaseAssignment
UNION ALL SELECT 'SettlementStatement', COUNT(*) FROM dbo.SettlementStatement
UNION ALL SELECT 'SettlementDetail', COUNT(*) FROM dbo.SettlementDetail
UNION ALL SELECT 'ReconciliationDifference', COUNT(*) FROM dbo.ReconciliationDifference
UNION ALL SELECT 'SettlementInvoice', COUNT(*) FROM dbo.SettlementInvoice
UNION ALL SELECT 'SettlementCarryoverAdjustment', COUNT(*) FROM dbo.SettlementCarryoverAdjustment
UNION ALL SELECT 'SettlementReviewCase', COUNT(*) FROM dbo.SettlementReviewCase
UNION ALL SELECT 'OperationLog', COUNT(*) FROM dbo.OperationLog;

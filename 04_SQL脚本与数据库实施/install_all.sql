-- =============================================================
-- 全组一键安装（SQLCMD 模式）
-- 使用：SSMS 打开本文件 → 菜单「查询」→ 勾选「SQLCMD 模式」→ 执行
-- 先在本机新建并选中专用于本次联调的 EV_B_TEST 空库
-- 说明：全组顺序，不调用 00_b_fixture.sql（该夹具仅用于 D 独立自测）
-- =============================================================

-- B 的 50/51 号种子固定 USE EV_B_TEST。已结束账期要求在任何 DDL 之前检查。
:ON ERROR EXIT
IF DB_NAME() <> N'EV_B_TEST'
    THROW 50162, N'全组安装须使用本机专用的 EV_B_TEST 空库', 1;
IF EXISTS (SELECT 1 FROM sys.tables WHERE is_ms_shipped = 0)
    THROW 50163, N'全组安装要求空库', 1;
IF SYSDATETIME() < DATEADD(MONTH, 1, DATEFROMPARTS(2026, 10, 1))
    THROW 50164, N'202610 账期尚未结束，须在 2026 年 11 月 1 日或之后安装', 1;
GO

-- 1) 建表（R/C/D 先建，B 的表有外键指向 R/C）
:r sql\schema\r_core.sql
:r sql\schema\c_partition.sql
:r sql\schema\c_core.sql
:r sql\schema\d_core.sql
:r sql\schema\20_A1_tables.sql
:r sql\schema\20_B_tables.sql
:r sql\schema\20_A2_tables.sql

-- 2) 外键与索引
:r sql\constraints\30_A1_foreign_keys.sql
:r sql\constraints\30_A1_indexes.sql
:r sql\constraints\30_B_foreign_keys.sql
:r sql\constraints\30_B_indexes.sql
:r sql\constraints\30_A2_foreign_keys.sql
:r sql\constraints\30_A2_indexes.sql
:r sql\constraints\31_A1B_R_C_foreign_keys.sql
:r sql\constraints\35_A2_A1B_foreign_keys.sql
:r sql\constraints\36_A2_R_foreign_keys.sql
:r sql\constraints\d_constraints.sql

-- 3) 视图
:r sql\views\45_A1_views.sql
:r sql\views\46_B_views.sql
:r sql\views\47_B_order_settlement_source.sql
:r sql\views\48_A2_views.sql
:r sql\views\d_views.sql

-- 4) 过程
:r sql\routines\40_B_price_charging_order.sql
:r sql\routines\41_A1_update_device_status.sql
:r sql\routines\42_A2_generate_enterprise_settlement.sql
:r sql\routines\c_dispatch.sql
:r sql\routines\d_generate.sql
:r sql\routines\d_flows.sql
:r sql\routines\d_register_carryover.sql

-- 5) 种子（顺序按依赖）
:r sql\seed\r_base.sql
:r sql\seed\50_B_demo_settlement_data.sql
:r sql\seed\51_B_demo_enterprise_settlement.sql
:r sql\seed\60_D_demo_bulk_data.sql
:r sql\seed\c_base_integration.sql
:r sql\seed\d_base.sql

-- 6) 校验演示链路的落库结果，按站点和业务编号限定范围。
DECLARE @statements TABLE (id BIGINT PRIMARY KEY, station_id VARCHAR(20), period_month CHAR(6));
INSERT INTO @statements
SELECT settlement_id, station_id, period_month
FROM dbo.SettlementStatement
WHERE station_id IN ('B_DEMO_ST01','D_DEMO_ST02','D_DEMO_ST03','D_DEMO_ST04','D_DEMO_ST05')
  AND period_month BETWEEN '202606' AND '202610';

DECLARE @statement_count INT = (SELECT COUNT(*) FROM @statements);
DECLARE @details INT = (SELECT COUNT(*) FROM dbo.SettlementDetail d JOIN @statements s ON s.id = d.settlement_id);
DECLARE @differences INT = (
    SELECT COUNT(*) FROM dbo.ReconciliationDifference d JOIN @statements s ON s.id = d.settlement_id
    WHERE s.period_month = '202610' AND d.status = 2
);
DECLARE @carryovers INT = (
    SELECT COUNT(*) FROM dbo.SettlementCarryoverAdjustment c
    JOIN @statements o ON o.id = c.original_settlement_id
    JOIN @statements t ON t.id = c.target_settlement_id AND t.station_id = o.station_id
    JOIN dbo.RefundRecord r ON r.refund_id = c.refund_id
    WHERE c.status = 'APPLIED' AND r.refund_no = 'D-DEMO-REF-' + o.station_id + '-' + o.period_month
      AND t.period_month = CONVERT(CHAR(6), DATEADD(MONTH, 1, CONVERT(DATE, o.period_month + '01', 112)), 112)
);
DECLARE @invoices INT = (
    SELECT COUNT(*) FROM dbo.SettlementInvoice i JOIN @statements s ON s.id = i.settlement_id
    WHERE i.status = 1 AND i.invoice_no = 'D-DEMO-INV-' + s.station_id + '-' + s.period_month
);
DECLARE @review_cases INT = (
    SELECT COUNT(*) FROM dbo.SettlementReviewCase q
    JOIN dbo.RefundRecord r ON r.refund_id = q.refund_id
    JOIN dbo.PaymentRecord p ON p.payment_id = r.payment_id AND q.order_id = p.order_id
    JOIN dbo.SettlementCarryoverAdjustment c ON c.refund_id = r.refund_id AND c.status = 'APPLIED'
    JOIN @statements s ON s.id = c.original_settlement_id AND s.period_month = q.period_month
    JOIN dbo.SettlementStatement original ON original.settlement_id = s.id
    JOIN dbo.SettlementDetail d ON d.settlement_id = s.id AND d.order_id = q.order_id
    WHERE q.reason_code = 'POST_LOCK_REFUND'
      AND r.refund_no = 'D-DEMO-REF-' + s.station_id + '-' + s.period_month
      AND p.pay_channel = 'OTHER' AND p.transaction_no = 'D-DEMO-PAY-' + s.station_id + '-' + s.period_month
      AND original.status IN (1,2) AND r.status = 'SUCCESS' AND r.refunded_at > original.confirmed_at
);
SELECT @statement_count AS statements, @details AS details, @carryovers AS applied_carryovers,
       @differences AS closed_differences, @invoices AS blue_invoices, @review_cases AS review_cases;
IF @statement_count <> 25 OR @details < 25 OR @carryovers <> 20
   OR @differences < 20 OR @invoices < 20 OR @review_cases <> 20
    THROW 50165, N'联调结果未满足数量要求，请查看各项实际计数', 1;
GO

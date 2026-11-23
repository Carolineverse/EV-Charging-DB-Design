-- D/C reporting views in the integrated d_views.sql package.
SET NOCOUNT ON;
IF DB_NAME() <> N'EV_B_TEST' THROW 52920, N'Choose EV_B_TEST', 1;

IF (SELECT COUNT(*) FROM dbo.v_SettlementLedger)
   <> (SELECT COUNT(*) FROM dbo.SettlementStatement)
    THROW 52921, N'v_SettlementLedger omitted or duplicated a statement.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.v_SettlementLedger AS l
    CROSS APPLY (
        SELECT COUNT(*) AS detail_count,
               COALESCE(SUM(electricity_base + service_base + minimum_adjustment),0) AS gross_amount
        FROM dbo.SettlementDetail AS d
        WHERE d.settlement_id=l.settlement_id
    ) AS expected
    WHERE l.detail_count<>expected.detail_count OR l.gross_amount<>expected.gross_amount
)
    THROW 52922, N'v_SettlementLedger detail totals disagree with source rows.', 1;

IF (SELECT COUNT(*) FROM dbo.v_SettlementDifference)
   <> (SELECT COUNT(*) FROM dbo.ReconciliationDifference AS r
       JOIN dbo.SettlementDetail AS d ON d.settlement_id=r.settlement_id AND d.order_id=r.order_id)
    THROW 52923, N'v_SettlementDifference does not expose each traceable difference.', 1;

IF EXISTS (
    SELECT 1 FROM dbo.v_InvoiceBalanceAndRed AS v
    WHERE v.invoice_balance<>v.payable_amount-v.effective_amount
)
    THROW 52924, N'v_InvoiceBalanceAndRed balance formula is inconsistent.', 1;

IF (SELECT COUNT(DISTINCT settlement_id) FROM dbo.v_InvoiceBalanceAndRed)
   <> (SELECT COUNT(*) FROM dbo.SettlementStatement)
    THROW 52925, N'v_InvoiceBalanceAndRed omitted a settlement with no invoice.', 1;

IF (SELECT COUNT(*) FROM dbo.v_DeviceReportAbnormal)
   < (SELECT COUNT(*) FROM dbo.DeviceReport)
    THROW 52926, N'v_DeviceReportAbnormal lost reports without monitoring rows.', 1;

IF (SELECT COUNT(*) FROM dbo.v_PendingAlarm)
   <> (SELECT COUNT(*) FROM dbo.Alarm AS a
       JOIN dbo.AlarmCodeDict AS c ON c.alarm_code=a.alarm_code
       JOIN dbo.AlarmLevelPolicy AS p ON p.alarm_level=a.alarm_level
       WHERE a.status IN ('PENDING','PENDING_VERIFY'))
    THROW 52927, N'v_PendingAlarm does not match pending alarm source rows.', 1;

IF (SELECT COUNT(*) FROM dbo.v_WorkOrderProgress)
   <> (SELECT COUNT(*) FROM dbo.WorkOrder AS w JOIN dbo.Alarm AS a ON a.alarm_id=w.alarm_id)
    THROW 52928, N'v_WorkOrderProgress does not match work-order source rows.', 1;

SELECT N'D/C reporting views' AS test_name, N'passed' AS test_result,
       6 AS views_checked;

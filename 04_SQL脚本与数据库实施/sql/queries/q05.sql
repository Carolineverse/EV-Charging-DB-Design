DECLARE @period_month CHAR(6) = '202610';

SELECT l.operator_id, l.operator_name, l.station_id, l.station_name, l.period_month,
       l.detail_count, l.gross_amount, l.platform_fee,
       l.adjustment_amount, l.carryover_amount, l.payable_amount,
       diff.diff_count, COALESCE(inv.invoice_amount, 0) AS invoice_amount,
       l.payable_amount - CAST(COALESCE(inv.invoice_amount, 0) AS DECIMAL(28,2)) AS invoice_balance
FROM dbo.v_SettlementLedger AS l
OUTER APPLY (
    SELECT COUNT(*) AS diff_count FROM dbo.ReconciliationDifference AS d
    WHERE d.settlement_id = l.settlement_id
) AS diff
OUTER APPLY (
    SELECT SUM(i.amount) AS invoice_amount FROM dbo.SettlementInvoice AS i
    WHERE i.settlement_id = l.settlement_id AND i.status IN (1, -1)
) AS inv
WHERE l.period_month = @period_month
ORDER BY l.operator_id, l.station_id;

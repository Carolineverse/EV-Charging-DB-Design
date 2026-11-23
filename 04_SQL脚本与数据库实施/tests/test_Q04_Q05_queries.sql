-- Result assertions for the task-book's Q04/Q05 multi-table SQL requirements.
SET NOCOUNT ON;
IF DB_NAME() <> N'EV_B_TEST' THROW 52930, N'Choose EV_B_TEST', 1;

DECLARE @q04 TABLE
(
    alarm_id BIGINT,
    alarm_code VARCHAR(20),
    alarm_status VARCHAR(20),
    work_order_id BIGINT NULL,
    engineer_name NVARCHAR(50) NULL
);
INSERT INTO @q04
SELECT a.alarm_id,a.alarm_code,a.status,w.work_order_id,eng.staff_name
FROM dbo.Alarm a
JOIN dbo.AlarmCodeDict d ON a.alarm_code=d.alarm_code
JOIN dbo.AlarmLevelPolicy lv ON a.alarm_level=lv.alarm_level
JOIN dbo.ChargingPile p ON a.pile_id=p.pile_id
JOIN dbo.ChargingStation s ON p.station_id=s.station_id
LEFT JOIN dbo.WorkOrder w ON w.alarm_id=a.alarm_id
LEFT JOIN dbo.StaffProfile eng ON w.engineer_staff_id=eng.staff_id
WHERE s.station_id='B_DEMO_ST01';
IF (SELECT COUNT(*) FROM @q04)<>4
    THROW 52931, N'Q04 expected four alarm/work-order rows for the demo station.', 1;
IF EXISTS (SELECT 1 FROM @q04 WHERE alarm_code IS NULL OR alarm_status IS NULL)
    THROW 52932, N'Q04 returned an incomplete alarm result.', 1;

DECLARE @period CHAR(6)='202610';
DECLARE @q05 TABLE
(
    operator_id VARCHAR(20),
    station_id VARCHAR(20),
    detail_count BIGINT,
    payable_amount DECIMAL(28,2),
    diff_count INT,
    invoice_amount DECIMAL(28,2),
    invoice_balance DECIMAL(28,2)
);
INSERT INTO @q05
SELECT op.operator_id,l.station_id,l.detail_count,l.payable_amount,
       (SELECT COUNT(*) FROM dbo.ReconciliationDifference r
        WHERE r.settlement_id=l.settlement_id AND r.status=2),
       CAST((SELECT ISNULL(SUM(i.amount),0) FROM dbo.SettlementInvoice i
             WHERE i.settlement_id=l.settlement_id AND i.status IN (1,-1)) AS DECIMAL(28,2)),
       l.payable_amount-CAST((SELECT ISNULL(SUM(i.amount),0) FROM dbo.SettlementInvoice i
                              WHERE i.settlement_id=l.settlement_id AND i.status IN (1,-1)) AS DECIMAL(28,2))
FROM dbo.v_SettlementLedger l
JOIN dbo.ChargingStation st ON st.station_id=l.station_id
JOIN dbo.Operator op ON op.operator_id=st.operator_id
WHERE l.period_month=@period;
IF (SELECT COUNT(*) FROM @q05)<>5
    THROW 52933, N'Q05 expected five station settlements for 202610.', 1;
IF EXISTS
(
    SELECT 1 FROM @q05
    WHERE detail_count<1 OR payable_amount<0 OR invoice_balance<>payable_amount-invoice_amount
)
    THROW 52934, N'Q05 returned inconsistent settlement or invoice totals.', 1;
IF EXISTS (SELECT 1 FROM @q05 WHERE operator_id<>'B_DEMO_OP01')
    THROW 52935, N'Q05 attributed a station to the wrong operator.', 1;

SELECT N'Q04/Q05 multi-table query assertions' AS test_name,
       N'passed' AS test_result,
       (SELECT COUNT(*) FROM @q04) AS q04_rows,
       (SELECT COUNT(*) FROM @q05) AS q05_rows;

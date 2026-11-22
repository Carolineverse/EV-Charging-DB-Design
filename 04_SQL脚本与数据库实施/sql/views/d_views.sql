CREATE VIEW dbo.v_DeviceReportAbnormal AS
SELECT r.report_id, r.pile_id, r.received_at, r.report_type, r.processing_status,
       m.monitoring_id, m.gun_id, m.collected_at, m.output_voltage, m.output_current,
       m.power, m.module_temperature, m.raw_fault_code
FROM dbo.DeviceReport r
LEFT JOIN dbo.DeviceMonitoringData m ON m.report_id = r.report_id;
GO

-- [C] 2. 待处理告警
CREATE VIEW dbo.v_PendingAlarm AS
SELECT a.alarm_id, a.pile_id, a.gun_id, a.alarm_code, d.alarm_name, d.target_type,
       lv.level_name, a.alarm_level, a.alarm_description, a.alarm_source,
       a.occurred_at, a.status
FROM dbo.Alarm a
JOIN dbo.AlarmCodeDict d ON a.alarm_code = d.alarm_code
JOIN dbo.AlarmLevelPolicy lv ON a.alarm_level = lv.alarm_level
WHERE a.status IN ('PENDING','PENDING_VERIFY');
GO

-- [C] 3. 工单处置进度
CREATE VIEW dbo.v_WorkOrderProgress AS
SELECT w.work_order_id, w.alarm_id, w.status AS workorder_status,
       w.assigned_at, w.accept_deadline, w.accepted_at, w.arrival_deadline, w.arrival_at,
       w.repaired_at, w.parts_replaced, w.result,
       eng.staff_name AS engineer_name, disp.staff_name AS dispatcher_name,
       a.alarm_code, a.alarm_description, a.status AS alarm_status
FROM dbo.WorkOrder w
JOIN dbo.Alarm a ON w.alarm_id = a.alarm_id
LEFT JOIN dbo.StaffProfile eng ON w.engineer_staff_id = eng.staff_id
LEFT JOIN dbo.StaffProfile disp ON w.dispatcher_staff_id = disp.staff_id;
GO

-- [D] 4. 结算台账
CREATE VIEW dbo.v_SettlementLedger AS
SELECT s.settlement_id, s.station_id, st.station_name, op.operator_id, op.operator_name,
       s.period_month, s.platform_rate, d.detail_count,
       COALESCE(d.gross_amount, 0) AS gross_amount,
       COALESCE(d.platform_fee, 0) AS platform_fee,
       s.adjustment_amount, COALESCE(c.carryover_amount, 0) AS carryover_amount,
       CAST(COALESCE(d.gross_amount, 0) AS DECIMAL(28,2))
           - CAST(COALESCE(d.platform_fee, 0) AS DECIMAL(28,2))
           + s.adjustment_amount + CAST(COALESCE(c.carryover_amount, 0) AS DECIMAL(28,2)) AS payable_amount,
       s.status, s.confirmed_at, s.completed_at
FROM dbo.SettlementStatement s
JOIN dbo.ChargingStation st ON s.station_id = st.station_id
JOIN dbo.Operator op ON st.operator_id = op.operator_id
OUTER APPLY (
    SELECT COUNT(*) AS detail_count,
           SUM(d.electricity_base + d.service_base + d.minimum_adjustment) AS gross_amount,
           SUM(CAST(ROUND((d.service_base + d.minimum_adjustment) * s.platform_rate, 2)
                    AS DECIMAL(19,2))) AS platform_fee
    FROM dbo.SettlementDetail d
    WHERE d.settlement_id = s.settlement_id
) d
OUTER APPLY (
    SELECT SUM(c.adjustment_amount) AS carryover_amount
    FROM dbo.SettlementCarryoverAdjustment c
    WHERE c.target_settlement_id = s.settlement_id AND c.status = 'APPLIED'
) c;
GO

-- [D] 5. 逐单差异追溯
CREATE VIEW dbo.v_SettlementDifference AS
SELECT r.difference_id, r.settlement_id, r.order_id, r.difference_type, r.difference_amount,
       r.status, r.resolution, r.operator_evidence, r.created_at, r.reviewed_at,
       d.energy_snapshot, d.electricity_base, d.service_base, d.minimum_adjustment,
       d.settlement_source
FROM dbo.ReconciliationDifference r
JOIN dbo.SettlementDetail d ON d.settlement_id = r.settlement_id AND d.order_id = r.order_id;
GO

-- [D] 6. 开票余额与红冲追溯
CREATE VIEW dbo.v_InvoiceBalanceAndRed AS
SELECT l.settlement_id, l.payable_amount, COALESCE(t.effective_amount, 0) AS effective_amount,
       l.payable_amount - CAST(COALESCE(t.effective_amount, 0) AS DECIMAL(28,2)) AS invoice_balance,
       i.invoice_id, i.invoice_no, i.invoice_title, i.amount, i.status,
       i.original_invoice_id, i.red_reason, i.issued_at, i.approved_at,
       orig.invoice_no AS original_invoice_no
FROM dbo.v_SettlementLedger l
LEFT JOIN dbo.SettlementInvoice i ON i.settlement_id = l.settlement_id
LEFT JOIN dbo.SettlementInvoice orig ON i.original_invoice_id = orig.invoice_id
OUTER APPLY (
    SELECT SUM(r.amount) AS effective_amount
    FROM dbo.SettlementInvoice r
    WHERE r.settlement_id = l.settlement_id AND r.status IN (1, -1)
) t;
GO

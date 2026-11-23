-- =============================================================
-- 全组 5 条多表查询（每条 ≥3 表，覆盖不同业务场景）
-- Q01~Q03 为 B 负责；Q04~Q05 为 D 负责（可直接在 D 测试库运行）。
-- =============================================================

-- =============================================================
-- Q01（B）场站设备统计：各运营商/场站的桩数、枪数、可用枪数
-- 关系：Operator + ChargingStation + ChargingPile + ChargingGun（4 表）
-- =============================================================
SELECT op.operator_id, op.operator_name, s.station_id, s.station_name,
       COUNT(DISTINCT p.pile_id) AS pile_count,
       COUNT(DISTINCT g.gun_id)  AS gun_count,
       SUM(CASE WHEN g.status = 'IDLE' THEN 1 ELSE 0 END) AS idle_gun_count
FROM dbo.Operator op
JOIN dbo.ChargingStation s ON s.operator_id = op.operator_id
JOIN dbo.ChargingPile    p ON p.station_id  = s.station_id
JOIN dbo.ChargingGun     g ON g.pile_id     = p.pile_id
GROUP BY op.operator_id, op.operator_name, s.station_id, s.station_name
ORDER BY op.operator_name, s.station_id;

-- =============================================================
-- Q02（B）某场站近 30 天分时段充电电量与收入构成
-- 关系：ChargingStation + ChargingOrder + OrderFeeDetail + BillingRule（4 表）
-- 参数：场站编号、日期范围（此处以 B_DEMO_ST01 近 30 天为例）
-- =============================================================
SELECT b.period_type,
       SUM(o.energy_kwh)                                          AS total_energy_kwh,
       SUM(ROUND(f.segment_energy_kwh * b.electricity_price, 2))  AS electricity_fee,
       SUM(ROUND(f.segment_energy_kwh * b.service_price, 2))      AS service_fee
FROM dbo.ChargingOrder o
JOIN dbo.ChargingStation s ON s.station_id = o.opening_station_id
JOIN dbo.OrderFeeDetail  f ON f.order_id = o.order_id
JOIN dbo.BillingRule     b ON b.billing_rule_id = f.billing_rule_id
WHERE s.station_id = 'B_DEMO_ST01'
  AND o.end_time >= DATEADD(day, -30, SYSDATETIME())
  AND o.status IN ('PENDING_PAYMENT','PAID')
GROUP BY b.period_type
ORDER BY b.period_type;

-- =============================================================
-- Q03（B）企业月结：企业账期金额、订单笔数、结清情况
-- 关系：EnterpriseProfile + EnterpriseSettlement + EnterpriseSettlementDetail + ChargingOrder（4 表）
-- =============================================================
SELECT e.enterprise_id, e.enterprise_name, m.billing_period_start,
       m.total_order_count, m.total_amount,
       m.confirmed_at, m.paid_at,
       CASE WHEN m.paid_at IS NOT NULL THEN N'已结清'
            WHEN m.confirmed_at IS NOT NULL THEN N'已确认'
            ELSE N'已生成' END AS settle_status
FROM dbo.EnterpriseProfile e
JOIN dbo.EnterpriseSettlement m ON m.enterprise_id = e.enterprise_id
JOIN dbo.EnterpriseSettlementDetail d ON d.enterprise_settlement_id = m.enterprise_settlement_id
JOIN dbo.ChargingOrder o ON o.order_id = d.order_id
WHERE m.billing_period_start >= '2026-01-01'
GROUP BY e.enterprise_id, e.enterprise_name, m.billing_period_start,
         m.total_order_count, m.total_amount, m.confirmed_at, m.paid_at
ORDER BY e.enterprise_name, m.billing_period_start;

-- =============================================================
-- Q04（D）告警与工单：指定场站告警、处理进度及工程师
-- 关系：ChargingStation + ChargingPile + Alarm + AlarmCodeDict
--       + AlarmLevelPolicy + WorkOrder + StaffProfile（7 表）
-- =============================================================
SELECT s.station_id, s.station_name, a.alarm_id, a.alarm_code, d.alarm_name, lv.level_name,
       a.status AS alarm_status, a.occurred_at, a.recovered_at,
       w.work_order_id, w.status AS workorder_status, w.assigned_at, w.repaired_at,
       eng.staff_name AS engineer_name
FROM dbo.ChargingStation s
JOIN dbo.ChargingPile p ON p.station_id = s.station_id
JOIN dbo.Alarm a        ON a.pile_id = p.pile_id
JOIN dbo.AlarmCodeDict d ON a.alarm_code = d.alarm_code
JOIN dbo.AlarmLevelPolicy lv ON a.alarm_level = lv.alarm_level
LEFT JOIN dbo.WorkOrder w ON w.alarm_id = a.alarm_id
LEFT JOIN dbo.StaffProfile eng ON w.engineer_staff_id = eng.staff_id
WHERE s.station_id = 'B_DEMO_ST01'
ORDER BY a.occurred_at DESC;

-- =============================================================
-- Q05（D）运营商账期汇总：应结金额、已生效差异笔数、开票净额
-- 关系：Operator + ChargingStation + SettlementStatement + SettlementDetail
--       + ReconciliationDifference + SettlementInvoice（6 表）
-- 从表用标量子查询聚合，避免一行多票/多差异导致行爆炸
-- =============================================================
DECLARE @period_month CHAR(6) = '202610';

SELECT op.operator_id, op.operator_name, l.station_id, l.station_name, l.period_month,
       l.detail_count, l.gross_amount, l.platform_fee,
       l.adjustment_amount, l.carryover_amount, l.payable_amount,
       (SELECT COUNT(*) FROM dbo.ReconciliationDifference r
         WHERE r.settlement_id = l.settlement_id AND r.status = 2) AS closed_diff_count,
       (SELECT ISNULL(SUM(i.amount), 0) FROM dbo.SettlementInvoice i
         WHERE i.settlement_id = l.settlement_id AND i.status IN (1, -1)) AS effective_invoice_amount,
       l.status AS statement_status
FROM dbo.v_SettlementLedger l
JOIN dbo.ChargingStation st ON st.station_id = l.station_id
JOIN dbo.Operator       op ON op.operator_id = st.operator_id
WHERE l.period_month = @period_month
ORDER BY op.operator_name, l.station_id;

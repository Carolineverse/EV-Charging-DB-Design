-- Q04 告警和工单：指定场站 B_DEMO_ST01 的告警、处理进度及工程师
SELECT a.alarm_id, a.alarm_code, d.alarm_name, lv.level_name,
       a.status AS alarm_status, a.occurred_at, a.recovered_at,
       w.work_order_id, w.status AS workorder_status,
       w.assigned_at, w.accepted_at, w.repaired_at,
       eng.staff_name AS engineer_name
FROM dbo.Alarm a
JOIN dbo.AlarmCodeDict d ON a.alarm_code = d.alarm_code
JOIN dbo.AlarmLevelPolicy lv ON a.alarm_level = lv.alarm_level
JOIN dbo.ChargingPile p ON a.pile_id = p.pile_id
JOIN dbo.ChargingStation s ON p.station_id = s.station_id
LEFT JOIN dbo.WorkOrder w ON w.alarm_id = a.alarm_id
LEFT JOIN dbo.StaffProfile eng ON w.engineer_staff_id = eng.staff_id
WHERE s.station_id = 'B_DEMO_ST01'
ORDER BY a.occurred_at DESC;
GO

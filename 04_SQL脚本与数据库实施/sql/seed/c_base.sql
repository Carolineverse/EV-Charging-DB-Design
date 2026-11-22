-- =============================================================
-- C 线种子：告警等级/告警码/场站分配/排班/报文/监测/告警/工单/通知/反馈
-- 前置：r_base.sql（员工账号）、00_b_fixture.sql（场站桩枪 + 车主）
-- 目标：业务表达到 20 条以上；字典表按业务域（等级 3、告警码 10）
-- =============================================================
SET NOCOUNT ON;

-- 三级告警时限
INSERT INTO dbo.AlarmLevelPolicy (alarm_level, level_name, accept_timeout_minutes, accept_urge_grace_minutes, arrival_timeout_minutes) VALUES
(1, N'一般', 30, 10, 120), (2, N'重要', 15, 5, 60), (3, N'紧急', 5, 2, 30);

-- 告警码（AL001~AL010）
INSERT INTO dbo.AlarmCodeDict (alarm_code, alarm_name, target_type, default_level, blocks_new_order, normal_observation_count, recovery_rule_description) VALUES
('AL001', N'模块过温',   'PILE', 2, 1, 3, N'连续三次模块温度正常后解除'),
('AL002', N'输出过流',   'GUN',  2, 1, 3, N'连续三次电流正常后解除'),
('AL003', N'输出过压',   'GUN',  2, 1, 3, N'连续三次电压正常后解除'),
('AL004', N'通信中断',   'PILE', 3, 1, 3, N'恢复心跳后解除'),
('AL005', N'设备离线',   'PILE', 2, 0, 3, N'恢复有效心跳后解除'),
('AL006', N'人工报障',   'BOTH', 1, 0, NULL, N'人工核查后关闭'),
('AL007', N'未知故障码', 'BOTH', 1, 0, 3, N'人工映射故障码后解除'),
('AL008', N'绝缘异常',   'GUN',  3, 1, 3, N'绝缘测试通过后解除'),
('AL009', N'枪温过高',   'GUN',  2, 1, 3, N'连续三次枪温正常后解除'),
('AL010', N'计量异常',   'PILE', 2, 1, 3, N'计量校验通过后解除');

-- 故障码映射（12 条，两个型号 × 6 个原始码）
INSERT INTO dbo.DeviceFaultCodeMapping (device_model, raw_fault_code, alarm_code) VALUES
('DC-120KW','F001','AL001'),('DC-120KW','F002','AL002'),('DC-120KW','F003','AL003'),
('DC-120KW','F004','AL004'),('DC-120KW','F005','AL008'),('DC-120KW','F006','AL010'),
('AC-7KW','F001','AL001'),('AC-7KW','F002','AL002'),('AC-7KW','F003','AL003'),
('AC-7KW','F004','AL004'),('AC-7KW','F007','AL009'),('AC-7KW','F008','AL010');

-- 场站分配：4 名工程师 × 5 个场站 = 20 条
INSERT INTO dbo.StaffStationAssignment (staff_id, station_id, effective_from)
SELECT e.staff_id, 'ST-' + RIGHT('00' + CAST(n AS VARCHAR), 3), '2026-08-01T08:00:00'
FROM (VALUES ('STF-DEMO-R02'),('STF-DEMO-R02A'),('STF-DEMO-R02B'),('STF-DEMO-R02C')) e(staff_id)
CROSS JOIN (VALUES (1),(2),(3),(4),(5)) v(n);

-- 值班表：20 条（4 名工程师；前 4 条覆盖当前时刻，供派单演示）
DECLARE @duty INT = 1;
WHILE @duty <= 20
BEGIN
    DECLARE @duty_eng VARCHAR(20) = CASE @duty % 4 WHEN 0 THEN 'STF-DEMO-R02C' WHEN 1 THEN 'STF-DEMO-R02' WHEN 2 THEN 'STF-DEMO-R02A' ELSE 'STF-DEMO-R02B' END;
    DECLARE @duty_start DATETIME2(3) = CASE WHEN @duty <= 4 THEN DATEADD(hour, -2, SYSDATETIME()) ELSE DATEADD(day, -@duty, SYSDATETIME()) END;
    DECLARE @duty_end DATETIME2(3) = CASE WHEN @duty <= 4 THEN DATEADD(hour, 10, SYSDATETIME()) ELSE DATEADD(hour, 12, DATEADD(day, -@duty, SYSDATETIME())) END;
    INSERT INTO dbo.EngineerDutySchedule (staff_id, duty_start, duty_end, duty_status, accepting_status)
    VALUES (@duty_eng, @duty_start, @duty_end, 'ACTIVE', 'ACCEPTING');
    SET @duty = @duty + 1;
END;

-- 设备报文：20 条
DECLARE @rpt INT = 1;
WHILE @rpt <= 20
BEGIN
    INSERT INTO dbo.DeviceReport (report_id, pile_id, generated_at, received_at, payload_hash, processing_status, processed_at, report_type)
    VALUES ('RPT-' + RIGHT('0000' + CAST(@rpt AS VARCHAR), 4),
            'PILE-' + RIGHT('00' + CAST(((@rpt - 1) % 10) + 1 AS VARCHAR), 3),
            DATEADD(minute, @rpt * 10, '2026-11-01T08:00:00'), DATEADD(second, 1, DATEADD(minute, @rpt * 10, '2026-11-01T08:00:00')),
            REPLICATE('0', 64), 'PROCESSED', DATEADD(second, 2, DATEADD(minute, @rpt * 10, '2026-11-01T08:00:00')), 'MINUTE_MONITOR');
    SET @rpt = @rpt + 1;
END;

-- 运行监测数据：40 条（跨 11、12 两月，覆盖分区）
DECLARE @mon INT = 1;
WHILE @mon <= 40
BEGIN
    INSERT INTO dbo.DeviceMonitoringData (report_id, pile_id, gun_id, collected_at, output_voltage, output_current, power, module_temperature, raw_fault_code)
    VALUES ('RPT-' + RIGHT('0000' + CAST(((@mon - 1) % 20) + 1 AS VARCHAR), 4),
            'PILE-' + RIGHT('00' + CAST(((@mon - 1) % 10) + 1 AS VARCHAR), 3),
            CASE WHEN @mon % 2 = 0 THEN 'GUN-' + RIGHT('00' + CAST(((@mon - 1) % 10) + 1 AS VARCHAR), 3) + '-01' ELSE NULL END,
            CASE WHEN @mon <= 20 THEN DATEADD(minute, @mon * 5, '2026-11-01T08:00:00') ELSE DATEADD(minute, (@mon - 20) * 5, '2026-12-01T08:00:00') END,
            220 + (@mon % 6) * 0.5, 32 + (@mon % 4), 7 + (@mon % 9) * 0.5, 25 + (@mon % 7) * 9, NULL);
    SET @mon = @mon + 1;
END;

-- 告警：20 条
DECLARE @al INT = 1;
WHILE @al <= 20
BEGIN
    INSERT INTO dbo.Alarm (pile_id, gun_id, alarm_code, alarm_level, alarm_description, alarm_source, occurred_at, status)
    VALUES ('PILE-' + RIGHT('00' + CAST(((@al - 1) % 10) + 1 AS VARCHAR), 3),
            NULL, 'AL' + RIGHT('00' + CAST(((@al - 1) % 7) + 1 AS VARCHAR), 3), 1 + (@al % 3),
            N'演示告警 ' + CAST(@al AS NVARCHAR), CASE WHEN @al % 3 = 0 THEN 'MANUAL_ENTRY' ELSE 'DEVICE_REPORT' END,
            DATEADD(day, @al, '2026-11-01T09:00:00'),
            CASE @al % 6 WHEN 0 THEN 'PENDING_VERIFY' WHEN 1 THEN 'PENDING' WHEN 2 THEN 'PROCESSING' WHEN 3 THEN 'PENDING_REVIEW' WHEN 4 THEN 'RECOVERED' ELSE 'CLOSED_UNCONFIRMED' END);
    SET @al = @al + 1;
END;

-- 工单：20 条（关联告警 1..20）
DECLARE @wo INT = 1;
WHILE @wo <= 20
BEGIN
    INSERT INTO dbo.WorkOrder (alarm_id, dispatcher_staff_id, engineer_staff_id, assigned_at, status, accept_deadline, accept_urge_deadline, arrival_deadline)
    VALUES (@wo, 'STF-DEMO-R01',
            CASE @wo % 4 WHEN 0 THEN 'STF-DEMO-R02C' WHEN 1 THEN 'STF-DEMO-R02' WHEN 2 THEN 'STF-DEMO-R02A' ELSE 'STF-DEMO-R02B' END,
            DATEADD(day, @wo, '2026-11-01T09:10:00'),
            CASE @wo % 6 WHEN 0 THEN 'PENDING_ACCEPT' WHEN 1 THEN 'PENDING_ARRIVAL' WHEN 2 THEN 'PROCESSING' WHEN 3 THEN 'PENDING_REVIEW' WHEN 4 THEN 'COMPLETED' ELSE 'TERMINATED' END,
            DATEADD(minute, 30, DATEADD(day, @wo, '2026-11-01T09:10:00')), NULL, NULL);
    SET @wo = @wo + 1;
END;

-- 通知：20 条
DECLARE @nt INT = 1;
WHILE @nt <= 20
BEGIN
    INSERT INTO dbo.NotificationLog (business_type, business_id, recipient_account_id, event_code, content, delivery_status, sent_at, created_at)
    VALUES (CASE WHEN @nt % 2 = 0 THEN 'WORKORDER' ELSE 'ALARM' END, @nt,
            (SELECT account_id FROM dbo.SysAccount WHERE username='demo_engineer_r02'),
            'DISPATCH', N'演示通知 ' + CAST(@nt AS NVARCHAR), 'SENT', SYSDATETIME(), SYSDATETIME());
    SET @nt = @nt + 1;
END;

-- 用户反馈：20 条
DECLARE @fb INT = 1;
WHILE @fb <= 20
BEGIN
    INSERT INTO dbo.CustomerFeedback (user_id, feedback_type, station_id, pile_id, order_id, rating, content, status, created_at)
    VALUES ('U-' + RIGHT('000' + CAST(@fb AS VARCHAR), 3),
            CASE @fb % 3 WHEN 0 THEN 'FAULT_REPORT' WHEN 1 THEN 'COMPLAINT' ELSE 'REVIEW' END,
            'ST-' + RIGHT('00' + CAST(((@fb - 1) % 5) + 1 AS VARCHAR), 3),
            'PILE-' + RIGHT('00' + CAST(((@fb - 1) % 10) + 1 AS VARCHAR), 3),
            NULL, CASE WHEN @fb % 3 = 2 THEN 4 + (@fb % 2) ELSE NULL END,
            N'演示反馈 ' + CAST(@fb AS NVARCHAR), CASE WHEN @fb % 3 = 2 THEN 'CLOSED' ELSE 'SUBMITTED' END, SYSDATETIME());
    SET @fb = @fb + 1;
END;

-- 反馈-告警关联：20 条
DECLARE @fa INT = 1;
WHILE @fa <= 20
BEGIN
    INSERT INTO dbo.FeedbackAlarm (feedback_id, alarm_id, created_at)
    VALUES (@fa, @fa, SYSDATETIME());
    SET @fa = @fa + 1;
END;
GO

-- 校验行数
SELECT 'AlarmLevelPolicy' t, COUNT(*) n FROM dbo.AlarmLevelPolicy
UNION ALL SELECT 'AlarmCodeDict', COUNT(*) FROM dbo.AlarmCodeDict
UNION ALL SELECT 'StaffStationAssignment', COUNT(*) FROM dbo.StaffStationAssignment
UNION ALL SELECT 'EngineerDutySchedule', COUNT(*) FROM dbo.EngineerDutySchedule
UNION ALL SELECT 'DeviceReport', COUNT(*) FROM dbo.DeviceReport
UNION ALL SELECT 'DeviceMonitoringData', COUNT(*) FROM dbo.DeviceMonitoringData
UNION ALL SELECT 'Alarm', COUNT(*) FROM dbo.Alarm
UNION ALL SELECT 'WorkOrder', COUNT(*) FROM dbo.WorkOrder
UNION ALL SELECT 'NotificationLog', COUNT(*) FROM dbo.NotificationLog
UNION ALL SELECT 'CustomerFeedback', COUNT(*) FROM dbo.CustomerFeedback
UNION ALL SELECT 'FeedbackAlarm', COUNT(*) FROM dbo.FeedbackAlarm
UNION ALL SELECT 'DeviceFaultCodeMapping', COUNT(*) FROM dbo.DeviceFaultCodeMapping;

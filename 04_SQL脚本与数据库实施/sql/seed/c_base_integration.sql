-- =============================================================
-- C 线种子 前置：r_base、50_B_demo_settlement_data、60_D_demo_bulk_data 已执行
-- =============================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRY
BEGIN TRANSACTION;

DECLARE @stations TABLE (idx INT, station_id VARCHAR(20), pile_id VARCHAR(20), gun_id VARCHAR(20));
INSERT INTO @stations VALUES
 (1,'B_DEMO_ST01','B_DEMO_PILE01','B_DEMO_GUN01'),
 (2,'D_DEMO_ST02','D_DEMO_PILE02','D_DEMO_GUN02'),
 (3,'D_DEMO_ST03','D_DEMO_PILE03','D_DEMO_GUN03'),
 (4,'D_DEMO_ST04','D_DEMO_PILE04','D_DEMO_GUN04'),
 (5,'D_DEMO_ST05','D_DEMO_PILE05','D_DEMO_GUN05');

-- 告警等级
IF NOT EXISTS (SELECT 1 FROM dbo.AlarmLevelPolicy)
    INSERT INTO dbo.AlarmLevelPolicy (alarm_level, level_name, accept_timeout_minutes, accept_urge_grace_minutes, arrival_timeout_minutes) VALUES
    (1, N'一般', 30, 10, 120), (2, N'重要', 15, 5, 60), (3, N'紧急', 5, 2, 30);

-- 告警码
IF NOT EXISTS (SELECT 1 FROM dbo.AlarmCodeDict)
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

-- 故障码映射
IF NOT EXISTS (SELECT 1 FROM dbo.DeviceFaultCodeMapping)
    INSERT INTO dbo.DeviceFaultCodeMapping (device_model, raw_fault_code, alarm_code) VALUES
    ('B-DEMO-DC120','F001','AL001'),('B-DEMO-DC120','F002','AL002'),('B-DEMO-DC120','F003','AL003'),
    ('B-DEMO-DC120','F004','AL004'),('B-DEMO-DC120','F005','AL008'),('B-DEMO-DC120','F006','AL010'),
    ('D-DEMO-DC120','F001','AL001'),('D-DEMO-DC120','F002','AL002'),('D-DEMO-DC120','F003','AL003'),
    ('D-DEMO-DC120','F004','AL004'),('D-DEMO-DC120','F007','AL009'),('D-DEMO-DC120','F008','AL010');

-- 场站分配：4 名工程师 × 5 站 = 20
IF NOT EXISTS (SELECT 1 FROM dbo.StaffStationAssignment)
    INSERT INTO dbo.StaffStationAssignment (staff_id, station_id, effective_from)
    SELECT e.staff_id, s.station_id, '2026-06-01T08:00:00'
    FROM (VALUES ('STF-DEMO-R02'),('STF-DEMO-R02A'),('STF-DEMO-R02B'),('STF-DEMO-R02C')) e(staff_id)
    CROSS JOIN @stations s;

-- 值班：20（前 4 条覆盖当前时刻）
IF NOT EXISTS (SELECT 1 FROM dbo.EngineerDutySchedule)
BEGIN
    DECLARE @duty INT = 1;
    WHILE @duty <= 20
    BEGIN
        DECLARE @deng VARCHAR(20) = CASE @duty % 4 WHEN 0 THEN 'STF-DEMO-R02C' WHEN 1 THEN 'STF-DEMO-R02' WHEN 2 THEN 'STF-DEMO-R02A' ELSE 'STF-DEMO-R02B' END;
        INSERT INTO dbo.EngineerDutySchedule (staff_id, duty_start, duty_end, duty_status, accepting_status)
        VALUES (@deng,
                CASE WHEN @duty <= 4 THEN DATEADD(hour, -2, SYSDATETIME()) ELSE DATEADD(day, -@duty, SYSDATETIME()) END,
                CASE WHEN @duty <= 4 THEN DATEADD(hour, 10, SYSDATETIME()) ELSE DATEADD(hour, 12, DATEADD(day, -@duty, SYSDATETIME())) END,
                'ACTIVE', 'ACCEPTING');
        SET @duty = @duty + 1;
    END;
END;

-- 报文 + 监测 + 告警（按 5 个桩，覆盖 9/10 两月）
DECLARE @k INT = 1;
WHILE @k <= 40
BEGIN
    DECLARE @pid VARCHAR(20);
    SELECT @pid = pile_id FROM @stations WHERE idx = ((@k - 1) % 5) + 1;
    DECLARE @t DATETIME2(3) = CASE WHEN @k <= 20
        THEN DATEADD(minute, @k * 5, '2026-09-01T08:00:00')
        ELSE DATEADD(minute, (@k - 20) * 5, '2026-10-01T08:00:00') END;

    IF NOT EXISTS (SELECT 1 FROM dbo.DeviceReport WHERE report_id = 'RPT-' + RIGHT('0000' + CAST(@k AS VARCHAR), 4))
        INSERT INTO dbo.DeviceReport (report_id, pile_id, generated_at, received_at, payload_hash, processing_status, processed_at, report_type)
        VALUES ('RPT-' + RIGHT('0000' + CAST(@k AS VARCHAR), 4), @pid, @t, DATEADD(second,1,@t), REPLICATE('0',64), 'PROCESSED', DATEADD(second,2,@t), 'MINUTE_MONITOR');

    INSERT INTO dbo.DeviceMonitoringData (report_id, pile_id, gun_id, collected_at, output_voltage, output_current, power, module_temperature, raw_fault_code)
    VALUES ('RPT-' + RIGHT('0000' + CAST(@k AS VARCHAR), 4), @pid, NULL, @t,
            220 + (@k % 6) * 0.5, 32 + (@k % 4), 7 + (@k % 9) * 0.5, 25 + (@k % 7) * 9, NULL);
    SET @k = @k + 1;
END;

-- 告警 20
DECLARE @alarms TABLE (seq INT PRIMARY KEY, alarm_id BIGINT);
DECLARE @work_orders TABLE (seq INT PRIMARY KEY, work_order_id BIGINT);
DECLARE @feedback TABLE (seq INT PRIMARY KEY, feedback_id BIGINT);
DECLARE @al INT = 1;
WHILE @al <= 20
BEGIN
    DECLARE @apid VARCHAR(20), @alarm_gun VARCHAR(20);
    SELECT @apid = pile_id, @alarm_gun = gun_id FROM @stations WHERE idx = ((@al - 1) % 5) + 1;
    INSERT INTO dbo.Alarm (pile_id, gun_id, alarm_code, alarm_level, alarm_description, alarm_source, occurred_at, status)
    OUTPUT @al, inserted.alarm_id INTO @alarms
    VALUES (@apid, CASE WHEN ((@al - 1) % 7) + 1 IN (2,3) THEN @alarm_gun END, 'AL' + RIGHT('00' + CAST(((@al - 1) % 7) + 1 AS VARCHAR), 3), 1 + (@al % 3),
            N'演示告警 ' + CAST(@al AS NVARCHAR), CASE WHEN @al % 3 = 0 THEN 'MANUAL_ENTRY' ELSE 'DEVICE_REPORT' END,
            DATEADD(day, @al, '2026-10-01T09:00:00'),
            CASE @al % 6 WHEN 0 THEN 'PENDING_VERIFY' WHEN 1 THEN 'PENDING' WHEN 2 THEN 'PROCESSING' WHEN 3 THEN 'PENDING_REVIEW' WHEN 4 THEN 'RECOVERED' ELSE 'CLOSED_UNCONFIRMED' END);
    SET @al = @al + 1;
END;

-- 工单 20
DECLARE @wo INT = 1;
WHILE @wo <= 20
BEGIN
    INSERT INTO dbo.WorkOrder (alarm_id, dispatcher_staff_id, engineer_staff_id, assigned_at, status, accept_deadline)
    OUTPUT @wo, inserted.work_order_id INTO @work_orders
    VALUES ((SELECT alarm_id FROM @alarms WHERE seq = @wo), 'STF-DEMO-R01',
            CASE @wo % 4 WHEN 0 THEN 'STF-DEMO-R02C' WHEN 1 THEN 'STF-DEMO-R02' WHEN 2 THEN 'STF-DEMO-R02A' ELSE 'STF-DEMO-R02B' END,
            DATEADD(day, @wo, '2026-10-01T09:10:00'),
            CASE @wo % 6 WHEN 0 THEN 'PENDING_ACCEPT' WHEN 1 THEN 'PENDING_ARRIVAL' WHEN 2 THEN 'PROCESSING' WHEN 3 THEN 'PENDING_REVIEW' WHEN 4 THEN 'COMPLETED' ELSE 'TERMINATED' END,
            DATEADD(minute, 30, DATEADD(day, @wo, '2026-10-01T09:10:00')));
    SET @wo = @wo + 1;
END;

-- 通知 20
DECLARE @nt INT = 1;
WHILE @nt <= 20
BEGIN
    INSERT INTO dbo.NotificationLog (business_type, business_id, recipient_account_id, event_code, content, delivery_status, sent_at, created_at)
    VALUES (CASE WHEN @nt % 2 = 0 THEN 'WORKORDER' ELSE 'ALARM' END,
            CASE WHEN @nt % 2 = 0 THEN (SELECT work_order_id FROM @work_orders WHERE seq = @nt)
                 ELSE (SELECT alarm_id FROM @alarms WHERE seq = @nt) END,
            (SELECT account_id FROM dbo.SysAccount WHERE username='demo_engineer_r02'),
            'DISPATCH', N'演示通知 ' + CAST(@nt AS NVARCHAR), 'SENT', SYSDATETIME(), SYSDATETIME());
    SET @nt = @nt + 1;
END;

-- 反馈 20（用户统一 B_DEMO_USER01）
DECLARE @fb INT = 1;
WHILE @fb <= 20
BEGIN
    DECLARE @fst VARCHAR(20), @fpid VARCHAR(20);
    SELECT @fst = station_id, @fpid = pile_id FROM @stations WHERE idx = ((@fb - 1) % 5) + 1;
    INSERT INTO dbo.CustomerFeedback (user_id, feedback_type, station_id, pile_id, order_id, rating, content, status, created_at)
    OUTPUT @fb, inserted.feedback_id INTO @feedback
    VALUES ('B_DEMO_USER01',
            CASE @fb % 3 WHEN 0 THEN 'FAULT_REPORT' WHEN 1 THEN 'COMPLAINT' ELSE 'REVIEW' END,
            @fst, @fpid, NULL,
            CASE WHEN @fb % 3 = 2 THEN 4 + (@fb % 2) ELSE NULL END,
            N'演示反馈 ' + CAST(@fb AS NVARCHAR),
            CASE WHEN @fb % 3 = 2 THEN 'CLOSED' ELSE 'SUBMITTED' END, SYSDATETIME());
    SET @fb = @fb + 1;
END;

-- 反馈-告警关联 20
INSERT INTO dbo.FeedbackAlarm (feedback_id, alarm_id, created_at)
SELECT f.feedback_id, a.alarm_id, SYSDATETIME()
FROM @feedback f JOIN @alarms a ON a.seq = f.seq;

COMMIT TRANSACTION;
SELECT 'AlarmCodeDict' t, COUNT(*) n FROM dbo.AlarmCodeDict
UNION ALL SELECT 'StaffStationAssignment', COUNT(*) FROM dbo.StaffStationAssignment
UNION ALL SELECT 'EngineerDutySchedule', COUNT(*) FROM dbo.EngineerDutySchedule
UNION ALL SELECT 'DeviceReport', COUNT(*) FROM dbo.DeviceReport
UNION ALL SELECT 'DeviceMonitoringData', COUNT(*) FROM dbo.DeviceMonitoringData
UNION ALL SELECT 'Alarm', COUNT(*) FROM dbo.Alarm
UNION ALL SELECT 'WorkOrder', COUNT(*) FROM dbo.WorkOrder
UNION ALL SELECT 'NotificationLog', COUNT(*) FROM dbo.NotificationLog
UNION ALL SELECT 'CustomerFeedback', COUNT(*) FROM dbo.CustomerFeedback
UNION ALL SELECT 'FeedbackAlarm', COUNT(*) FROM dbo.FeedbackAlarm;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
END CATCH;
GO

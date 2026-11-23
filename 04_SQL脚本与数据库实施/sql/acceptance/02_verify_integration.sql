-- Read-only verification of the installed EV_B_TEST business dataset.
SET NOCOUNT ON;
IF DB_NAME() <> N'EV_B_TEST' THROW 52620, N'Choose EV_B_TEST', 1;

DECLARE @expected TABLE(table_name SYSNAME PRIMARY KEY, target_rows INT NULL, minimum_rows INT NULL);
INSERT INTO @expected VALUES
    ('Alarm',NULL,20),
    ('AlarmCodeDict',NULL,7),
    ('AlarmLevelPolicy',3,NULL),
    ('BillingRule',NULL,20),
    ('BillingRuleVersion',NULL,20),
    ('ChargingGun',NULL,20),
    ('ChargingMeterSample',NULL,20),
    ('ChargingOrder',NULL,20),
    ('ChargingPile',NULL,20),
    ('ChargingStation',NULL,20),
    ('CouponRedemption',NULL,20),
    ('CustomerFeedback',NULL,20),
    ('DeviceAssetCase',NULL,20),
    ('DeviceCommunicationConfig',1,NULL),
    ('DeviceFaultCodeMapping',NULL,20),
    ('DeviceMonitoringData',NULL,20),
    ('DeviceReport',NULL,20),
    ('DeviceStatusHistory',NULL,20),
    ('EngineerDutySchedule',NULL,20),
    ('EnterpriseCard',NULL,20),
    ('EnterpriseCardBinding',NULL,20),
    ('EnterpriseProfile',NULL,20),
    ('EnterpriseQuota',NULL,20),
    ('EnterpriseServiceApplication',NULL,20),
    ('EnterpriseSettlement',NULL,20),
    ('EnterpriseSettlementDetail',NULL,20),
    ('FeedbackAlarm',NULL,20),
    ('FleetMember',NULL,20),
    ('MemberLevel',3,NULL),
    ('NotificationLog',NULL,20),
    ('OperationLog',NULL,20),
    ('Operator',NULL,20),
    ('OperatorSettlementRate',NULL,20),
    ('OrderCommand',NULL,20),
    ('OrderFeeDetail',NULL,20),
    ('PaymentRecord',NULL,20),
    ('PersonalInvoiceAdjustment',NULL,20),
    ('PersonalInvoiceApplication',NULL,20),
    ('Promotion',NULL,20),
    ('PromotionMemberLevel',NULL,20),
    ('PromotionStation',NULL,20),
    ('ReconciliationDifference',NULL,20),
    ('RefundRecord',NULL,20),
    ('RolePermission',84,NULL),
    ('ServiceCaseAssignment',NULL,20),
    ('SettlementCarryoverAdjustment',NULL,20),
    ('SettlementDetail',28,NULL),
    ('SettlementInvoice',NULL,20),
    ('SettlementReviewCase',NULL,20),
    ('SettlementStatement',25,NULL),
    ('StaffProfile',NULL,20),
    ('StaffStationAssignment',NULL,20),
    ('SysAccount',NULL,20),
    ('SysPermission',70,NULL),
    ('SysRole',5,NULL),
    ('UserCoupon',NULL,20),
    ('UserMemberLevel',NULL,20),
    ('UserProfile',NULL,20),
    ('UserWallet',NULL,20),
    ('Vehicle',NULL,20),
    ('WalletTransaction',NULL,20),
    ('WorkOrder',NULL,20);

DECLARE @counts TABLE (table_name SYSNAME PRIMARY KEY, actual_rows BIGINT);
DECLARE @name SYSNAME, @sql NVARCHAR(MAX), @rows BIGINT;
DECLARE tables CURSOR LOCAL FAST_FORWARD FOR
    SELECT t.name FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE s.name='dbo';
OPEN tables;
FETCH NEXT FROM tables INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql=N'SELECT @rows=COUNT_BIG(*) FROM dbo.'+QUOTENAME(@name);
    EXEC sys.sp_executesql @sql,N'@rows BIGINT OUTPUT',@rows OUTPUT;
    INSERT INTO @counts VALUES (@name,@rows);
    FETCH NEXT FROM tables INTO @name;
END;
CLOSE tables;
DEALLOCATE tables;

SELECT COUNT(*) AS dbo_tables, 62 AS expected_tables FROM @counts;
SELECT COALESCE(e.table_name,c.table_name) AS table_name, e.target_rows, e.minimum_rows, c.actual_rows,
       CASE WHEN c.table_name IS NULL THEN 'MISSING'
            WHEN e.table_name IS NULL THEN 'UNEXPECTED'
            WHEN e.target_rows IS NOT NULL AND c.actual_rows<>e.target_rows THEN 'WRONG_COUNT'
            WHEN e.minimum_rows IS NOT NULL AND c.actual_rows<e.minimum_rows THEN 'BELOW_MINIMUM'
            ELSE 'OK' END AS check_result
FROM @expected e FULL JOIN @counts c ON c.table_name=e.table_name
ORDER BY table_name;

-- Dictionary contents, in addition to the row targets above.
SELECT role_code FROM dbo.SysRole ORDER BY role_code;
SELECT alarm_level,level_name FROM dbo.AlarmLevelPolicy ORDER BY alarm_level;
SELECT member_level_id,level_name,level_sort FROM dbo.MemberLevel ORDER BY level_sort;
SELECT config_id,heartbeat_interval_seconds,offline_threshold_seconds FROM dbo.DeviceCommunicationConfig;
SELECT alarm_code,alarm_name FROM dbo.AlarmCodeDict ORDER BY alarm_code;

DECLARE @matrix TABLE(role_code VARCHAR(30),permission_code VARCHAR(80),data_scope VARCHAR(20),
                      PRIMARY KEY(role_code,permission_code));
INSERT INTO @matrix VALUES
    ('R01','ALARM_VIEW','ALL'),
    ('R01','ASSIGNMENT_MANAGE','ALL'),
    ('R01','DEVICE_CHANGE_REVIEW','ALL'),
    ('R01','DEVICE_MANAGE','ALL'),
    ('R01','DEVICE_VIEW','ALL'),
    ('R01','DUTY_MANAGE','ALL'),
    ('R01','INVOICE_RED_APPROVE','ALL'),
    ('R01','KPI_VIEW','ALL'),
    ('R01','MONITORING_VIEW','ALL'),
    ('R01','NOTIFICATION_VIEW','SELF'),
    ('R01','OPERATOR_MANAGE','ALL'),
    ('R01','PRICE_ADJUST_APPROVE','ALL'),
    ('R01','PROMOTION_REVIEW','ALL'),
    ('R01','ROLE_GRANT','ALL'),
    ('R01','SETTLEMENT_ADJUST_APPROVE','ALL'),
    ('R01','SETTLEMENT_CONFIRM','ALL'),
    ('R01','SETTLEMENT_VIEW','ALL'),
    ('R01','STAFF_STATION_MANAGE','ALL'),
    ('R01','STATION_MANAGE','ALL'),
    ('R01','STATION_VIEW','ALL'),
    ('R01','TARIFF_MANAGE','ALL'),
    ('R01','WORKORDER_REASSIGN','ALL'),
    ('R01','WORKORDER_URGE','ALL'),
    ('R01','WORKORDER_VIEW','ALL'),
    ('R02','ALARM_HANDLE','ASSIGNED'),
    ('R02','ALARM_VIEW','ASSIGNED'),
    ('R02','DEVICE_ACCEPTANCE','ASSIGNED'),
    ('R02','DEVICE_CHANGE_APPLY','ASSIGNED'),
    ('R02','DEVICE_VIEW','ASSIGNED'),
    ('R02','INSPECTION_RECORD','ASSIGNED'),
    ('R02','MONITORING_VIEW','ASSIGNED'),
    ('R02','NOTIFICATION_VIEW','SELF'),
    ('R02','PARTS_REPLACEMENT_RECORD','ASSIGNED'),
    ('R02','WORKORDER_ACCEPT','ASSIGNED'),
    ('R02','WORKORDER_UPDATE','ASSIGNED'),
    ('R02','WORKORDER_VIEW','ASSIGNED'),
    ('R03','ALARM_CREATE_MANUAL','ASSIGNED'),
    ('R03','ALARM_VIEW','ASSIGNED'),
    ('R03','CHARGING_EXCEPTION_HANDLE','ASSIGNED'),
    ('R03','CUSTOMER_PROFILE_MANAGE','ASSIGNED'),
    ('R03','DEVICE_VIEW','ASSIGNED'),
    ('R03','ENTERPRISE_BILL_HANDLE','ASSIGNED'),
    ('R03','FEEDBACK_HANDLE','ASSIGNED'),
    ('R03','INVOICE_APPEAL_HANDLE','ASSIGNED'),
    ('R03','INVOICE_ISSUE','ASSIGNED'),
    ('R03','INVOICE_RED_FLUSH','ASSIGNED'),
    ('R03','NOTIFICATION_VIEW','SELF'),
    ('R03','OPERATOR_CONFIRM_FOLLOW','ASSIGNED'),
    ('R03','ORDER_VIEW','ASSIGNED'),
    ('R03','PERSONAL_INVOICE_HANDLE','ASSIGNED'),
    ('R03','PROMOTION_CREATE','ASSIGNED'),
    ('R03','PROMOTION_ISSUE','ASSIGNED'),
    ('R03','RECONCILIATION_HANDLE','ASSIGNED'),
    ('R03','REFUND_HANDLE','ASSIGNED'),
    ('R03','SETTLEMENT_GENERATE','ASSIGNED'),
    ('R03','SETTLEMENT_VIEW','ASSIGNED'),
    ('R03','WORKORDER_VIEW','ASSIGNED'),
    ('R04','BALANCE_VIEW','SELF'),
    ('R04','CHARGING_PROGRESS_VIEW','SELF'),
    ('R04','CHARGING_START','SELF'),
    ('R04','CHARGING_STOP','SELF'),
    ('R04','COMPLAINT_SUBMIT','SELF'),
    ('R04','FAULT_REPORT','SELF'),
    ('R04','FEEDBACK_VIEW','SELF'),
    ('R04','INVOICE_APPLY','SELF'),
    ('R04','NOTIFICATION_VIEW','SELF'),
    ('R04','ORDER_VIEW','SELF'),
    ('R04','PAYMENT_EXECUTE','SELF'),
    ('R04','SERVICE_REVIEW','SELF'),
    ('R04','STATION_VIEW','PUBLIC'),
    ('R04','VEHICLE_MANAGE_SELF','SELF'),
    ('R04','WALLET_RECHARGE','SELF'),
    ('R05','CORPORATE_SETTLEMENT_APPLY','ENTERPRISE'),
    ('R05','DRIVER_MANAGE','ENTERPRISE'),
    ('R05','ENTERPRISE_BILL_CONFIRM','ENTERPRISE'),
    ('R05','ENTERPRISE_CARD_MANAGE','ENTERPRISE'),
    ('R05','ENTERPRISE_PAYMENT_SUBMIT','ENTERPRISE'),
    ('R05','ENTERPRISE_PRICE_APPLY','ENTERPRISE'),
    ('R05','FLEET_ORDER_VIEW','ENTERPRISE'),
    ('R05','MONTHLY_BILL_VIEW','ENTERPRISE'),
    ('R05','NOTIFICATION_VIEW','SELF'),
    ('R05','QUOTA_MANAGE','ENTERPRISE'),
    ('R05','STATION_VIEW','PUBLIC'),
    ('R05','VEHICLE_BIND','ENTERPRISE');
DECLARE @permission_codes TABLE(permission_code VARCHAR(80) PRIMARY KEY);
INSERT INTO @permission_codes SELECT DISTINCT permission_code FROM @matrix;
INSERT INTO @permission_codes VALUES ('SENSITIVE_EXPORT');

SELECT (SELECT COUNT(*) FROM dbo.SysPermission) AS permission_count,
       (SELECT COUNT(*) FROM dbo.RolePermission) AS grant_count,
       (SELECT COUNT(*) FROM dbo.SysPermission WHERE permission_code='SENSITIVE_EXPORT') AS sensitive_definition_count,
       (SELECT COUNT(*) FROM dbo.RolePermission rp JOIN dbo.SysPermission p ON p.permission_id=rp.permission_id
        WHERE p.permission_code='SENSITIVE_EXPORT') AS sensitive_grant_count;

DECLARE @actual_grants TABLE(role_code VARCHAR(30),permission_code VARCHAR(80),data_scope VARCHAR(20));
INSERT INTO @actual_grants
SELECT r.role_code,p.permission_code,rp.data_scope
FROM dbo.RolePermission rp JOIN dbo.SysRole r ON r.role_id=rp.role_id
JOIN dbo.SysPermission p ON p.permission_id=rp.permission_id
WHERE rp.status=1 AND p.status=1;
WITH missing AS (
    SELECT * FROM @matrix EXCEPT SELECT * FROM @actual_grants
), extra AS (
    SELECT * FROM @actual_grants EXCEPT SELECT * FROM @matrix
)
SELECT 'MISSING_GRANT' AS issue, role_code,permission_code,data_scope FROM missing
UNION ALL SELECT 'EXTRA_GRANT',role_code,permission_code,data_scope FROM extra
ORDER BY issue,role_code,permission_code;
WITH missing AS (
    SELECT permission_code FROM @permission_codes EXCEPT SELECT permission_code FROM dbo.SysPermission WHERE status=1
), extra AS (
    SELECT permission_code FROM dbo.SysPermission WHERE status=1 EXCEPT SELECT permission_code FROM @permission_codes
)
SELECT 'MISSING_PERMISSION' AS issue,permission_code FROM missing
UNION ALL SELECT 'EXTRA_PERMISSION',permission_code FROM extra ORDER BY issue,permission_code;

-- Literal manifest covers all 20 orders. Join by the same stable columns used by the seed.
DECLARE @manifest TABLE(station_id VARCHAR(20),user_id VARCHAR(20),gun_id VARCHAR(20),created_at DATETIME2(3),
    PRIMARY KEY(station_id,user_id,gun_id,created_at));
INSERT INTO @manifest
SELECT 'BLK_ST_'+n.suffix,'BLK_USER_'+n.suffix,'BLK_GUN_'+n.suffix,'2026-10-05T09:59:59.123'
FROM (VALUES ('01'),('02'),('03'),('04'),('05'),('06'),('07'),('08'),('09'),('10'),
             ('11'),('12'),('13'),('14'),('15'),('16'),('17'),('18'),('19'),('20')) n(suffix);
DECLARE @special TABLE(
    station_id VARCHAR(20),user_id VARCHAR(20),gun_id VARCHAR(20),created_at DATETIME2(3),
    order_id BIGINT NULL, source_order_id BIGINT NULL, is_settleable BIT NULL, eligibility_reason VARCHAR(80) NULL,
    settlement_details BIGINT, enterprise_details BIGINT
);
INSERT INTO @special
SELECT m.station_id,m.user_id,m.gun_id,m.created_at,o.order_id,v.order_id,v.is_settleable,v.eligibility_reason,
       (SELECT COUNT_BIG(*) FROM dbo.SettlementDetail d WHERE d.order_id=o.order_id),
       (SELECT COUNT_BIG(*) FROM dbo.EnterpriseSettlementDetail d WHERE d.order_id=o.order_id)
FROM @manifest m
LEFT JOIN dbo.ChargingOrder o ON o.opening_station_id=m.station_id AND o.user_id=m.user_id
    AND o.gun_id=m.gun_id AND o.created_at=m.created_at
LEFT JOIN dbo.v_OrderSettlementSource v ON v.order_id=o.order_id;
SELECT station_id,user_id,gun_id,CONVERT(VARCHAR(33),created_at,126) AS created_at,order_id,
       source_order_id,is_settleable,eligibility_reason,settlement_details,enterprise_details
FROM @special ORDER BY station_id;

-- Same station scope, states and business keys as install_all.sql.
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
IF @statement_count <> 25 OR @details <> 28 OR @carryovers <> 20
   OR @differences <> 20 OR @invoices <> 20 OR @review_cases <> 20
    THROW 50165, N'联调结果未满足数量要求，请查看各项实际计数', 1;

IF EXISTS (
    SELECT 1 FROM @expected e FULL JOIN @counts c ON c.table_name=e.table_name
    WHERE e.table_name IS NULL OR c.table_name IS NULL OR (e.target_rows IS NOT NULL AND c.actual_rows<>e.target_rows)
           OR (e.minimum_rows IS NOT NULL AND c.actual_rows<e.minimum_rows)
) OR EXISTS (
    SELECT id FROM (VALUES ('R01'),('R02'),('R03'),('R04'),('R05')) r(id)
    EXCEPT SELECT role_code FROM dbo.SysRole
) OR EXISTS (
    SELECT id FROM (VALUES (1),(2),(3)) r(id)
    EXCEPT SELECT alarm_level FROM dbo.AlarmLevelPolicy
) OR EXISTS (
    SELECT id,name,sort FROM (VALUES ('L01',N'普通',1),('L02',N'银卡',2),('L03',N'金卡',3)) l(id,name,sort)
    EXCEPT SELECT member_level_id,level_name,level_sort FROM dbo.MemberLevel WHERE status='ACTIVE'
) OR NOT EXISTS (
    SELECT 1 FROM dbo.DeviceCommunicationConfig WHERE config_id=1 AND heartbeat_interval_seconds=60 AND offline_threshold_seconds=180
) OR EXISTS (
    SELECT code FROM (VALUES ('AL001'),('AL002'),('AL003'),('AL004'),('AL005'),('AL006'),('AL007')) a(code)
    EXCEPT SELECT alarm_code FROM dbo.AlarmCodeDict WHERE status='ACTIVE'
) OR EXISTS (
    SELECT * FROM @matrix EXCEPT SELECT * FROM @actual_grants
) OR EXISTS (
    SELECT * FROM @actual_grants EXCEPT SELECT * FROM @matrix
) OR EXISTS (
    SELECT permission_code FROM @permission_codes EXCEPT SELECT permission_code FROM dbo.SysPermission WHERE status=1
) OR EXISTS (
    SELECT permission_code FROM dbo.SysPermission WHERE status=1 EXCEPT SELECT permission_code FROM @permission_codes
) OR EXISTS (
    SELECT 1 FROM dbo.RolePermission rp JOIN dbo.SysPermission p ON p.permission_id=rp.permission_id
    WHERE p.permission_code='SENSITIVE_EXPORT'
) OR (SELECT COUNT(*) FROM @special)<>20 OR EXISTS (
    SELECT 1 FROM @special WHERE order_id IS NULL OR source_order_id IS NULL OR ISNULL(is_settleable,1)<>0
        OR eligibility_reason IS NULL OR eligibility_reason<>'ENTERPRISE_RECEIPT_MISMATCH'
        OR settlement_details<>0 OR enterprise_details<>1
) OR EXISTS (
    SELECT o.order_id FROM dbo.ChargingOrder o WHERE o.opening_station_id LIKE 'BLK[_]ST[_]%'
    EXCEPT SELECT order_id FROM @special
)
    THROW 52621, N'Integration counts, dictionary, permission matrix or special order check failed.', 1;

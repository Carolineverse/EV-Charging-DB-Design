SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. 固定角色 R01-R05
    DECLARE @RoleSeed TABLE (role_id TINYINT, role_code VARCHAR(30), role_name NVARCHAR(50), subject_type VARCHAR(20), role_desc NVARCHAR(500));
    INSERT INTO @RoleSeed VALUES
        (1, 'R01', N'平台运营管理员', 'STAFF', N'按授权管理平台资产、角色配置、运营协调和结算审批。'),
        (2, 'R02', N'场站运维工程师', 'STAFF', N'仅在有效负责场站范围内查看运维数据并办理本人当前工单。'),
        (3, 'R03', N'客服与结算专员', 'STAFF', N'按本人有效分派办理订单异常、退款、发票、结算及相关服务事项。'),
        (4, 'R04', N'车主用户', 'PERSONAL', N'办理本人车辆、订单、支付、优惠、反馈和个人发票业务。'),
        (5, 'R05', N'企业客户', 'ENTERPRISE', N'仅办理和查看本企业业务。');

    IF EXISTS (SELECT 1 FROM @RoleSeed s JOIN dbo.SysRole r ON r.role_id=s.role_id WHERE r.role_code<>s.role_code)
        THROW 51001, N'SysRole.role_id 与固定角色编码冲突，请先检查数据库。', 1;
    IF EXISTS (SELECT 1 FROM @RoleSeed s JOIN dbo.SysRole r ON r.role_code=s.role_code WHERE r.role_id<>s.role_id)
        THROW 51002, N'SysRole.role_code 已绑定到其他编号，请先检查数据库。', 1;
    UPDATE r SET role_name=s.role_name, subject_type=s.subject_type, role_desc=s.role_desc, status=1, updated_at=SYSDATETIME()
    FROM dbo.SysRole r JOIN @RoleSeed s ON s.role_id=r.role_id;
    INSERT INTO dbo.SysRole(role_id,role_code,role_name,subject_type,role_desc)
    SELECT s.role_id,s.role_code,s.role_name,s.subject_type,s.role_desc FROM @RoleSeed s
    WHERE NOT EXISTS (SELECT 1 FROM dbo.SysRole r WHERE r.role_id=s.role_id);

    -- 2. 完整权限字典；同一权限码只存一行。
    DECLARE @PermissionSeed TABLE (permission_code VARCHAR(80), permission_name NVARCHAR(100), module_code VARCHAR(30), action_code VARCHAR(30), description NVARCHAR(255));
    INSERT INTO @PermissionSeed(permission_code,permission_name,module_code,action_code,description) VALUES
        ('STATION_VIEW', N'查看场站', 'A1', 'VIEW', N'查看场站'),
        ('STATION_MANAGE', N'维护场站档案', 'A1', 'MANAGE', N'维护场站档案'),
        ('DEVICE_VIEW', N'查看设备', 'A1', 'VIEW', N'查看设备'),
        ('DEVICE_MANAGE', N'维护设备档案', 'A1', 'MANAGE', N'维护设备档案'),
        ('OPERATOR_MANAGE', N'维护运营商档案', 'A1', 'MANAGE', N'维护运营商档案'),
        ('TARIFF_MANAGE', N'配置计费规则', 'B', 'MANAGE', N'配置计费规则'),
        ('PROMOTION_REVIEW', N'审核活动方案', 'A2', 'REVIEW', N'审核活动方案'),
        ('PRICE_ADJUST_APPROVE', N'审核价格调整', 'B', 'ADJUST_APPROVE', N'审核价格调整'),
        ('KPI_VIEW', N'查看运营指标', 'R', 'VIEW', N'查看运营指标'),
        ('SETTLEMENT_VIEW', N'查看结算数据/结算单', 'D', 'VIEW', N'查看结算数据/结算单'),
        ('SETTLEMENT_ADJUST_APPROVE', N'审批结算调整', 'D', 'ADJUST_APPROVE', N'审批结算调整'),
        ('ALARM_VIEW', N'查看设备告警', 'C', 'VIEW', N'查看设备告警'),
        ('ALARM_HANDLE', N'处理设备告警', 'C', 'HANDLE', N'处理设备告警'),
        ('WORKORDER_VIEW', N'查看维修工单', 'C', 'VIEW', N'查看维修工单'),
        ('WORKORDER_ACCEPT', N'接收维修工单', 'C', 'ACCEPT', N'接收维修工单'),
        ('WORKORDER_UPDATE', N'更新维修工单', 'C', 'UPDATE', N'仅限本人当前负责工单；历史本人任务只读。'),
        ('INSPECTION_RECORD', N'填写巡检记录', 'C', 'RECORD', N'填写巡检记录'),
        ('PARTS_REPLACEMENT_RECORD', N'记录备件更换', 'C', 'REPLACEMENT_RECORD', N'记录备件更换'),
        ('DEVICE_CHANGE_APPLY', N'提交设备变更申请', 'A1', 'CHANGE_APPLY', N'提交设备变更申请'),
        ('DEVICE_ACCEPTANCE', N'配合设备验收', 'A1', 'ACCEPTANCE', N'配合设备验收'),
        ('ORDER_VIEW', N'查看充电订单', 'B', 'VIEW', N'查看充电订单'),
        ('CHARGING_EXCEPTION_HANDLE', N'处理充电异常', 'B', 'EXCEPTION_HANDLE', N'处理充电异常'),
        ('REFUND_HANDLE', N'处理退款', 'B', 'HANDLE', N'处理退款'),
        ('INVOICE_APPEAL_HANDLE', N'处理发票申诉', 'A2', 'APPEAL_HANDLE', N'处理发票申诉'),
        ('RECONCILIATION_HANDLE', N'处理对账差异', 'D', 'HANDLE', N'处理对账差异'),
        ('OPERATOR_CONFIRM_FOLLOW', N'跟进运营商确认', 'D', 'CONFIRM_FOLLOW', N'跟进运营商确认'),
        ('INVOICE_ISSUE', N'办理开票', 'D', 'ISSUE', N'办理开票'),
        ('INVOICE_RED_FLUSH', N'办理红冲', 'D', 'RED_FLUSH', N'办理红冲'),
        ('CUSTOMER_PROFILE_MANAGE', N'维护客户服务档案', 'R', 'PROFILE_MANAGE', N'维护客户服务档案'),
        ('CHARGING_START', N'启动充电', 'B', 'START', N'启动充电'),
        ('CHARGING_PROGRESS_VIEW', N'查看充电进度', 'B', 'PROGRESS_VIEW', N'查看充电进度'),
        ('PAYMENT_EXECUTE', N'支付充电费用', 'B', 'EXECUTE', N'支付充电费用'),
        ('BALANCE_VIEW', N'查看个人账户余额', 'A2', 'VIEW', N'查看个人账户余额'),
        ('FAULT_REPORT', N'提交设备故障反馈', 'C', 'REPORT', N'提交设备故障反馈'),
        ('SERVICE_REVIEW', N'评价服务', 'A2', 'REVIEW', N'评价服务'),
        ('INVOICE_APPLY', N'申请个人发票', 'A2', 'APPLY', N'申请个人发票'),
        ('ENTERPRISE_CARD_MANAGE', N'管理企业卡', 'A2', 'CARD_MANAGE', N'管理企业卡'),
        ('VEHICLE_BIND', N'绑定企业车辆', 'A2', 'BIND', N'绑定企业车辆'),
        ('DRIVER_MANAGE', N'管理车队成员/用车人', 'A2', 'DRIVER_MANAGE', N'管理车队成员/用车人'),
        ('QUOTA_MANAGE', N'管理用车额度', 'A2', 'QUOTA_MANAGE', N'管理用车额度'),
        ('FLEET_ORDER_VIEW', N'查看车队充电明细', 'A2', 'ORDER_VIEW', N'查看车队充电明细'),
        ('MONTHLY_BILL_VIEW', N'查看企业月结账单', 'A2', 'BILL_VIEW', N'查看企业月结账单'),
        ('CORPORATE_SETTLEMENT_APPLY', N'申请对公结算', 'A2', 'SETTLEMENT_APPLY', N'申请对公结算'),
        ('ENTERPRISE_PRICE_APPLY', N'申请企业专属价格', 'A2', 'PRICE_APPLY', N'申请企业专属价格'),
        ('MONITORING_VIEW', N'查看设备监测数据', 'C', 'VIEW', N'查看设备监测数据'),
        ('WORKORDER_URGE', N'催办维修工单', 'C', 'URGE', N'催办维修工单'),
        ('WORKORDER_REASSIGN', N'转派维修工单', 'C', 'REASSIGN', N'转派维修工单'),
        ('STAFF_STATION_MANAGE', N'维护员工场站分配', 'C', 'MANAGE', N'维护员工场站分配'),
        ('DUTY_MANAGE', N'维护工程师值班安排', 'C', 'MANAGE', N'维护工程师值班安排'),
        ('ASSIGNMENT_MANAGE', N'管理业务事项分派', 'C', 'MANAGE', N'管理业务事项分派'),
        ('DEVICE_CHANGE_REVIEW', N'审批设备变更', 'A1', 'CHANGE_REVIEW', N'审批设备变更'),
        ('ROLE_GRANT', N'配置角色权限', 'R', 'GRANT', N'配置角色权限'),
        ('SETTLEMENT_CONFIRM', N'审批结算终审', 'D', 'CONFIRM', N'终审由 R01 执行；审批人与经办人分离。'),
        ('INVOICE_RED_APPROVE', N'审批发票红冲', 'D', 'RED_APPROVE', N'红冲由 R01 审批；审批人与申请人分离。'),
        ('SENSITIVE_EXPORT', N'导出敏感数据', 'R', 'EXPORT', N'按需单独授权；本种子不默认分配给任何角色。'),
        ('ALARM_CREATE_MANUAL', N'人工创建告警', 'C', 'CREATE_MANUAL', N'人工创建告警'),
        ('FEEDBACK_HANDLE', N'处理用户反馈', 'C', 'HANDLE', N'处理用户反馈'),
        ('PROMOTION_CREATE', N'创建营销活动', 'A2', 'CREATE', N'创建营销活动'),
        ('PROMOTION_ISSUE', N'发放优惠券', 'A2', 'ISSUE', N'发放优惠券'),
        ('SETTLEMENT_GENERATE', N'生成运营商结算单', 'D', 'GENERATE', N'须有 R01 对场站编号|YYYYMM 的有效事项分派；R03 按获派范围生成。'),
        ('ENTERPRISE_BILL_HANDLE', N'办理企业月结账单', 'A2', 'BILL_HANDLE', N'办理企业月结账单'),
        ('PERSONAL_INVOICE_HANDLE', N'办理个人发票', 'R', 'PERSONAL_INVOICE_HANDLE', N'办理个人发票'),
        ('FEEDBACK_VIEW', N'查看本人反馈', 'C', 'VIEW', N'查看本人反馈'),
        ('COMPLAINT_SUBMIT', N'提交投诉', 'C', 'SUBMIT', N'提交投诉'),
        ('VEHICLE_MANAGE_SELF', N'管理本人车辆', 'A2', 'MANAGE_SELF', N'管理本人车辆'),
        ('CHARGING_STOP', N'停止本人充电', 'B', 'STOP', N'停止本人充电'),
        ('WALLET_RECHARGE', N'充值本人钱包', 'A2', 'RECHARGE', N'充值本人钱包'),
        ('NOTIFICATION_VIEW', N'查看本人通知', 'R', 'VIEW', N'仅查看接收 account_id 为当前账号的通知。'),
        ('ENTERPRISE_BILL_CONFIRM', N'确认本企业月结账单', 'A2', 'BILL_CONFIRM', N'确认本企业月结账单'),
        ('ENTERPRISE_PAYMENT_SUBMIT', N'提交本企业付款凭据', 'A2', 'PAYMENT_SUBMIT', N'提交本企业付款凭据');
    UPDATE p SET permission_name=s.permission_name,module_code=s.module_code,action_code=s.action_code,description=s.description,status=1,updated_at=SYSDATETIME()
    FROM dbo.SysPermission p JOIN @PermissionSeed s ON s.permission_code=p.permission_code;
    INSERT INTO dbo.SysPermission(permission_code,permission_name,module_code,action_code,description)
    SELECT s.permission_code,s.permission_name,s.module_code,s.action_code,s.description FROM @PermissionSeed s
    WHERE NOT EXISTS (SELECT 1 FROM dbo.SysPermission p WHERE p.permission_code=s.permission_code);

    -- 3. 正式角色授权：文档矩阵共 85 项；SENSITIVE_EXPORT 按需单独授权，默认写入84项。
    DECLARE @GrantSeed TABLE (role_code VARCHAR(30), permission_code VARCHAR(80), data_scope VARCHAR(20), PRIMARY KEY(role_code,permission_code));
    INSERT INTO @GrantSeed(role_code,permission_code,data_scope) VALUES
        ('R01', 'STATION_VIEW', 'ALL'),
        ('R01', 'STATION_MANAGE', 'ALL'),
        ('R01', 'DEVICE_VIEW', 'ALL'),
        ('R01', 'DEVICE_MANAGE', 'ALL'),
        ('R01', 'OPERATOR_MANAGE', 'ALL'),
        ('R01', 'TARIFF_MANAGE', 'ALL'),
        ('R01', 'PROMOTION_REVIEW', 'ALL'),
        ('R01', 'PRICE_ADJUST_APPROVE', 'ALL'),
        ('R01', 'KPI_VIEW', 'ALL'),
        ('R01', 'SETTLEMENT_VIEW', 'ALL'),
        ('R01', 'SETTLEMENT_ADJUST_APPROVE', 'ALL'),
        ('R02', 'DEVICE_VIEW', 'ASSIGNED'),
        ('R02', 'ALARM_VIEW', 'ASSIGNED'),
        ('R02', 'ALARM_HANDLE', 'ASSIGNED'),
        ('R02', 'WORKORDER_VIEW', 'ASSIGNED'),
        ('R02', 'WORKORDER_ACCEPT', 'ASSIGNED'),
        ('R02', 'WORKORDER_UPDATE', 'ASSIGNED'),
        ('R02', 'INSPECTION_RECORD', 'ASSIGNED'),
        ('R02', 'PARTS_REPLACEMENT_RECORD', 'ASSIGNED'),
        ('R02', 'DEVICE_CHANGE_APPLY', 'ASSIGNED'),
        ('R02', 'DEVICE_ACCEPTANCE', 'ASSIGNED'),
        ('R03', 'ORDER_VIEW', 'ASSIGNED'),
        ('R03', 'CHARGING_EXCEPTION_HANDLE', 'ASSIGNED'),
        ('R03', 'REFUND_HANDLE', 'ASSIGNED'),
        ('R03', 'INVOICE_APPEAL_HANDLE', 'ASSIGNED'),
        ('R03', 'SETTLEMENT_VIEW', 'ASSIGNED'),
        ('R03', 'RECONCILIATION_HANDLE', 'ASSIGNED'),
        ('R03', 'OPERATOR_CONFIRM_FOLLOW', 'ASSIGNED'),
        ('R03', 'INVOICE_ISSUE', 'ASSIGNED'),
        ('R03', 'INVOICE_RED_FLUSH', 'ASSIGNED'),
        ('R03', 'CUSTOMER_PROFILE_MANAGE', 'ASSIGNED'),
        ('R04', 'STATION_VIEW', 'PUBLIC'),
        ('R04', 'CHARGING_START', 'SELF'),
        ('R04', 'CHARGING_PROGRESS_VIEW', 'SELF'),
        ('R04', 'ORDER_VIEW', 'SELF'),
        ('R04', 'PAYMENT_EXECUTE', 'SELF'),
        ('R04', 'BALANCE_VIEW', 'SELF'),
        ('R04', 'FAULT_REPORT', 'SELF'),
        ('R04', 'SERVICE_REVIEW', 'SELF'),
        ('R04', 'INVOICE_APPLY', 'SELF'),
        ('R05', 'STATION_VIEW', 'PUBLIC'),
        ('R05', 'ENTERPRISE_CARD_MANAGE', 'ENTERPRISE'),
        ('R05', 'VEHICLE_BIND', 'ENTERPRISE'),
        ('R05', 'DRIVER_MANAGE', 'ENTERPRISE'),
        ('R05', 'QUOTA_MANAGE', 'ENTERPRISE'),
        ('R05', 'FLEET_ORDER_VIEW', 'ENTERPRISE'),
        ('R05', 'MONTHLY_BILL_VIEW', 'ENTERPRISE'),
        ('R05', 'CORPORATE_SETTLEMENT_APPLY', 'ENTERPRISE'),
        ('R05', 'ENTERPRISE_PRICE_APPLY', 'ENTERPRISE'),
        ('R01', 'MONITORING_VIEW', 'ALL'),
        ('R01', 'ALARM_VIEW', 'ALL'),
        ('R01', 'WORKORDER_VIEW', 'ALL'),
        ('R01', 'WORKORDER_URGE', 'ALL'),
        ('R01', 'WORKORDER_REASSIGN', 'ALL'),
        ('R01', 'STAFF_STATION_MANAGE', 'ALL'),
        ('R01', 'DUTY_MANAGE', 'ALL'),
        ('R01', 'ASSIGNMENT_MANAGE', 'ALL'),
        ('R01', 'DEVICE_CHANGE_REVIEW', 'ALL'),
        ('R01', 'ROLE_GRANT', 'ALL'),
        ('R01', 'SETTLEMENT_CONFIRM', 'ALL'),
        ('R01', 'INVOICE_RED_APPROVE', 'ALL'),
        ('R02', 'MONITORING_VIEW', 'ASSIGNED'),
        ('R03', 'DEVICE_VIEW', 'ASSIGNED'),
        ('R03', 'ALARM_VIEW', 'ASSIGNED'),
        ('R03', 'WORKORDER_VIEW', 'ASSIGNED'),
        ('R03', 'ALARM_CREATE_MANUAL', 'ASSIGNED'),
        ('R03', 'FEEDBACK_HANDLE', 'ASSIGNED'),
        ('R03', 'PROMOTION_CREATE', 'ASSIGNED'),
        ('R03', 'PROMOTION_ISSUE', 'ASSIGNED'),
        ('R03', 'SETTLEMENT_GENERATE', 'ASSIGNED'),
        ('R03', 'ENTERPRISE_BILL_HANDLE', 'ASSIGNED'),
        ('R03', 'PERSONAL_INVOICE_HANDLE', 'ASSIGNED'),
        ('R04', 'FEEDBACK_VIEW', 'SELF'),
        ('R04', 'COMPLAINT_SUBMIT', 'SELF'),
        ('R04', 'VEHICLE_MANAGE_SELF', 'SELF'),
        ('R04', 'CHARGING_STOP', 'SELF'),
        ('R04', 'WALLET_RECHARGE', 'SELF'),
        ('R01', 'NOTIFICATION_VIEW', 'SELF'),
        ('R02', 'NOTIFICATION_VIEW', 'SELF'),
        ('R03', 'NOTIFICATION_VIEW', 'SELF'),
        ('R04', 'NOTIFICATION_VIEW', 'SELF'),
        ('R05', 'NOTIFICATION_VIEW', 'SELF'),
        ('R05', 'ENTERPRISE_BILL_CONFIRM', 'ENTERPRISE'),
        ('R05', 'ENTERPRISE_PAYMENT_SUBMIT', 'ENTERPRISE');
    -- 旧演示脚本中的临时权限码不属于本版全局字典，保留记录但停用。
    UPDATE dbo.SysPermission SET status=0, updated_at=SYSDATETIME()
    WHERE permission_code IN ('D.SETTLEMENT.GENERATE','D.SETTLEMENT.REVIEW','C.WORKORDER.DISPATCH','R.LOG.WRITE');

    -- 矩阵外既有授权停用，不物理删除；保留按需人工授予的 SENSITIVE_EXPORT.
    UPDATE rp SET status=0, updated_at=SYSDATETIME()
    FROM dbo.RolePermission rp JOIN dbo.SysRole r ON r.role_id=rp.role_id JOIN dbo.SysPermission p ON p.permission_id=rp.permission_id
    WHERE r.role_code IN ('R01','R02','R03','R04','R05')
      AND p.permission_code <> 'SENSITIVE_EXPORT'
      AND NOT EXISTS (SELECT 1 FROM @GrantSeed g WHERE g.role_code=r.role_code AND g.permission_code=p.permission_code);
    UPDATE rp SET data_scope=g.data_scope,status=1,updated_at=SYSDATETIME()
    FROM dbo.RolePermission rp JOIN dbo.SysRole r ON r.role_id=rp.role_id JOIN dbo.SysPermission p ON p.permission_id=rp.permission_id
    JOIN @GrantSeed g ON g.role_code=r.role_code AND g.permission_code=p.permission_code;
    INSERT INTO dbo.RolePermission(role_id,permission_id,data_scope,status)
    SELECT r.role_id,p.permission_id,g.data_scope,1 FROM @GrantSeed g JOIN dbo.SysRole r ON r.role_code=g.role_code JOIN dbo.SysPermission p ON p.permission_code=g.permission_code
    WHERE NOT EXISTS (SELECT 1 FROM dbo.RolePermission rp WHERE rp.role_id=r.role_id AND rp.permission_id=p.permission_id);

    -- 4. 最小员工演示账号，用于 D/R 的外键、审批和日志验证。
    IF EXISTS (SELECT 1 FROM dbo.SysAccount a JOIN dbo.SysRole r ON r.role_id=a.role_id WHERE a.username='demo_admin_r01' AND r.role_code<>'R01')
        THROW 51003, N'demo_admin_r01 已存在但角色不是 R01，请先检查账号。', 1;
    IF EXISTS (SELECT 1 FROM dbo.SysAccount a JOIN dbo.SysRole r ON r.role_id=a.role_id WHERE a.username='demo_settlement_r03' AND r.role_code<>'R03')
        THROW 51004, N'demo_settlement_r03 已存在但角色不是 R03，请先检查账号。', 1;
    IF EXISTS (SELECT 1 FROM dbo.SysAccount a JOIN dbo.SysRole r ON r.role_id=a.role_id WHERE a.username='demo_engineer_r02' AND r.role_code<>'R02')
        THROW 51005, N'demo_engineer_r02 已存在但角色不是 R02，请先检查账号。', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE username='demo_admin_r01')
        INSERT INTO dbo.SysAccount(username,password_hash,role_id) SELECT 'demo_admin_r01','REPLACE_WITH_REAL_PASSWORD_HASH',role_id FROM dbo.SysRole WHERE role_code='R01';
    IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE username='demo_settlement_r03')
        INSERT INTO dbo.SysAccount(username,password_hash,role_id) SELECT 'demo_settlement_r03','REPLACE_WITH_REAL_PASSWORD_HASH',role_id FROM dbo.SysRole WHERE role_code='R03';
    IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE username='demo_engineer_r02')
        INSERT INTO dbo.SysAccount(username,password_hash,role_id) SELECT 'demo_engineer_r02','REPLACE_WITH_REAL_PASSWORD_HASH',role_id FROM dbo.SysRole WHERE role_code='R02';
    IF NOT EXISTS (SELECT 1 FROM dbo.StaffProfile WHERE staff_id='STF-DEMO-R01')
        INSERT INTO dbo.StaffProfile(staff_id,account_id,employee_no,staff_name,gender,birth_date,department_name,employment_status)
        SELECT 'STF-DEMO-R01',a.account_id,'DEMO-R01',N'演示平台管理员','UNKNOWN','1990-01-01',N'平台运营部','ACTIVE' FROM dbo.SysAccount a WHERE a.username='demo_admin_r01';
    IF NOT EXISTS (SELECT 1 FROM dbo.StaffProfile WHERE staff_id='STF-DEMO-R03')
        INSERT INTO dbo.StaffProfile(staff_id,account_id,employee_no,staff_name,gender,birth_date,department_name,employment_status)
        SELECT 'STF-DEMO-R03',a.account_id,'DEMO-R03',N'演示结算专员','UNKNOWN','1995-01-01',N'客服结算部','ACTIVE' FROM dbo.SysAccount a WHERE a.username='demo_settlement_r03';
    IF NOT EXISTS (SELECT 1 FROM dbo.StaffProfile WHERE staff_id='STF-DEMO-R02')
        INSERT INTO dbo.StaffProfile(staff_id,account_id,employee_no,staff_name,gender,birth_date,department_name,employment_status)
        SELECT 'STF-DEMO-R02',a.account_id,'DEMO-R02',N'演示运维工程师','UNKNOWN','1992-01-01',N'场站运维部','ACTIVE' FROM dbo.SysAccount a WHERE a.username='demo_engineer_r02';

    -- 补充 3 名 R02 运维工程师与 2 名 R03 结算专员（D 员工种子，供 c_base 场站分配/值班/工单引用）
    IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE username='demo_engineer_r02_1')
        INSERT INTO dbo.SysAccount(username,password_hash,role_id) SELECT 'demo_engineer_r02_1','REPLACE_WITH_REAL_PASSWORD_HASH',role_id FROM dbo.SysRole WHERE role_code='R02';
    IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE username='demo_engineer_r02_2')
        INSERT INTO dbo.SysAccount(username,password_hash,role_id) SELECT 'demo_engineer_r02_2','REPLACE_WITH_REAL_PASSWORD_HASH',role_id FROM dbo.SysRole WHERE role_code='R02';
    IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE username='demo_engineer_r02_3')
        INSERT INTO dbo.SysAccount(username,password_hash,role_id) SELECT 'demo_engineer_r02_3','REPLACE_WITH_REAL_PASSWORD_HASH',role_id FROM dbo.SysRole WHERE role_code='R02';
    IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE username='demo_settlement_r03_1')
        INSERT INTO dbo.SysAccount(username,password_hash,role_id) SELECT 'demo_settlement_r03_1','REPLACE_WITH_REAL_PASSWORD_HASH',role_id FROM dbo.SysRole WHERE role_code='R03';
    IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE username='demo_settlement_r03_2')
        INSERT INTO dbo.SysAccount(username,password_hash,role_id) SELECT 'demo_settlement_r03_2','REPLACE_WITH_REAL_PASSWORD_HASH',role_id FROM dbo.SysRole WHERE role_code='R03';

    IF NOT EXISTS (SELECT 1 FROM dbo.StaffProfile WHERE staff_id='STF-DEMO-R02A')
        INSERT INTO dbo.StaffProfile(staff_id,account_id,employee_no,staff_name,gender,birth_date,department_name,employment_status)
        SELECT 'STF-DEMO-R02A',a.account_id,'DEMO-R02A',N'运维工程师A','MALE','1992-01-01',N'场站运维部','ACTIVE' FROM dbo.SysAccount a WHERE a.username='demo_engineer_r02_1';
    IF NOT EXISTS (SELECT 1 FROM dbo.StaffProfile WHERE staff_id='STF-DEMO-R02B')
        INSERT INTO dbo.StaffProfile(staff_id,account_id,employee_no,staff_name,gender,birth_date,department_name,employment_status)
        SELECT 'STF-DEMO-R02B',a.account_id,'DEMO-R02B',N'运维工程师B','MALE','1992-01-01',N'场站运维部','ACTIVE' FROM dbo.SysAccount a WHERE a.username='demo_engineer_r02_2';
    IF NOT EXISTS (SELECT 1 FROM dbo.StaffProfile WHERE staff_id='STF-DEMO-R02C')
        INSERT INTO dbo.StaffProfile(staff_id,account_id,employee_no,staff_name,gender,birth_date,department_name,employment_status)
        SELECT 'STF-DEMO-R02C',a.account_id,'DEMO-R02C',N'运维工程师C','MALE','1992-01-01',N'场站运维部','ACTIVE' FROM dbo.SysAccount a WHERE a.username='demo_engineer_r02_3';
    IF NOT EXISTS (SELECT 1 FROM dbo.StaffProfile WHERE staff_id='STF-DEMO-R03A')
        INSERT INTO dbo.StaffProfile(staff_id,account_id,employee_no,staff_name,gender,birth_date,department_name,employment_status)
        SELECT 'STF-DEMO-R03A',a.account_id,'DEMO-R03A',N'结算专员A','FEMALE','1995-01-01',N'客服结算部','ACTIVE' FROM dbo.SysAccount a WHERE a.username='demo_settlement_r03_1';
    IF NOT EXISTS (SELECT 1 FROM dbo.StaffProfile WHERE staff_id='STF-DEMO-R03B')
        INSERT INTO dbo.StaffProfile(staff_id,account_id,employee_no,staff_name,gender,birth_date,department_name,employment_status)
        SELECT 'STF-DEMO-R03B',a.account_id,'DEMO-R03B',N'结算专员B','FEMALE','1995-01-01',N'客服结算部','ACTIVE' FROM dbo.SysAccount a WHERE a.username='demo_settlement_r03_2';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- 5. 执行后核对
SELECT r.role_code,r.role_name,p.permission_code,p.permission_name,rp.data_scope FROM dbo.RolePermission rp JOIN dbo.SysRole r ON r.role_id=rp.role_id JOIN dbo.SysPermission p ON p.permission_id=rp.permission_id WHERE rp.status=1 AND p.status=1 ORDER BY r.role_id,p.permission_code;

SELECT r.role_code,COUNT(*) AS active_permission_count FROM dbo.SysRole r JOIN dbo.RolePermission rp ON rp.role_id=r.role_id AND rp.status=1 JOIN dbo.SysPermission p ON p.permission_id=rp.permission_id AND p.status=1 GROUP BY r.role_code ORDER BY r.role_code;

SELECT permission_code,permission_name FROM dbo.SysPermission WHERE permission_code='SENSITIVE_EXPORT'; -- 字典中存在，但无默认授权
GO

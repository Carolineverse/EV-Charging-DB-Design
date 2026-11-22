-- ---------- 1. DeviceMonitoringData（分区表）----------
CREATE TABLE dbo.DeviceMonitoringData (
    monitoring_id             BIGINT IDENTITY(1,1) NOT NULL,
    report_id                 VARCHAR(50)   NULL,
    pile_id                   VARCHAR(20)   NOT NULL,
    gun_id                    VARCHAR(20)   NULL,
    collected_at              DATETIME2(3)  NOT NULL,
    output_voltage            DECIMAL(10,2) NULL,
    output_current            DECIMAL(10,2) NULL,
    power                     DECIMAL(10,2) NULL,
    module_temperature        DECIMAL(6,2)  NULL,
    offline_duration_seconds  INT           NULL,
    raw_fault_code            VARCHAR(50)   NULL,
    created_at                DATETIME2(3)  NOT NULL CONSTRAINT DF_DeviceMonitoringData_created DEFAULT SYSDATETIME(),
    partition_key AS ((YEAR(collected_at) * 100 + MONTH(collected_at)) * 10
        + CONVERT(int, CONVERT(tinyint, SUBSTRING(HASHBYTES('SHA2_256', CONVERT(varbinary(20), pile_id)), 1, 1))) % 4) PERSISTED,
    CONSTRAINT CK_DeviceMonitoringData_voltage CHECK (output_voltage IS NULL OR output_voltage >= 0),
    CONSTRAINT CK_DeviceMonitoringData_current CHECK (output_current IS NULL OR output_current >= 0),
    CONSTRAINT CK_DeviceMonitoringData_power   CHECK (power IS NULL OR power >= 0),
    CONSTRAINT CK_DeviceMonitoringData_offline CHECK (offline_duration_seconds IS NULL OR offline_duration_seconds >= 0)
);
GO
-- 非聚集主键（放 PRIMARY，未对齐的全局唯一索引）
ALTER TABLE dbo.DeviceMonitoringData
    ADD CONSTRAINT PK_DeviceMonitoringData PRIMARY KEY NONCLUSTERED (monitoring_id) ON [PRIMARY];
GO
-- 唯一聚集索引（与分区对齐）
CREATE UNIQUE CLUSTERED INDEX CX_DeviceMonitoringData_01
    ON dbo.DeviceMonitoringData (partition_key, monitoring_id)
    ON PS_DeviceMonitoringData (partition_key);
GO
CREATE INDEX IX_DeviceMonitoringData_02 ON dbo.DeviceMonitoringData (pile_id, collected_at DESC) ON PS_DeviceMonitoringData (partition_key);
CREATE INDEX IX_DeviceMonitoringData_03 ON dbo.DeviceMonitoringData (report_id) ON PS_DeviceMonitoringData (partition_key);
GO

-- ---------- 2. AlarmLevelPolicy ----------
CREATE TABLE dbo.AlarmLevelPolicy (
    alarm_level               TINYINT      NOT NULL,
    level_name                NVARCHAR(20) NOT NULL,
    accept_timeout_minutes    INT          NOT NULL,
    accept_urge_grace_minutes INT          NOT NULL,
    arrival_timeout_minutes   INT          NOT NULL,
    created_at                DATETIME2(3) NOT NULL CONSTRAINT DF_AlarmLevelPolicy_created DEFAULT SYSDATETIME(),
    updated_at                DATETIME2(3) NOT NULL CONSTRAINT DF_AlarmLevelPolicy_updated DEFAULT SYSDATETIME(),
    CONSTRAINT PK_AlarmLevelPolicy PRIMARY KEY (alarm_level),
    CONSTRAINT UQ_AlarmLevelPolicy_01 UNIQUE (level_name),
    CONSTRAINT CK_AlarmLevelPolicy_level CHECK (alarm_level IN (1,2,3)),
    CONSTRAINT CK_AlarmLevelPolicy_accept CHECK (accept_timeout_minutes > 0),
    CONSTRAINT CK_AlarmLevelPolicy_grace CHECK (accept_urge_grace_minutes > 0),
    CONSTRAINT CK_AlarmLevelPolicy_arrival CHECK (arrival_timeout_minutes > 0)
);

-- ---------- 3. AlarmCodeDict ----------
CREATE TABLE dbo.AlarmCodeDict (
    alarm_code                VARCHAR(20)  NOT NULL,
    alarm_name                NVARCHAR(50) NOT NULL,
    target_type               VARCHAR(10)  NOT NULL,
    default_level             TINYINT      NOT NULL,
    description               NVARCHAR(200) NULL,
    status                    VARCHAR(20)  NOT NULL CONSTRAINT DF_AlarmCodeDict_status DEFAULT 'ACTIVE',
    created_at                DATETIME2(3) NOT NULL CONSTRAINT DF_AlarmCodeDict_created DEFAULT SYSDATETIME(),
    updated_at                DATETIME2(3) NOT NULL CONSTRAINT DF_AlarmCodeDict_updated DEFAULT SYSDATETIME(),
    blocks_new_order          BIT          NOT NULL,
    normal_observation_count  INT          NULL,
    recovery_rule_description NVARCHAR(1000) NOT NULL,
    CONSTRAINT PK_AlarmCodeDict PRIMARY KEY (alarm_code),
    CONSTRAINT CK_AlarmCodeDict_target CHECK (target_type IN ('PILE','GUN','BOTH')),
    CONSTRAINT CK_AlarmCodeDict_status CHECK (status IN ('ACTIVE','DISABLED')),
    CONSTRAINT CK_AlarmCodeDict_obs CHECK (normal_observation_count IS NULL OR normal_observation_count > 0)
);

-- ---------- 4. Alarm ----------
CREATE TABLE dbo.Alarm (
    alarm_id           BIGINT IDENTITY(1,1) NOT NULL,
    pile_id            VARCHAR(20)  NOT NULL,
    gun_id             VARCHAR(20)  NULL,
    alarm_code         VARCHAR(20)  NOT NULL,
    alarm_level        TINYINT      NOT NULL,
    alarm_description  NVARCHAR(500) NOT NULL,
    alarm_source       VARCHAR(20)  NOT NULL,
    occurred_at        DATETIME2(3) NOT NULL,
    recovered_at       DATETIME2(3) NULL,
    status             VARCHAR(20)  NOT NULL,
    created_at         DATETIME2(3) NOT NULL CONSTRAINT DF_Alarm_created DEFAULT SYSDATETIME(),
    updated_at         DATETIME2(3) NOT NULL CONSTRAINT DF_Alarm_updated DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Alarm PRIMARY KEY (alarm_id),
    CONSTRAINT CK_Alarm_source CHECK (alarm_source IN ('DEVICE_REPORT','PLATFORM_RULE','MANUAL_ENTRY')),
    CONSTRAINT CK_Alarm_status CHECK (status IN ('PENDING_VERIFY','PENDING','PROCESSING','PENDING_REVIEW','RECOVERED','CLOSED_UNCONFIRMED'))
);

-- ---------- 5. WorkOrder ----------
CREATE TABLE dbo.WorkOrder (
    work_order_id              BIGINT IDENTITY(1,1) NOT NULL,
    alarm_id                   BIGINT       NOT NULL,
    dispatcher_staff_id        VARCHAR(20)  NULL,
    engineer_staff_id          VARCHAR(20)  NOT NULL,
    assigned_at                DATETIME2(3) NOT NULL,
    accepted_at                DATETIME2(3) NULL,
    accept_urged_at            DATETIME2(3) NULL,
    arrival_at                 DATETIME2(3) NULL,
    arrival_urged_at           DATETIME2(3) NULL,
    arrival_urge_deadline      DATETIME2(3) NULL,
    repaired_at                DATETIME2(3) NULL,
    parts_replaced             NVARCHAR(300) NULL,
    result                     NVARCHAR(1000) NULL,
    status                     VARCHAR(20)  NOT NULL CONSTRAINT DF_WorkOrder_status DEFAULT 'PENDING_ACCEPT',
    created_at                 DATETIME2(3) NOT NULL CONSTRAINT DF_WorkOrder_created DEFAULT SYSDATETIME(),
    updated_at                 DATETIME2(3) NOT NULL CONSTRAINT DF_WorkOrder_updated DEFAULT SYSDATETIME(),
    accept_deadline            DATETIME2(3) NOT NULL,
    accept_urge_deadline       DATETIME2(3) NULL,
    arrival_deadline           DATETIME2(3) NULL,
    accept_timeout_processed_at DATETIME2(3) NULL,
    CONSTRAINT PK_WorkOrder PRIMARY KEY (work_order_id),
    CONSTRAINT CK_WorkOrder_status CHECK (status IN ('PENDING_ACCEPT','PENDING_ARRIVAL','PROCESSING','PENDING_REVIEW','COMPLETED','TERMINATED')),
    CONSTRAINT CK_WorkOrder_deadline CHECK (accept_deadline > assigned_at)
);

-- ---------- 6. StaffStationAssignment ----------
CREATE TABLE dbo.StaffStationAssignment (
    assignment_id  BIGINT IDENTITY(1,1) NOT NULL,
    staff_id       VARCHAR(20)  NOT NULL,
    station_id     VARCHAR(20)  NOT NULL,
    effective_from DATETIME2(3) NOT NULL,
    effective_to   DATETIME2(3) NULL,
    created_at     DATETIME2(3) NOT NULL CONSTRAINT DF_StaffStationAssignment_created DEFAULT SYSDATETIME(),
    CONSTRAINT PK_StaffStationAssignment PRIMARY KEY (assignment_id)
);

-- ---------- 7. EngineerDutySchedule ----------
CREATE TABLE dbo.EngineerDutySchedule (
    duty_id          BIGINT IDENTITY(1,1) NOT NULL,
    staff_id         VARCHAR(20) NOT NULL,
    duty_start       DATETIME2(3) NOT NULL,
    duty_end         DATETIME2(3) NOT NULL,
    duty_status      VARCHAR(20) NOT NULL CONSTRAINT DF_EngineerDutySchedule_status DEFAULT 'ACTIVE',
    accepting_status VARCHAR(20) NOT NULL,
    created_at       DATETIME2(3) NOT NULL CONSTRAINT DF_EngineerDutySchedule_created DEFAULT SYSDATETIME(),
    updated_at       DATETIME2(3) NOT NULL CONSTRAINT DF_EngineerDutySchedule_updated DEFAULT SYSDATETIME(),
    CONSTRAINT PK_EngineerDutySchedule PRIMARY KEY (duty_id),
    CONSTRAINT CK_EngineerDutySchedule_status CHECK (duty_status IN ('ACTIVE','CANCELLED')),
    CONSTRAINT CK_EngineerDutySchedule_accept CHECK (accepting_status IN ('ACCEPTING','UNAVAILABLE')),
    CONSTRAINT CK_EngineerDutySchedule_end CHECK (duty_end > duty_start)
);

-- ---------- 8. DeviceReport ----------
CREATE TABLE dbo.DeviceReport (
    report_id         VARCHAR(50)  NOT NULL,
    pile_id           VARCHAR(20)  NOT NULL,
    generated_at      DATETIME2(3) NOT NULL,
    received_at       DATETIME2(3) NOT NULL,
    payload_hash      CHAR(64)     NOT NULL,
    processing_status VARCHAR(20)  NOT NULL CONSTRAINT DF_DeviceReport_status DEFAULT 'RECEIVED',
    processed_at      DATETIME2(3) NULL,
    created_at        DATETIME2(3) NOT NULL CONSTRAINT DF_DeviceReport_created DEFAULT SYSDATETIME(),
    report_type       VARCHAR(20)  NOT NULL,
    CONSTRAINT PK_DeviceReport PRIMARY KEY (report_id),
    CONSTRAINT CK_DeviceReport_status CHECK (processing_status IN ('RECEIVED','PROCESSED','FAILED')),
    CONSTRAINT CK_DeviceReport_type CHECK (report_type IN ('MINUTE_MONITOR','CHARGING_START','CHARGING_END'))
);

-- ---------- 9. NotificationLog ----------
CREATE TABLE dbo.NotificationLog (
    notification_id     BIGINT IDENTITY(1,1) NOT NULL,
    business_type       VARCHAR(30)  NOT NULL,
    business_id         BIGINT       NOT NULL,
    recipient_account_id BIGINT      NOT NULL,
    event_code          VARCHAR(50)  NOT NULL,
    content             NVARCHAR(1000) NOT NULL,
    delivery_status     VARCHAR(20)  NOT NULL CONSTRAINT DF_NotificationLog_status DEFAULT 'PENDING',
    sent_at             DATETIME2(3) NULL,
    handled_at          DATETIME2(3) NULL,
    created_at          DATETIME2(3) NOT NULL CONSTRAINT DF_NotificationLog_created DEFAULT SYSDATETIME(),
    CONSTRAINT PK_NotificationLog PRIMARY KEY (notification_id),
    CONSTRAINT CK_NotificationLog_btype CHECK (business_type IN ('ALARM','WORKORDER')),
    CONSTRAINT CK_NotificationLog_status CHECK (delivery_status IN ('PENDING','SENT','FAILED'))
);

-- ---------- 10. CustomerFeedback ----------
CREATE TABLE dbo.CustomerFeedback (
    feedback_id       BIGINT IDENTITY(1,1) NOT NULL,
    user_id           VARCHAR(20)  NOT NULL,
    feedback_type     VARCHAR(30)  NOT NULL,
    station_id        VARCHAR(20)  NULL,
    pile_id           VARCHAR(20)  NULL,
    gun_id            VARCHAR(20)  NULL,
    order_id          BIGINT       NULL,
    rating            TINYINT      NULL,
    content           NVARCHAR(1000) NOT NULL,
    status            VARCHAR(20)  NOT NULL CONSTRAINT DF_CustomerFeedback_status DEFAULT 'SUBMITTED',
    assigned_staff_id VARCHAR(20)  NULL,
    reply_content     NVARCHAR(1000) NULL,
    replied_at        DATETIME2(3) NULL,
    created_at        DATETIME2(3) NOT NULL CONSTRAINT DF_CustomerFeedback_created DEFAULT SYSDATETIME(),
    closed_at         DATETIME2(3) NULL,
    CONSTRAINT PK_CustomerFeedback PRIMARY KEY (feedback_id),
    CONSTRAINT CK_CustomerFeedback_type CHECK (feedback_type IN ('FAULT_REPORT','COMPLAINT','REVIEW')),
    CONSTRAINT CK_CustomerFeedback_rating CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
    CONSTRAINT CK_CustomerFeedback_status CHECK (status IN ('SUBMITTED','ASSIGNED','PROCESSING','CLOSED')),
    CONSTRAINT CK_Feedback_CloseTime CHECK (status = 'CLOSED' OR closed_at IS NULL),
    CONSTRAINT CK_Feedback_ReplyPair CHECK ((reply_content IS NULL AND replied_at IS NULL) OR (reply_content IS NOT NULL AND replied_at IS NOT NULL))
);

-- ---------- 11. FeedbackAlarm ----------
CREATE TABLE dbo.FeedbackAlarm (
    feedback_id BIGINT NOT NULL,
    alarm_id    BIGINT NOT NULL,
    created_at  DATETIME2(3) NOT NULL CONSTRAINT DF_FeedbackAlarm_created DEFAULT SYSDATETIME(),
    CONSTRAINT PK_FeedbackAlarm PRIMARY KEY (feedback_id, alarm_id)
);

-- ---------- 12. DeviceFaultCodeMapping ----------
CREATE TABLE dbo.DeviceFaultCodeMapping (
    device_model   NVARCHAR(50) NOT NULL,
    raw_fault_code VARCHAR(50)  NOT NULL,
    alarm_code     VARCHAR(20)  NOT NULL,
    CONSTRAINT PK_DeviceFaultCodeMapping PRIMARY KEY (device_model, raw_fault_code)
);
GO

-- =============================================================

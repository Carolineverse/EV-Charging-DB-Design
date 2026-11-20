-- =====================================================
-- A1 场站与充电设施模块
-- 负责：B 线
-- 依据：最终版数据库物理结构设计
-- 第一张表：dbo.Operator
-- =====================================================

-- 请在 SSMS 中选择正确的目标数据库后执行。
-- 建议顺序：先建表，再添加外键和索引。

CREATE TABLE dbo.Operator
(
    operator_id VARCHAR(20) NOT NULL,
    operator_name NVARCHAR(100) NOT NULL,

    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_Operator_status DEFAULT ('ACTIVE'),

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_Operator_created_at DEFAULT (SYSDATETIME()),

    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_Operator_updated_at DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_Operator
        PRIMARY KEY CLUSTERED (operator_id),

    CONSTRAINT CK_Operator_status
        CHECK (status IN ('ACTIVE', 'INACTIVE'))
);

GO
-- =====================================================
-- A1 第二张表：dbo.ChargingStation
-- =====================================================

CREATE TABLE dbo.ChargingStation
(
    station_id VARCHAR(20) NOT NULL,
    station_name NVARCHAR(100) NOT NULL,
    address NVARCHAR(255) NOT NULL,

    longitude DECIMAL(10,6) NOT NULL,
    latitude DECIMAL(9,6) NOT NULL,

    operator_id VARCHAR(20) NOT NULL,
    total_spaces INT NOT NULL,

    business_hours NVARCHAR(100) NOT NULL,
    parking_fee_standard NVARCHAR(200) NOT NULL,

    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_ChargingStation_status
        DEFAULT ('OPERATING'),

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_ChargingStation_created_at
        DEFAULT (SYSDATETIME()),

    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_ChargingStation_updated_at
        DEFAULT (SYSDATETIME()),

    workorder_notice_account_id BIGINT NOT NULL,

    CONSTRAINT PK_ChargingStation
        PRIMARY KEY CLUSTERED (station_id),

    CONSTRAINT CK_ChargingStation_longitude
        CHECK (longitude BETWEEN -180 AND 180),

    CONSTRAINT CK_ChargingStation_latitude
        CHECK (latitude BETWEEN -90 AND 90),

    CONSTRAINT CK_ChargingStation_total_spaces
        CHECK (total_spaces >= 0),

    CONSTRAINT CK_ChargingStation_status
        CHECK (status IN ('OPERATING', 'SUSPENDED', 'CLOSED'))
);
GO

-- =====================================================
-- A1 第三张表：dbo.ChargingPile
-- =====================================================

CREATE TABLE dbo.ChargingPile
(
    pile_id VARCHAR(20) NOT NULL,
    station_id VARCHAR(20) NOT NULL,
    device_model NVARCHAR(50) NOT NULL,
    rated_power_kw DECIMAL(8,2) NOT NULL,
    communication_protocol NVARCHAR(50) NOT NULL,
    commissioned_date DATE NOT NULL,
    warranty_end_date DATE NOT NULL,

    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_ChargingPile_status
        DEFAULT ('UNKNOWN'),

    reported_status VARCHAR(20) NULL,
    last_heartbeat_at DATETIME2(3) NULL,

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_ChargingPile_created_at
        DEFAULT (SYSDATETIME()),

    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_ChargingPile_updated_at
        DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_ChargingPile
        PRIMARY KEY CLUSTERED (pile_id),

    CONSTRAINT CK_ChargingPile_power
        CHECK (rated_power_kw > 0),

    CONSTRAINT CK_ChargingPile_warranty
        CHECK (warranty_end_date >= commissioned_date),

    CONSTRAINT CK_ChargingPile_status
        CHECK (status IN (
            'UNKNOWN', 'IDLE', 'OCCUPIED', 'FAULT', 'OFFLINE'
        )),

    CONSTRAINT CK_ChargingPile_reported_status
        CHECK (
            reported_status IS NULL
            OR reported_status IN ('IDLE', 'OCCUPIED', 'FAULT')
        )
);
GO

-- =====================================================
-- A1 第四张表：dbo.ChargingGun
-- =====================================================

CREATE TABLE dbo.ChargingGun
(
    gun_id VARCHAR(20) NOT NULL,
    pile_id VARCHAR(20) NOT NULL,
    gun_sequence INT NOT NULL,
    gun_type VARCHAR(20) NOT NULL,
    interface_standard NVARCHAR(30) NOT NULL,
    max_output_power_kw DECIMAL(8,2) NOT NULL,

    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_ChargingGun_status
        DEFAULT ('UNKNOWN'),

    reported_status VARCHAR(20) NULL,
    last_reported_at DATETIME2(3) NULL,

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_ChargingGun_created_at
        DEFAULT (SYSDATETIME()),

    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_ChargingGun_updated_at
        DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_ChargingGun
        PRIMARY KEY CLUSTERED (gun_id),

    CONSTRAINT UQ_ChargingGun_01
        UNIQUE NONCLUSTERED (pile_id, gun_sequence),

    CONSTRAINT CK_ChargingGun_power_sequence
        CHECK (
            gun_sequence > 0
            AND max_output_power_kw > 0
        ),

    CONSTRAINT CK_ChargingGun_type
        CHECK (gun_type IN ('DC_FAST', 'AC_SLOW')),

    CONSTRAINT CK_ChargingGun_status
        CHECK (
            status IN (
                'UNKNOWN', 'IDLE', 'OCCUPIED', 'FAULT', 'OFFLINE'
            )
        ),

    CONSTRAINT CK_ChargingGun_reported_status
        CHECK (
            reported_status IS NULL
            OR reported_status IN ('IDLE', 'OCCUPIED', 'FAULT')
        )
);
GO

-- =====================================================
-- A1 第五张表：dbo.DeviceStatusHistory
-- =====================================================

CREATE TABLE dbo.DeviceStatusHistory
(
    history_id BIGINT IDENTITY(1,1) NOT NULL,
    pile_id VARCHAR(20) NULL,
    gun_id VARCHAR(20) NULL,

    old_status VARCHAR(20) NULL,
    new_status VARCHAR(20) NOT NULL,
    changed_at DATETIME2(3) NOT NULL,
    change_reason NVARCHAR(200) NOT NULL,
    change_source VARCHAR(30) NOT NULL,

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_DeviceStatusHistory_created_at
        DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_DeviceStatusHistory
        PRIMARY KEY CLUSTERED (history_id),

    CONSTRAINT CK_DeviceStatusHistory_target
        CHECK (
            (pile_id IS NOT NULL AND gun_id IS NULL)
            OR
            (pile_id IS NULL AND gun_id IS NOT NULL)
        ),

    CONSTRAINT CK_DeviceStatusHistory_old_status
        CHECK (
            old_status IS NULL
            OR old_status IN (
                'UNKNOWN', 'IDLE', 'OCCUPIED', 'FAULT', 'OFFLINE'
            )
        ),

    CONSTRAINT CK_DeviceStatusHistory_new_status
        CHECK (
            new_status IN (
                'UNKNOWN', 'IDLE', 'OCCUPIED', 'FAULT', 'OFFLINE'
            )
        ),

    CONSTRAINT CK_DeviceStatusHistory_status_change
        CHECK (
            old_status IS NULL
            OR old_status <> new_status
        ),

    CONSTRAINT CK_DeviceStatusHistory_change_source
        CHECK (
            change_source IN (
                'DEVICE_REPORT',
                'HEARTBEAT_CHECK',
                'DEVICE_MONITOR',
                'CHARGING_ORDER',
                'REPAIR_REVIEW',
                'MANUAL',
                'SYSTEM_RULE'
            )
        )
);
GO

-- =====================================================
-- A1 第六张表：dbo.DeviceCommunicationConfig
-- =====================================================

CREATE TABLE dbo.DeviceCommunicationConfig
(
    config_id TINYINT NOT NULL,

    heartbeat_interval_seconds INT NOT NULL
        CONSTRAINT DF_DeviceCommunicationConfig_heartbeat
        DEFAULT (60),

    offline_threshold_seconds INT NOT NULL
        CONSTRAINT DF_DeviceCommunicationConfig_offline
        DEFAULT (180),

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_DeviceCommunicationConfig_created_at
        DEFAULT (SYSDATETIME()),

    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_DeviceCommunicationConfig_updated_at
        DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_DeviceCommunicationConfig
        PRIMARY KEY CLUSTERED (config_id),

    CONSTRAINT CK_DeviceCommunicationConfig_id
        CHECK (config_id = 1),

    CONSTRAINT CK_DeviceCommunicationConfig_heartbeat
        CHECK (heartbeat_interval_seconds > 0),

    CONSTRAINT CK_DeviceCommunicationConfig_offline
        CHECK (
            offline_threshold_seconds > heartbeat_interval_seconds
        )
);
GO

-- =====================================================
-- A1 第七张表：dbo.DeviceAssetCase
-- =====================================================

CREATE TABLE dbo.DeviceAssetCase
(
    asset_case_id BIGINT IDENTITY(1,1) NOT NULL,
    pile_id VARCHAR(20) NOT NULL,
    gun_id VARCHAR(20) NULL,

    case_type VARCHAR(20) NOT NULL,
    submitted_by BIGINT NOT NULL,
    submitted_at DATETIME2(3) NOT NULL,
    details NVARCHAR(1000) NOT NULL,

    status VARCHAR(20) NOT NULL,

    reviewed_by BIGINT NULL,
    reviewed_at DATETIME2(3) NULL,
    decision NVARCHAR(500) NULL,

    CONSTRAINT PK_DeviceAssetCase
        PRIMARY KEY CLUSTERED (asset_case_id),

    CONSTRAINT CK_DeviceAssetCase_case_type
        CHECK (
            case_type IN (
                'ACCEPTANCE',
                'INSPECTION',
                'UPGRADE',
                'MIGRATE',
                'RETIRE'
            )
        ),

    CONSTRAINT CK_DeviceAssetCase_status
        CHECK (
            status IN (
                'SUBMITTED',
                'APPROVED',
                'REJECTED',
                'COMPLETED'
            )
        )
);
GO
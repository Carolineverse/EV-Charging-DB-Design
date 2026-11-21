-- =====================================================
-- B 模块：充电订单与计费
-- 负责：B 线
-- 依据：最终版全组数据库物理结构设计（采样规则同步版）
--
-- 执行前：在 SSMS 中选择目标数据库并确认 SELECT DB_NAME()
-- 执行顺序：建表 -> 外键与索引 -> 测试
-- =====================================================

-- =====================================================
-- B 第 1 张表：dbo.BillingRuleVersion
-- 计费规则版本表
-- =====================================================

CREATE TABLE dbo.BillingRuleVersion
(
    rule_version_id BIGINT NOT NULL,

    station_id VARCHAR(20) NOT NULL,

    enterprise_id VARCHAR(20) NULL,

    free_minutes INT NOT NULL
        CONSTRAINT DF_BillingRuleVersion_free_minutes
        DEFAULT (0),

    minimum_amount DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_BillingRuleVersion_minimum_amount
        DEFAULT (0),

    effective_from DATETIME2(3) NOT NULL,

    effective_to DATETIME2(3) NULL,

    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_BillingRuleVersion_status
        DEFAULT ('ACTIVE'),

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_BillingRuleVersion_created_at
        DEFAULT (SYSDATETIME()),

    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_BillingRuleVersion_updated_at
        DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_BillingRuleVersion
        PRIMARY KEY CLUSTERED (rule_version_id),

    CONSTRAINT CK_BillingRuleVersion_free_minutes
        CHECK (free_minutes >= 0),

    CONSTRAINT CK_BillingRuleVersion_minimum_amount
        CHECK (minimum_amount >= 0),

    CONSTRAINT CK_BillingRuleVersion_effective_time
        CHECK (
            effective_to IS NULL
            OR effective_to > effective_from
        ),

    CONSTRAINT CK_BillingRuleVersion_status
        CHECK (status IN ('ACTIVE', 'INACTIVE'))
);
GO

-- =====================================================
-- B 第 2 张表：dbo.BillingRule
-- 分时计费规则表
-- =====================================================

CREATE TABLE dbo.BillingRule
(
    billing_rule_id BIGINT IDENTITY(1,1) NOT NULL,

    rule_version_id BIGINT NOT NULL,

    period_type NCHAR(1) NOT NULL,

    period_start_time TIME(0) NOT NULL,

    period_end_time TIME(0) NOT NULL,

    electricity_price DECIMAL(10,4) NOT NULL
        CONSTRAINT DF_BillingRule_electricity_price
        DEFAULT (0),

    service_price DECIMAL(10,4) NOT NULL
        CONSTRAINT DF_BillingRule_service_price
        DEFAULT (0),

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_BillingRule_created_at
        DEFAULT (SYSDATETIME()),

    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_BillingRule_updated_at
        DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_BillingRule
        PRIMARY KEY CLUSTERED (billing_rule_id),

    CONSTRAINT CK_BillingRule_electricity_price
        CHECK (electricity_price >= 0),

    CONSTRAINT CK_BillingRule_service_price
        CHECK (service_price >= 0),

    CONSTRAINT CK_BillingRule_period_time
        CHECK (period_start_time <> period_end_time),

    CONSTRAINT CK_BillingRule_period_type
        CHECK (period_type IN (N'峰', N'平', N'谷')),

    CONSTRAINT UQ_BillingRule_01
        UNIQUE NONCLUSTERED
        (rule_version_id, period_start_time)
);
GO

-- =====================================================
-- B 第 3 张表：dbo.ChargingOrder
-- 充电订单表
-- =====================================================

CREATE TABLE dbo.ChargingOrder
(
    order_id BIGINT IDENTITY(1,1) NOT NULL,

    order_type VARCHAR(20) NOT NULL
        CONSTRAINT DF_ChargingOrder_order_type
        DEFAULT ('PERSONAL'),

    user_id VARCHAR(20) NOT NULL,

    gun_id VARCHAR(20) NOT NULL,

    binding_id BIGINT NULL,

    enterprise_quota_id VARCHAR(20) NULL,

    start_time DATETIME2(3) NULL,

    end_time DATETIME2(3) NULL,

    energy_kwh DECIMAL(10,3) NOT NULL
        CONSTRAINT DF_ChargingOrder_energy_kwh
        DEFAULT (0),

    start_soc DECIMAL(5,2) NULL,

    end_soc DECIMAL(5,2) NULL,

    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_ChargingOrder_status
        DEFAULT ('CREATED'),

    gross_amount DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_ChargingOrder_gross_amount
        DEFAULT (0),

    minimum_adjustment DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_ChargingOrder_minimum_adjustment
        DEFAULT (0),

    discount_amount DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_ChargingOrder_discount_amount
        DEFAULT (0),

    paid_amount DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_ChargingOrder_paid_amount
        DEFAULT (0),

    refund_amount DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_ChargingOrder_refund_amount
        DEFAULT (0),

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_ChargingOrder_created_at
        DEFAULT (SYSDATETIME()),

    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_ChargingOrder_updated_at
        DEFAULT (SYSDATETIME()),

    opening_station_id VARCHAR(20) NOT NULL,

    settled_at DATETIME2(3) NULL,

    startup_rule_version_id BIGINT NULL,

    priced_at DATETIME2(3) NULL,

    device_released_at DATETIME2(3) NULL,

    -- 主键
    CONSTRAINT PK_ChargingOrder
        PRIMARY KEY CLUSTERED (order_id),

    -- 订单类型
    CONSTRAINT CK_ChargingOrder_order_type
        CHECK (order_type IN ('PERSONAL', 'ENTERPRISE')),

    -- 订单状态
    CONSTRAINT CK_ChargingOrder_status
        CHECK (
            status IN (
                'CREATED',
                'CHARGING',
                'PENDING_PAYMENT',
                'PAID',
                'CANCELLED',
                'ABNORMAL'
            )
        ),

    -- 个人单不能绑定企业卡和额度
    -- 企业单必须同时提供绑定及额度
    CONSTRAINT CK_ChargingOrder_enterprise_fields
        CHECK (
            (
                order_type = 'PERSONAL'
                AND binding_id IS NULL
                AND enterprise_quota_id IS NULL
            )
            OR
            (
                order_type = 'ENTERPRISE'
                AND binding_id IS NOT NULL
                AND enterprise_quota_id IS NOT NULL
            )
        ),

    -- 实际充电起止时间
    CONSTRAINT CK_ChargingOrder_time
        CHECK (
            start_time IS NULL
            OR end_time IS NULL
            OR end_time >= start_time
        ),

    -- SOC 百分比
    CONSTRAINT CK_ChargingOrder_start_soc
        CHECK (start_soc IS NULL OR start_soc BETWEEN 0 AND 100),

    CONSTRAINT CK_ChargingOrder_end_soc
        CHECK (end_soc IS NULL OR end_soc BETWEEN 0 AND 100),

    -- 电量不得为负
    CONSTRAINT CK_ChargingOrder_energy
        CHECK (energy_kwh >= 0),

    -- 金额不得为负
    CONSTRAINT CK_ChargingOrder_amounts
        CHECK (
            gross_amount >= 0
            AND minimum_adjustment >= 0
            AND discount_amount >= 0
            AND paid_amount >= 0
            AND refund_amount >= 0
        ),

    -- 优惠金额不得超过优惠前金额
    CONSTRAINT CK_ChargingOrder_discount
        CHECK (discount_amount <= gross_amount),

    -- 已退款金额不得超过已付金额
    CONSTRAINT CK_ChargingOrder_refund
        CHECK (refund_amount <= paid_amount),

    -- 已结清订单必须有首次结清时间
    CONSTRAINT CK_ChargingOrder_paid_settled
        CHECK (
            status <> 'PAID'
            OR settled_at IS NOT NULL
        )
);
GO

-- =====================================================
-- B 第 4 张表：dbo.OrderFeeDetail
-- 订单费用明细表
-- =====================================================

CREATE TABLE dbo.OrderFeeDetail
(
    order_fee_detail_id BIGINT IDENTITY(1,1) NOT NULL,

    order_id BIGINT NOT NULL,

    billing_rule_id BIGINT NOT NULL,

    segment_start DATETIME2(3) NOT NULL,

    segment_end DATETIME2(3) NOT NULL,

    segment_energy_kwh DECIMAL(10,3) NOT NULL
        CONSTRAINT DF_OrderFeeDetail_segment_energy_kwh
        DEFAULT (0),

    free_service_fee DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_OrderFeeDetail_free_service_fee
        DEFAULT (0),

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_OrderFeeDetail_created_at
        DEFAULT (SYSDATETIME()),

    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_OrderFeeDetail_updated_at
        DEFAULT (SYSDATETIME()),

    -- 主键
    CONSTRAINT PK_OrderFeeDetail
        PRIMARY KEY CLUSTERED (order_fee_detail_id),

    -- 分段结束时间必须晚于开始时间
    CONSTRAINT CK_OrderFeeDetail_segment_time
        CHECK (segment_end > segment_start),

    -- 分段电量不得为负
    CONSTRAINT CK_OrderFeeDetail_segment_energy
        CHECK (segment_energy_kwh >= 0),

    -- 免费服务费折抵额不得为负
    CONSTRAINT CK_OrderFeeDetail_free_service_fee
        CHECK (free_service_fee >= 0),

    -- 同一订单的分段开始时间不得重复
    CONSTRAINT UQ_OrderFeeDetail_01
        UNIQUE NONCLUSTERED (order_id, segment_start)
);
GO

-- =====================================================
-- B 第 5 张表：dbo.PaymentRecord
-- 支付记录表
-- =====================================================

CREATE TABLE dbo.PaymentRecord
(
    payment_id BIGINT IDENTITY(1,1) NOT NULL,

    order_id BIGINT NOT NULL,

    pay_channel VARCHAR(20) NOT NULL,

    transaction_no VARCHAR(64) NOT NULL,

    pay_amount DECIMAL(12,2) NOT NULL,

    pay_time DATETIME2(3) NOT NULL
        CONSTRAINT DF_PaymentRecord_pay_time
        DEFAULT (SYSDATETIME()),

    refund_amount DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_PaymentRecord_refund_amount
        DEFAULT (0),

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_PaymentRecord_created_at
        DEFAULT (SYSDATETIME()),

    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_PaymentRecord_updated_at
        DEFAULT (SYSDATETIME()),

    -- 主键
    CONSTRAINT PK_PaymentRecord
        PRIMARY KEY CLUSTERED (payment_id),

    -- 支付渠道
    CONSTRAINT CK_PaymentRecord_pay_channel
        CHECK (
            pay_channel IN (
                'WECHAT',
                'ALIPAY',
                'BALANCE',
                'OTHER'
            )
        ),

    -- 渠道流水号不能是空字符串或全空格
    CONSTRAINT CK_PaymentRecord_transaction_no
        CHECK (
            LEN(LTRIM(RTRIM(transaction_no))) > 0
        ),

    -- 支付金额必须大于 0
    CONSTRAINT CK_PaymentRecord_pay_amount
        CHECK (pay_amount > 0),

    -- 成功退款累计不能超过支付金额
    CONSTRAINT CK_PaymentRecord_refund_amount
        CHECK (
            refund_amount >= 0
            AND refund_amount <= pay_amount
        ),

    -- 同一渠道的流水号必须唯一
    CONSTRAINT UQ_PaymentRecord_01
        UNIQUE NONCLUSTERED
        (pay_channel, transaction_no)
);
GO

-- =====================================================
-- B 第 6 张表：dbo.RefundRecord
-- 退款记录表
-- =====================================================

CREATE TABLE dbo.RefundRecord
(
    refund_id BIGINT IDENTITY(1,1) NOT NULL,

    payment_id BIGINT NOT NULL,

    refund_no VARCHAR(64) NOT NULL,

    refund_amount DECIMAL(12,2) NOT NULL,

    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_RefundRecord_status
        DEFAULT ('PROCESSING'),

    reason NVARCHAR(255) NULL,

    refunded_at DATETIME2(3) NULL,

    created_by BIGINT NULL,

    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_RefundRecord_created_at
        DEFAULT (SYSDATETIME()),

    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_RefundRecord_updated_at
        DEFAULT (SYSDATETIME()),

    -- 主键
    CONSTRAINT PK_RefundRecord
        PRIMARY KEY CLUSTERED (refund_id),

    -- 退款流水号不得为空字符串或全空格
    CONSTRAINT CK_RefundRecord_refund_no
        CHECK (
            LEN(LTRIM(RTRIM(refund_no))) > 0
        ),

    -- 本次退款金额必须大于 0
    CONSTRAINT CK_RefundRecord_refund_amount
        CHECK (refund_amount > 0),

    -- 退款状态枚举
    CONSTRAINT CK_RefundRecord_status
        CHECK (
            status IN (
                'PROCESSING',
                'SUCCESS',
                'FAILED',
                'CANCELLED'
            )
        ),

    -- 只有成功退款才允许填写成功时间
    CONSTRAINT CK_RefundRecord_refunded_at
        CHECK (
            (
                status = 'SUCCESS'
                AND refunded_at IS NOT NULL
            )
            OR
            (
                status <> 'SUCCESS'
                AND refunded_at IS NULL
            )
        ),

    -- 平台退款业务流水号全表唯一
    CONSTRAINT UQ_RefundRecord_01
        UNIQUE NONCLUSTERED (refund_no)
);
GO

-- =====================================================
-- B 第 7 张表：dbo.ChargingMeterSample
-- 充电计量采样表
-- =====================================================

CREATE TABLE dbo.ChargingMeterSample
(
    sample_id BIGINT IDENTITY(1,1) NOT NULL,

    order_id BIGINT NOT NULL,

    device_session_no VARCHAR(64) NOT NULL,

    report_id VARCHAR(50) NOT NULL,

    collected_at DATETIME2(3) NOT NULL,

    cumulative_kwh DECIMAL(12,3) NULL,

    sample_type VARCHAR(20) NOT NULL,

    validation_status VARCHAR(20) NOT NULL,

    invalid_reason NVARCHAR(200) NULL,

    -- 主键
    CONSTRAINT PK_ChargingMeterSample
        PRIMARY KEY CLUSTERED (sample_id),

    -- 累计电量允许缺测，但不能为负数
    CONSTRAINT CK_ChargingMeterSample_cumulative_kwh
        CHECK (
            cumulative_kwh IS NULL
            OR cumulative_kwh >= 0
        ),

    -- 采样阶段
    CONSTRAINT CK_ChargingMeterSample_sample_type
        CHECK (
            sample_type IN (
                'START',
                'PERIODIC',
                'END'
            )
        ),

    -- 校验状态
    CONSTRAINT CK_ChargingMeterSample_validation_status
        CHECK (
            validation_status IN (
                'VALID',
                'INVALID'
            )
        ),

    -- 有效样本必须有累计读数
    -- 无效样本必须填写非空白原因
    CONSTRAINT CK_ChargingMeterSample_validation
        CHECK (
            (
                validation_status = 'VALID'
                AND cumulative_kwh IS NOT NULL
            )
            OR
            (
                validation_status = 'INVALID'
                AND invalid_reason IS NOT NULL
                AND LEN(LTRIM(RTRIM(invalid_reason))) > 0
            )
        )
);
GO

-- =====================================================
-- B 第 8 张表：dbo.OrderCommand
-- 订单设备命令表
-- =====================================================

CREATE TABLE dbo.OrderCommand
(
    command_id BIGINT IDENTITY(1,1) NOT NULL,

    order_id BIGINT NOT NULL,

    command_type VARCHAR(10) NOT NULL,

    status VARCHAR(20) NOT NULL,

    created_at DATETIME2(3) NOT NULL,

    deadline_at DATETIME2(3) NOT NULL,

    last_attempt_at DATETIME2(3) NULL,

    confirmed_at DATETIME2(3) NULL,

    last_error NVARCHAR(300) NULL,

    processed_event_id VARCHAR(64) NULL,

    result_hash CHAR(64) NULL,

    result_snapshot NVARCHAR(MAX) NULL,

    -- 主键
    CONSTRAINT PK_OrderCommand
        PRIMARY KEY CLUSTERED (command_id),

    -- 命令类型
    CONSTRAINT CK_OrderCommand_command_type
        CHECK (command_type IN ('START', 'STOP')),

    -- 超时复查时间必须晚于登记时间
    CONSTRAINT CK_OrderCommand_deadline
        CHECK (deadline_at > created_at),

    -- 状态与三个最终结果字段必须保持一致
    CONSTRAINT CK_OrderCommand_result_fields
        CHECK (
            (
                status IN ('PENDING', 'SENT')
                AND processed_event_id IS NULL
                AND result_hash IS NULL
                AND result_snapshot IS NULL
            )
            OR
            (
                status IN ('CONFIRMED', 'FAILED')
                AND processed_event_id IS NOT NULL
                AND result_hash IS NOT NULL
                AND result_snapshot IS NOT NULL
            )
        ),

    -- CONFIRMED 必须有设备确认时间
    CONSTRAINT CK_OrderCommand_confirmed_at
        CHECK (
            status <> 'CONFIRMED'
            OR confirmed_at IS NOT NULL
        ),

    -- 结果快照必须是合法 JSON
    CONSTRAINT CK_OrderCommand_result_snapshot
        CHECK (
            result_snapshot IS NULL
            OR ISJSON(result_snapshot) = 1
        ),

    -- SHA-256 摘要必须是 64 位小写十六进制字符串
    CONSTRAINT CK_OrderCommand_result_hash
        CHECK (
            result_hash IS NULL
            OR
            (
                LEN(result_hash) = 64
                AND result_hash COLLATE Latin1_General_100_BIN2
                    NOT LIKE '%[^0-9a-f]%'
            )
        ),

    -- 每个订单的每种命令只能存在一条
    CONSTRAINT UQ_OrderCommand_01
        UNIQUE NONCLUSTERED (order_id, command_type)
);
GO

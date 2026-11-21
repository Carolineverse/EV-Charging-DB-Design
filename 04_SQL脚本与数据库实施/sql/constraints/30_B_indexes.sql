-- =====================================================
-- B 模块索引
-- ChargingMeterSample 采样去重及查询索引
-- =====================================================

SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- BillingRuleVersion：按场站、企业和生效时间定位适用版本
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.BillingRuleVersion')
      AND name = N'IX_BillingRuleVersion_01'
)
    CREATE NONCLUSTERED INDEX IX_BillingRuleVersion_01
    ON dbo.BillingRuleVersion
    (
        station_id,
        enterprise_id,
        effective_from DESC
    );
GO

-- 1. 全采样报文去重
-- 注意：不能添加 WHERE validation_status = 'VALID'
-- INVALID 样本也必须参与去重
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ChargingMeterSample')
      AND name = N'UXN_ChargingMeterSample_01'
)
    CREATE UNIQUE NONCLUSTERED INDEX UXN_ChargingMeterSample_01
    ON dbo.ChargingMeterSample
    (
        report_id,
        order_id,
        sample_type
    );
GO

-- 2. 每个订单最多一条有效 START
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ChargingMeterSample')
      AND name = N'UX_ChargingMeterSample_02'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_ChargingMeterSample_02
    ON dbo.ChargingMeterSample (order_id)
    WHERE sample_type = 'START'
      AND validation_status = 'VALID';
GO

-- 3. 每个订单最多一条有效 END
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ChargingMeterSample')
      AND name = N'UX_ChargingMeterSample_03'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_ChargingMeterSample_03
    ON dbo.ChargingMeterSample (order_id)
    WHERE sample_type = 'END'
      AND validation_status = 'VALID';
GO

-- 4. 按订单及采集时间查询
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ChargingMeterSample')
      AND name = N'IX_ChargingMeterSample_04'
)
    CREATE NONCLUSTERED INDEX IX_ChargingMeterSample_04
    ON dbo.ChargingMeterSample
    (
        order_id,
        collected_at DESC
    );
GO

-- =====================================================
-- OrderCommand 索引
-- =====================================================

-- 1. 已处理事件编号全局唯一
-- NULL 不参与唯一性限制
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.OrderCommand')
      AND name = N'UX_OrderCommand_02'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_OrderCommand_02
    ON dbo.OrderCommand (processed_event_id)
    WHERE processed_event_id IS NOT NULL;
GO

-- 2. 按状态及超时复查时间扫描
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.OrderCommand')
      AND name = N'IX_OrderCommand_03'
)
    CREATE NONCLUSTERED INDEX IX_OrderCommand_03
    ON dbo.OrderCommand (status, deadline_at);
GO

-- =====================================================
-- B 模块：补充普通查询索引
-- ChargingOrder / PaymentRecord / RefundRecord
-- =====================================================

-- ChargingOrder：占枪判定
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ChargingOrder')
      AND name = N'IX_ChargingOrder_01'
)
    CREATE NONCLUSTERED INDEX IX_ChargingOrder_01
    ON dbo.ChargingOrder (gun_id, status);
GO

-- ChargingOrder：查询用户历史订单
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ChargingOrder')
      AND name = N'IX_ChargingOrder_02'
)
    CREATE NONCLUSTERED INDEX IX_ChargingOrder_02
    ON dbo.ChargingOrder (user_id, created_at DESC);
GO

-- ChargingOrder：按场站及结束时间查询
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ChargingOrder')
      AND name = N'IX_ChargingOrder_03'
)
    CREATE NONCLUSTERED INDEX IX_ChargingOrder_03
    ON dbo.ChargingOrder (opening_station_id, end_time);
GO

-- ChargingOrder：企业额度占用核对
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ChargingOrder')
      AND name = N'IX_ChargingOrder_04'
)
    CREATE NONCLUSTERED INDEX IX_ChargingOrder_04
    ON dbo.ChargingOrder (enterprise_quota_id, created_at);
GO

-- PaymentRecord：按订单查询支付记录
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.PaymentRecord')
      AND name = N'IX_PaymentRecord_02'
)
    CREATE NONCLUSTERED INDEX IX_PaymentRecord_02
    ON dbo.PaymentRecord (order_id, pay_time);
GO

-- RefundRecord：按支付记录及退款状态查询
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.RefundRecord')
      AND name = N'IX_RefundRecord_02'
)
    CREATE NONCLUSTERED INDEX IX_RefundRecord_02
    ON dbo.RefundRecord (payment_id, status);
GO

-- A1 场站与设备模块：物理设计要求的普通查询索引
-- 通过 sqlcmd -d 或 SSMS 当前数据库选择目标库；本脚本不切换数据库。
-- 可重复执行。

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ChargingStation') AND name = N'IX_ChargingStation_01')
    CREATE NONCLUSTERED INDEX IX_ChargingStation_01
    ON dbo.ChargingStation (operator_id, status);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ChargingPile') AND name = N'IX_ChargingPile_01')
    CREATE NONCLUSTERED INDEX IX_ChargingPile_01
    ON dbo.ChargingPile (station_id, status);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.ChargingPile') AND name = N'IX_ChargingPile_02')
    CREATE NONCLUSTERED INDEX IX_ChargingPile_02
    ON dbo.ChargingPile (last_heartbeat_at);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DeviceStatusHistory') AND name = N'IX_DeviceStatusHistory_01')
    CREATE NONCLUSTERED INDEX IX_DeviceStatusHistory_01
    ON dbo.DeviceStatusHistory (pile_id, changed_at DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DeviceStatusHistory') AND name = N'IX_DeviceStatusHistory_02')
    CREATE NONCLUSTERED INDEX IX_DeviceStatusHistory_02
    ON dbo.DeviceStatusHistory (gun_id, changed_at DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DeviceAssetCase') AND name = N'IX_DeviceAssetCase_01')
    CREATE NONCLUSTERED INDEX IX_DeviceAssetCase_01
    ON dbo.DeviceAssetCase (pile_id, submitted_at DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.DeviceAssetCase') AND name = N'IX_DeviceAssetCase_02')
    CREATE NONCLUSTERED INDEX IX_DeviceAssetCase_02
    ON dbo.DeviceAssetCase (status, submitted_at);
GO

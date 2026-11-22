-- =====================================================
-- A1 场站与设备模块：内部外键
-- 负责：B 线
-- =====================================================

-- 通过 sqlcmd -d 或 SSMS 当前数据库选择目标库；本脚本不切换数据库。
-- 可重复执行；跨模块 R 外键单独等待正式 R 表就绪。

-- 1. 场站 -> 运营商
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingStation_Operator')
    ALTER TABLE dbo.ChargingStation WITH CHECK
    ADD CONSTRAINT FK_ChargingStation_Operator
    FOREIGN KEY (operator_id)
    REFERENCES dbo.Operator(operator_id);
GO

-- 2. 充电桩 -> 场站
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingPile_ChargingStation')
    ALTER TABLE dbo.ChargingPile WITH CHECK
    ADD CONSTRAINT FK_ChargingPile_ChargingStation
    FOREIGN KEY (station_id)
    REFERENCES dbo.ChargingStation(station_id);
GO

-- 3. 充电枪 -> 充电桩
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingGun_ChargingPile')
    ALTER TABLE dbo.ChargingGun WITH CHECK
    ADD CONSTRAINT FK_ChargingGun_ChargingPile
    FOREIGN KEY (pile_id)
    REFERENCES dbo.ChargingPile(pile_id);
GO

-- 4. 状态历史 -> 充电桩
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DeviceStatusHistory_ChargingPile')
    ALTER TABLE dbo.DeviceStatusHistory WITH CHECK
    ADD CONSTRAINT FK_DeviceStatusHistory_ChargingPile
    FOREIGN KEY (pile_id)
    REFERENCES dbo.ChargingPile(pile_id);
GO

-- 5. 状态历史 -> 充电枪
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DeviceStatusHistory_ChargingGun')
    ALTER TABLE dbo.DeviceStatusHistory WITH CHECK
    ADD CONSTRAINT FK_DeviceStatusHistory_ChargingGun
    FOREIGN KEY (gun_id)
    REFERENCES dbo.ChargingGun(gun_id);
GO

-- 6. 设备资产申请 -> 充电桩
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DeviceAssetCase_ChargingPile')
    ALTER TABLE dbo.DeviceAssetCase WITH CHECK
    ADD CONSTRAINT FK_DeviceAssetCase_ChargingPile
    FOREIGN KEY (pile_id)
    REFERENCES dbo.ChargingPile(pile_id);
GO

-- 7. 设备资产申请 -> 充电枪
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DeviceAssetCase_ChargingGun')
    ALTER TABLE dbo.DeviceAssetCase WITH CHECK
    ADD CONSTRAINT FK_DeviceAssetCase_ChargingGun
    FOREIGN KEY (gun_id)
    REFERENCES dbo.ChargingGun(gun_id);
GO

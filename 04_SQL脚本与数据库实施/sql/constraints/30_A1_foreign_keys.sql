-- =====================================================
-- A1 场站与设备模块：内部外键
-- 负责：B 线
-- =====================================================

-- 请在 SSMS 中选择正确的目标数据库后执行。
-- 建议顺序：先建表，再添加外键和索引。

-- 1. 场站 -> 运营商
ALTER TABLE dbo.ChargingStation WITH CHECK
ADD CONSTRAINT FK_ChargingStation_Operator
FOREIGN KEY (operator_id)
REFERENCES dbo.Operator(operator_id);
GO

-- 2. 充电桩 -> 场站
ALTER TABLE dbo.ChargingPile WITH CHECK
ADD CONSTRAINT FK_ChargingPile_ChargingStation
FOREIGN KEY (station_id)
REFERENCES dbo.ChargingStation(station_id);
GO

-- 3. 充电枪 -> 充电桩
ALTER TABLE dbo.ChargingGun WITH CHECK
ADD CONSTRAINT FK_ChargingGun_ChargingPile
FOREIGN KEY (pile_id)
REFERENCES dbo.ChargingPile(pile_id);
GO

-- 4. 状态历史 -> 充电桩
ALTER TABLE dbo.DeviceStatusHistory WITH CHECK
ADD CONSTRAINT FK_DeviceStatusHistory_ChargingPile
FOREIGN KEY (pile_id)
REFERENCES dbo.ChargingPile(pile_id);
GO

-- 5. 状态历史 -> 充电枪
ALTER TABLE dbo.DeviceStatusHistory WITH CHECK
ADD CONSTRAINT FK_DeviceStatusHistory_ChargingGun
FOREIGN KEY (gun_id)
REFERENCES dbo.ChargingGun(gun_id);
GO

-- 6. 设备资产申请 -> 充电桩
ALTER TABLE dbo.DeviceAssetCase WITH CHECK
ADD CONSTRAINT FK_DeviceAssetCase_ChargingPile
FOREIGN KEY (pile_id)
REFERENCES dbo.ChargingPile(pile_id);
GO

-- 7. 设备资产申请 -> 充电枪
ALTER TABLE dbo.DeviceAssetCase WITH CHECK
ADD CONSTRAINT FK_DeviceAssetCase_ChargingGun
FOREIGN KEY (gun_id)
REFERENCES dbo.ChargingGun(gun_id);
GO
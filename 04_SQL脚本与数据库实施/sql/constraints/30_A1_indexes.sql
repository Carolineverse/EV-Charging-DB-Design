-- =====================================================
-- A1 场站与设备模块：普通查询索引
-- 负责：B 线
-- =====================================================

-- 请在SSMS中选择正确的目标数据库后执行
-- 建议顺序：先建表，再添加外键和索引

-- 1. 按运营商查询场站
CREATE NONCLUSTERED INDEX IX_ChargingStation_operator
ON dbo.ChargingStation(operator_id);
GO

-- 2. 按场站查询充电桩
CREATE NONCLUSTERED INDEX IX_ChargingPile_station
ON dbo.ChargingPile(station_id);
GO


-- 3. 按充电桩查询充电枪
--CREATE NONCLUSTERED INDEX IX_ChargingGun_pile
--ON dbo.ChargingGun(pile_id);
--GO

-- 4. 查询充电桩的状态变化历史
CREATE NONCLUSTERED INDEX IX_DeviceStatusHistory_pile_time
ON dbo.DeviceStatusHistory(pile_id, changed_at DESC);
GO

-- 5. 按充电桩查询资产申请
CREATE NONCLUSTERED INDEX IX_DeviceAssetCase_pile
ON dbo.DeviceAssetCase(pile_id);
GO
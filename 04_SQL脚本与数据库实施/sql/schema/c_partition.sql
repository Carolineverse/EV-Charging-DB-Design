-- ---------- 分区对象（仅 DeviceMonitoringData 用）----------
IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'PF_DeviceMonitoringData')
CREATE PARTITION FUNCTION PF_DeviceMonitoringData (INT) AS RANGE RIGHT FOR VALUES
    (2026110, 2026111, 2026112, 2026113,   -- 2026-11 组 0/1/2/3
     2026120, 2026121, 2026122, 2026123,   -- 2026-12 组 0/1/2/3
     2027010);                              -- 2027-01 组 0（后续月份按需加边界）
GO
IF NOT EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'PS_DeviceMonitoringData')
CREATE PARTITION SCHEME PS_DeviceMonitoringData AS PARTITION PF_DeviceMonitoringData ALL TO ([PRIMARY]);
GO

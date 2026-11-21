-- A1 V01: 场站设备概览。
-- 设备先按场站聚合，再关联，避免枪数导致桩数重复。
CREATE OR ALTER VIEW dbo.v_A1StationDeviceOverview
AS
WITH pile_counts AS
(
    SELECT station_id,
           COUNT(*) AS pile_count,
           SUM(CASE WHEN status = 'UNKNOWN' THEN 1 ELSE 0 END) AS unknown_pile_count,
           SUM(CASE WHEN status = 'IDLE' THEN 1 ELSE 0 END) AS idle_pile_count,
           SUM(CASE WHEN status = 'OCCUPIED' THEN 1 ELSE 0 END) AS occupied_pile_count,
           SUM(CASE WHEN status = 'FAULT' THEN 1 ELSE 0 END) AS fault_pile_count,
           SUM(CASE WHEN status = 'OFFLINE' THEN 1 ELSE 0 END) AS offline_pile_count
    FROM dbo.ChargingPile
    GROUP BY station_id
), gun_counts AS
(
    SELECT p.station_id,
           COUNT(*) AS gun_count,
           SUM(CASE WHEN g.status = 'UNKNOWN' THEN 1 ELSE 0 END) AS unknown_gun_count,
           SUM(CASE WHEN g.status = 'IDLE' THEN 1 ELSE 0 END) AS idle_gun_count,
           SUM(CASE WHEN g.status = 'OCCUPIED' THEN 1 ELSE 0 END) AS occupied_gun_count,
           SUM(CASE WHEN g.status = 'FAULT' THEN 1 ELSE 0 END) AS fault_gun_count,
           SUM(CASE WHEN g.status = 'OFFLINE' THEN 1 ELSE 0 END) AS offline_gun_count
    FROM dbo.ChargingPile AS p
    INNER JOIN dbo.ChargingGun AS g ON g.pile_id = p.pile_id
    GROUP BY p.station_id
)
SELECT op.operator_id,
       op.operator_name,
       s.station_id,
       s.station_name,
       s.status AS station_status,
       COALESCE(pc.pile_count, 0) AS pile_count,
       COALESCE(pc.unknown_pile_count, 0) AS unknown_pile_count,
       COALESCE(pc.idle_pile_count, 0) AS idle_pile_count,
       COALESCE(pc.occupied_pile_count, 0) AS occupied_pile_count,
       COALESCE(pc.fault_pile_count, 0) AS fault_pile_count,
       COALESCE(pc.offline_pile_count, 0) AS offline_pile_count,
       COALESCE(gc.gun_count, 0) AS gun_count,
       COALESCE(gc.unknown_gun_count, 0) AS unknown_gun_count,
       COALESCE(gc.idle_gun_count, 0) AS idle_gun_count,
       COALESCE(gc.occupied_gun_count, 0) AS occupied_gun_count,
       COALESCE(gc.fault_gun_count, 0) AS fault_gun_count,
       COALESCE(gc.offline_gun_count, 0) AS offline_gun_count
FROM dbo.ChargingStation AS s
INNER JOIN dbo.Operator AS op ON op.operator_id = s.operator_id
LEFT JOIN pile_counts AS pc ON pc.station_id = s.station_id
LEFT JOIN gun_counts AS gc ON gc.station_id = s.station_id;
GO

-- A1 V02: 逐桩/枪展示当前状态、最近上报状态和最近通信时间。
-- 当前状态与上报状态分别保留；没有枪的桩仍输出一行。
CREATE OR ALTER VIEW dbo.v_A1GunPileAvailability
AS
SELECT s.station_id,
       s.station_name,
       s.status AS station_status,
       p.pile_id,
       p.status AS pile_status,
       p.reported_status AS pile_reported_status,
       p.last_heartbeat_at,
       g.gun_id,
       g.status AS gun_status,
       g.reported_status AS gun_reported_status,
       g.last_reported_at AS gun_last_reported_at
FROM dbo.ChargingPile AS p
INNER JOIN dbo.ChargingStation AS s ON s.station_id = p.station_id
LEFT JOIN dbo.ChargingGun AS g ON g.pile_id = p.pile_id;
GO

-- A1 V03: 设备资产事项追溯。
-- current_station_id/name 是按当前桩归属派生，不是提交时的历史站场快照。
CREATE OR ALTER VIEW dbo.v_A1AssetCaseTrace
AS
SELECT c.asset_case_id,
       c.pile_id,
       s.station_id AS current_station_id,
       s.station_name AS current_station_name,
       c.gun_id,
       p.status AS current_pile_status,
       g.status AS current_gun_status,
       c.case_type,
       c.submitted_by,
       c.submitted_at,
       c.details,
       c.status AS case_status,
       c.reviewed_by,
       c.reviewed_at,
       c.decision
FROM dbo.DeviceAssetCase AS c
INNER JOIN dbo.ChargingPile AS p ON p.pile_id = c.pile_id
INNER JOIN dbo.ChargingStation AS s ON s.station_id = p.station_id
LEFT JOIN dbo.ChargingGun AS g
    ON g.gun_id = c.gun_id
   AND g.pile_id = c.pile_id;
GO

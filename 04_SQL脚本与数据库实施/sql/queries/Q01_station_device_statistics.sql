-- Q01: 每个场站的桩、枪与当前 IDLE 枪数量。
-- 桩数和枪数先按场站聚合，避免多枪 JOIN 重复计算桩数。
-- idle_gun_count 仅表示 ChargingGun.status='IDLE'；它不推断场站或充电桩状态。

WITH pile_count AS
(
    SELECT station_id, COUNT(*) AS pile_count
    FROM dbo.ChargingPile
    GROUP BY station_id
), gun_count AS
(
    SELECT p.station_id,
           COUNT(*) AS gun_count,
           SUM(CASE WHEN g.status = 'IDLE' THEN 1 ELSE 0 END) AS idle_gun_count
    FROM dbo.ChargingPile AS p
    INNER JOIN dbo.ChargingGun AS g ON g.pile_id = p.pile_id
    GROUP BY p.station_id
)
SELECT op.operator_id,
       op.operator_name,
       s.station_id,
       s.station_name,
       COALESCE(pc.pile_count, 0) AS pile_count,
       COALESCE(gc.gun_count, 0) AS gun_count,
       COALESCE(gc.idle_gun_count, 0) AS idle_gun_count
FROM dbo.ChargingStation AS s
INNER JOIN dbo.Operator AS op ON op.operator_id = s.operator_id
LEFT JOIN pile_count AS pc ON pc.station_id = s.station_id
LEFT JOIN gun_count AS gc ON gc.station_id = s.station_id
ORDER BY op.operator_id, s.station_id;

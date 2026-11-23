-- Run on the 22dcb98 EV_B_TEST installation. Export the first two result sets as headerless CSV.
SET NOCOUNT ON;
SELECT station_id, period_month, settlement_id, status
FROM dbo.SettlementStatement
ORDER BY station_id, period_month;

SELECT s.station_id, s.period_month, o.user_id, o.gun_id,
       CONVERT(VARCHAR(33), o.created_at, 126) AS created_at, o.order_id
FROM dbo.SettlementDetail d
JOIN dbo.SettlementStatement s ON s.settlement_id=d.settlement_id
JOIN dbo.ChargingOrder o ON o.order_id=d.order_id
ORDER BY s.station_id, s.period_month, o.user_id, o.gun_id, o.created_at;

SELECT station_id, period_month, COUNT(*) AS duplicate_count
FROM dbo.SettlementStatement GROUP BY station_id,period_month HAVING COUNT(*) > 1;
SELECT s.station_id,s.period_month,o.user_id,o.gun_id,CONVERT(VARCHAR(33),o.created_at,126) AS created_at,
       COUNT(*) AS duplicate_count
FROM dbo.SettlementDetail d
JOIN dbo.SettlementStatement s ON s.settlement_id=d.settlement_id
JOIN dbo.ChargingOrder o ON o.order_id=d.order_id
GROUP BY s.station_id,s.period_month,o.user_id,o.gun_id,o.created_at HAVING COUNT(*) > 1;

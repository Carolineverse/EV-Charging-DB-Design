-- Run this entire file in one session on the newly installed EV_B_TEST.
SET NOCOUNT ON;
IF DB_NAME() <> N'EV_B_TEST' THROW 52610, N'Choose EV_B_TEST', 1;
DROP TABLE IF EXISTS #current_settlements, #current_details;
DECLARE @baseline_settlements TABLE (
    station_id VARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL, period_month CHAR(6) COLLATE DATABASE_DEFAULT NOT NULL,
    settlement_id BIGINT NOT NULL, status TINYINT NOT NULL
);
DECLARE @baseline_details TABLE (
    station_id VARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL, period_month CHAR(6) COLLATE DATABASE_DEFAULT NOT NULL,
    user_id VARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL, gun_id VARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL,
    created_at VARCHAR(33) COLLATE DATABASE_DEFAULT NOT NULL, order_id BIGINT NOT NULL
);

-- Embedded verbatim from the two headerless CSV exports of 22dcb98.
INSERT INTO @baseline_settlements (station_id, period_month, settlement_id, status) VALUES
    ('B_DEMO_ST01', '202606', 1, 1),
    ('B_DEMO_ST01', '202607', 2, 1),
    ('B_DEMO_ST01', '202608', 3, 1),
    ('B_DEMO_ST01', '202609', 4, 1),
    ('B_DEMO_ST01', '202610', 5, 0),
    ('D_DEMO_ST02', '202606', 6, 1),
    ('D_DEMO_ST02', '202607', 7, 1),
    ('D_DEMO_ST02', '202608', 8, 1),
    ('D_DEMO_ST02', '202609', 9, 1),
    ('D_DEMO_ST02', '202610', 10, 0),
    ('D_DEMO_ST03', '202606', 11, 1),
    ('D_DEMO_ST03', '202607', 12, 1),
    ('D_DEMO_ST03', '202608', 13, 1),
    ('D_DEMO_ST03', '202609', 14, 1),
    ('D_DEMO_ST03', '202610', 15, 0),
    ('D_DEMO_ST04', '202606', 16, 1),
    ('D_DEMO_ST04', '202607', 17, 1),
    ('D_DEMO_ST04', '202608', 18, 1),
    ('D_DEMO_ST04', '202609', 19, 1),
    ('D_DEMO_ST04', '202610', 20, 0),
    ('D_DEMO_ST05', '202606', 21, 1),
    ('D_DEMO_ST05', '202607', 22, 1),
    ('D_DEMO_ST05', '202608', 23, 1),
    ('D_DEMO_ST05', '202609', 24, 1),
    ('D_DEMO_ST05', '202610', 25, 0);

INSERT INTO @baseline_details (station_id, period_month, user_id, gun_id, created_at, order_id) VALUES
    ('B_DEMO_ST01', '202606', 'B_DEMO_USER01', 'B_DEMO_GUN01', '2026-06-10T08:59:59', 5),
    ('B_DEMO_ST01', '202607', 'B_DEMO_USER01', 'B_DEMO_GUN01', '2026-07-10T08:59:59', 6),
    ('B_DEMO_ST01', '202608', 'B_DEMO_USER01', 'B_DEMO_GUN01', '2026-08-10T08:59:59', 7),
    ('B_DEMO_ST01', '202609', 'B_DEMO_USER01', 'B_DEMO_GUN01', '2026-09-10T08:59:59', 8),
    ('B_DEMO_ST01', '202609', 'B_DEMO_USER01', 'B_DEMO_GUN01', '2026-10-01T00:00:02', 2),
    ('B_DEMO_ST01', '202610', 'B_DEMO_USER01', 'B_DEMO_GUN01', '2026-10-01T00:00:01', 1),
    ('B_DEMO_ST01', '202610', 'B_DEMO_USER01', 'B_DEMO_GUN01', '2026-10-01T00:00:04', 4),
    ('B_DEMO_ST01', '202610', 'B_DEMO_USER01', 'B_DEMO_GUN01', '2026-10-10T08:59:59', 9),
    ('D_DEMO_ST02', '202606', 'B_DEMO_USER01', 'D_DEMO_GUN02', '2026-06-10T08:59:59', 10),
    ('D_DEMO_ST02', '202607', 'B_DEMO_USER01', 'D_DEMO_GUN02', '2026-07-10T08:59:59', 11),
    ('D_DEMO_ST02', '202608', 'B_DEMO_USER01', 'D_DEMO_GUN02', '2026-08-10T08:59:59', 12),
    ('D_DEMO_ST02', '202609', 'B_DEMO_USER01', 'D_DEMO_GUN02', '2026-09-10T08:59:59', 13),
    ('D_DEMO_ST02', '202610', 'B_DEMO_USER01', 'D_DEMO_GUN02', '2026-10-10T08:59:59', 14),
    ('D_DEMO_ST03', '202606', 'B_DEMO_USER01', 'D_DEMO_GUN03', '2026-06-10T08:59:59', 15),
    ('D_DEMO_ST03', '202607', 'B_DEMO_USER01', 'D_DEMO_GUN03', '2026-07-10T08:59:59', 16),
    ('D_DEMO_ST03', '202608', 'B_DEMO_USER01', 'D_DEMO_GUN03', '2026-08-10T08:59:59', 17),
    ('D_DEMO_ST03', '202609', 'B_DEMO_USER01', 'D_DEMO_GUN03', '2026-09-10T08:59:59', 18),
    ('D_DEMO_ST03', '202610', 'B_DEMO_USER01', 'D_DEMO_GUN03', '2026-10-10T08:59:59', 19),
    ('D_DEMO_ST04', '202606', 'B_DEMO_USER01', 'D_DEMO_GUN04', '2026-06-10T08:59:59', 20),
    ('D_DEMO_ST04', '202607', 'B_DEMO_USER01', 'D_DEMO_GUN04', '2026-07-10T08:59:59', 21),
    ('D_DEMO_ST04', '202608', 'B_DEMO_USER01', 'D_DEMO_GUN04', '2026-08-10T08:59:59', 22),
    ('D_DEMO_ST04', '202609', 'B_DEMO_USER01', 'D_DEMO_GUN04', '2026-09-10T08:59:59', 23),
    ('D_DEMO_ST04', '202610', 'B_DEMO_USER01', 'D_DEMO_GUN04', '2026-10-10T08:59:59', 24),
    ('D_DEMO_ST05', '202606', 'B_DEMO_USER01', 'D_DEMO_GUN05', '2026-06-10T08:59:59', 25),
    ('D_DEMO_ST05', '202607', 'B_DEMO_USER01', 'D_DEMO_GUN05', '2026-07-10T08:59:59', 26),
    ('D_DEMO_ST05', '202608', 'B_DEMO_USER01', 'D_DEMO_GUN05', '2026-08-10T08:59:59', 27),
    ('D_DEMO_ST05', '202609', 'B_DEMO_USER01', 'D_DEMO_GUN05', '2026-09-10T08:59:59', 28),
    ('D_DEMO_ST05', '202610', 'B_DEMO_USER01', 'D_DEMO_GUN05', '2026-10-10T08:59:59', 29);

SELECT station_id,period_month,settlement_id,status INTO #current_settlements FROM dbo.SettlementStatement;
SELECT s.station_id,s.period_month,o.user_id,o.gun_id,
       CONVERT(VARCHAR(33),o.created_at,126) AS created_at,o.order_id
INTO #current_details
FROM dbo.SettlementDetail d
JOIN dbo.SettlementStatement s ON s.settlement_id=d.settlement_id
JOIN dbo.ChargingOrder o ON o.order_id=d.order_id;

SELECT (SELECT COUNT(*) FROM @baseline_settlements) AS baseline_settlements,
       (SELECT COUNT(*) FROM #current_settlements) AS current_settlements,
       (SELECT COUNT(*) FROM @baseline_details) AS baseline_details,
       (SELECT COUNT(*) FROM #current_details) AS current_details;

-- Report duplicates on either side. EXCEPT alone would discard duplicate keys.
SELECT 'BASELINE' AS origin, station_id, period_month, COUNT(*) AS occurrences
FROM @baseline_settlements GROUP BY station_id,period_month HAVING COUNT(*)>1
UNION ALL
SELECT 'CURRENT',station_id,period_month,COUNT(*)
FROM #current_settlements GROUP BY station_id,period_month HAVING COUNT(*)>1;
SELECT 'BASELINE' AS origin,station_id,period_month,user_id,gun_id,created_at,COUNT(*) AS occurrences
FROM @baseline_details GROUP BY station_id,period_month,user_id,gun_id,created_at HAVING COUNT(*)>1
UNION ALL
SELECT 'CURRENT',station_id,period_month,user_id,gun_id,created_at,COUNT(*)
FROM #current_details GROUP BY station_id,period_month,user_id,gun_id,created_at HAVING COUNT(*)>1;

WITH missing AS (
    SELECT station_id,period_month FROM @baseline_settlements
    EXCEPT SELECT station_id,period_month FROM #current_settlements
), extra AS (
    SELECT station_id,period_month FROM #current_settlements
    EXCEPT SELECT station_id,period_month FROM @baseline_settlements
)
SELECT 'MISSING_IN_NEW' AS difference_type, station_id,period_month FROM missing
UNION ALL SELECT 'EXTRA_IN_NEW',station_id,period_month FROM extra
ORDER BY difference_type,station_id,period_month;

WITH missing AS (
    SELECT station_id,period_month,user_id,gun_id,created_at FROM @baseline_details
    EXCEPT SELECT station_id,period_month,user_id,gun_id,created_at FROM #current_details
), extra AS (
    SELECT station_id,period_month,user_id,gun_id,created_at FROM #current_details
    EXCEPT SELECT station_id,period_month,user_id,gun_id,created_at FROM @baseline_details
)
SELECT 'MISSING_IN_NEW' AS difference_type, m.*, b.order_id AS diagnostic_order_id
FROM missing m JOIN @baseline_details b
  ON b.station_id=m.station_id AND b.period_month=m.period_month AND b.user_id=m.user_id
 AND b.gun_id=m.gun_id AND b.created_at=m.created_at
UNION ALL
SELECT 'EXTRA_IN_NEW', e.*, n.order_id
FROM extra e JOIN #current_details n
  ON n.station_id=e.station_id AND n.period_month=e.period_month AND n.user_id=e.user_id
 AND n.gun_id=e.gun_id AND n.created_at=e.created_at
ORDER BY difference_type,station_id,period_month,user_id,gun_id,created_at;

IF (SELECT COUNT(*) FROM @baseline_settlements) <> 25 OR (SELECT COUNT(*) FROM #current_settlements) <> 25
   OR (SELECT COUNT(*) FROM @baseline_details) <> 28 OR (SELECT COUNT(*) FROM #current_details) <> 28
   OR (SELECT COUNT(*) FROM (SELECT DISTINCT station_id,period_month FROM @baseline_settlements) s) <> 25
   OR (SELECT COUNT(*) FROM (SELECT DISTINCT station_id,period_month FROM #current_settlements) s) <> 25
   OR (SELECT COUNT(*) FROM (SELECT DISTINCT station_id,period_month,user_id,gun_id,created_at FROM @baseline_details) d) <> 28
   OR (SELECT COUNT(*) FROM (SELECT DISTINCT station_id,period_month,user_id,gun_id,created_at FROM #current_details) d) <> 28
   OR EXISTS (SELECT station_id,period_month FROM @baseline_settlements
              EXCEPT SELECT station_id,period_month FROM #current_settlements)
   OR EXISTS (SELECT station_id,period_month FROM #current_settlements
              EXCEPT SELECT station_id,period_month FROM @baseline_settlements)
   OR EXISTS (SELECT station_id,period_month,user_id,gun_id,created_at FROM @baseline_details
              EXCEPT SELECT station_id,period_month,user_id,gun_id,created_at FROM #current_details)
   OR EXISTS (SELECT station_id,period_month,user_id,gun_id,created_at FROM #current_details
              EXCEPT SELECT station_id,period_month,user_id,gun_id,created_at FROM @baseline_details)
    THROW 52611, N'Baseline membership or key uniqueness differs. Inspect the preceding result sets.', 1;

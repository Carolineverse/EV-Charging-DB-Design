-- Q01 回归测试：保留无桩场站，且多枪不重复计算充电桩。
-- 所有夹具在 EV_B_TEST 的事务中回滚。

SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51100, 'This test must run in EV_B_TEST.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @OperatorId VARCHAR(20) = 'Q01OP' + @Token;
DECLARE @EmptyStationId VARCHAR(20) = 'Q01SE' + @Token;
DECLARE @FullStationId VARCHAR(20) = 'Q01SF' + @Token;
DECLARE @PileOneId VARCHAR(20) = 'Q01P1' + @Token;
DECLARE @PileTwoId VARCHAR(20) = 'Q01P2' + @Token;
DECLARE @GunOneId VARCHAR(20) = 'Q01G1' + @Token;
DECLARE @GunTwoId VARCHAR(20) = 'Q01G2' + @Token;
DECLARE @GunThreeId VARCHAR(20) = 'Q01G3' + @Token;
DECLARE @Actual TABLE
(
    station_id VARCHAR(20) PRIMARY KEY,
    pile_count INT NOT NULL,
    gun_count INT NOT NULL,
    idle_gun_count INT NOT NULL
);

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'Q01测试运营商');

    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@EmptyStationId, N'Q01空站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         0, N'00:00-24:00', N'测试', 1),
        (@FullStationId, N'Q01多枪站', N'测试地址', 116.410000, 39.910000, @OperatorId,
         2, N'00:00-24:00', N'测试', 1);

    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileOneId, @FullStationId, N'Q01-MODEL', 60.00, N'OCPP', '2026-01-01', '2028-01-01', 'IDLE'),
        (@PileTwoId, @FullStationId, N'Q01-MODEL', 60.00, N'OCPP', '2026-01-01', '2028-01-01', 'IDLE');

    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunOneId, @PileOneId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE'),
        (@GunTwoId, @PileOneId, 2, 'DC_FAST', N'GB/T', 60.00, 'OCCUPIED'),
        (@GunThreeId, @PileTwoId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE');

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
    INSERT INTO @Actual (station_id, pile_count, gun_count, idle_gun_count)
    SELECT s.station_id,
           COALESCE(pc.pile_count, 0),
           COALESCE(gc.gun_count, 0),
           COALESCE(gc.idle_gun_count, 0)
    FROM dbo.ChargingStation AS s
    LEFT JOIN pile_count AS pc ON pc.station_id = s.station_id
    LEFT JOIN gun_count AS gc ON gc.station_id = s.station_id
    WHERE s.station_id IN (@EmptyStationId, @FullStationId);

    IF (SELECT COUNT(*) FROM @Actual) <> 2
        THROW 51101, 'Q01 did not return both fixture stations.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM @Actual WHERE station_id = @EmptyStationId
        AND pile_count = 0 AND gun_count = 0 AND idle_gun_count = 0)
        THROW 51102, 'Q01 did not preserve the station with no piles.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM @Actual WHERE station_id = @FullStationId
        AND pile_count = 2 AND gun_count = 3 AND idle_gun_count = 2)
        THROW 51103, 'Q01 duplicated pile counts or miscounted guns.', 1;

    SELECT station_id, pile_count, gun_count, idle_gun_count
    FROM @Actual
    ORDER BY station_id;
    SELECT N'Q01 空站保留及多枪计数' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

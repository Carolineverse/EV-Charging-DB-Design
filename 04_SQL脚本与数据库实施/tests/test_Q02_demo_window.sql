-- Q02 sample-window regression: non-empty result and fee-segment energy totals.
SET NOCOUNT ON;
IF DB_NAME()<>N'EV_B_TEST' THROW 52960,N'Choose EV_B_TEST',1;

DECLARE @StationId VARCHAR(20)='B_DEMO_ST01';
DECLARE @EndExclusive DATETIME2(3)='2026-11-01T00:00:00';
DECLARE @StartInclusive DATETIME2(3)=DATEADD(day,-30,@EndExclusive);
DECLARE @Actual TABLE
(
    period_type NCHAR(1) NOT NULL,
    energy_kwh DECIMAL(12,3) NOT NULL,
    electricity_fee DECIMAL(12,2) NOT NULL,
    service_fee_before_free DECIMAL(12,2) NOT NULL,
    free_service_fee DECIMAL(12,2) NOT NULL,
    service_fee DECIMAL(12,2) NOT NULL
);

WITH priced_segments AS
(
    SELECT b.period_type,f.segment_energy_kwh,b.electricity_price,
           b.service_price,f.free_service_fee
    FROM dbo.ChargingOrder o
    JOIN dbo.ChargingStation s ON s.station_id=o.opening_station_id
    JOIN dbo.BillingRuleVersion v
      ON v.rule_version_id=o.startup_rule_version_id
     AND v.station_id=o.opening_station_id
    JOIN dbo.OrderFeeDetail f ON f.order_id=o.order_id
    JOIN dbo.BillingRule b
      ON b.billing_rule_id=f.billing_rule_id
     AND b.rule_version_id=v.rule_version_id
    WHERE s.station_id=@StationId
      AND f.segment_start>=@StartInclusive
      AND f.segment_start<@EndExclusive
      AND o.priced_at IS NOT NULL
)
INSERT INTO @Actual
SELECT period_type,
       SUM(segment_energy_kwh),
       SUM(ROUND(segment_energy_kwh*electricity_price,2)),
       SUM(ROUND(segment_energy_kwh*service_price,2)),
       SUM(free_service_fee),
       SUM(ROUND(segment_energy_kwh*service_price,2)-free_service_fee)
FROM priced_segments
GROUP BY period_type;

IF (SELECT COUNT(*) FROM @Actual)<>1
   THROW 52961,N'Q02 should return one non-empty tariff group for the demo station window.',1;
IF NOT EXISTS
(
    SELECT 1 FROM @Actual
    WHERE period_type=N'平' AND energy_kwh=5.000
      AND electricity_fee=10.00 AND service_fee_before_free=5.00
      AND free_service_fee=0.00 AND service_fee=5.00
)
   THROW 52962,N'Q02 demo totals do not match the fee-segment facts.',1;

SELECT N'Q02 demo-window segment aggregation' AS test_name,
       N'passed' AS test_result,* FROM @Actual;

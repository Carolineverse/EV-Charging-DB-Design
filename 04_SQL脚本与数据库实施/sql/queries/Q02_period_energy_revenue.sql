-- Q02: 按场站与费率时段汇总已核价费用段。
-- 日期区间左闭右开，按每个费用段的 segment_start 归属日期。
-- 金额逐段舍入；本查询是核价金额分析，不代表实际到账或结算收入。

DECLARE @StationId VARCHAR(20) = NULL; -- NULL 表示查询全部场站。
DECLARE @StartInclusive DATETIME2(3) = '2026-10-01T00:00:00';
DECLARE @EndExclusive DATETIME2(3) = '2026-11-01T00:00:00';

WITH priced_segments AS
(
    SELECT s.station_id,
           s.station_name,
           r.period_type,
           d.segment_energy_kwh,
           r.electricity_price,
           r.service_price,
           d.free_service_fee
    FROM dbo.ChargingOrder AS o
    INNER JOIN dbo.ChargingStation AS s
        ON s.station_id = o.opening_station_id
    INNER JOIN dbo.BillingRuleVersion AS v
        ON v.rule_version_id = o.startup_rule_version_id
       AND v.station_id = o.opening_station_id
    INNER JOIN dbo.OrderFeeDetail AS d
        ON d.order_id = o.order_id
       AND d.segment_start >= @StartInclusive
       AND d.segment_start < @EndExclusive
    INNER JOIN dbo.BillingRule AS r
        ON r.billing_rule_id = d.billing_rule_id
       AND r.rule_version_id = v.rule_version_id
    WHERE o.priced_at IS NOT NULL
      AND (@StationId IS NULL OR o.opening_station_id = @StationId)
)
SELECT station_id,
       station_name,
       period_type,
       SUM(segment_energy_kwh) AS energy_kwh,
       SUM(ROUND(segment_energy_kwh * electricity_price, 2)) AS electricity_amount,
       SUM(ROUND(segment_energy_kwh * service_price, 2)) AS service_amount_before_free,
       SUM(free_service_fee) AS free_service_fee,
       SUM(ROUND(segment_energy_kwh * service_price, 2) - free_service_fee)
           AS service_amount_after_free
FROM priced_segments
GROUP BY station_id, station_name, period_type
ORDER BY station_id, period_type;

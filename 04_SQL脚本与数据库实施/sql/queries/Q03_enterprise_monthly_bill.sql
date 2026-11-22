-- Q03: 按企业与账期汇总月结快照，并核对明细订单实际结束月。
-- 本地 R EnterpriseProfile 未安装；使用 enterprise_id 作为企业稳定标识。

DECLARE @EnterpriseId VARCHAR(20) = NULL; -- NULL 表示该账期全部企业。
DECLARE @BillingPeriodStart DATE = '2026-10-01';

WITH detail_summary AS
(
    SELECT e.enterprise_settlement_id,
           COUNT_BIG(*) AS detail_order_count,
           SUM(d.energy_kwh) AS detail_energy_kwh,
           SUM(d.payable_amount) AS detail_amount,
           SUM(CASE WHEN o.end_time >= e.billing_period_start
                     AND o.end_time < DATEADD(MONTH, 1, e.billing_period_start)
                    THEN 1 ELSE 0 END) AS order_end_in_period_count,
           SUM(CASE WHEN o.status = 'PAID' AND o.settled_at IS NOT NULL
                    THEN 1 ELSE 0 END) AS paid_order_count
    FROM dbo.EnterpriseSettlement AS e
    INNER JOIN dbo.EnterpriseSettlementDetail AS d
        ON d.enterprise_settlement_id = e.enterprise_settlement_id
    INNER JOIN dbo.ChargingOrder AS o ON o.order_id = d.order_id
    WHERE e.billing_period_start = @BillingPeriodStart
      AND (@EnterpriseId IS NULL OR e.enterprise_id = @EnterpriseId)
    GROUP BY e.enterprise_settlement_id
)
SELECT e.enterprise_settlement_id,
       e.enterprise_id,
       e.billing_period_start,
       e.total_order_count AS header_order_count,
       COALESCE(ds.detail_order_count, 0) AS detail_order_count,
       e.total_energy_kwh AS header_energy_kwh,
       COALESCE(ds.detail_energy_kwh, 0) AS detail_energy_kwh,
       e.total_amount AS header_amount,
       COALESCE(ds.detail_amount, 0) AS detail_amount,
       COALESCE(ds.order_end_in_period_count, 0) AS order_end_in_period_count,
       COALESCE(ds.paid_order_count, 0) AS paid_order_count,
       CASE WHEN e.paid_at IS NOT NULL THEN 'PAID'
            WHEN e.confirmed_at IS NOT NULL THEN 'CONFIRMED'
            ELSE 'GENERATED' END AS settlement_state,
       e.confirmed_at,
       e.paid_at,
       e.payment_reference
FROM dbo.EnterpriseSettlement AS e
LEFT JOIN detail_summary AS ds
    ON ds.enterprise_settlement_id = e.enterprise_settlement_id
WHERE e.billing_period_start = @BillingPeriodStart
  AND (@EnterpriseId IS NULL OR e.enterprise_id = @EnterpriseId)
ORDER BY e.enterprise_id, e.enterprise_settlement_id;

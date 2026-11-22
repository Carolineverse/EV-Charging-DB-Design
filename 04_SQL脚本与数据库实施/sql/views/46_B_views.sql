-- B V05: 订单费用段及按段派生的金额。
-- 费用金额是派生列；priced_at 与 rule_version_matches 用于判断核价事实状态。
CREATE OR ALTER VIEW dbo.v_BOrderFeeSegments
AS
SELECT o.order_id,
       o.opening_station_id,
       o.order_type,
       o.status AS order_status,
       o.start_time,
       o.end_time,
       o.priced_at,
       o.startup_rule_version_id,
       d.order_fee_detail_id,
       d.billing_rule_id,
       r.rule_version_id AS fee_rule_version_id,
       CONVERT(BIT, CASE
           WHEN v.rule_version_id IS NOT NULL
            AND r.rule_version_id = o.startup_rule_version_id
            AND v.station_id = o.opening_station_id THEN 1 ELSE 0
       END) AS rule_version_matches,
       r.period_type,
       r.period_start_time,
       r.period_end_time,
       r.electricity_price,
       r.service_price,
       d.segment_start,
       d.segment_end,
       d.segment_energy_kwh,
       ROUND(d.segment_energy_kwh * r.electricity_price, 2) AS electricity_amount,
       ROUND(d.segment_energy_kwh * r.service_price, 2) AS service_amount_before_free,
       d.free_service_fee,
       ROUND(d.segment_energy_kwh * r.service_price, 2) - d.free_service_fee
           AS service_amount_after_free
FROM dbo.OrderFeeDetail AS d
INNER JOIN dbo.ChargingOrder AS o ON o.order_id = d.order_id
INNER JOIN dbo.BillingRule AS r ON r.billing_rule_id = d.billing_rule_id
LEFT JOIN dbo.BillingRuleVersion AS v
    ON v.rule_version_id = o.startup_rule_version_id;
GO

-- B V06: 一订单一行的支付/退款凭据汇总。
-- 先分别按订单聚合支付与退款，避免多笔记录相互放大金额。
CREATE OR ALTER VIEW dbo.v_BPaymentRefundTrace
AS
WITH payment_by_order AS
(
    SELECT order_id,
           COUNT_BIG(*) AS payment_record_count,
           SUM(pay_amount) AS payment_amount,
           SUM(refund_amount) AS payment_refund_amount
    FROM dbo.PaymentRecord
    GROUP BY order_id
), refund_by_order AS
(
    SELECT p.order_id,
           COUNT_BIG(*) AS refund_record_count,
           SUM(CASE WHEN r.status = 'SUCCESS' THEN r.refund_amount ELSE 0 END)
               AS successful_refund_amount,
           SUM(CASE WHEN r.status = 'PROCESSING' THEN r.refund_amount ELSE 0 END)
               AS processing_refund_amount,
           SUM(CASE WHEN r.status = 'FAILED' THEN r.refund_amount ELSE 0 END)
               AS failed_refund_amount,
           SUM(CASE WHEN r.status = 'CANCELLED' THEN r.refund_amount ELSE 0 END)
               AS cancelled_refund_amount
    FROM dbo.PaymentRecord AS p
    INNER JOIN dbo.RefundRecord AS r ON r.payment_id = p.payment_id
    GROUP BY p.order_id
)
SELECT o.order_id,
       o.opening_station_id,
       o.status AS order_status,
       COALESCE(p.payment_record_count, 0) AS payment_record_count,
       COALESCE(p.payment_amount, 0) AS payment_amount,
       COALESCE(p.payment_refund_amount, 0) AS payment_refund_amount,
       COALESCE(r.refund_record_count, 0) AS refund_record_count,
       COALESCE(r.successful_refund_amount, 0) AS successful_refund_amount,
       COALESCE(r.processing_refund_amount, 0) AS processing_refund_amount,
       COALESCE(r.failed_refund_amount, 0) AS failed_refund_amount,
       COALESCE(r.cancelled_refund_amount, 0) AS cancelled_refund_amount
FROM dbo.ChargingOrder AS o
LEFT JOIN payment_by_order AS p ON p.order_id = o.order_id
LEFT JOIN refund_by_order AS r ON r.order_id = o.order_id;
GO

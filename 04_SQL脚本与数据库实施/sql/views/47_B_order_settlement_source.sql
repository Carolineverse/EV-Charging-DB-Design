-- B V04: 供 D 结算生成读取的订单来源。
-- 输出 SettlementDetail 的 B 侧快照字段；辅助资格列提供可审阅的排除/复核原因。
-- 多行费用、支付、退款和 A2 企业回执均先按订单聚合，保证一单最多一行。
CREATE OR ALTER VIEW dbo.v_OrderSettlementSource
AS
WITH order_context AS
(
    SELECT o.order_id,
           o.order_type,
           o.user_id,
           o.gun_id,
           o.binding_id,
           o.start_time,
           o.end_time,
           o.energy_kwh,
           o.status,
           o.gross_amount,
           o.minimum_adjustment,
           o.discount_amount,
           o.paid_amount,
           o.refund_amount,
           o.opening_station_id,
           o.settled_at,
           o.startup_rule_version_id,
           o.priced_at,
           c.enterprise_id,
           b.fleet_member_id,
           b.vehicle_id
    FROM dbo.ChargingOrder AS o
    LEFT JOIN dbo.EnterpriseCardBinding AS b ON b.binding_id = o.binding_id
    LEFT JOIN dbo.EnterpriseCard AS c ON c.enterprise_card_id = b.enterprise_card_id
), fee_by_order AS
(
    SELECT o.order_id,
           COUNT_BIG(*) AS fee_segment_count,
           SUM(d.segment_energy_kwh) AS fee_energy_kwh,
           SUM(ROUND(d.segment_energy_kwh * r.electricity_price, 2)) AS electricity_base,
           SUM(ROUND(d.segment_energy_kwh * r.service_price, 2) - d.free_service_fee)
               AS service_base,
           SUM(d.free_service_fee) AS free_service_fee_total,
           SUM(CASE
               WHEN r.rule_version_id <> o.startup_rule_version_id
                 OR v.rule_version_id IS NULL
                 OR v.station_id <> o.opening_station_id
                 OR (o.order_type = 'PERSONAL' AND v.enterprise_id IS NOT NULL)
                 OR (o.order_type = 'ENTERPRISE'
                     AND (o.enterprise_id IS NULL OR v.enterprise_id <> o.enterprise_id))
               THEN 1 ELSE 0
           END) AS invalid_fee_rule_count
    FROM order_context AS o
    INNER JOIN dbo.OrderFeeDetail AS d ON d.order_id = o.order_id
    INNER JOIN dbo.BillingRule AS r ON r.billing_rule_id = d.billing_rule_id
    LEFT JOIN dbo.BillingRuleVersion AS v ON v.rule_version_id = r.rule_version_id
    GROUP BY o.order_id
), payment_by_order AS
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
), enterprise_receipt AS
(
    SELECT d.order_id,
           d.payable_amount,
           d.energy_kwh,
           d.fleet_member_id,
           d.vehicle_id,
           s.enterprise_id,
           s.billing_period_start,
           s.confirmed_at,
           s.paid_at,
           s.payment_reference
    FROM dbo.EnterpriseSettlementDetail AS d
    INNER JOIN dbo.EnterpriseSettlement AS s
        ON s.enterprise_settlement_id = d.enterprise_settlement_id
), source_rows AS
(
SELECT o.order_id,
       o.opening_station_id,
       o.end_time AS ended_at_snapshot,
       CASE WHEN o.end_time IS NOT NULL AND o.priced_at IS NOT NULL
                  AND o.energy_kwh > 0 AND f.fee_segment_count > 0
                  AND f.fee_energy_kwh = o.energy_kwh
                  AND f.invalid_fee_rule_count = 0
                  AND o.gross_amount = f.electricity_base + f.service_base + o.minimum_adjustment
            THEN o.energy_kwh END AS energy_snapshot,
       CASE WHEN o.priced_at IS NOT NULL AND f.fee_segment_count > 0
                  AND f.fee_energy_kwh = o.energy_kwh
                  AND f.invalid_fee_rule_count = 0
                  AND o.gross_amount = f.electricity_base + f.service_base + o.minimum_adjustment
            THEN f.electricity_base END AS electricity_base,
       CASE WHEN o.priced_at IS NOT NULL AND f.fee_segment_count > 0
                  AND f.fee_energy_kwh = o.energy_kwh
                  AND f.invalid_fee_rule_count = 0
                  AND o.gross_amount = f.electricity_base + f.service_base + o.minimum_adjustment
            THEN f.service_base END AS service_base,
       CASE WHEN o.priced_at IS NOT NULL AND f.fee_segment_count > 0
                  AND f.fee_energy_kwh = o.energy_kwh
                  AND f.invalid_fee_rule_count = 0
                  AND o.gross_amount = f.electricity_base + f.service_base + o.minimum_adjustment
            THEN o.minimum_adjustment END AS minimum_adjustment,
       o.settled_at AS settled_at_snapshot,
       o.order_type AS settlement_source,
       CONVERT(DATETIME2(3), SYSDATETIME()) AS eligibility_checked_at,
       CASE
           WHEN o.order_type = 'ENTERPRISE' THEN 'NONE'
           WHEN COALESCE(r.successful_refund_amount, 0) = 0
            AND COALESCE(r.processing_refund_amount, 0) = 0
            AND COALESCE(r.refund_record_count, 0) = 0 THEN 'NONE'
           WHEN COALESCE(r.successful_refund_amount, 0) = 0
            AND COALESCE(r.processing_refund_amount, 0) = 0 THEN 'FAILED_CANCELLED'
           ELSE NULL
       END AS refund_state_snapshot,
       CASE WHEN o.priced_at IS NOT NULL THEN o.gross_amount END AS gross_amount,
       CASE WHEN o.priced_at IS NOT NULL THEN o.discount_amount END AS discount_amount,
       CASE WHEN o.priced_at IS NOT NULL THEN o.gross_amount - o.discount_amount END AS payable_amount,
       o.paid_amount,
       COALESCE(p.payment_record_count, 0) AS payment_record_count,
       COALESCE(p.payment_amount, 0) AS payment_amount,
       o.refund_amount AS order_refund_amount,
       COALESCE(p.payment_refund_amount, 0) AS payment_refund_amount,
       COALESCE(r.refund_record_count, 0) AS refund_record_count,
       COALESCE(r.successful_refund_amount, 0) AS successful_refund_amount,
       COALESCE(r.processing_refund_amount, 0) AS processing_refund_amount,
       COALESCE(r.failed_refund_amount, 0) AS failed_refund_amount,
       COALESCE(r.cancelled_refund_amount, 0) AS cancelled_refund_amount,
       CASE WHEN o.order_type = 'ENTERPRISE' THEN CONVERT(BIT, 1) ELSE CONVERT(BIT, 0) END
           AS enterprise_refund_check_required,
       CASE WHEN e.order_id IS NOT NULL
                  AND e.enterprise_id = o.enterprise_id
                  AND e.fleet_member_id = o.fleet_member_id
                  AND e.vehicle_id = o.vehicle_id
                  AND e.confirmed_at IS NOT NULL
                  AND e.paid_at IS NOT NULL
                  AND e.paid_at >= o.settled_at
                  AND e.billing_period_start = DATEFROMPARTS(YEAR(o.end_time), MONTH(o.end_time), 1)
                  AND NULLIF(LTRIM(RTRIM(e.payment_reference)), '') IS NOT NULL
                  AND e.energy_kwh = o.energy_kwh
                  AND e.payable_amount = o.gross_amount - o.discount_amount
            THEN CONVERT(BIT, 1) ELSE CONVERT(BIT, 0) END AS enterprise_receipt_verified,
       CASE
           WHEN o.end_time IS NULL THEN 'MISSING_END_TIME'
           WHEN o.priced_at IS NULL THEN 'NOT_PRICED'
           WHEN o.energy_kwh = 0 THEN 'ZERO_ENERGY_EVIDENCE_REQUIRED'
           WHEN f.fee_segment_count IS NULL
             OR f.fee_energy_kwh <> o.energy_kwh
             OR f.invalid_fee_rule_count <> 0
             OR o.gross_amount <> f.electricity_base + f.service_base + o.minimum_adjustment
               THEN 'FEE_INPUT_MISMATCH'
           WHEN o.status <> 'PAID' OR o.settled_at IS NULL THEN 'NOT_SETTLED'
           WHEN o.order_type = 'PERSONAL'
            AND COALESCE(p.payment_amount, 0) <> o.paid_amount THEN 'PAYMENT_TOTAL_MISMATCH'
           WHEN o.order_type = 'PERSONAL'
            AND o.paid_amount < o.gross_amount - o.discount_amount THEN 'PAYMENT_INSUFFICIENT'
           WHEN o.order_type = 'PERSONAL'
            AND (COALESCE(p.payment_refund_amount, 0) <> o.refund_amount
                 OR COALESCE(r.successful_refund_amount, 0) <> o.refund_amount)
               THEN 'REFUND_TOTAL_MISMATCH'
           WHEN o.order_type = 'PERSONAL'
            AND COALESCE(r.processing_refund_amount, 0) > 0 THEN 'REFUND_PROCESSING'
           WHEN o.order_type = 'PERSONAL'
            AND COALESCE(r.successful_refund_amount, 0) > 0 THEN 'PRE_SETTLE_REFUND'
           WHEN o.order_type = 'ENTERPRISE' AND e.order_id IS NULL THEN 'ENTERPRISE_RECEIPT_MISSING'
           WHEN o.order_type = 'ENTERPRISE'
            AND NOT (e.enterprise_id = o.enterprise_id
                 AND e.fleet_member_id = o.fleet_member_id
                 AND e.vehicle_id = o.vehicle_id
                 AND e.confirmed_at IS NOT NULL AND e.paid_at IS NOT NULL
                 AND e.paid_at >= o.settled_at
                 AND e.billing_period_start = DATEFROMPARTS(YEAR(o.end_time), MONTH(o.end_time), 1)
                 AND NULLIF(LTRIM(RTRIM(e.payment_reference)), '') IS NOT NULL
                 AND e.energy_kwh = o.energy_kwh
                 AND e.payable_amount = o.gross_amount - o.discount_amount)
               THEN 'ENTERPRISE_RECEIPT_MISMATCH'
           WHEN o.order_type = 'ENTERPRISE' THEN 'ENTERPRISE_REFUND_CHECK_REQUIRED'
           ELSE NULL
       END AS eligibility_reason,
       CASE
           WHEN o.end_time IS NULL OR o.priced_at IS NULL OR o.energy_kwh = 0
             OR f.fee_segment_count IS NULL OR f.fee_energy_kwh <> o.energy_kwh
             OR f.invalid_fee_rule_count <> 0
             OR o.gross_amount <> f.electricity_base + f.service_base + o.minimum_adjustment
             OR o.status <> 'PAID' OR o.settled_at IS NULL THEN 'INELIGIBLE'
           WHEN o.order_type = 'PERSONAL'
            AND (COALESCE(p.payment_amount, 0) <> o.paid_amount
                 OR o.paid_amount < o.gross_amount - o.discount_amount
                 OR COALESCE(p.payment_refund_amount, 0) <> o.refund_amount
                 OR COALESCE(r.successful_refund_amount, 0) <> o.refund_amount
                 OR COALESCE(r.processing_refund_amount, 0) > 0
                 OR COALESCE(r.successful_refund_amount, 0) > 0) THEN 'INELIGIBLE'
           WHEN o.order_type = 'ENTERPRISE' AND e.order_id IS NULL THEN 'INELIGIBLE'
           WHEN o.order_type = 'ENTERPRISE'
            AND NOT (e.enterprise_id = o.enterprise_id
                 AND e.fleet_member_id = o.fleet_member_id
                 AND e.vehicle_id = o.vehicle_id
                 AND e.confirmed_at IS NOT NULL AND e.paid_at IS NOT NULL
                 AND e.paid_at >= o.settled_at
                 AND e.billing_period_start = DATEFROMPARTS(YEAR(o.end_time), MONTH(o.end_time), 1)
                 AND NULLIF(LTRIM(RTRIM(e.payment_reference)), '') IS NOT NULL
                 AND e.energy_kwh = o.energy_kwh
                 AND e.payable_amount = o.gross_amount - o.discount_amount) THEN 'INELIGIBLE'
           WHEN o.order_type = 'ENTERPRISE' THEN 'REVIEW_REQUIRED'
           ELSE 'ELIGIBLE'
       END AS eligibility_status,
       CASE WHEN e.order_id IS NOT NULL THEN e.payable_amount END AS enterprise_receipt_amount,
       CASE WHEN e.order_id IS NOT NULL THEN e.billing_period_start END
           AS enterprise_receipt_billing_period_start,
       CASE WHEN e.order_id IS NOT NULL THEN e.paid_at END AS enterprise_receipt_paid_at
FROM order_context AS o
LEFT JOIN fee_by_order AS f ON f.order_id = o.order_id
LEFT JOIN payment_by_order AS p ON p.order_id = o.order_id
LEFT JOIN refund_by_order AS r ON r.order_id = o.order_id
LEFT JOIN enterprise_receipt AS e ON e.order_id = o.order_id
), source_contract AS
(
    SELECT base_rows.*,
           base_rows.opening_station_id AS station_id,
           base_rows.ended_at_snapshot AS ended_at,
           base_rows.settled_at_snapshot AS settled_at,
           base_rows.energy_snapshot AS energy_kwh,
           CONVERT(BIT, CASE
               WHEN base_rows.eligibility_status = 'ELIGIBLE' THEN 1
               WHEN base_rows.eligibility_status = 'REVIEW_REQUIRED'
                AND base_rows.enterprise_receipt_verified = 1 THEN 1
               ELSE 0
           END) AS is_settleable,
           CASE
               WHEN base_rows.eligibility_status = 'ELIGIBLE' THEN NULL
               WHEN base_rows.eligibility_status = 'REVIEW_REQUIRED'
                AND base_rows.enterprise_receipt_verified = 1 THEN NULL
               ELSE COALESCE(base_rows.eligibility_reason, base_rows.eligibility_status)
           END AS unsettleable_reason
    FROM
    (
        SELECT * FROM source_rows
    ) AS base_rows
)
SELECT *
FROM source_contract;
GO

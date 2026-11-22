-- A2 V07: A2 用户范围内的当前会员等级与钱包快照。
-- 余额直接读取 UserWallet.balance；UserProfile 未安装时不扩造全体用户清单。
CREATE OR ALTER VIEW dbo.v_A2MemberWalletSummary
AS
WITH a2_users AS
(
    SELECT user_id FROM dbo.UserMemberLevel
    UNION
    SELECT user_id FROM dbo.UserWallet
)
SELECT u.user_id,
       uml.member_level_id,
       ml.level_name,
       ml.level_sort,
       ml.status AS member_level_status,
       w.balance AS wallet_balance,
       w.status AS wallet_status,
       w.updated_at AS wallet_updated_at
FROM a2_users AS u
LEFT JOIN dbo.UserMemberLevel AS uml ON uml.user_id = u.user_id
LEFT JOIN dbo.MemberLevel AS ml ON ml.member_level_id = uml.member_level_id
LEFT JOIN dbo.UserWallet AS w ON w.user_id = u.user_id;
GO

-- A2 V08: 优惠券发放与核销追溯。
-- 以 UserCoupon 为粒度；没有核销的券保留，订单仅通过唯一核销记录关联。
CREATE OR ALTER VIEW dbo.v_A2CouponRedemptionTrace
AS
SELECT uc.user_coupon_id,
       uc.user_id,
       uc.coupon_code,
       uc.promotion_id,
       p.promotion_name,
       p.promotion_type,
       p.status AS promotion_status,
       uc.face_value,
       uc.min_spend,
       uc.issued_at,
       uc.valid_start_at,
       uc.valid_end_at,
       uc.status AS coupon_status,
       cr.coupon_redemption_id,
       cr.order_id,
       o.status AS order_status,
       cr.redeemed_amount,
       cr.redeemed_at,
       CONVERT(BIT, CASE
           WHEN (uc.status = 'USED' AND cr.coupon_redemption_id IS NOT NULL)
             OR (uc.status <> 'USED' AND cr.coupon_redemption_id IS NULL) THEN 1
           ELSE 0
       END) AS coupon_redemption_state_matches,
       CONVERT(BIT, CASE
           WHEN cr.coupon_redemption_id IS NULL THEN 1
           WHEN o.user_id = uc.user_id THEN 1
           ELSE 0
       END) AS redemption_user_matches_coupon
FROM dbo.UserCoupon AS uc
INNER JOIN dbo.Promotion AS p ON p.promotion_id = uc.promotion_id
LEFT JOIN dbo.CouponRedemption AS cr ON cr.user_coupon_id = uc.user_coupon_id
LEFT JOIN dbo.ChargingOrder AS o ON o.order_id = cr.order_id;
GO

-- A2 V09: 企业月结明细与订单实际事实对照。
-- 账期使用订单实际 end_time 所在自然月，不以创建时间或启动时间替代。
CREATE OR ALTER VIEW dbo.v_A2EnterpriseMonthlyDetail
AS
SELECT es.enterprise_settlement_id,
       es.enterprise_id,
       es.billing_period_start,
       es.total_order_count,
       es.total_energy_kwh,
       es.total_amount,
       es.generated_at,
       es.confirmed_at,
       es.paid_at,
       es.payment_reference,
       CASE WHEN es.paid_at IS NOT NULL THEN 'PAID'
            WHEN es.confirmed_at IS NOT NULL THEN 'CONFIRMED'
            ELSE 'GENERATED' END AS settlement_state,
       d.enterprise_settlement_detail_id,
       d.order_id,
       d.fleet_member_id,
       d.vehicle_id,
       d.payable_amount AS detail_payable_amount,
       d.energy_kwh AS detail_energy_kwh,
       d.created_at AS detail_created_at,
       o.end_time AS order_end_time,
       o.energy_kwh AS order_energy_kwh,
       o.status AS order_status,
       o.priced_at,
       CASE WHEN o.priced_at IS NOT NULL
            THEN o.gross_amount - o.discount_amount END AS order_payable_amount,
       CONVERT(BIT, CASE
           WHEN o.end_time IS NOT NULL
            AND es.billing_period_start = DATEFROMPARTS(YEAR(o.end_time), MONTH(o.end_time), 1)
           THEN 1 ELSE 0
       END) AS period_matches_order_end_month,
       CONVERT(BIT, CASE WHEN d.energy_kwh = o.energy_kwh THEN 1 ELSE 0 END)
           AS detail_energy_matches_order,
       CASE WHEN o.priced_at IS NULL THEN NULL
            WHEN d.payable_amount = o.gross_amount - o.discount_amount
            THEN CONVERT(BIT, 1) ELSE CONVERT(BIT, 0)
       END AS detail_amount_matches_order
FROM dbo.EnterpriseSettlement AS es
INNER JOIN dbo.EnterpriseSettlementDetail AS d
    ON d.enterprise_settlement_id = es.enterprise_settlement_id
INNER JOIN dbo.ChargingOrder AS o ON o.order_id = d.order_id;
GO

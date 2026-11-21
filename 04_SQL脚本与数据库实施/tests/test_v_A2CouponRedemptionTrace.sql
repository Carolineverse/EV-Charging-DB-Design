-- V08 回归测试：保留未核销券，核销订单不造成重复券行。
-- 所有夹具在 EV_B_TEST 的事务中回滚；不依赖 R.UserProfile。

SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 52000, 'This test must run in EV_B_TEST.', 1;
IF OBJECT_ID(N'dbo.v_A2CouponRedemptionTrace', N'V') IS NULL
    THROW 52001, 'Install dbo.v_A2CouponRedemptionTrace before this test.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @OperatorId VARCHAR(20) = 'V08OP' + @Token;
DECLARE @StationId VARCHAR(20) = 'V08ST' + @Token;
DECLARE @PileId VARCHAR(20) = 'V08PL' + @Token;
DECLARE @GunId VARCHAR(20) = 'V08GN' + @Token;
DECLARE @PromotionId VARCHAR(20) = 'V08PR' + @Token;
DECLARE @UnusedCouponId VARCHAR(20) = 'V08U' + @Token;
DECLARE @UsedCouponId VARCHAR(20) = 'V08R' + @Token;
DECLARE @UserId VARCHAR(20) = 'V08USER' + @Token;
DECLARE @OtherUserId VARCHAR(20) = 'V08OTHER' + @Token;
DECLARE @OrderId BIGINT;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'V08测试运营商');
    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'V08测试场站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         1, N'00:00-24:00', N'测试', 1);
    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileId, @StationId, N'V08-MODEL', 60.00, N'OCPP', '2026-01-01', '2028-01-01', 'IDLE');
    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE');

    INSERT INTO dbo.Promotion
        (promotion_id, promotion_name, promotion_type, face_value, min_spend,
         issue_start_at, issue_end_at, valid_start_at, valid_end_at, issue_quantity,
         target_audience, redemption_rule, status, reviewed_by, reviewed_at, review_result)
    VALUES
        (@PromotionId, N'V08测试活动', 'GENERAL', 3.00, 0.00,
         '2026-01-01', '2026-12-31', '2026-01-01', '2026-12-31', 100,
         'ALL', N'V08测试规则', 'ACTIVE', 202, '2026-01-01', 'APPROVED');

    INSERT INTO dbo.UserCoupon
        (user_coupon_id, promotion_id, user_id, coupon_code, face_value, min_spend,
         issued_at, valid_start_at, valid_end_at, status)
    VALUES
        (@UnusedCouponId, @PromotionId, @UserId, 'V08-CODE-U-' + @Token, 3.00, 0.00,
         '2026-10-01', '2026-10-01', '2026-12-31', 'UNUSED'),
        (@UsedCouponId, @PromotionId, @OtherUserId, 'V08-CODE-R-' + @Token, 3.00, 0.00,
         '2026-10-01', '2026-10-01', '2026-12-31', 'USED');

    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, start_time, end_time, energy_kwh, status,
         opening_station_id)
    VALUES
        ('PERSONAL', @OtherUserId, @GunId, '2026-10-15T10:00:00',
         '2026-10-15T11:00:00', 1.000, 'PENDING_PAYMENT', @StationId);
    SET @OrderId = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.CouponRedemption (user_coupon_id, order_id, redeemed_amount)
    VALUES (@UsedCouponId, @OrderId, 2.00);

    IF (SELECT COUNT(*) FROM dbo.v_A2CouponRedemptionTrace
        WHERE user_coupon_id IN (@UnusedCouponId, @UsedCouponId)) <> 2
        THROW 52002, 'V08 did not return exactly one row per coupon.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A2CouponRedemptionTrace
        WHERE user_coupon_id = @UnusedCouponId AND coupon_status = 'UNUSED'
          AND coupon_redemption_id IS NULL AND order_id IS NULL
          AND coupon_redemption_state_matches = 1)
        THROW 52003, 'V08 did not preserve the unredeemed coupon.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A2CouponRedemptionTrace
        WHERE user_coupon_id = @UsedCouponId AND coupon_status = 'USED'
          AND order_id = @OrderId AND redeemed_amount = 2.00
          AND coupon_redemption_state_matches = 1
          AND redemption_user_matches_coupon = 1)
        THROW 52004, 'V08 returned an incorrect redemption/order association.', 1;

    SELECT user_coupon_id, user_id, promotion_id, coupon_status,
           coupon_redemption_id, order_id, order_status, redeemed_amount,
           coupon_redemption_state_matches, redemption_user_matches_coupon
    FROM dbo.v_A2CouponRedemptionTrace
    WHERE user_coupon_id IN (@UnusedCouponId, @UsedCouponId)
    ORDER BY user_coupon_id;
    SELECT N'V08 优惠券核销追溯' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

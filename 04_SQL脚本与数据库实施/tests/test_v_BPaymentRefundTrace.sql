-- V06 回归测试：多笔支付/退款预聚合，不发生多对多金额倍增。
-- 所有夹具在 EV_B_TEST 的事务中回滚。

SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51700, 'This test must run in EV_B_TEST.', 1;
IF OBJECT_ID(N'dbo.v_BPaymentRefundTrace', N'V') IS NULL
    THROW 51701, 'Install dbo.v_BPaymentRefundTrace before this test.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @OperatorId VARCHAR(20) = 'V06OP' + @Token;
DECLARE @StationId VARCHAR(20) = 'V06ST' + @Token;
DECLARE @PileId VARCHAR(20) = 'V06PL' + @Token;
DECLARE @GunId VARCHAR(20) = 'V06GN' + @Token;
DECLARE @UserId VARCHAR(20) = 'TST_V06_U' + @Token;
DECLARE @OrderWithPayments BIGINT;
DECLARE @OrderWithoutPayments BIGINT;
DECLARE @PaymentOne BIGINT;
DECLARE @PaymentTwo BIGINT;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Complete the R-domain parents using the installed roles and this test's own identities.
    DECLARE @FixtureAccounts TABLE (username VARCHAR(50) PRIMARY KEY, account_id BIGINT NOT NULL);
    INSERT INTO dbo.SysAccount (username, password_hash, role_id)
    OUTPUT INSERTED.username, INSERTED.account_id INTO @FixtureAccounts (username, account_id)
    SELECT f.username, 'REPLACE_WITH_REAL_PASSWORD_HASH', r.role_id
    FROM (VALUES
        ('TST_V06_A' + @Token, 'R01'),
        (@UserId, 'R04')
    ) f(username, role_code)
    JOIN dbo.SysRole r ON r.role_code = f.role_code;
    IF @@ROWCOUNT <> 2
        THROW 52990, 'Install the required R roles before running this fixture.', 1;
    DECLARE @NoticeAccountId BIGINT = (SELECT account_id FROM @FixtureAccounts WHERE username = 'TST_V06_A' + @Token);

    INSERT INTO dbo.UserProfile
        (user_id, account_id, phone_ciphertext, phone_hash, real_name_status, registered_at, status)
    SELECT f.username, f.account_id, 0x00, CONVERT(CHAR(64), HASHBYTES('SHA2_256', f.username), 2),
           'UNVERIFIED', '2026-01-01', 'ACTIVE'
    FROM @FixtureAccounts f
    WHERE f.username IN (@UserId);

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@OperatorId, N'V06测试运营商');
    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
    VALUES
        (@StationId, N'V06测试场站', N'测试地址', 116.400000, 39.900000, @OperatorId,
         1, N'00:00-24:00', N'测试', @NoticeAccountId);
    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw, communication_protocol,
         commissioned_date, warranty_end_date, status)
    VALUES
        (@PileId, @StationId, N'V06-MODEL', 60.00, N'OCPP', '2026-01-01', '2028-01-01', 'IDLE');
    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
         max_output_power_kw, status)
    VALUES
        (@GunId, @PileId, 1, 'DC_FAST', N'GB/T', 60.00, 'IDLE');

    INSERT INTO dbo.ChargingOrder
        (order_type, user_id, gun_id, start_time, end_time, energy_kwh, status,
         opening_station_id)
    VALUES
        ('PERSONAL', @UserId, @GunId, '2026-10-15T10:00:00',
         '2026-10-15T11:00:00', 1.000, 'PENDING_PAYMENT', @StationId),
        ('PERSONAL', @UserId, @GunId, '2026-10-15T12:00:00',
         '2026-10-15T13:00:00', 1.000, 'PENDING_PAYMENT', @StationId);
    SELECT @OrderWithPayments = MIN(order_id), @OrderWithoutPayments = MAX(order_id)
    FROM dbo.ChargingOrder
    WHERE user_id = @UserId;

    INSERT INTO dbo.PaymentRecord
        (order_id, pay_channel, transaction_no, pay_amount, refund_amount, pay_time)
    VALUES
        (@OrderWithPayments, 'WECHAT', 'V06-' + @Token + '-P1', 3.00, 1.00, '2026-10-15T11:05:00'),
        (@OrderWithPayments, 'ALIPAY', 'V06-' + @Token + '-P2', 5.00, 0.50, '2026-10-15T11:10:00');
    SELECT @PaymentOne = MIN(payment_id), @PaymentTwo = MAX(payment_id)
    FROM dbo.PaymentRecord
    WHERE order_id = @OrderWithPayments;

    INSERT INTO dbo.RefundRecord
        (payment_id, refund_no, refund_amount, status, refunded_at)
    VALUES
        (@PaymentOne, 'V06-' + @Token + '-R1', 1.00, 'SUCCESS', '2026-10-16T09:00:00'),
        (@PaymentOne, 'V06-' + @Token + '-R2', 2.00, 'PROCESSING', NULL),
        (@PaymentTwo, 'V06-' + @Token + '-R3', 0.50, 'SUCCESS', '2026-10-16T09:10:00'),
        (@PaymentTwo, 'V06-' + @Token + '-R4', 1.00, 'FAILED', NULL);

    IF (SELECT COUNT(*) FROM dbo.v_BPaymentRefundTrace
        WHERE order_id IN (@OrderWithPayments, @OrderWithoutPayments)) <> 2
        THROW 51702, 'V06 did not return one row per order.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_BPaymentRefundTrace
        WHERE order_id = @OrderWithPayments
          AND payment_record_count = 2 AND payment_amount = 8.00
          AND payment_refund_amount = 1.50 AND refund_record_count = 4
          AND successful_refund_amount = 1.50 AND processing_refund_amount = 2.00
          AND failed_refund_amount = 1.00 AND cancelled_refund_amount = 0.00)
        THROW 51703, 'V06 payment/refund aggregation multiplied or misclassified amounts.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_BPaymentRefundTrace
        WHERE order_id = @OrderWithoutPayments AND payment_record_count = 0
          AND payment_amount = 0.00 AND payment_refund_amount = 0.00
          AND refund_record_count = 0 AND successful_refund_amount = 0.00)
        THROW 51704, 'V06 did not preserve an order without payment records.', 1;

    SELECT order_id, payment_record_count, payment_amount, payment_refund_amount,
           refund_record_count, successful_refund_amount, processing_refund_amount,
           failed_refund_amount, cancelled_refund_amount
    FROM dbo.v_BPaymentRefundTrace
    WHERE order_id IN (@OrderWithPayments, @OrderWithoutPayments)
    ORDER BY order_id;
    SELECT N'V06 支付退款预聚合与无支付订单保留' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

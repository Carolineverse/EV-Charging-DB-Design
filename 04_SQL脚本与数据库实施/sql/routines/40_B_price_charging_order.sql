CREATE OR ALTER PROCEDURE dbo.usp_PriceChargingOrder
    @order_id BIGINT,
    @discount_amount DECIMAL(12,2) = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @@TRANCOUNT = 0
    BEGIN
        SELECT 'TRANSACTION_REQUIRED' AS result_code,
               N'核价必须在调用方事务中执行。' AS message;
        RETURN;
    END;

    DECLARE @order_type VARCHAR(20);
    DECLARE @opening_station_id VARCHAR(20);
    DECLARE @start_time DATETIME2(3);
    DECLARE @end_time DATETIME2(3);
    DECLARE @energy_kwh DECIMAL(10,3);
    DECLARE @status VARCHAR(20);
    DECLARE @stored_gross_amount DECIMAL(12,2);
    DECLARE @stored_minimum_adjustment DECIMAL(12,2);
    DECLARE @stored_discount DECIMAL(12,2);
    DECLARE @startup_rule_version_id BIGINT;
    DECLARE @priced_at DATETIME2(3);

    SELECT @order_type = order_type,
           @opening_station_id = opening_station_id,
           @start_time = start_time,
           @end_time = end_time,
           @energy_kwh = energy_kwh,
           @status = status,
           @stored_gross_amount = gross_amount,
           @stored_minimum_adjustment = minimum_adjustment,
           @stored_discount = discount_amount,
           @startup_rule_version_id = startup_rule_version_id,
           @priced_at = priced_at
    FROM dbo.ChargingOrder WITH (UPDLOCK, HOLDLOCK)
    WHERE order_id = @order_id;

    IF @status IS NULL
    BEGIN
        SELECT 'ORDER_NOT_FOUND' AS result_code,
               N'订单不存在。' AS message;
        RETURN;
    END;

    IF @order_type <> 'PERSONAL'
    BEGIN
        SELECT 'UNSUPPORTED_ORDER_TYPE' AS result_code,
               N'当前核价过程仅支持个人订单。' AS message;
        RETURN;
    END;

    IF @start_time IS NULL OR @end_time IS NULL OR @end_time < @start_time
       OR @startup_rule_version_id IS NULL
       OR (@priced_at IS NULL AND @status NOT IN ('CHARGING', 'PENDING_PAYMENT'))
    BEGIN
        SELECT 'ORDER_NOT_READY' AS result_code,
               N'订单缺少确认时间或冻结计费版本，或订单状态不可核价。' AS message;
        RETURN;
    END;

    IF @discount_amount IS NULL OR @discount_amount < 0
    BEGIN
        SELECT 'DISCOUNT_INVALID' AS result_code,
               N'优惠金额不得为空或为负数。' AS message;
        RETURN;
    END;

    DECLARE @version_station_id VARCHAR(20);
    DECLARE @version_enterprise_id VARCHAR(20);
    DECLARE @free_minutes INT;
    DECLARE @minimum_amount DECIMAL(12,2);
    DECLARE @effective_from DATETIME2(3);
    DECLARE @effective_to DATETIME2(3);

    SELECT @version_station_id = station_id,
           @version_enterprise_id = enterprise_id,
           @free_minutes = free_minutes,
           @minimum_amount = minimum_amount,
           @effective_from = effective_from,
           @effective_to = effective_to
    FROM dbo.BillingRuleVersion WITH (HOLDLOCK)
    WHERE rule_version_id = @startup_rule_version_id;

    IF @version_station_id IS NULL
       OR @version_station_id <> @opening_station_id
       OR @version_enterprise_id IS NOT NULL
       OR @start_time < @effective_from
       OR (@effective_to IS NOT NULL AND @start_time >= @effective_to)
    BEGIN
        SELECT 'PRICING_RULE_MISMATCH' AS result_code,
               N'冻结计费版本不存在、不适用于该场站/订单，或在开单时尚未生效。' AS message;
        RETURN;
    END;

    CREATE TABLE #FeeSegments
    (
        order_fee_detail_id BIGINT NOT NULL PRIMARY KEY,
        segment_start DATETIME2(3) NOT NULL,
        segment_end DATETIME2(3) NOT NULL,
        segment_energy_kwh DECIMAL(10,3) NOT NULL,
        free_service_fee DECIMAL(12,2) NOT NULL,
        rule_version_id BIGINT NOT NULL,
        electricity_price DECIMAL(10,4) NOT NULL,
        service_price DECIMAL(10,4) NOT NULL,
        period_start_time TIME(0) NOT NULL,
        period_end_time TIME(0) NOT NULL
    );

    INSERT INTO #FeeSegments
        (order_fee_detail_id, segment_start, segment_end, segment_energy_kwh,
         free_service_fee, rule_version_id, electricity_price, service_price,
         period_start_time, period_end_time)
    SELECT d.order_fee_detail_id,
           d.segment_start,
           d.segment_end,
           d.segment_energy_kwh,
           d.free_service_fee,
           r.rule_version_id,
           r.electricity_price,
           r.service_price,
           r.period_start_time,
           r.period_end_time
    FROM dbo.OrderFeeDetail AS d WITH (HOLDLOCK)
    JOIN dbo.BillingRule AS r WITH (HOLDLOCK)
      ON r.billing_rule_id = d.billing_rule_id
    WHERE d.order_id = @order_id;

    IF @energy_kwh <> 0 AND NOT EXISTS (SELECT 1 FROM #FeeSegments)
    BEGIN
        SELECT 'PRICING_INPUT_INSUFFICIENT' AS result_code,
               N'计费输入不足：缺少可信的费用段电量。' AS message;
        RETURN;
    END;

    DECLARE @allocated_energy DECIMAL(38,3);
    SELECT @allocated_energy = COALESCE(SUM(segment_energy_kwh), 0)
    FROM #FeeSegments;

    IF @allocated_energy <> @energy_kwh
    BEGIN
        SELECT 'PRICING_INPUT_INSUFFICIENT' AS result_code,
               N'计费输入不足：分段电量合计与订单核定电量不一致。' AS message;
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM #FeeSegments
        WHERE rule_version_id <> @startup_rule_version_id
           OR NOT (
                (period_start_time < period_end_time
                 AND CONVERT(date, segment_start) = CONVERT(date, segment_end)
                 AND CONVERT(time(0), segment_start) >= period_start_time
                 AND CONVERT(time(0), segment_end) <= period_end_time)
                OR
                (period_start_time > period_end_time
                 AND CONVERT(date, segment_start) = CONVERT(date, segment_end)
                 AND (CONVERT(time(0), segment_start) >= period_start_time
                      OR CONVERT(time(0), segment_end) <= period_end_time))
                OR
                (period_start_time > period_end_time
                 AND CONVERT(date, segment_end) = DATEADD(day, 1, CONVERT(date, segment_start))
                 AND CONVERT(time(0), segment_start) >= period_start_time
                 AND CONVERT(time(0), segment_end) <= period_end_time)
           )
    )
    BEGIN
        SELECT 'PRICING_RULE_MISMATCH' AS result_code,
               N'费用段引用了错误版本或不适用的计费时段。' AS message;
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM
        (
            SELECT segment_start,
                   segment_end,
                   ROW_NUMBER() OVER (ORDER BY segment_start, order_fee_detail_id) AS row_no,
                   LAG(segment_end) OVER (ORDER BY segment_start, order_fee_detail_id) AS previous_end
            FROM #FeeSegments
        ) AS ordered_segments
        WHERE segment_end <= segment_start
           OR (row_no = 1 AND segment_start <> @start_time)
           OR (row_no > 1 AND segment_start <> previous_end)
    )
       OR (EXISTS (SELECT 1 FROM #FeeSegments)
           AND (SELECT MAX(segment_end) FROM #FeeSegments) <> @end_time)
    BEGIN
        SELECT 'FEE_SEGMENTS_INVALID' AS result_code,
               N'费用段必须按时间连续覆盖订单区间，不能断档或重叠。' AS message;
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM #FeeSegments
        WHERE free_service_fee < 0
           OR free_service_fee > ROUND(segment_energy_kwh * service_price, 2)
    )
    BEGIN
        SELECT 'FEE_SEGMENTS_INVALID' AS result_code,
               N'分段免费服务费不得为负或超过该段折前服务费。' AS message;
        RETURN;
    END;

    DECLARE @electricity_base DECIMAL(12,2);
    DECLARE @service_before_free DECIMAL(12,2);
    DECLARE @free_service_fee DECIMAL(12,2);
    DECLARE @service_base DECIMAL(12,2);
    DECLARE @minimum_adjustment DECIMAL(12,2);
    DECLARE @gross_amount DECIMAL(12,2);
    DECLARE @payable_amount DECIMAL(12,2);

    SELECT @electricity_base = COALESCE(CAST(SUM(ROUND(segment_energy_kwh * electricity_price, 2)) AS DECIMAL(12,2)), 0),
           @service_before_free = COALESCE(CAST(SUM(ROUND(segment_energy_kwh * service_price, 2)) AS DECIMAL(12,2)), 0),
           @free_service_fee = COALESCE(CAST(SUM(free_service_fee) AS DECIMAL(12,2)), 0)
    FROM #FeeSegments;

    SET @service_base = @service_before_free - @free_service_fee;
    IF @service_base < 0
    BEGIN
        SELECT 'FEE_SEGMENTS_INVALID' AS result_code,
               N'免费服务费合计超过折前服务费。' AS message;
        RETURN;
    END;

    SET @minimum_adjustment =
        CASE WHEN @energy_kwh > 0 AND @minimum_amount > @electricity_base + @service_base
             THEN @minimum_amount - @electricity_base - @service_base
             ELSE 0 END;
    SET @gross_amount = @electricity_base + @service_base + @minimum_adjustment;

    IF @discount_amount > @gross_amount
    BEGIN
        SELECT 'DISCOUNT_INVALID' AS result_code,
               N'优惠金额不得超过订单优惠前总额。' AS message;
        RETURN;
    END;

    SET @payable_amount = @gross_amount - @discount_amount;

    IF @priced_at IS NOT NULL
    BEGIN
        IF @discount_amount <> @stored_discount
           OR @gross_amount <> @stored_gross_amount
           OR @minimum_adjustment <> @stored_minimum_adjustment
        BEGIN
            SELECT 'PRICING_ALREADY_FINALIZED' AS result_code,
                   N'订单已使用不同优惠或费用事实发生变化，不能重复核价。' AS message;
            RETURN;
        END;

        SELECT 'OK' AS result_code,
               N'' AS message,
               @electricity_base AS electricity_base,
               @service_before_free AS service_before_free,
               @free_service_fee AS free_service_fee,
               @service_base AS service_base,
               @minimum_adjustment AS minimum_adjustment,
               @gross_amount AS gross_amount,
               @discount_amount AS discount_amount,
               @payable_amount AS payable_amount,
               @free_minutes AS free_minutes_applied,
               CAST(1 AS BIT) AS is_idempotent;
        RETURN;
    END;

    UPDATE dbo.ChargingOrder
    SET gross_amount = @gross_amount,
        minimum_adjustment = @minimum_adjustment,
        discount_amount = @discount_amount,
        status = 'PENDING_PAYMENT',
        priced_at = SYSDATETIME(),
        updated_at = SYSDATETIME()
    WHERE order_id = @order_id
      AND priced_at IS NULL;

    SELECT 'OK' AS result_code,
           N'' AS message,
           @electricity_base AS electricity_base,
           @service_before_free AS service_before_free,
           @free_service_fee AS free_service_fee,
           @service_base AS service_base,
           @minimum_adjustment AS minimum_adjustment,
           @gross_amount AS gross_amount,
           @discount_amount AS discount_amount,
           @payable_amount AS payable_amount,
           @free_minutes AS free_minutes_applied,
           CAST(0 AS BIT) AS is_idempotent;
END;
GO

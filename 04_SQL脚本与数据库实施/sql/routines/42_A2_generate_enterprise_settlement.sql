CREATE OR ALTER PROCEDURE dbo.usp_A2_GenerateEnterpriseSettlement
    @enterprise_settlement_id VARCHAR(20),
    @enterprise_id VARCHAR(20),
    @billing_period_start DATE,
    @generated_at DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    IF @enterprise_settlement_id IS NULL
       OR LEN(LTRIM(RTRIM(@enterprise_settlement_id))) = 0
        THROW 52400, 'A non-empty enterprise settlement ID is required.', 1;
    IF @enterprise_id IS NULL OR LEN(LTRIM(RTRIM(@enterprise_id))) = 0
        THROW 52401, 'A non-empty enterprise ID is required.', 1;
    IF @billing_period_start IS NULL OR DAY(@billing_period_start) <> 1
        THROW 52402, 'The billing period must be the first day of a month.', 1;

    DECLARE @owns_transaction BIT = 0;
    DECLARE @effective_generated_at DATETIME2(3) = COALESCE(@generated_at, SYSDATETIME());

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @owns_transaction = 1;
        END
        ELSE
            SAVE TRANSACTION A2GenerateSettleSave;

        -- The unique enterprise/month index protects this key range during concurrent generation.
        IF EXISTS
        (
            SELECT 1
            FROM dbo.EnterpriseSettlement WITH (UPDLOCK, HOLDLOCK)
            WHERE enterprise_id = @enterprise_id
              AND billing_period_start = @billing_period_start
        )
            THROW 52403, 'An enterprise settlement already exists for this billing month.', 1;

        CREATE TABLE #EligibleOrders
        (
            order_id BIGINT NOT NULL PRIMARY KEY,
            fleet_member_id VARCHAR(20) NOT NULL,
            vehicle_id VARCHAR(20) NOT NULL,
            payable_amount DECIMAL(12,2) NOT NULL,
            energy_kwh DECIMAL(12,3) NOT NULL
        );

        INSERT INTO #EligibleOrders
            (order_id, fleet_member_id, vehicle_id, payable_amount, energy_kwh)
        SELECT o.order_id,
               fm.fleet_member_id,
               v.vehicle_id,
               CAST(o.gross_amount - o.discount_amount AS DECIMAL(12,2)),
               o.energy_kwh
        FROM dbo.ChargingOrder AS o WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.EnterpriseCardBinding AS b WITH (HOLDLOCK)
            ON b.binding_id = o.binding_id
           AND o.start_time >= b.effective_start_at
           AND (b.effective_end_at IS NULL OR o.start_time < b.effective_end_at)
        INNER JOIN dbo.EnterpriseCard AS c WITH (HOLDLOCK)
            ON c.enterprise_card_id = b.enterprise_card_id
           AND c.enterprise_id = @enterprise_id
        INNER JOIN dbo.FleetMember AS fm WITH (HOLDLOCK)
            ON fm.fleet_member_id = b.fleet_member_id
           AND fm.enterprise_id = @enterprise_id
           AND fm.user_id = o.user_id
           AND fm.joined_at <= o.start_time
           AND (fm.left_at IS NULL OR o.start_time < fm.left_at)
        INNER JOIN dbo.Vehicle AS v WITH (HOLDLOCK)
            ON v.vehicle_id = b.vehicle_id
           AND v.enterprise_id = @enterprise_id
           AND v.user_id IS NULL
        INNER JOIN dbo.EnterpriseQuota AS q WITH (HOLDLOCK)
            ON q.enterprise_quota_id = o.enterprise_quota_id
           AND q.fleet_member_id = fm.fleet_member_id
           AND q.quota_month = DATEFROMPARTS(YEAR(o.start_time), MONTH(o.start_time), 1)
        INNER JOIN dbo.BillingRuleVersion AS rv WITH (HOLDLOCK)
            ON rv.rule_version_id = o.startup_rule_version_id
           AND rv.station_id = o.opening_station_id
           AND rv.enterprise_id = @enterprise_id
           AND o.start_time >= rv.effective_from
           AND (rv.effective_to IS NULL OR o.start_time < rv.effective_to)
        WHERE o.order_type = 'ENTERPRISE'
          AND o.status = 'PAID'
          AND o.settled_at IS NOT NULL
          AND o.priced_at IS NOT NULL
          AND o.start_time IS NOT NULL
          AND o.end_time >= @billing_period_start
          AND o.end_time < DATEADD(MONTH, 1, @billing_period_start)
          AND o.energy_kwh > 0
          AND o.gross_amount >= o.discount_amount
          AND o.order_type = 'ENTERPRISE';

        IF EXISTS
        (
            SELECT 1
            FROM dbo.ChargingOrder AS o
            INNER JOIN #EligibleOrders AS eligible ON eligible.order_id = o.order_id
            WHERE EXISTS
            (
                SELECT 1 FROM dbo.EnterpriseSettlementDetail AS existing_detail
                WHERE existing_detail.order_id = o.order_id
            )
        )
            THROW 52404, 'An eligible enterprise order is already present in a settlement detail.', 1;

        INSERT INTO dbo.EnterpriseSettlement
            (enterprise_settlement_id, enterprise_id, billing_period_start,
             total_order_count, total_energy_kwh, total_amount,
             generated_at, created_at, updated_at)
        SELECT @enterprise_settlement_id,
               @enterprise_id,
               @billing_period_start,
               COUNT(*),
               COALESCE(SUM(energy_kwh), 0),
               COALESCE(SUM(payable_amount), 0),
               @effective_generated_at,
               @effective_generated_at,
               @effective_generated_at
        FROM #EligibleOrders;

        INSERT INTO dbo.EnterpriseSettlementDetail
            (enterprise_settlement_id, order_id, fleet_member_id, vehicle_id,
             payable_amount, energy_kwh, created_at)
        SELECT @enterprise_settlement_id,
               order_id,
               fleet_member_id,
               vehicle_id,
               payable_amount,
               energy_kwh,
               @effective_generated_at
        FROM #EligibleOrders;

        IF @owns_transaction = 1 COMMIT TRANSACTION;

        SELECT @enterprise_settlement_id AS enterprise_settlement_id,
               COUNT(*) AS order_count,
               COALESCE(SUM(energy_kwh), 0) AS total_energy_kwh,
               COALESCE(SUM(payable_amount), 0) AS total_amount
        FROM #EligibleOrders;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @owns_transaction = 1
                ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1
                ROLLBACK TRANSACTION A2GenerateSettleSave;
        END;
        THROW;
    END CATCH;
END;
GO

-- =============================================================
-- [D] 生成站月结算单（依赖 B 的 v_OrderSettlementSource + R 的事项分派）
-- 权限：该场站|账期必须已分派给 @assigned_account_id，且生成人即获派专员
-- 接口约定（B 的视图必须按此列名）：
--   order_id, station_id, settlement_source(PERSONAL/ENTERPRISE), ended_at,
--   settled_at, energy_kwh, electricity_base, service_base, minimum_adjustment,
--   refund_state_snapshot(NONE/FAILED_CANCELLED), is_settleable(BIT), unsettleable_reason
-- =============================================================
CREATE PROCEDURE dbo.usp_GenerateSettlement
    @station_id          VARCHAR(20),
    @period_month        CHAR(6),
    @assigned_account_id BIGINT,
    @created_by          BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @now DATETIME2(3) = SYSDATETIME();
        DECLARE @period_start DATE = TRY_CONVERT(date, @period_month + '01', 112);
        DECLARE @period_end   DATE = DATEADD(month, 1, @period_start);
        DECLARE @settlement_id BIGINT;
        DECLARE @platform_rate DECIMAL(7,6);

        IF @period_start IS NULL THROW 50010, N'账期格式错误', 1;

        -- 权限：该场站|账期已分派给当前专员，且生成人 = 获派专员本人
        IF NOT EXISTS (
            SELECT 1 FROM dbo.ServiceCaseAssignment WITH (UPDLOCK, HOLDLOCK)
            WHERE case_type = 'SETTLEMENT_GENERATE'
              AND case_id   = @station_id + '|' + @period_month
              AND assigned_account_id = @assigned_account_id
              AND effective_from <= @now
              AND (effective_to IS NULL OR effective_to > @now)
        )
            THROW 50014, N'该场站账期未分派给当前专员，或无有效分派', 1;
        IF @created_by <> @assigned_account_id
            THROW 50015, N'生成人必须为获派专员本人', 1;

        IF EXISTS (SELECT 1 FROM dbo.SettlementStatement WITH (UPDLOCK, HOLDLOCK)
                   WHERE station_id = @station_id AND period_month = @period_month)
            THROW 50011, N'该场站该账期已生成结算单', 1;

        -- 月初取值。分别核对两层候选数，包括被站级费率覆盖的默认档。
        DECLARE @station_count INT, @operator_count INT, @default_rate DECIMAL(7,6);
        SELECT @station_count = COUNT(*), @platform_rate = MAX(platform_rate)
        FROM dbo.OperatorSettlementRate WITH (HOLDLOCK)
        WHERE station_id = @station_id AND effective_from <= @period_start
          AND (effective_to IS NULL OR effective_to > @period_start) AND status = 'ACTIVE';

        SELECT @operator_count = COUNT(*), @default_rate = MAX(r.platform_rate)
        FROM dbo.ChargingStation s
        JOIN dbo.OperatorSettlementRate r WITH (HOLDLOCK) ON r.operator_id = s.operator_id
        WHERE s.station_id = @station_id AND r.station_id IS NULL
          AND r.effective_from <= @period_start
          AND (r.effective_to IS NULL OR r.effective_to > @period_start) AND r.status = 'ACTIVE';

        IF @station_count > 1 OR @operator_count > 1
            THROW 50149, N'结算费率同级有效区间重叠', 1;
        SET @platform_rate = COALESCE(@platform_rate, @default_rate);
        IF @platform_rate IS NULL THROW 50012, N'未配置结算费率', 1;

        INSERT INTO dbo.SettlementStatement (station_id, period_month, platform_rate, status, assigned_account_id, created_by, created_at)
        VALUES (@station_id, @period_month, @platform_rate, 0, @assigned_account_id, @created_by, @now);
        SET @settlement_id = SCOPE_IDENTITY();

        INSERT INTO dbo.SettlementDetail (settlement_id, order_id, ended_at_snapshot, energy_snapshot,
                                          electricity_base, service_base, minimum_adjustment, created_at,
                                          settled_at_snapshot, settlement_source, eligibility_checked_at, refund_state_snapshot)
        SELECT @settlement_id, src.order_id, src.ended_at, src.energy_kwh,
               src.electricity_base, src.service_base, src.minimum_adjustment, @now,
               src.settled_at, src.settlement_source, @now, src.refund_state_snapshot
        FROM dbo.v_OrderSettlementSource src
        WHERE src.station_id = @station_id
          AND src.ended_at >= @period_start AND src.ended_at < @period_end
          AND src.is_settleable = 1
          AND src.settled_at <= @now
          AND NOT EXISTS (
              SELECT 1 FROM dbo.SettlementDetail existing WITH (UPDLOCK, HOLDLOCK)
              WHERE existing.order_id = src.order_id
          );

        IF @@ROWCOUNT = 0
            THROW 50013, N'该场站账期没有可入单订单', 1;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('D', 'SETTLEMENT', CONVERT(varchar(50), @settlement_id), 'GENERATE_SETTLEMENT', 'HUMAN', @created_by, @now,
                N'{"period_month":"' + @period_month + N'"}');

        COMMIT TRANSACTION;
        SELECT @settlement_id AS settlement_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

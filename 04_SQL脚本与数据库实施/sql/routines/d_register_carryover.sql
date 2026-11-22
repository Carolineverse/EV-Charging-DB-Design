-- 登记锁定后退款的运营商扣回。审批与应用各自为独立业务操作。
CREATE PROCEDURE dbo.usp_RegisterCarryover
    @settlement_id BIGINT,
    @refund_id BIGINT,
    @target_settlement_id BIGINT,
    @adjustment_amount DECIMAL(18,2),
    @assessment_evidence NVARCHAR(500),
    @created_by BIGINT,
    @carryover_id BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @order_id BIGINT, @refunded_at DATETIME2(3), @confirmed_at DATETIME2(3);
        DECLARE @station_id VARCHAR(20), @period_month CHAR(6), @target_month CHAR(6);

        SELECT @order_id = p.order_id, @refunded_at = r.refunded_at
        FROM dbo.RefundRecord r
        JOIN dbo.PaymentRecord p ON p.payment_id = r.payment_id
        WHERE r.refund_id = @refund_id AND r.status = 'SUCCESS';
        IF @order_id IS NULL THROW 50123, N'退款不存在或未成功', 1;
        EXEC dbo.usp_LockSettlementRefundOrder @order_id;

        SELECT @station_id = station_id, @period_month = period_month, @confirmed_at = confirmed_at
        FROM dbo.SettlementStatement WITH (UPDLOCK, HOLDLOCK)
        WHERE settlement_id = @settlement_id AND status IN (1,2);
        IF @confirmed_at IS NULL THROW 50121, N'原结算单未终审锁定', 1;
        IF @refunded_at IS NULL OR @refunded_at <= @confirmed_at
            THROW 50124, N'退款必须发生在原单锁定之后', 1;

        SELECT @target_month = period_month
        FROM dbo.SettlementStatement WITH (UPDLOCK, HOLDLOCK)
        WHERE settlement_id = @target_settlement_id AND station_id = @station_id
          AND period_month > @period_month AND status = 0 AND assigned_account_id = @created_by;
        IF @target_month IS NULL THROW 50127, N'目标单须为获派的同站后期待对账单', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE account_id = @created_by AND role_id = 3 AND status = 1)
            THROW 50122, N'登记人须为启用的 R03 专员', 1;
        IF NULLIF(LTRIM(RTRIM(@assessment_evidence)), N'') IS NULL THROW 50130, N'登记须有核验依据', 1;
        IF EXISTS (SELECT 1 FROM dbo.SettlementCarryoverAdjustment WHERE refund_id = @refund_id)
            THROW 50129, N'该退款已有结转记录', 1;

        EXEC dbo.usp_CheckSettlementRefundAmount @settlement_id, @order_id, @refund_id, @adjustment_amount;

        DECLARE @inserted TABLE (id BIGINT);
        INSERT INTO dbo.SettlementCarryoverAdjustment
            (original_settlement_id, refund_id, target_period_month, adjustment_amount,
             status, created_by, assessment_evidence)
        OUTPUT inserted.carryover_adjustment_id INTO @inserted
        VALUES (@settlement_id, @refund_id, @target_month, @adjustment_amount, 'PENDING', @created_by, @assessment_evidence);
        SELECT @carryover_id = id FROM @inserted;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('D', 'CARRYOVER', CONVERT(VARCHAR(50), @carryover_id), 'REGISTER_CARRYOVER',
                'HUMAN', @created_by, SYSDATETIME(), N'{"status":"PENDING"}');
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

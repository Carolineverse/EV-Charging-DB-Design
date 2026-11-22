-- =============================================================
-- D 线 · 结算流程过程 + 完整性保护触发器
-- 金额口径（设计 5.5.4）：
--   adjustment_amount 只汇总「已关闭差异合计」；
--   结转 APPLIED 由 v_SettlementLedger 单独读取，不写回 adjustment_amount。
-- =============================================================

-- 按订单串行化两种退款扣回。事务结束时自动释放。
CREATE PROCEDURE dbo.usp_LockSettlementRefundOrder @order_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF @order_id IS NULL OR @@TRANCOUNT = 0
        THROW 50140, N'退款扣回必须关联订单并在事务内办理', 1;

    DECLARE @resource NVARCHAR(255) = CONCAT(N'D:SettlementRefund:Order:', @order_id);
    DECLARE @result INT;
    EXEC @result = sys.sp_getapplock
        @Resource = @resource, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
    IF @result < 0 THROW 50141, N'无法取得订单退款扣回锁', 1;
END
GO

-- 调用方先取得订单锁。运营商基础收益使用台账相同的逐笔佣金舍入。
CREATE PROCEDURE dbo.usp_CheckSettlementRefundAmount
    @settlement_id BIGINT, @order_id BIGINT, @refund_id BIGINT,
    @amount DECIMAL(18,2), @carryover_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @amount IS NULL OR @amount >= 0
        THROW 50142, N'退款扣回金额必须为负数', 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.RefundRecord r
        JOIN dbo.PaymentRecord p ON p.payment_id = r.payment_id
        WHERE r.refund_id = @refund_id AND p.order_id = @order_id AND r.status = 'SUCCESS'
    ) THROW 50143, N'退款未成功或不属于指定订单', 1;

    DECLARE @limit DECIMAL(28,2), @difference DECIMAL(28,2), @carryover DECIMAL(28,2);
    SELECT @limit = d.electricity_base + d.service_base + d.minimum_adjustment
                    - ROUND((d.service_base + d.minimum_adjustment) * s.platform_rate, 2)
    FROM dbo.SettlementDetail d
    JOIN dbo.SettlementStatement s ON s.settlement_id = d.settlement_id
    WHERE d.settlement_id = @settlement_id AND d.order_id = @order_id;
    IF @limit IS NULL THROW 50144, N'指定订单不在原结算单明细中', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.ReconciliationDifference
        WHERE refund_id = @refund_id AND difference_type = 4 AND status = 2
    ) OR EXISTS (
        SELECT 1 FROM dbo.SettlementCarryoverAdjustment
        WHERE refund_id = @refund_id AND status IN ('PENDING','APPROVED','APPLIED')
          AND (@carryover_id IS NULL OR carryover_adjustment_id <> @carryover_id)
    ) THROW 50145, N'同一退款已占用其他扣回路径', 1;

    SELECT @difference = COALESCE(SUM(difference_amount), 0)
    FROM dbo.ReconciliationDifference
    WHERE order_id = @order_id AND difference_type = 4 AND status = 2 AND difference_amount < 0;

    SELECT @carryover = COALESCE(SUM(c.adjustment_amount), 0)
    FROM dbo.SettlementCarryoverAdjustment c
    JOIN dbo.RefundRecord r ON r.refund_id = c.refund_id
    JOIN dbo.PaymentRecord p ON p.payment_id = r.payment_id
    WHERE p.order_id = @order_id AND c.status IN ('PENDING','APPROVED','APPLIED')
      AND (@carryover_id IS NULL OR c.carryover_adjustment_id <> @carryover_id);

    IF -(@difference + @carryover + @amount) > @limit
        THROW 50146, N'累计扣回超过原订单运营商收益', 1;
END
GO

-- ---------- 登记差异（R03 获派本人；类型4须有效退款）----------
CREATE PROCEDURE dbo.usp_RegisterDifference
    @settlement_id     BIGINT,
    @order_id          BIGINT,
    @difference_type   TINYINT,
    @difference_amount DECIMAL(12,2),
    @refund_id         BIGINT = NULL,
    @created_by        BIGINT,
    @difference_id     BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @st TINYINT, @assignee BIGINT;
        IF @difference_type = 4 EXEC dbo.usp_LockSettlementRefundOrder @order_id;

        SELECT @st = status, @assignee = assigned_account_id
        FROM dbo.SettlementStatement WITH (UPDLOCK, HOLDLOCK) WHERE settlement_id = @settlement_id;
        IF @st IS NULL THROW 50026, N'结算单不存在', 1;
        IF @st <> 0 THROW 50027, N'结算单不在待对账状态，不能登记差异', 1;
        IF @created_by <> @assignee THROW 50028, N'只能由获派专员本人登记差异', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.SettlementDetail WHERE settlement_id = @settlement_id AND order_id = @order_id)
            THROW 50029, N'订单不在该结算单明细中', 1;

        IF @difference_type = 4
        BEGIN
            IF @refund_id IS NULL THROW 50031, N'类型4（退款调整）必须填退款号', 1;
            EXEC dbo.usp_CheckSettlementRefundAmount
                @settlement_id, @order_id, @refund_id, @difference_amount;
        END
        ELSE
        BEGIN
            IF @refund_id IS NOT NULL THROW 50033, N'非类型4不应填退款号', 1;
        END;

        INSERT INTO dbo.ReconciliationDifference (settlement_id, order_id, difference_type, difference_amount, status, refund_id, created_by, created_at)
        VALUES (@settlement_id, @order_id, @difference_type, @difference_amount, 0, @refund_id, @created_by, SYSDATETIME());
        SET @difference_id = CONVERT(BIGINT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

-- ---------- 关闭差异（R01 审批；只累加差异额到 adjustment_amount）----------
CREATE PROCEDURE dbo.usp_CloseDifference
    @difference_id     BIGINT,
    @reviewed_by       BIGINT,
    @operator_evidence NVARCHAR(500),
    @resolution        NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @now DATETIME2(3) = SYSDATETIME();
        DECLARE @settlement_id BIGINT, @amount DECIMAL(12,2), @status TINYINT, @created_by BIGINT, @sst TINYINT;
        DECLARE @difference_type TINYINT, @refund_id BIGINT, @order_id BIGINT, @payable DECIMAL(28,2);
        SELECT @order_id = order_id, @difference_type = difference_type
        FROM dbo.ReconciliationDifference WHERE difference_id = @difference_id;
        IF @difference_type = 4 EXEC dbo.usp_LockSettlementRefundOrder @order_id;

        SELECT @settlement_id = settlement_id, @amount = difference_amount,
               @status = status, @created_by = created_by,
               @difference_type = difference_type, @refund_id = refund_id
        FROM dbo.ReconciliationDifference WITH (UPDLOCK, HOLDLOCK)
        WHERE difference_id = @difference_id;

        IF @settlement_id IS NULL THROW 50020, N'差异不存在', 1;
        IF @status NOT IN (0,1) THROW 50021, N'差异不在待处理或处理中状态', 1;
        IF @reviewed_by = @created_by THROW 50022, N'审批人与登记人不能相同', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE account_id = @reviewed_by AND role_id = 1 AND status = 1)
            THROW 50023, N'审批人必须是启用的 R01 管理员', 1;
        IF @operator_evidence IS NULL OR @operator_evidence = N'' THROW 50024, N'关闭须有运营商确认依据', 1;
        IF @resolution IS NULL OR @resolution = N'' THROW 50025, N'关闭须有处理结论', 1;

        SELECT @sst = status FROM dbo.SettlementStatement WITH (UPDLOCK, HOLDLOCK) WHERE settlement_id = @settlement_id;
        IF @sst IS NULL THROW 50039, N'所属结算单不存在', 1;
        IF @sst <> 0 THROW 50030, N'结算单不在待对账状态，不能关闭差异', 1;

        IF @difference_type = 4
            EXEC dbo.usp_CheckSettlementRefundAmount @settlement_id, @order_id, @refund_id, @amount;

        SELECT @payable = payable_amount FROM dbo.v_SettlementLedger WHERE settlement_id = @settlement_id;
        IF @payable IS NULL OR @payable + @amount < 0
            THROW 50147, N'关闭差异后最终应结不能为负', 1;

        UPDATE dbo.ReconciliationDifference
        SET status = 2, resolution = @resolution, operator_evidence = @operator_evidence,
            reviewed_by = @reviewed_by, reviewed_at = @now
        WHERE difference_id = @difference_id;

        UPDATE dbo.SettlementStatement
        SET adjustment_amount = adjustment_amount + @amount
        WHERE settlement_id = @settlement_id;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('D', 'DIFFERENCE', CONVERT(varchar(50), @difference_id), 'CLOSE_DIFFERENCE', 'HUMAN', @reviewed_by, @now, N'{"status":2}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

-- ---------- 终审锁定（R01；无待处理差异；零元直接完成）----------
CREATE PROCEDURE dbo.usp_ConfirmSettlement
    @settlement_id         BIGINT,
    @confirmed_by          BIGINT,
    @confirmation_evidence NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @now DATETIME2(3) = SYSDATETIME();
        DECLARE @status TINYINT, @created_by BIGINT, @payable DECIMAL(28,2);

        SELECT @status = status, @created_by = created_by
        FROM dbo.SettlementStatement WITH (UPDLOCK, HOLDLOCK)
        WHERE settlement_id = @settlement_id;

        IF @status IS NULL THROW 50040, N'结算单不存在', 1;
        IF @status <> 0 THROW 50041, N'结算单不在待对账状态', 1;
        IF @confirmed_by = @created_by THROW 50042, N'终审人不能是生成人', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE account_id = @confirmed_by AND role_id = 1 AND status = 1)
            THROW 50043, N'终审人必须是启用的 R01 管理员', 1;
        IF @confirmation_evidence IS NULL OR @confirmation_evidence = N'' THROW 50044, N'终审须有确认依据', 1;
        IF EXISTS (SELECT 1 FROM dbo.ReconciliationDifference WHERE settlement_id = @settlement_id AND status IN (0,1))
            THROW 50045, N'存在未关闭差异，不能终审', 1;

        SELECT @payable = payable_amount FROM dbo.v_SettlementLedger WHERE settlement_id = @settlement_id;

        IF @payable = 0
            UPDATE dbo.SettlementStatement
            SET status = 2, completed_at = @now, confirmed_by = @confirmed_by, confirmed_at = @now, confirmation_evidence = @confirmation_evidence
            WHERE settlement_id = @settlement_id;
        ELSE
            UPDATE dbo.SettlementStatement
            SET status = 1, confirmed_by = @confirmed_by, confirmed_at = @now, confirmation_evidence = @confirmation_evidence
            WHERE settlement_id = @settlement_id;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('D', 'SETTLEMENT', CONVERT(varchar(50), @settlement_id), 'CONFIRM_SETTLEMENT', 'HUMAN', @confirmed_by, @now, N'{"status":1}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

-- ---------- 登记蓝票（R03 获派本人；已确认才开；锁行；足额置完成）----------
CREATE PROCEDURE dbo.usp_RegisterInvoice
    @settlement_id BIGINT, @invoice_no VARCHAR(50), @invoice_title NVARCHAR(100),
    @tax_number VARCHAR(30), @amount DECIMAL(18,2), @created_by BIGINT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @now DATETIME2(3) = SYSDATETIME();
        DECLARE @payable DECIMAL(28,2), @invoiced DECIMAL(18,2), @st TINYINT, @assignee BIGINT;

        IF @amount <= 0 THROW 50050, N'蓝票金额必须为正', 1;
        IF @invoice_no IS NULL OR @invoice_no = '' THROW 50051, N'票号必填', 1;

        SELECT @st = status, @assignee = assigned_account_id
        FROM dbo.SettlementStatement WITH (UPDLOCK, HOLDLOCK) WHERE settlement_id = @settlement_id;
        IF @st IS NULL THROW 50052, N'结算单不存在', 1;
        IF @st <> 1 THROW 50053, N'结算单未确认（待补票），不能开票', 1;
        IF @created_by <> @assignee THROW 50054, N'只能由获派专员本人开票', 1;

        SELECT @payable = payable_amount FROM dbo.v_SettlementLedger WHERE settlement_id = @settlement_id;
        SELECT @invoiced = ISNULL(SUM(amount), 0) FROM dbo.SettlementInvoice WHERE settlement_id = @settlement_id AND status IN (1, -1);
        IF @invoiced + @amount > @payable THROW 50055, N'超出可开票余额', 1;

        INSERT INTO dbo.SettlementInvoice (settlement_id, invoice_no, invoice_title, tax_number, amount, status, created_by, created_at, issued_at)
        VALUES (@settlement_id, @invoice_no, @invoice_title, @tax_number, @amount, 1, @created_by, @now, @now);

        SELECT @invoiced = ISNULL(SUM(amount), 0) FROM dbo.SettlementInvoice WHERE settlement_id = @settlement_id AND status IN (1, -1);
        IF @invoiced >= @payable
            UPDATE dbo.SettlementStatement SET status = 2, completed_at = @now WHERE settlement_id = @settlement_id;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('D', 'INVOICE', @invoice_no, 'REGISTER_INVOICE', 'HUMAN', @created_by, @now, N'{"status":1}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

-- ---------- 红冲申请（R03 提出，status=0 待审批）----------
CREATE PROCEDURE dbo.usp_ApplyRedFlush
    @original_invoice_id BIGINT, @red_reason NVARCHAR(500), @created_by BIGINT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @now DATETIME2(3) = SYSDATETIME();
        DECLARE @settlement_id BIGINT, @amount DECIMAL(18,2), @status SMALLINT, @assignee BIGINT;

        SELECT @settlement_id = settlement_id, @amount = amount, @status = status
        FROM dbo.SettlementInvoice WITH (UPDLOCK, HOLDLOCK) WHERE invoice_id = @original_invoice_id;
        IF @settlement_id IS NULL THROW 50060, N'原蓝票不存在', 1;
        IF @status <> 1 OR @amount <= 0 THROW 50061, N'原票不是已开蓝票', 1;
        IF @red_reason IS NULL OR @red_reason = N'' THROW 50062, N'红冲原因必填', 1;

        SELECT @assignee = assigned_account_id FROM dbo.SettlementStatement WHERE settlement_id = @settlement_id;
        IF @created_by <> @assignee THROW 50063, N'只能由获派专员本人提出红冲', 1;

        INSERT INTO dbo.SettlementInvoice (settlement_id, invoice_no, invoice_title, tax_number, amount, status,
                                           original_invoice_id, red_reason, created_by, created_at)
        SELECT settlement_id, NULL, invoice_title, tax_number, -@amount, 0,
               @original_invoice_id, @red_reason, @created_by, @now
        FROM dbo.SettlementInvoice WHERE invoice_id = @original_invoice_id;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('D', 'INVOICE', CONVERT(varchar(50), @original_invoice_id), 'APPLY_RED_FLUSH', 'HUMAN', @created_by, @now, N'{"status":0}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

-- ---------- 红冲审批（R01，status=0→-1，写红票号，恢复待补票）----------
CREATE PROCEDURE dbo.usp_ApproveRedFlush
    @red_application_id BIGINT, @red_invoice_no VARCHAR(50), @approved_by BIGINT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @now DATETIME2(3) = SYSDATETIME();
        DECLARE @settlement_id BIGINT, @status SMALLINT, @created_by BIGINT;

        SELECT @settlement_id = settlement_id, @status = status, @created_by = created_by
        FROM dbo.SettlementInvoice WITH (UPDLOCK, HOLDLOCK) WHERE invoice_id = @red_application_id;
        IF @settlement_id IS NULL THROW 50070, N'红冲申请不存在', 1;
        IF @status <> 0 THROW 50071, N'该记录不在待审批状态', 1;
        IF @approved_by = @created_by THROW 50072, N'审批人不能是申请人', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE account_id = @approved_by AND role_id = 1 AND status = 1)
            THROW 50073, N'审批人必须是启用的 R01 管理员', 1;
        IF @red_invoice_no IS NULL OR @red_invoice_no = '' THROW 50074, N'成功红票必须有票号', 1;

        UPDATE dbo.SettlementInvoice
        SET status = -1, invoice_no = @red_invoice_no, issued_at = @now, approved_by = @approved_by, approved_at = @now
        WHERE invoice_id = @red_application_id;

        UPDATE dbo.SettlementStatement SET status = 1, completed_at = NULL WHERE settlement_id = @settlement_id AND status = 2;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('D', 'INVOICE', @red_invoice_no, 'APPROVE_RED_FLUSH', 'HUMAN', @approved_by, @now, N'{"status":-1}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

-- ---------- 结转审批（R01，PENDING→APPROVED）----------
CREATE PROCEDURE dbo.usp_ApproveCarryover
    @carryover_adjustment_id BIGINT, @approved_by BIGINT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @now DATETIME2(3) = SYSDATETIME();
        DECLARE @status VARCHAR(20);

        SELECT @status = status FROM dbo.SettlementCarryoverAdjustment WITH (UPDLOCK, HOLDLOCK)
        WHERE carryover_adjustment_id = @carryover_adjustment_id;
        IF @status IS NULL THROW 50080, N'结转记录不存在', 1;
        IF @status <> 'PENDING' THROW 50081, N'结转不在待审批状态', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE account_id = @approved_by AND role_id = 1 AND status = 1)
            THROW 50082, N'审批人必须是启用的 R01 管理员', 1;

        UPDATE dbo.SettlementCarryoverAdjustment SET status = 'APPROVED', approved_by = @approved_by, approved_at = @now
        WHERE carryover_adjustment_id = @carryover_adjustment_id;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('D', 'CARRYOVER', CONVERT(varchar(50), @carryover_adjustment_id), 'APPROVE_CARRYOVER', 'HUMAN', @approved_by, @now, N'{"status":"APPROVED"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

-- ---------- 应用跨期扣回（获派 R03；只标 APPLIED，不写 adjustment_amount）----------
CREATE PROCEDURE dbo.usp_ApplyCarryover
    @carryover_adjustment_id BIGINT, @target_settlement_id BIGINT, @applied_by BIGINT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @now DATETIME2(3) = SYSDATETIME();
        DECLARE @status VARCHAR(20), @amount DECIMAL(18,2), @plan_month CHAR(6), @orig_settlement BIGINT;
        DECLARE @target_month CHAR(6), @target_station VARCHAR(20), @orig_station VARCHAR(20), @tst TINYINT, @tpayable DECIMAL(28,2);
        DECLARE @refund_id BIGINT, @orig_month CHAR(6), @order_id BIGINT, @assignee BIGINT;
        DECLARE @confirmed_at DATETIME2(3), @refunded_at DATETIME2(3);
        SELECT @order_id = p.order_id
        FROM dbo.SettlementCarryoverAdjustment c
        JOIN dbo.RefundRecord r ON r.refund_id = c.refund_id
        JOIN dbo.PaymentRecord p ON p.payment_id = r.payment_id
        WHERE c.carryover_adjustment_id = @carryover_adjustment_id;
        IF @order_id IS NULL THROW 50090, N'结转记录或关联订单不存在', 1;
        EXEC dbo.usp_LockSettlementRefundOrder @order_id;

        SELECT @status = status, @amount = adjustment_amount, @plan_month = target_period_month,
               @orig_settlement = original_settlement_id, @refund_id = refund_id
        FROM dbo.SettlementCarryoverAdjustment WITH (UPDLOCK, HOLDLOCK) WHERE carryover_adjustment_id = @carryover_adjustment_id;

        IF @status IS NULL THROW 50090, N'结转记录不存在', 1;
        IF @status <> 'APPROVED' THROW 50091, N'结转未审批通过，不能应用', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE account_id = @applied_by AND role_id = 3 AND status = 1)
            THROW 50092, N'应用人必须是启用的 R03 专员', 1;

        SELECT @orig_station = station_id, @orig_month = period_month, @confirmed_at = confirmed_at
        FROM dbo.SettlementStatement WITH (UPDLOCK, HOLDLOCK)
        WHERE settlement_id = @orig_settlement AND status IN (1,2);
        SELECT @refunded_at = refunded_at FROM dbo.RefundRecord WHERE refund_id = @refund_id AND status = 'SUCCESS';
        IF @confirmed_at IS NULL OR @refunded_at IS NULL OR @refunded_at <= @confirmed_at
            THROW 50151, N'应用前须核实原单已锁定且退款发生在锁定后', 1;

        SELECT @target_month = period_month, @target_station = station_id, @tst = status,
               @assignee = assigned_account_id
        FROM dbo.SettlementStatement WITH (UPDLOCK, HOLDLOCK) WHERE settlement_id = @target_settlement_id;
        IF @target_month IS NULL THROW 50093, N'目标结算单不存在', 1;
        IF @target_month <> @plan_month THROW 50094, N'目标结算单账期与计划账期不一致', 1;
        IF @target_month <= @orig_month THROW 50095, N'目标账期必须晚于原账期', 1;
        IF @target_station <> @orig_station THROW 50096, N'结转必须落到同站后续账期', 1;
        IF @tst <> 0 THROW 50097, N'目标结算单必须是待对账状态', 1;
        IF @applied_by <> @assignee THROW 50148, N'只能由目标结算单获派专员应用结转', 1;

        EXEC dbo.usp_CheckSettlementRefundAmount
            @orig_settlement, @order_id, @refund_id, @amount, @carryover_adjustment_id;

        -- 足额可扣：应用后应结不得为负（结转额只通过 APPLIED 记录参与汇总）
        SELECT @tpayable = payable_amount FROM dbo.v_SettlementLedger WHERE settlement_id = @target_settlement_id;
        IF @tpayable IS NULL OR @tpayable + @amount < 0 THROW 50099, N'目标结算单余额不足，不能应用该扣回', 1;

        UPDATE dbo.SettlementCarryoverAdjustment SET status = 'APPLIED', target_settlement_id = @target_settlement_id
        WHERE carryover_adjustment_id = @carryover_adjustment_id;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('D', 'CARRYOVER', CONVERT(varchar(50), @carryover_adjustment_id), 'APPLY_CARRYOVER', 'HUMAN', @applied_by, @now, N'{"status":"APPLIED"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

-- ---------- 关闭人工核对事项（R03 获派本人）----------
CREATE PROCEDURE dbo.usp_CloseReviewCase
    @review_case_id BIGINT, @resolution NVARCHAR(500), @resolved_by BIGINT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @now DATETIME2(3) = SYSDATETIME();
        DECLARE @status VARCHAR(20), @assignee BIGINT;

        SELECT @status = status, @assignee = assigned_account_id
        FROM dbo.SettlementReviewCase WITH (UPDLOCK, HOLDLOCK) WHERE review_case_id = @review_case_id;
        IF @status IS NULL THROW 50100, N'核对事项不存在', 1;
        IF @status <> 'PENDING' THROW 50101, N'核对事项不在待处理状态', 1;
        IF @resolved_by <> @assignee THROW 50102, N'只能由获派专员本人关闭', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.SysAccount WHERE account_id = @resolved_by AND role_id = 3 AND status = 1)
            THROW 50103, N'关闭人必须是启用的 R03 专员', 1;
        IF @resolution IS NULL OR @resolution = N'' THROW 50104, N'关闭须有结论', 1;

        UPDATE dbo.SettlementReviewCase SET status = 'RESOLVED', resolution = @resolution, resolved_at = @now
        WHERE review_case_id = @review_case_id;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('D', 'REVIEW_CASE', CONVERT(varchar(50), @review_case_id), 'CLOSE_REVIEW_CASE', 'HUMAN', @resolved_by, @now, N'{"status":"RESOLVED"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

-- ---------- 漏单补入（待对账时，从来源视图核对后写明细）----------
CREATE PROCEDURE dbo.usp_SupplementDetail
    @settlement_id BIGINT,
    @order_id      BIGINT,
    @created_by    BIGINT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @now DATETIME2(3) = SYSDATETIME();
        DECLARE @st TINYINT, @assignee BIGINT, @station_id VARCHAR(20), @period_month CHAR(6);
        DECLARE @ps DATE, @pe DATE;

        SELECT @st = status, @assignee = assigned_account_id,
               @station_id = station_id, @period_month = period_month
        FROM dbo.SettlementStatement WITH (UPDLOCK, HOLDLOCK) WHERE settlement_id = @settlement_id;
        IF @st IS NULL THROW 50110, N'结算单不存在', 1;
        IF @st <> 0 THROW 50111, N'结算单不在待对账状态，不能补单', 1;
        IF @created_by <> @assignee THROW 50112, N'只能由获派专员本人补单', 1;

        -- 已入任一有效明细则拒绝（跨有效账单不重复）
        IF EXISTS (SELECT 1 FROM dbo.SettlementDetail WHERE order_id = @order_id)
            THROW 50113, N'该订单已在某张结算单明细中', 1;

        SET @ps = CONVERT(date, @period_month + '01', 112);
        SET @pe = DATEADD(month, 1, @ps);

        INSERT INTO dbo.SettlementDetail (settlement_id, order_id, ended_at_snapshot, energy_snapshot,
                                          electricity_base, service_base, minimum_adjustment, created_at,
                                          settled_at_snapshot, settlement_source, eligibility_checked_at, refund_state_snapshot)
        SELECT @settlement_id, src.order_id, src.ended_at, src.energy_kwh,
               src.electricity_base, src.service_base, src.minimum_adjustment, @now,
               src.settled_at, src.settlement_source, @now, src.refund_state_snapshot
        FROM dbo.v_OrderSettlementSource src
        WHERE src.order_id = @order_id
          AND src.station_id = @station_id
          AND src.ended_at >= @ps AND src.ended_at < @pe
          AND src.is_settleable = 1;

        IF @@ROWCOUNT = 0
            THROW 50114, N'该订单不属于本场站本账期或不符合结算资格', 1;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('D', 'SETTLEMENT', CONVERT(varchar(50), @settlement_id), 'SUPPLEMENT_DETAIL', 'HUMAN', @created_by, @now,
                N'{"order_id":' + CAST(@order_id AS VARCHAR(20)) + N'}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW;
    END CATCH
END
GO

-- =============================================================
-- 完整性保护触发器：OperationLog 只追加，禁止 UPDATE/DELETE
-- =============================================================
CREATE TRIGGER dbo.trg_OperationLog_Protect ON dbo.OperationLog
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 50190, N'OperationLog 为只追加审计表，禁止修改或删除', 1;
END
GO

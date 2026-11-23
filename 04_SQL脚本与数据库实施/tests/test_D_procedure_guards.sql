-- D procedure guard regressions for the integrated database.
-- Every call must reject a deliberately invalid/missing input before writing data.
SET NOCOUNT ON;
IF DB_NAME() <> N'EV_B_TEST' THROW 52900, N'Choose EV_B_TEST', 1;

DECLARE @error INT;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_GenerateSettlement 'TST_D_MISSING', 'BAD', -1, -1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50010 THROW 52901, N'GenerateSettlement did not reject an invalid period.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_LockSettlementRefundOrder -1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50140 THROW 52902, N'LockSettlementRefundOrder did not require a transaction.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_CheckSettlementRefundAmount -1, -1, -1, 0;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50142 THROW 52903, N'CheckSettlementRefundAmount accepted a non-negative deduction.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_RegisterDifference -1, -1, 1, 1, NULL, -1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50026 THROW 52904, N'RegisterDifference did not reject a missing settlement.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_CloseDifference -1, -1, N'evidence', N'resolution';
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50020 THROW 52905, N'CloseDifference did not reject a missing difference.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_ConfirmSettlement -1, -1, N'evidence';
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50040 THROW 52906, N'ConfirmSettlement did not reject a missing settlement.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_RegisterInvoice -1, 'TST-D-NO-INVOICE', N'Test', NULL, 0, -1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50050 THROW 52907, N'RegisterInvoice accepted a non-positive amount.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_ApplyRedFlush -1, N'reason', -1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50060 THROW 52908, N'ApplyRedFlush did not reject a missing original invoice.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_ApproveRedFlush -1, 'TST-D-NO-RED', -1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50070 THROW 52909, N'ApproveRedFlush did not reject a missing application.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_ApproveCarryover -1, -1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50080 THROW 52910, N'ApproveCarryover did not reject a missing carryover.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_ApplyCarryover -1, -1, -1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50090 THROW 52911, N'ApplyCarryover did not reject a missing carryover.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_CloseReviewCase -1, N'resolution', -1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50100 THROW 52912, N'CloseReviewCase did not reject a missing review case.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_SupplementDetail -1, -1, -1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50110 THROW 52913, N'SupplementDetail did not reject a missing settlement.', 1;

SET @error = 0;
BEGIN TRY
    EXEC dbo.usp_RegisterCarryover -1, -1, -1, -1, N'evidence', -1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;
IF @error <> 50123 THROW 52914, N'RegisterCarryover did not reject a missing successful refund.', 1;

SELECT N'D procedure guard regressions' AS test_name, N'passed' AS test_result,
       14 AS procedures_checked;

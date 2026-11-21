SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51000, 'This test must run in EV_B_TEST.', 1;

IF OBJECT_ID(N'dbo.BillingRule', N'U') IS NULL
    THROW 51001, 'dbo.BillingRule does not exist.', 1;

DECLARE @index_ok bit = 0;

IF EXISTS (
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id = OBJECT_ID(N'dbo.BillingRule', N'U')
      AND i.name = N'UQ_BillingRule_01'
      AND i.is_unique = 1
      AND i.is_disabled = 0
      AND i.has_filter = 0
      AND (
          SELECT COUNT(*)
          FROM sys.index_columns AS ic
          WHERE ic.object_id = i.object_id
            AND ic.index_id = i.index_id
            AND ic.key_ordinal > 0
      ) = 2
      AND EXISTS (
          SELECT 1
          FROM sys.index_columns AS ic
          JOIN sys.columns AS c
            ON c.object_id = ic.object_id
           AND c.column_id = ic.column_id
          WHERE ic.object_id = i.object_id
            AND ic.index_id = i.index_id
            AND ic.key_ordinal = 1
            AND c.name = N'rule_version_id'
      )
      AND EXISTS (
          SELECT 1
          FROM sys.index_columns AS ic
          JOIN sys.columns AS c
            ON c.object_id = ic.object_id
           AND c.column_id = ic.column_id
          WHERE ic.object_id = i.object_id
            AND ic.index_id = i.index_id
            AND ic.key_ordinal = 2
            AND c.name = N'period_start_time'
      )
) SET @index_ok = 1;

SELECT N'索引结构' AS test_name,
       CASE WHEN @index_ok = 1 THEN N'通过'
            ELSE N'失败：索引缺失或结构不符' END AS test_result;

IF @index_ok = 0
    THROW 51002, 'UQ_BillingRule_01 is missing or has an unexpected definition.', 1;

DECLARE @operator_id varchar(20) =
    'BTU' + LEFT(REPLACE(CONVERT(varchar(36), NEWID()), '-', ''), 17);
DECLARE @station_id varchar(20) =
    'BTS' + LEFT(REPLACE(CONVERT(varchar(36), NEWID()), '-', ''), 17);
DECLARE @version_id bigint = -ABS(CONVERT(bigint, CHECKSUM(NEWID())));
DECLARE @caught_error int = NULL;
DECLARE @caught_message nvarchar(4000) = NULL;
DECLARE @duplicate_rejected bit = 0;

WHILE EXISTS (
    SELECT 1 FROM dbo.BillingRuleVersion WHERE rule_version_id = @version_id
)
    SET @version_id -= 1;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES (@operator_id, N'计费规则唯一性测试临时运营商');

    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude, operator_id,
         total_spaces, business_hours, parking_fee_standard,
         workorder_notice_account_id)
    VALUES
        (@station_id, N'计费规则唯一性测试临时场站', N'测试数据，事务回滚',
         0, 0, @operator_id, 0, N'00:00-24:00', N'测试', 1);

    INSERT INTO dbo.BillingRuleVersion
        (rule_version_id, station_id, enterprise_id, free_minutes,
         minimum_amount, effective_from, status)
    VALUES
        (@version_id, @station_id, NULL, 0, 0, '2026-01-01', 'ACTIVE');

    INSERT INTO dbo.BillingRule
        (rule_version_id, period_type, period_start_time, period_end_time,
         electricity_price, service_price)
    VALUES
        (@version_id, N'平', '08:00:00', '12:00:00', 0.60, 0.20);

    BEGIN TRY
        INSERT INTO dbo.BillingRule
            (rule_version_id, period_type, period_start_time, period_end_time,
             electricity_price, service_price)
        VALUES
            (@version_id, N'峰', '08:00:00', '16:00:00', 0.80, 0.30);

        SET @caught_message = N'失败：数据库允许重复的 (rule_version_id, period_start_time)';
    END TRY
    BEGIN CATCH
        SET @caught_error = ERROR_NUMBER();
        SET @caught_message = ERROR_MESSAGE();
        IF @caught_error IN (2601, 2627)
            SET @duplicate_rejected = 1;
    END CATCH;

    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    SET @caught_error = ERROR_NUMBER();
    SET @caught_message = ERROR_MESSAGE();
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
END CATCH;

DECLARE @cleanup_ok bit = CASE
    WHEN NOT EXISTS (SELECT 1 FROM dbo.Operator WHERE operator_id = @operator_id)
     AND NOT EXISTS (SELECT 1 FROM dbo.ChargingStation WHERE station_id = @station_id)
     AND NOT EXISTS (SELECT 1 FROM dbo.BillingRuleVersion WHERE rule_version_id = @version_id)
    THEN 1 ELSE 0 END;

SELECT N'重复键插入' AS test_name,
       CASE WHEN @duplicate_rejected = 1 THEN N'通过：数据库拒绝重复键'
            ELSE N'失败：重复键未被唯一约束拒绝' END AS test_result,
       @caught_error AS error_number,
       CAST(@caught_message AS nvarchar(300)) AS error_message;
SELECT N'事务清理' AS test_name,
       CASE WHEN @cleanup_ok = 1 THEN N'通过：临时数据已回滚'
            ELSE N'失败：发现未清理的临时数据' END AS test_result;

IF @duplicate_rejected = 0 OR @cleanup_ok = 0
    THROW 51003, 'BillingRule uniqueness behavior test failed.', 1;
GO

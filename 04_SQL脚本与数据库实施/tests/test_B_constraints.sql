SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51000, 'This test must run in EV_B_TEST.', 1;

DECLARE @Passed INT = 0;
DECLARE @Failed INT = 0;
DECLARE @VersionId BIGINT;
DECLARE @StationId VARCHAR(20) = 'BTST' + LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16);
DECLARE @OperatorId VARCHAR(20) = 'BTOP' + LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 16);
DECLARE @DuplicateRejected BIT = 0;
DECLARE @CleanupOk BIT = 0;

SET @VersionId = -ABS(CONVERT(BIGINT, CHECKSUM(NEWID())));
WHILE EXISTS (SELECT 1 FROM dbo.BillingRuleVersion WHERE rule_version_id = @VersionId)
    SET @VersionId -= 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. 创建临时运营商
    INSERT INTO dbo.Operator
        (operator_id, operator_name)
    VALUES
        (@OperatorId, N'B线唯一约束测试运营商');

    -- 2. 创建临时场站
    INSERT INTO dbo.ChargingStation
        (
            station_id,
            station_name,
            address,
            longitude,
            latitude,
            operator_id,
            total_spaces,
            business_hours,
            parking_fee_standard,
            workorder_notice_account_id
        )
    VALUES
        (
            @StationId,
            N'B线唯一约束测试场站',
            N'测试地址',
            116.400000,
            39.900000,
            @OperatorId,
            2,
            N'00:00-24:00',
            N'免费',
            1
        );

    -- 3. 创建计费版本
    INSERT INTO dbo.BillingRuleVersion
        (
            rule_version_id,
            station_id,
            enterprise_id,
            free_minutes,
            minimum_amount,
            effective_from,
            status
        )
    VALUES
        (
            @VersionId,
            @StationId,
            NULL,
            0,
            0,
            '2026-01-01',
            'ACTIVE'
        );

    -- 4. 插入第一条合法计费规则
    INSERT INTO dbo.BillingRule
        (
            rule_version_id,
            period_type,
            period_start_time,
            period_end_time,
            electricity_price,
            service_price
        )
    VALUES
        (
            @VersionId,
            N'平',
            '08:00:00',
            '12:00:00',
            0.60,
            0.20
        );

    -- 5. 尝试插入重复规则
    BEGIN TRY

        INSERT INTO dbo.BillingRule
            (
                rule_version_id,
                period_type,
                period_start_time,
                period_end_time,
                electricity_price,
                service_price
            )
        VALUES
            (
                @VersionId,
                N'峰',
                '08:00:00',
                '16:00:00',
                0.80,
                0.30
            );

        SET @Failed += 1;

        PRINT N'测试失败：数据库允许重复计费时段起点';

    END TRY
    BEGIN CATCH

        IF ERROR_NUMBER() IN (2601, 2627)
        BEGIN
            SET @Passed += 1;
            SET @DuplicateRejected = 1;
            PRINT N'测试通过：数据库拒绝重复计费时段起点';
        END
        ELSE
        BEGIN
            SET @Failed += 1;
            PRINT N'测试失败：' + ERROR_MESSAGE();
        END

    END CATCH;

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    SET @Failed += 1;

    PRINT N'测试准备失败：' + ERROR_MESSAGE();

END CATCH;

SET @CleanupOk = CASE
    WHEN NOT EXISTS (SELECT 1 FROM dbo.Operator WHERE operator_id = @OperatorId)
     AND NOT EXISTS (SELECT 1 FROM dbo.ChargingStation WHERE station_id = @StationId)
     AND NOT EXISTS (SELECT 1 FROM dbo.BillingRuleVersion WHERE rule_version_id = @VersionId)
    THEN 1 ELSE 0 END;

IF @CleanupOk = 1
    SET @Passed += 1;
ELSE
    SET @Failed += 1;

SELECT
    @Passed AS passed_tests,
    @Failed AS failed_tests,
    @DuplicateRejected AS duplicate_rejected,
    @CleanupOk AS rollback_cleanup_ok,
    CASE
        WHEN @DuplicateRejected = 1 AND @CleanupOk = 1 AND @Failed = 0
            THEN N'全部通过'
        ELSE N'存在失败'
    END AS test_result;

IF @DuplicateRejected = 0 OR @CleanupOk = 0 OR @Failed > 0
    THROW 51001, 'BillingRule duplicate-key test failed.', 1;

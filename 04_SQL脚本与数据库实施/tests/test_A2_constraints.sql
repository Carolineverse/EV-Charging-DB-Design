SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51100, 'This test must run in EV_B_TEST.', 1;

DECLARE @ExpectedTables TABLE (table_name sysname PRIMARY KEY);
INSERT INTO @ExpectedTables (table_name)
VALUES
    (N'MemberLevel'), (N'UserMemberLevel'), (N'Vehicle'), (N'FleetMember'),
    (N'EnterpriseCard'), (N'EnterpriseCardBinding'), (N'EnterpriseQuota'),
    (N'Promotion'), (N'PromotionStation'), (N'PromotionMemberLevel'),
    (N'UserCoupon'), (N'CouponRedemption'), (N'UserWallet'),
    (N'WalletTransaction'), (N'PersonalInvoiceApplication'),
    (N'EnterpriseSettlement'), (N'EnterpriseSettlementDetail'),
    (N'EnterpriseServiceApplication'), (N'PersonalInvoiceAdjustment');

DECLARE @MissingTables int = (
    SELECT COUNT(*)
    FROM @ExpectedTables AS e
    LEFT JOIN sys.tables AS t ON t.name = e.table_name
    WHERE t.object_id IS NULL
);
DECLARE @UntrustedChecks int = (
    SELECT COUNT(*)
    FROM sys.check_constraints AS cc
    JOIN @ExpectedTables AS e ON e.table_name = OBJECT_NAME(cc.parent_object_id)
    WHERE cc.is_disabled = 1 OR cc.is_not_trusted = 1
);
DECLARE @UntrustedForeignKeys int = (
    SELECT COUNT(*)
    FROM sys.foreign_keys AS fk
    JOIN @ExpectedTables AS e ON e.table_name = OBJECT_NAME(fk.parent_object_id)
    WHERE fk.is_disabled = 1 OR fk.is_not_trusted = 1
);
DECLARE @MissingIndexes int = (
    SELECT CASE WHEN COUNT(*) = 21 THEN 0 ELSE 1 END
    FROM sys.indexes AS i
    JOIN @ExpectedTables AS e ON e.table_name = OBJECT_NAME(i.object_id)
    WHERE i.name LIKE N'IX[_]%' OR i.name LIKE N'UX[_]%'
);

SELECT N'A2 表清单' AS test_name,
       CASE WHEN @MissingTables = 0 THEN N'通过' ELSE N'失败' END AS test_result,
       @MissingTables AS missing_tables;
SELECT N'约束可信状态' AS test_name,
       CASE WHEN @UntrustedChecks = 0 AND @UntrustedForeignKeys = 0
            THEN N'通过' ELSE N'失败' END AS test_result,
       @UntrustedChecks AS disabled_or_untrusted_checks,
       @UntrustedForeignKeys AS disabled_or_untrusted_foreign_keys;
SELECT N'A2 二级索引' AS test_name,
       CASE WHEN @MissingIndexes = 0 THEN N'通过' ELSE N'失败' END AS test_result;

IF @MissingTables <> 0 OR @UntrustedChecks <> 0
   OR @UntrustedForeignKeys <> 0 OR @MissingIndexes <> 0
    THROW 51101, 'A2 catalog validation failed.', 1;

DECLARE @member_level_id varchar(20) =
    'AT' + LEFT(REPLACE(CONVERT(varchar(36), NEWID()), '-', ''), 10);
DECLARE @level_name nvarchar(30) = N'A2T' + LEFT(CONVERT(varchar(36), NEWID()), 10);
DECLARE @promotion_id varchar(20) =
    'AP' + LEFT(REPLACE(CONVERT(varchar(36), NEWID()), '-', ''), 10);
DECLARE @vehicle_id varchar(20) =
    'AV' + LEFT(REPLACE(CONVERT(varchar(36), NEWID()), '-', ''), 18);
DECLARE @Results TABLE (test_name nvarchar(80), passed bit, detail nvarchar(300));

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.MemberLevel (member_level_id, level_name, level_sort, status)
    VALUES (@member_level_id, @level_name, 987654321, 'ACTIVE');

    BEGIN TRY
        INSERT INTO dbo.MemberLevel (member_level_id, level_name, level_sort, status)
        VALUES (@member_level_id + 'X', @level_name + N'X', 0, 'ACTIVE');
        INSERT INTO @Results VALUES (N'会员等级排序下限', 0, N'level_sort=0 被接受');
    END TRY
    BEGIN CATCH
        INSERT INTO @Results
        VALUES (N'会员等级排序下限',
                IIF(CHARINDEX(N'CK_MemberLevel_level_sort', ERROR_MESSAGE()) > 0, 1, 0),
                ERROR_MESSAGE());
    END CATCH;

    BEGIN TRY
        INSERT INTO dbo.MemberLevel (member_level_id, level_name, level_sort, status)
        VALUES (@member_level_id + 'Y', @level_name + N'Y', 987654322, 'INVALID');
        INSERT INTO @Results VALUES (N'会员等级状态枚举', 0, N'非法 status 被接受');
    END TRY
    BEGIN CATCH
        INSERT INTO @Results
        VALUES (N'会员等级状态枚举',
                IIF(CHARINDEX(N'CK_MemberLevel_status', ERROR_MESSAGE()) > 0, 1, 0),
                ERROR_MESSAGE());
    END CATCH;

    BEGIN TRY
        INSERT INTO dbo.MemberLevel (member_level_id, level_name, level_sort, status)
        VALUES (@member_level_id + 'Z', @level_name, 987654323, 'ACTIVE');
        INSERT INTO @Results VALUES (N'会员等级名称唯一', 0, N'重复 level_name 被接受');
    END TRY
    BEGIN CATCH
        INSERT INTO @Results
        VALUES (N'会员等级名称唯一',
                IIF(ERROR_NUMBER() IN (2601, 2627), 1, 0), ERROR_MESSAGE());
    END CATCH;

    BEGIN TRY
        INSERT INTO dbo.MemberLevel (member_level_id, level_name, level_sort, status)
        VALUES (@member_level_id + 'W', @level_name + N'W', 987654321, 'ACTIVE');
        INSERT INTO @Results VALUES (N'会员等级排序唯一', 0, N'重复 level_sort 被接受');
    END TRY
    BEGIN CATCH
        INSERT INTO @Results
        VALUES (N'会员等级排序唯一',
                IIF(ERROR_NUMBER() IN (2601, 2627), 1, 0), ERROR_MESSAGE());
    END CATCH;

    BEGIN TRY
        INSERT INTO dbo.Promotion
            (promotion_id, promotion_name, promotion_type, face_value, min_spend,
             issue_start_at, issue_end_at, valid_start_at, valid_end_at,
             issue_quantity, member_level_scope, target_audience, redemption_rule)
        VALUES
            (@promotion_id, N'A2测试活动', 'GENERAL', 1, 0,
             '2026-02-01', '2026-01-01', '2026-01-01', '2026-02-01',
             1, 'ALL', 'ALL', N'test');
        INSERT INTO @Results VALUES (N'活动发放时间顺序', 0, N'结束时间早于开始时间仍被接受');
    END TRY
    BEGIN CATCH
        INSERT INTO @Results
        VALUES (N'活动发放时间顺序',
                IIF(CHARINDEX(N'CK_Promotion_issue_time', ERROR_MESSAGE()) > 0, 1, 0),
                ERROR_MESSAGE());
    END CATCH;

    BEGIN TRY
        INSERT INTO dbo.Promotion
            (promotion_id, promotion_name, promotion_type, face_value, min_spend,
             issue_start_at, issue_end_at, valid_start_at, valid_end_at,
             issue_quantity, member_level_scope, target_audience, redemption_rule,
             status)
        VALUES
            (@promotion_id, N'A2测试活动', 'GENERAL', 1, 0,
             '2026-01-01', '2026-02-01', '2026-01-01', '2026-02-01',
             1, 'ALL', 'ALL', N'test', 'ACTIVE');
        INSERT INTO @Results VALUES (N'活动启用须审批', 0, N'未审批活动被启用');
    END TRY
    BEGIN CATCH
        INSERT INTO @Results
        VALUES (N'活动启用须审批',
                IIF(CHARINDEX(N'CK_Promotion_active_review', ERROR_MESSAGE()) > 0, 1, 0),
                ERROR_MESSAGE());
    END CATCH;

    BEGIN TRY
        INSERT INTO dbo.Vehicle
            (vehicle_id, user_id, enterprise_id, plate_ciphertext, plate_hash,
             vehicle_model, battery_capacity_kwh, max_charging_power_kw)
        VALUES
            (@vehicle_id, NULL, NULL, 0x01,
             REPLACE(CONVERT(char(64), HASHBYTES('SHA2_256', @vehicle_id), 2), ' ', ''),
             N'A2测试车辆', 0, 1);
        INSERT INTO @Results VALUES (N'车辆归属二选一', 0, N'个人和企业归属同时为空仍被接受');
    END TRY
    BEGIN CATCH
        INSERT INTO @Results
        VALUES (N'车辆归属二选一',
                IIF(CHARINDEX(N'CK_Vehicle_owner', ERROR_MESSAGE()) > 0, 1, 0),
                ERROR_MESSAGE());
    END CATCH;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT test_name,
       CASE WHEN passed = 1 THEN N'通过' ELSE N'失败' END AS test_result,
       detail
FROM @Results
ORDER BY test_name;

IF EXISTS (SELECT 1 FROM @Results WHERE passed = 0)
    THROW 51102, 'One or more A2 behavior tests failed.', 1;
GO


SET NOCOUNT ON;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51000, 'This test must run in EV_B_TEST.', 1;

IF OBJECT_ID(N'dbo.ChargingOrder', N'U') IS NULL
    THROW 51001, 'dbo.ChargingOrder does not exist.', 1;

PRINT N'========== ChargingOrder CHECK 约束检查 ==========';

-- 1. 列出实际存在的 CHECK 约束
SELECT
    cc.name AS constraint_name,
    cc.definition,
    cc.is_disabled,
    cc.is_not_trusted
FROM sys.check_constraints AS cc
WHERE cc.parent_object_id = OBJECT_ID(N'dbo.ChargingOrder')
ORDER BY cc.name;

-- 2. 核对设计要求的 11 项 CHECK 约束
-- 名称与此前创建的约束保持一致
DECLARE @Expected TABLE (
    constraint_name SYSNAME PRIMARY KEY
);

INSERT INTO @Expected (constraint_name)
VALUES
    (N'CK_ChargingOrder_amounts'),
    (N'CK_ChargingOrder_discount'),
    (N'CK_ChargingOrder_end_soc'),
    (N'CK_ChargingOrder_energy'),
    (N'CK_ChargingOrder_enterprise_fields'),
    (N'CK_ChargingOrder_order_type'),
    (N'CK_ChargingOrder_paid_settled'),
    (N'CK_ChargingOrder_refund'),
    (N'CK_ChargingOrder_start_soc'),
    (N'CK_ChargingOrder_status'),
    (N'CK_ChargingOrder_time');

-- 3. 输出每项检查结果
SELECT
    e.constraint_name,
    CASE
        WHEN cc.object_id IS NULL THEN N'缺失'
        WHEN cc.is_disabled = 1 THEN N'已禁用'
        WHEN cc.is_not_trusted = 1 THEN N'不可信'
        ELSE N'通过'
    END AS test_result
FROM @Expected AS e
LEFT JOIN sys.check_constraints AS cc
    ON cc.parent_object_id = OBJECT_ID(N'dbo.ChargingOrder')
   AND cc.name = e.constraint_name
ORDER BY e.constraint_name;

-- 4. 汇总
SELECT
    COUNT(*) AS expected_tests,
    SUM(CASE
        WHEN cc.object_id IS NOT NULL
         AND cc.is_disabled = 0
         AND cc.is_not_trusted = 0
        THEN 1 ELSE 0
    END) AS passed_tests,
    SUM(CASE
        WHEN cc.object_id IS NULL
          OR cc.is_disabled = 1
          OR cc.is_not_trusted = 1
        THEN 1 ELSE 0
    END) AS failed_tests
FROM @Expected AS e
LEFT JOIN sys.check_constraints AS cc
    ON cc.parent_object_id = OBJECT_ID(N'dbo.ChargingOrder')
   AND cc.name = e.constraint_name;

IF EXISTS (
    SELECT 1
    FROM @Expected AS e
    LEFT JOIN sys.check_constraints AS cc
        ON cc.parent_object_id = OBJECT_ID(N'dbo.ChargingOrder')
       AND cc.name = e.constraint_name
    WHERE cc.object_id IS NULL
       OR cc.is_disabled = 1
       OR cc.is_not_trusted = 1
)
    THROW 51002, 'One or more ChargingOrder CHECK constraints are missing, disabled, or untrusted.', 1;

IF (SELECT COUNT(*) FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.ChargingOrder')) <> 11
    THROW 51003, 'ChargingOrder CHECK constraint count differs from the expected 11.', 1;
GO

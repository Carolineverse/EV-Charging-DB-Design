-- A1 核心约束回归测试（SQL Server / SSMS）
-- 覆盖：Operator CHECK、ChargingGun UNIQUE、ChargingPile FK、DeviceStatusHistory CHECK（两种非法情况）
-- 前提：A1 七张表、七个内部外键已安装；在空闲的开发/测试库执行。
-- 安全：所有成功插入的夹具数据均在同一事务中回滚；不在生产库运行。
-- 执行方式：先在 SSMS 连接目标库，并选择 EV_B_DEV（或 EV_B_TEST）；不要把 USE 固定在脚本里。

SET NOCOUNT ON;
SET XACT_ABORT OFF; -- 允许在 TRY/CATCH 中捕获预期的约束冲突

DECLARE @passed INT = 0;
DECLARE @expected INT = 5;
DECLARE @failed INT = 0;
DECLARE @err NVARCHAR(4000);

BEGIN TRY
    BEGIN TRANSACTION;

    -- 01：Operator.status 不能为 INVALID
    BEGIN TRY
        INSERT INTO dbo.Operator (operator_id, operator_name, status)
        VALUES ('TEST_BAD_001', N'A1非法状态测试', 'INVALID');
        PRINT N'FAIL 01：非法运营商状态被接受';
        SET @failed += 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE N'%CK_Operator_status%'
        BEGIN
            PRINT N'PASS 01：Operator 状态 CHECK 拒绝 INVALID';
            SET @passed += 1;
        END
        ELSE THROW;
    END CATCH;

    -- 02：ChargingPile.station_id 必须引用已有场站
    BEGIN TRY
        INSERT INTO dbo.ChargingPile
            (pile_id, station_id, device_model, rated_power_kw,
             communication_protocol, commissioned_date, warranty_end_date)
        VALUES
            ('TEST_FK_PL_001', 'TEST_NO_STATION', N'外键测试型号', 60.00,
             N'OCPP', '2026-01-01', '2028-01-01');
        PRINT N'FAIL 02：不存在的场站被接受';
        SET @failed += 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE N'%FK_ChargingPile_ChargingStation%'
        BEGIN
            PRINT N'PASS 02：ChargingPile 外键拒绝不存在的场站';
            SET @passed += 1;
        END
        ELSE THROW;
    END CATCH;

    -- 03：DeviceStatusHistory 的 pile_id、gun_id 不能同时为空
    BEGIN TRY
        INSERT INTO dbo.DeviceStatusHistory
            (pile_id, gun_id, old_status, new_status,
             changed_at, change_reason, change_source)
        VALUES
            (NULL, NULL, NULL, 'IDLE', SYSDATETIME(), N'双空测试', 'MANUAL');
        PRINT N'FAIL 03：状态历史两个目标都为空被接受';
        SET @failed += 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE N'%CK_DeviceStatusHistory_target%'
        BEGIN
            PRINT N'PASS 03：状态历史拒绝两个目标都为空';
            SET @passed += 1;
        END
        ELSE THROW;
    END CATCH;

    -- 04：DeviceStatusHistory 的 pile_id、gun_id 不能同时有值
    BEGIN TRY
        INSERT INTO dbo.DeviceStatusHistory
            (pile_id, gun_id, old_status, new_status,
             changed_at, change_reason, change_source)
        VALUES
            ('TEST_PILE', 'TEST_GUN', NULL, 'IDLE',
             SYSDATETIME(), N'双有值测试', 'MANUAL');
        PRINT N'FAIL 04：状态历史两个目标同时有值被接受';
        SET @failed += 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE N'%CK_DeviceStatusHistory_target%'
        BEGIN
            PRINT N'PASS 04：状态历史拒绝两个目标同时有值';
            SET @passed += 1;
        END
        ELSE THROW;
    END CATCH;

    -- 05：同一 pile_id 下 gun_sequence 必须唯一
    -- 创建合法的父表夹具，确保被拒绝的原因确实是唯一约束。
    INSERT INTO dbo.Operator (operator_id, operator_name)
    VALUES ('TEST_OP_001', N'A1唯一约束测试运营商');

    INSERT INTO dbo.ChargingStation
        (station_id, station_name, address, longitude, latitude,
         operator_id, total_spaces, business_hours,
         parking_fee_standard, workorder_notice_account_id)
    VALUES
        ('TEST_ST_001', N'A1唯一约束测试场站', N'测试地址', 116.400000, 39.900000,
         'TEST_OP_001', 10, N'全天', N'免费', 1);

    INSERT INTO dbo.ChargingPile
        (pile_id, station_id, device_model, rated_power_kw,
         communication_protocol, commissioned_date, warranty_end_date)
    VALUES
        ('TEST_PL_001', 'TEST_ST_001', N'测试型号', 120.00,
         N'OCPP', '2026-01-01', '2028-01-01');

    INSERT INTO dbo.ChargingGun
        (gun_id, pile_id, gun_sequence, gun_type,
         interface_standard, max_output_power_kw)
    VALUES
        ('TEST_GN_001', 'TEST_PL_001', 1, 'DC_FAST', N'GB/T', 60.00);

    BEGIN TRY
        INSERT INTO dbo.ChargingGun
            (gun_id, pile_id, gun_sequence, gun_type,
             interface_standard, max_output_power_kw)
        VALUES
            ('TEST_GN_002', 'TEST_PL_001', 1, 'DC_FAST', N'GB/T', 60.00);
        PRINT N'FAIL 05：同桩重复枪序号被接受';
        SET @failed += 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
           AND ERROR_MESSAGE() LIKE N'%UQ_ChargingGun_01%'
        BEGIN
            PRINT N'PASS 05：ChargingGun 唯一约束拒绝重复枪序号';
            SET @passed += 1;
        END
        ELSE THROW;
    END CATCH;

    -- 即使发生测试失败（约束未拦截），也不保留测试数据。
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    SET @err = ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    PRINT N'ERROR：测试执行异常（不是预期约束错误）：' + @err;
    SET @failed += 1;
END CATCH;

SELECT
    @passed AS passed_tests,
    @expected AS expected_tests,
    @failed AS failed_tests,
    CASE WHEN @passed = @expected AND @failed = 0
         THEN N'全部通过' ELSE N'未全部通过，请查看消息' END AS test_result;

-- 检查本脚本使用的测试编号是否有残留（正常均为 0）
SELECT
    (SELECT COUNT(*) FROM dbo.Operator
     WHERE operator_id IN ('TEST_BAD_001', 'TEST_OP_001')) AS operator_rows,
    (SELECT COUNT(*) FROM dbo.ChargingStation
     WHERE station_id = 'TEST_ST_001') AS station_rows,
    (SELECT COUNT(*) FROM dbo.ChargingPile
     WHERE pile_id IN ('TEST_FK_PL_001', 'TEST_PL_001')) AS pile_rows,
    (SELECT COUNT(*) FROM dbo.ChargingGun
     WHERE gun_id IN ('TEST_GN_001', 'TEST_GN_002')) AS gun_rows;

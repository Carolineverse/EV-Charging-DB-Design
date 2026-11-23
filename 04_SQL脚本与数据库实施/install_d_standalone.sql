-- =============================================================
-- D 线独立一键安装（SQLCMD 模式）
-- 使用：SSMS 打开本文件 → 菜单「查询」→ 勾选「SQLCMD 模式」→ 执行
-- 请先新建并选中目标库（EV_D_DEV / EV_D_TEST）
-- 必须提供主密钥口令：
--   sqlcmd ... -v EV_MASTER_KEY_PASSWORD="你的口令" -i install_d_standalone.sql
-- 说明：本入口使用 00_b_fixture.sql（ST-001 等旧编号）仅用于 D 自测；
--       全组联调请使用 install_all.sql
-- =============================================================

-- sqlcmd 默认 QUOTED_IDENTIFIER OFF，会导致 DeviceMonitoringData 的筛选索引创建失败（错误 1934）。
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

SELECT DB_NAME() AS [当前数据库];  -- 先确认不是 master
GO

:ON ERROR EXIT
IF DB_NAME() NOT IN (N'EV_D_DEV', N'EV_D_TEST')
    THROW 52722, N'D 独立安装仅支持 EV_D_DEV 或 EV_D_TEST。', 1;
GO

:r sql\security\00_crypto_keys.sql
:r sql\security\usp_encrypt_decrypt.sql
:r sql\schema\r_core.sql
:r sql\seed\r_base.sql
:r sql\seed\00_b_fixture.sql
:r sql\schema\c_partition.sql
:r sql\schema\c_core.sql
:r sql\schema\d_core.sql
:r sql\constraints\d_constraints.sql
:r sql\views\d_views.sql
:r sql\routines\c_dispatch.sql
:r sql\routines\d_generate.sql
:r sql\routines\d_flows.sql
:r sql\seed\c_base.sql
:r sql\seed\d_base_standalone.sql

-- 校验
SELECT COUNT(*) AS table_count FROM sys.tables WHERE schema_id = SCHEMA_ID('dbo');
SELECT COUNT(*) AS settlement_count FROM dbo.SettlementStatement;
SELECT COUNT(*) AS detail_count FROM dbo.SettlementDetail;
SELECT COUNT(*) AS monitor_count FROM dbo.DeviceMonitoringData;

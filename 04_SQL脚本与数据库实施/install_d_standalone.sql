-- =============================================================
-- 一键安装（SQLCMD 模式）
-- 使用：SSMS 打开本文件 → 菜单「查询」→ 勾选「SQLCMD 模式」→ 执行
-- 请先新建并选中目标库（EV_D_DEV / EV_D_TEST）
-- 注意：00_b_fixture.sql 为 B 精简夹具，联调时删除该行并改用 B 真脚本
-- =============================================================

SELECT DB_NAME() AS [当前数据库];  -- 先确认不是 master
GO

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

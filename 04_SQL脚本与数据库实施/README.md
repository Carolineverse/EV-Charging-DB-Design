# 新能源汽车充电平台 · 数据库课设（D 线完整实施包）

本包为 **D 成员**的交付：C 设备监控工单（12 表）+ D 运营商结算（7 表）+ R 公共权限（9 表），共 **28 张表**，以及视图、存储过程、触发器、5 条多表查询、Python 持久层、pytest 与测试数据。

## 一、环境要求

- SQL Server（2016+，DDL 使用 `ISJSON`；需支持 `HASHBYTES('SHA2_256')` 与分区）
- SSMS 18/19/20
- Python 3.9+
- ODBC Driver 17 或 18 for SQL Server
- 依赖：`SQLAlchemy==2.0.36`、`pyodbc==5.3.0`、`pytest==8.4.2`（见 `requirements.txt`）

## 二、目录结构

```
sql/schema/    建表（r_core 9 / c_partition / c_core 12 / d_core 7）
sql/constraints/  外键 + 索引（59 FK / 37 索引）
sql/seed/      种子（00_b_fixture B 精简夹具 / r_base / c_base / d_base）
sql/views/     6 个视图
sql/routines/  6 个过程（派单/生成/差异关闭/终审/开票/红冲）
sql/queries/   5 条多表查询
src/evplatform/  db.py / models.py / services.py
tests/          pytest 用例
```

## 三、从空库安装

**方式 A（推荐，SQLCMD 模式一键）**：SSMS 打开 `install_all.sql`，菜单「查询 → SQLCMD 模式」勾选后执行。

**方式 B（手动按顺序）**，每个文件一个查询窗口，先选中目标库（`SELECT DB_NAME()`）：

1. `sql/schema/r_core.sql`
2. `sql/seed/r_base.sql`
3. `sql/seed/00_b_fixture.sql`   ← B 精简夹具（联调时删除，用 B 真脚本）
4. `sql/schema/c_partition.sql`
5. `sql/schema/c_core.sql`
6. `sql/schema/d_core.sql`
7. `sql/constraints/d_constraints.sql`
8. `sql/views/d_views.sql`
9. `sql/routines/c_dispatch.sql`
10. `sql/routines/d_generate.sql`
11. `sql/routines/d_flows.sql`
12. `sql/seed/c_base.sql`
13. `sql/seed/d_base.sql`

装完校验：

```sql
SELECT COUNT(*) AS table_count FROM sys.tables WHERE schema_id = SCHEMA_ID('dbo');  -- 夹具含 B 表时 > 28
SELECT COUNT(*) FROM dbo.SettlementStatement;   -- 20
SELECT COUNT(*) FROM dbo.SettlementDetail;      -- 40
SELECT COUNT(*) FROM dbo.DeviceMonitoringData;  -- 40
```

## 四、Python 与测试

```powershell
$env:PYTHONPATH = "$PWD\src"
$env:EV_DB_ODBC = "DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\SQLEXPRESS;DATABASE=EV_D_TEST;Trusted_Connection=yes;TrustServerCertificate=yes"
.\.venv\Scripts\python.exe -m evplatform.db
.\.venv\Scripts\python.exe -m pytest -q
```

## 五、5 条多表查询（`sql/queries/q01_q05.sql`）

| 编号 | 场景 | 关系数 | 负责 |
|---|---|---|---|
| Q01 | 场站设备统计（桩/枪/可用枪） | 4 | B |
| Q02 | 场站近 30 天分时段电量与收入 | 4 | B |
| Q03 | 企业月结金额/笔数/结清 | 4 | B |
| Q04 | 告警与工单进度及工程师 | 7 | D |
| Q05 | 运营商账期应结/差异/开票汇总 | 6 | D |

## 六、结算演示链路

```
生成结算单 usp_GenerateSettlement（含事项分派权限校验）
  → 登记差异 register_difference → 关闭差异 usp_CloseDifference（R01 审批）
  → 终审 usp_ConfirmSettlement（无待处理差异才放行）
  → 开票 usp_RegisterInvoice（校验剩余可开票额）
  → 红冲申请 usp_ApplyRedFlush（R03，status=0）→ 红冲审批 usp_ApproveRedFlush（R01，写红票号，status=-1）
  → 结转审批 usp_ApproveCarryover（PENDING→APPROVED）→ 应用 usp_ApplyCarryover（只标 APPLIED，不写 adjustment_amount）
  → 漏单补入 usp_SupplementDetail（核对资格后写明细）→ 核对关闭 usp_CloseReviewCase
```

## 七、与 B 合并注意事项

1. **删除 `sql/seed/00_b_fixture.sql`**，改用 B 的 Operator/Station/Pile/Gun/Order/Payment/Refund 真实脚本。
2. **核对 `v_OrderSettlementSource` 列名**（`is_settleable`/`settled_at`/`settlement_source`/`refund_state_snapshot` 等），与 `usp_GenerateSettlement` 头部注释一致。
3. R04/R05 车主与企业主体由 B 的种子补充；本夹具中的 20 车主 + 3 企业仅用于 D 自测。
4. 每表 ≥20 条的条数例外：`SysRole`(5)、`AlarmLevelPolicy`(3)、`AlarmCodeDict`(10)、`OperatorSettlementRate`(6) 属固定字典，请组长统一核验。

## 八、完整性保护

- `trg_OperationLog_Protect`：OperationLog 只追加，禁止 UPDATE/DELETE。
- 过滤唯一索引：`SettlementInvoice` 票号去重、同蓝票只许一张有效红票；`SettlementReviewCase` 按退款号/企业凭据去重。
- 结算单「场站+账期」唯一、明细「结算单+订单」唯一、结转「退款号」唯一。

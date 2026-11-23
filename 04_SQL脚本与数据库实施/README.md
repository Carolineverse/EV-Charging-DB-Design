# 新能源汽车充电桩运营服务平台 · 数据库实施说明

本目录是课程设计《新能源汽车充电桩运营服务平台》的**完整数据库实现**：62 张表、15 个视图、18 个存储过程、2 个触发器、5 条多表查询、Python 持久层，以及配套的种子数据、测试与验收脚本。

用 `install_all.sql` 一条命令即可从空库装出全部对象并加载演示数据。

---

## 一、环境要求

| 项 | 要求 | 本项目实测环境 |
|---|---|---|
| 数据库 | SQL Server 2016+（需 `ISJSON`、分区、`CREATE OR ALTER`） | SQL Server 17.0 Express |
| 客户端 | SSMS 18+ | SSMS 21 |
| Python | 3.9+ | 3.9.0 |
| ODBC | Driver 17/18 for SQL Server | ODBC Driver 18 |
| 依赖 | `SQLAlchemy==2.0.36`、`pyodbc==5.3.0`、`pytest==8.4.2` | 同左 |

> **Express 版限制**：不支持备份压缩（`BACKUP ... WITH COMPRESSION` 报错 1844），不支持事务日志备份。

---

## 二、目录结构

```
04_SQL脚本与数据库实施/
├─ install_all.sql              全组一键安装（SQLCMD 模式）
├─ install_d_standalone.sql     D 线独立安装（使用旧夹具，含 ST-001 等）
├─ requirements.txt
├─ sql/
│  ├─ schema/       建表：r_core(9) c_partition c_core(12) d_core(7) 20_A1(7) 20_B(8) 20_A2(19)
│  ├─ constraints/  外键与索引：A1/B/A2 分模块 + 31/35/36 跨线 + d_constraints
│  ├─ views/        视图：45_A1(3) 46_B(2) 47_B(1) 48_A2(3) d_views(6)
│  ├─ routines/     过程：40_B 核价 41_A1 状态 42_A2 月结 c_dispatch d_generate d_flows d_register_carryover
│  ├─ security/     加密：主密钥/证书/对称密钥 + 加解密过程
│  ├─ maintenance/  运维：全量/差异备份与恢复演练脚本
│  ├─ seed/         种子：r_base 50 51 60 c_base_integration d_base 70 + 独立安装用三份
│  ├─ queries/      查询：Q01 Q02 Q03 q04 q05 + 合订稿
│  └─ acceptance/   验收：01 基线导出 02 联调验收 03 基线差集
├─ src/evplatform/  Python 持久层（11 个模块）
├─ tests/           pytest 用例 + 20 个 SQL 回归脚本
├─ docs/（仓库根）  安全策略、脱敏加密、备份恢复、联调验收、查询执行计划
└─ scripts/（仓库根）执行计划采集脚本
```

---

## 三、快速开始

### 第 1 步：准备空库

```powershell
sqlcmd -S ".\SQLEXPRESS" -d master -E -b -C -Q "IF DB_ID(N'EV_B_TEST') IS NOT NULL BEGIN ALTER DATABASE EV_B_TEST SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE EV_B_TEST; END; CREATE DATABASE EV_B_TEST;"
```

### 第 2 步：一键安装

```powershell
cd "D:\EV-Charging-DB-Design\04_SQL脚本与数据库实施"
sqlcmd -S ".\SQLEXPRESS" -d EV_B_TEST -E -b -C -I -f 65001 -v EV_MASTER_KEY_PASSWORD="你的主密钥口令" -i install_all.sql
```

**三个必带参数**：

| 参数 | 作用 | 漏掉的后果 |
|---|---|---|
| `-I` | `QUOTED_IDENTIFIER ON` | 监测表筛选索引建不出来（错误 1934） |
| `-f 65001` | 按 UTF-8 读脚本 | 中文乱码，`N'...'` 字面量被破坏 |
| `-v EV_MASTER_KEY_PASSWORD` | 数据库主密钥口令 | `CREATE MASTER KEY` 失败，加密种子报错 |

**必须从本目录启动**，因为 `install_all.sql` 用 `:r sql\schema\...` 相对路径引用子脚本。

### 第 3 步：验收

```powershell
# 表数量 + 逐表行数 + 权限矩阵 + 专用订单 + 结算六项（失败即 THROW，成功无输出）
sqlcmd -S ".\SQLEXPRESS" -d EV_B_TEST -E -b -C -I -f 65001 -i "sql\acceptance\02_verify_integration.sql"
"02_EXIT=$LASTEXITCODE"

# 与装库前基线做双向差集
sqlcmd -S ".\SQLEXPRESS" -d EV_B_TEST -E -b -C -I -f 65001 -i "sql\acceptance\03_compare_baseline.sql"
"03_EXIT=$LASTEXITCODE"
```

两个 `EXITCODE` 均为 `0` 即通过。

### 第 4 步：跑测试

```powershell
$env:PYTHONPATH = "$PWD\src"
$env:EV_DB_ODBC = "DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\SQLEXPRESS;DATABASE=EV_B_TEST;Trusted_Connection=yes;TrustServerCertificate=yes"
.\.venv\Scripts\python.exe -m pytest tests -q
```

```powershell
# SQL 层回归（20 个脚本，全部在事务内建夹具并回滚）
Get-ChildItem tests -Filter "test_*.sql" | ForEach-Object {
  & sqlcmd -S ".\SQLEXPRESS" -d EV_B_TEST -E -b -C -I -f 65001 -i $_.FullName | Out-Null
  "{0,-46} exit={1}" -f $_.Name, $LASTEXITCODE
}
```

---

## 四、安装顺序

`install_all.sql` 已按依赖排好，共 38 个 `:r`：

```
1) 建表      r_core → c_partition → c_core → d_core → 20_A1 → 20_B → 20_A2
2) 约束      A1/B/A2 内部 FK 与索引 → 31 跨线 → 35 → 36 → d_constraints
3) 视图      45_A1 → 46_B → 47_B(结算来源) → 48_A2 → d_views
4) 过程      40_B → 41_A1 → 42_A2 → c_dispatch → d_generate → d_flows → d_register_carryover
5) 安全      00_crypto_keys → usp_encrypt_decrypt   ← 必须早于种子
6) 种子      r_base → 50 → 51 → 60 → c_base_integration → d_base → 70
```

关键点：
- **跨模块外键必须等父表就绪**，所以拆成 `31/35/36` 三个文件；
- **加密密钥必须早于种子**，因为种子写 `*_ciphertext` 时要调用加解密过程；
- **70 号种子放在 `d_base` 之后**，它补的 20 笔企业订单不能进入已生成的结算单。

---

## 五、数据库对象清单

### 62 张表（按业务线）

| 模块 | 表数 | 主要内容 |
|---|---:|---|
| R 公共 | 9 | 角色、账号、员工、车主、企业、权限、授权、操作日志、事项分派 |
| C 设备监控工单 | 12 | 监测数据（分区）、告警等级/告警码字典、告警、工单、场站分配、值班、报文、通知、反馈、反馈告警、故障码映射 |
| D 运营商结算 | 7 | 分成费率、结算单、结算明细、对账差异、开票、跨期结转、人工复核 |
| A1 场站设施 | 7 | 运营商、场站、充电桩、充电枪、状态历史、通信配置、资产事项 |
| B 订单计费 | 8 | 计费版本、计费分段、充电订单、费用明细、支付、退款、电量采样、订单指令 |
| A2 用户会员 | 19 | 会员等级、车辆、车队、企业卡与绑定、额度、活动、券与核销、钱包与流水、发票、企业月结 |

### 15 个视图（每条业务线 3 个）

| 业务线 | 视图 |
|---|---|
| A1 | `v_A1StationDeviceOverview`、`v_A1GunPileAvailability`、`v_A1AssetCaseTrace` |
| B | `v_BOrderFeeSegments`、`v_BPaymentRefundTrace`、`v_OrderSettlementSource` |
| A2 | `v_A2MemberWalletSummary`、`v_A2CouponRedemptionTrace`、`v_A2EnterpriseMonthlyDetail` |
| C | `v_DeviceReportAbnormal`、`v_PendingAlarm`、`v_WorkOrderProgress` |
| D | `v_SettlementLedger`、`v_SettlementDifference`、`v_InvoiceBalanceAndRed` |

### 18 个过程 + 2 个触发器

| 业务线 | 过程 |
|---|---|
| A1 | `usp_A1_UpdateDeviceStatus` |
| B | `usp_PriceChargingOrder` |
| A2 | `usp_A2_GenerateEnterpriseSettlement` |
| C | `usp_DispatchWorkOrder` |
| D | `usp_GenerateSettlement`、`usp_RegisterCarryover`、`usp_RegisterDifference`、`usp_CloseDifference`、`usp_ConfirmSettlement`、`usp_RegisterInvoice`、`usp_ApplyRedFlush`、`usp_ApproveRedFlush`、`usp_ApproveCarryover`、`usp_ApplyCarryover`、`usp_CloseReviewCase`、`usp_SupplementDetail`、`usp_LockSettlementRefundOrder`、`usp_CheckSettlementRefundAmount` |

触发器：`trg_OperatorSettlementRate_NoOverlap`（费率区间防重叠）、`trg_OperationLog_Protect`（审计日志禁删）。

### 5 条多表查询

| 编号 | 场景 | 涉及表数 |
|---|---|---:|
| Q01 | 场站设备统计（桩/枪/可用枪） | 4 |
| Q02 | 分时段电量与收入构成 | 5 |
| Q03 | 企业月结账单明细 | 3 |
| Q04 | 场站告警→工单→工程师（默认 `B_DEMO_ST01`） | 7 |
| Q05 | 结算差异与开票余额（默认 `202610`） | 3 |

执行计划与 IO/耗时见 `docs/查询执行计划.md`，原始计划见 `docs/plans/*.sqlplan`。

---

## 六、Python 持久层（`src/evplatform/`）

| 模块 | 职责 |
|---|---|
| `db.py` | 从 `EV_DB_ODBC` 建引擎；`SessionLocal` 延迟建连 |
| `models.py` | 10 张表的 ORM 映射 |
| `orders.py` | `open_personal_order`：锁枪 → 校验占用 → 开单（调用方事务） |
| `order_queries.py` | `list_orders_page`：按 `created_at DESC, order_id DESC` 稳定分页 |
| `billing.py` | `price_order`：调用核价过程 |
| `payments.py` | `record_payment` / `request_refund` / `complete_refund`：行锁、幂等、分次支付 |
| `monitoring.py` | `insert_monitoring_batch`：监测数据批量写入，单事务，失败整批回滚 |
| `services.py` | 业务门面：派单、结算生成、差异、终审、开票、红冲、结转、复核、权限判定、场站范围过滤 |
| `auth.py` | 登录安全：PBKDF2-HMAC-SHA256（10 万轮 + 16 字节随机盐）、失败 5 次锁定、会话超时 |
| `masking.py` | `mask_phone` / `mask_plate` 展示脱敏 |

---

## 七、安全与完整性

| 机制 | 实现 |
|---|---|
| 密码存储 | `pbkdf2_sha256$100000$<salt_hex>$<hash_hex>`，存于 `SysAccount.password_hash VARCHAR(255)` |
| 登录保护 | 失败计数递增；连续 5 次置 `status=0` 锁定；成功清零并写 `last_login_at` |
| 会话超时 | `session_expired(last_login_at, 30)` |
| RBAC | 70 权限 / 84 授权；`has_permission()` 布尔判定；`filter_by_scope()` 按场站范围过滤 |
| 敏感导出 | `SENSITIVE_EXPORT` 仅在权限字典中定义，**默认不授予任何角色** |
| 加密存储 | `ENCRYPTBYKEY` + AES-256 对称密钥；手机号、车牌存 `VARBINARY(256)` 密文（实测 68 字节），另存 SHA-256 摘要用于等值查询 |
| 脱敏展示 | `mask_phone('13800001234') → '138****1234'`、`mask_plate` |
| 审计保护 | `trg_OperationLog_Protect` 禁止对 `OperationLog` 做 UPDATE/DELETE |
| 备份恢复 | `sql/maintenance/backup_restore.sql`：全量 + 差异 + `RESTORE VERIFYONLY` |

---

## 八、文档索引

| 文档 | 内容 |
|---|---|
| `docs/联调验收.md` | 加载顺序、62 表目标、本机执行步骤、20 笔专用订单清单 |
| `docs/查询执行计划.md` | Q01–Q05 的行数、逻辑读、耗时、主要算子与结论 |
| `docs/安全策略.md` | 加盐哈希、失败锁定、会话超时、RBAC、数据范围、敏感导出 |
| `docs/脱敏与加密方案.md` | 哈希+密文双列设计、密钥对象、主密钥口令 |
| `docs/备份与恢复策略.md` | 全量/差异周期、RPO/RTO、Express 限制、演练步骤 |

---

## 九、常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| 错误 1934：`QUOTED_IDENTIFIER` 设置不正确 | `sqlcmd` 默认 `QUOTED_IDENTIFIER OFF` | 命令加 `-I` |
| 中文乱码 / `N'...'` 语法错 | 脚本是 UTF-8，`sqlcmd` 按 GBK 读 | 加 `-f 65001` |
| `CREATE MASTER KEY` 失败 | 未传主密钥口令 | 加 `-v EV_MASTER_KEY_PASSWORD="..."` |
| `:r` 找不到文件 | 不在本目录启动 | `cd` 到本目录再执行 |
| 50163 要求空库 | 库里有残留对象 | 在 `master` 上下文 `DROP DATABASE` 后重建 |
| 备份报错误 5 拒绝访问 | 备份到用户目录，服务账号无权限 | 用相对文件名，落到实例默认备份目录 |
| 备份报错误 1844 | Express 版不支持压缩 | 去掉 `WITH COMPRESSION` |
| `pytest` 报 `paginate_alarms()` 缺参数 | 旧调用点未传 `account_id` | 补传账号参数 |

---

## 十、与 D 线独立安装的区别

| 入口 | 用途 | 规模（实测） | 种子 |
|---|---|---|---|
| `install_all.sql` | 全组联调 | **62 表 / 25 结算单 / 28 明细** | `r_base` + B 正式种子(50/51) + `60` + `c_base_integration` + `d_base` + `70` |
| `install_d_standalone.sql` | D 线单独自测，可脱离 B 的种子 | **35 表 / 25 结算单 / 50 明细 / 40 监测** | `r_base` + `00_b_fixture`（`ST-001` 等旧编号）+ `c_base` + `d_base_standalone` |

两套入口互不依赖：全组安装**不加载** `00_b_fixture.sql`。独立安装入口的目标库限制为 `EV_D_DEV` / `EV_D_TEST`，全组入口限制为 `EV_B_TEST`。

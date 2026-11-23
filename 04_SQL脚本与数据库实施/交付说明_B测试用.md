# 整合交付说明（B 测试用）

## 一、交付信息

| 项 | 内容 |
|---|---|
| 仓库 | `https://github.com/Carolineverse/EV-Charging-DB-Design.git` |
| 分支 | `integration` |
| 提交 | **`d00f66c`**（`d00f66cd980ff2d83a07dbade2f21a8435bc419b`） |
| 实施目录 | `04_SQL脚本与数据库实施` |
| 目标库 | `EV_B_TEST`（全组联调）；`EV_D_DEV` / `EV_D_TEST`（D 独立自测） |

### 本机环境（供对照）

| 项 | 版本 |
|---|---|
| SQL Server | 17.0.1000.7 Express，实例 `.\SQLEXPRESS` |
| SSMS | 21 |
| Python | 3.9.0（venv 在实施目录 `.venv`） |
| 依赖 | SQLAlchemy 2.0.36 / pyodbc 5.3.0 / pytest 8.4.2 |
| ODBC | Driver 18 for SQL Server |

---

## 二、本机验证结果（交付前最后一次完整运行）

| 检查 | 期望 | 本机实测 |
|---|---|---|
| 空库安装 | 无错误 | ✅ 无错误 |
| `dbo` 表数 | 62 | ✅ 62 |
| 逐表行数 | 业务表 ≥20 | ✅ 62 张逐项 `OK` |
| 结算单 / 明细 | 25 / 28 | ✅ 25 / 28 |
| 已应用结转 / 已关闭差异 | 20 / 20 | ✅ 20 / 20 |
| 蓝票 / 核对事项 | 20 / 20 | ✅ 20 / 20 |
| 权限定义 / 授权 | 70 / 84 | ✅ 70 / 84 |
| `SENSITIVE_EXPORT` | 定义 1 / 授权 0 | ✅ 1 / 0 |
| 基线双向差集 | 0 行 | ✅ 重复/缺失/额外均为空 |
| pytest | 全通过 | ✅ **63 passed** |
| SQL 回归测试 | 20 个 `exit=0` | ✅ 20 / 20 |
| 独立安装入口 | 可装通 | ✅ 35 表 / 25 单 / 50 明细 / 40 监测 |

**测试数据例外**（系统预设枚举与全局配置，行数由设计固定）：

| 表 | 行数 | 依据 |
|---|---:|---|
| `SysRole` | 5 | R01–R05 五种业务角色 |
| `AlarmLevelPolicy` | 3 | 一般 / 重要 / 紧急 |
| `MemberLevel` | 3 | L01 普通 / L02 银卡 / L03 金卡 |
| `DeviceCommunicationConfig` | 1 | 全局心跳与离线阈值单例 |
| `AlarmCodeDict` | 10 | 告警码字典（覆盖 AL001–AL007 及扩展） |

---

## 三、复现步骤

### 第 1 步：准备空库

```powershell
sqlcmd -S "你的实例" -d master -E -b -C -Q "IF DB_ID(N'EV_B_TEST') IS NOT NULL BEGIN ALTER DATABASE EV_B_TEST SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE EV_B_TEST; END; CREATE DATABASE EV_B_TEST;"
```

### 第 2 步：一键安装（关键：三个参数）

```powershell
cd "04_SQL脚本与数据库实施"
sqlcmd -S "你的实例" -d EV_B_TEST -E -b -C -I -f 65001 -v EV_MASTER_KEY_PASSWORD="Course@2026DbKey" -i install_all.sql
```

| 参数 | 作用 | 漏掉的后果 |
|---|---|---|
| `-I` | `QUOTED_IDENTIFIER ON` | 监测表筛选索引建不出来（错误 1934） |
| `-f 65001` | 按 UTF-8 读脚本 | 中文乱码，`N'...'` 字面量被破坏 |
| `-v EV_MASTER_KEY_PASSWORD` | 数据库主密钥口令 | `CREATE MASTER KEY` 失败，加密种子报错 |

**必须在本目录执行**，因为 `install_all.sql` 用 `:r sql\...` 相对路径引用子脚本。

### 第 3 步：验收（两个 EXITCODE 都要 0）

```powershell
sqlcmd -S "你的实例" -d EV_B_TEST -E -b -C -I -f 65001 -i "sql\acceptance\02_verify_integration.sql"
"02_EXIT=$LASTEXITCODE"

sqlcmd -S "你的实例" -d EV_B_TEST -E -b -C -I -f 65001 -i "sql\acceptance\03_compare_baseline.sql"
"03_EXIT=$LASTEXITCODE"
```

`02` 成功时**不抛错**（失败才 `THROW`）；正常会打印 62 表逐项检查、权限矩阵、20 笔专用订单、六项计数。

### 第 4 步：pytest（期望 63 passed）

```powershell
$env:PYTHONPATH = "$PWD\src"
$env:EV_DB_ODBC = "DRIVER={ODBC Driver 18 for SQL Server};SERVER=你的实例;DATABASE=EV_B_TEST;Trusted_Connection=yes;TrustServerCertificate=yes"
.\.venv\Scripts\python.exe -m pytest tests -q
```

### 第 5 步：SQL 回归测试（期望 20 个 `exit=0`）

```powershell
Get-ChildItem tests -Filter "test_*.sql" | ForEach-Object {
  & sqlcmd -S "你的实例" -d EV_B_TEST -E -b -C -I -f 65001 -i $_.FullName | Out-Null
  "{0,-46} exit={1}" -f $_.Name, $LASTEXITCODE
}
```

> 每个 SQL 测试都在事务内建夹具并回滚，**不会污染验收数据**；跑完请再执行一次 `02`，六项数字应保持不变。

---

## 四、文件清单与职责

### 4.1 根目录

| 文件 | 作用 |
|---|---|
| `install_all.sql` | **全组一键安装**，38 个 `:r`；含空库/账期/库名前置检查、`SET QUOTED_IDENTIFIER ON`、末尾 25/28/20/20/20/20 硬校验 |
| `install_d_standalone.sql` | **D 线独立安装**，15 个 `:r`，只允许 `EV_D_DEV` / `EV_D_TEST` |
| `README.md` | 实施说明：环境、目录、安装顺序、对象清单、安全、验收、常见问题 |
| `requirements.txt` | Python 依赖版本 |
| `交付说明_B测试用.md` | 本文档 |

### 4.2 `sql/schema/` — 建表（7 个文件 · 62 张表）

| 文件 | 含哪些表（中文） |
|---|---|
| `r_core.sql` | 角色、账号、员工档案、车主档案、企业档案、权限字典、角色授权、操作日志、事项分派 |
| `c_partition.sql` | 分区函数与分区方案（监测数据按"年月 + 桩号哈希"分区） |
| `c_core.sql` | 监测数据（分区表）、告警等级策略、告警码字典、告警、工单、员工负责场站、值班排班、设备报文、通知日志、用户反馈、反馈关联告警、故障码映射 |
| `d_core.sql` | 分成费率、结算单、结算明细、对账差异、开票记录、跨期结转、人工复核事项 |
| `20_A1_tables.sql` | 运营商、场站、充电桩、充电枪、设备状态历史、通信配置、设备资产事项 |
| `20_B_tables.sql` | 计费规则版本、计费分段规则、充电订单、订单费用明细、支付记录、退款记录、电量采样、订单指令 |
| `20_A2_tables.sql` | 会员等级、用户等级、车辆、车队成员、企业卡、卡绑定、企业额度、优惠活动、活动适用场站、活动适用等级、用户券、券核销、用户钱包、钱包流水、个人发票申请、企业月结单、企业月结明细、企业服务申请、发票调整 |

### 4.3 `sql/constraints/` — 外键与索引（10 个文件）

| 文件 | 内容 |
|---|---|
| `30_A1_foreign_keys.sql` / `30_A1_indexes.sql` | A1 内部 7 个外键 / 7 个索引 |
| `30_B_foreign_keys.sql` / `30_B_indexes.sql` | B 内部 13 个外键 / 12 个索引 |
| `30_A2_foreign_keys.sql` / `30_A2_indexes.sql` | A2 内部 15 个外键 / 21 个索引 |
| `31_A1B_R_C_foreign_keys.sql` | A1/B → 公共模块的跨线 7 个外键 |
| `35_A2_A1B_foreign_keys.sql` | A2 → A1/B 的 7 个外键 |
| `36_A2_R_foreign_keys.sql` | A2 → 公共模块的 14 个外键 |
| `d_constraints.sql` | D 线 59 外键 + 6 唯一约束 + 37 索引 + 费率防重叠触发器 |

### 4.4 `sql/views/` — 视图（5 个文件 · 15 个视图）

| 文件 | 视图（中文） |
|---|---|
| `45_A1_views.sql` | 场站设备总览、枪桩可用性、资产事项追溯 |
| `46_B_views.sql` | 订单计费分段、支付退款追溯 |
| `47_B_order_settlement_source.sql` | **结算来源视图**（37 列，判断每笔订单能否结算及原因） |
| `48_A2_views.sql` | 会员钱包汇总、券核销追溯、企业月结明细 |
| `d_views.sql` | 异常报文、待处理告警、工单进度、**结算台账**、差异追溯、开票余额与红冲 |

### 4.5 `sql/routines/` — 过程与触发器（7 个文件 · 18 过程 + 2 触发器）

| 文件 | 过程（中文） |
|---|---|
| `40_B_price_charging_order.sql` | 充电结束后按时段核价（峰平谷分段累加、免费时长折抵、起步补差） |
| `41_A1_update_device_status.sql` | 改桩/枪状态并写状态历史（同一事务） |
| `42_A2_generate_enterprise_settlement.sql` | 生成企业月结单（幂等） |
| `c_dispatch.sql` | 派维修工单（按场站、值班、在办工单校验） |
| `d_generate.sql` | 生成运营商结算单（按场站+账期，锁定后不可改） |
| `d_flows.sql` | 差异登记/关闭、终审、开票、红冲申请/审批、结转审批/应用、复核关闭、补明细、锁单、额度校验 + `trg_OperationLog_Protect` |
| `d_register_carryover.sql` | 登记跨期扣回（锁定后退款） |

### 4.6 `sql/security/` 与 `sql/maintenance/`

| 文件 | 作用 |
|---|---|
| `security/00_crypto_keys.sql` | 数据库主密钥 → 证书 `Cert_EV_Sensitive` → AES-256 对称密钥 `Key_EV_Sensitive` |
| `security/usp_encrypt_decrypt.sql` | `usp_EncryptSensitive` / `usp_DecryptSensitive`（带 OUTPUT 参数） |
| `maintenance/backup_restore.sql` | 全量/差异备份 + `RESTORE VERIFYONLY`，恢复演练命令保留为注释 |

### 4.7 `sql/seed/` — 种子数据（10 个文件）

| 文件 | 内容（中文） |
|---|---|
| `r_base.sql` | 5 个角色 + 70 权限 + 84 授权 + 8 个员工账号 |
| `50_B_demo_settlement_data.sql` | B 基础样例：运营商/场站/桩/枪/用户/企业/费率 + 3 笔订单（手机号已加密） |
| `51_B_demo_enterprise_settlement.sql` | 企业样例：车队/卡/额度/企业订单 + 月结（车牌已加密） |
| `60_D_demo_bulk_data.sql` | D 补的 4 个场站 + 25 笔订单（202606–202610） |
| `c_base_integration.sql` | C 线：40 报文 / 40 监测 / 20 告警 / 20 工单 / 20 通知 / 20 反馈 / 32 映射 |
| `d_base.sql` | 费率 + 25 条分派 + 生成 25 张结算单 + 差异/发票/结转/复核 |
| `70_integration_coverage.sql` | 补齐剩余业务表到 20 行 + 20 笔**不进结算**的企业订单（`BLK_`） |
| `00_b_fixture.sql` | **仅独立入口使用**的 B 最小夹具（`ST-001` 等旧编号），全组安装不加载 |
| `c_base.sql` / `d_base_standalone.sql` | 独立入口用的 C / D 种子 |

### 4.8 `sql/queries/` — 五条多表查询（6 个文件）

| 文件 | 场景 | 涉及表数 |
|---|---|---:|
| `Q01_station_device_statistics.sql` | 场站设备统计 | 4 |
| `Q02_period_energy_revenue.sql` | 分时段电量与收入构成 | 5 |
| `Q03_enterprise_monthly_bill.sql` | 企业月结账单明细 | 3 |
| `q04.sql` | 场站告警→工单→工程师（默认 `B_DEMO_ST01`） | 7 |
| `q05.sql` | 结算差异与开票余额（默认 `202610`） | 3 |
| `q01_q05.sql` | 五条合订稿（演示用，同时含视图与参数注释） | — |

### 4.9 `sql/acceptance/` — 验收（3 个文件）

| 文件 | 作用 |
|---|---|
| `01_export_baseline.sql` | 清库前导出 25 个「场站+账期」组合与 28 条明细稳定键（生成基线） |
| `02_verify_integration.sql` | 62 表逐项行数、例外字典、权限矩阵双向差集、20 笔专用订单排除、结算六项；失败即 `THROW` |
| `03_compare_baseline.sql` | 与基线做重复/缺失/额外三类差集（基线以表变量内嵌，不依赖外部 CSV） |

### 4.10 `src/evplatform/` — Python 持久层（13 个模块）

| 模块 | 作用 |
|---|---|
| `db.py` | 从 `EV_DB_ODBC` 建引擎；`SessionLocal` 延迟建连 |
| `models.py` | 10 张表的 ORM 映射 |
| `orders.py` | 开单：锁枪 → 校验占用 → 写订单（调用方事务） |
| `order_queries.py` | 订单分页：`created_at DESC, order_id DESC` 稳定排序 |
| `billing.py` | 调用核价过程 |
| `payments.py` | 支付、申请退款、完成退款（行锁、幂等、分次支付） |
| `monitoring.py` | 监测数据批量写入（单事务，失败整批回滚） |
| `services.py` | 业务门面：派单、结算生成、差异、终审、开票、红冲、结转、复核、权限判定、场站范围过滤、告警分页 |
| `auth.py` | 登录安全：PBKDF2-HMAC-SHA256（10 万轮 + 16 字节盐）、5 次失败锁定、会话超时 |
| `masking.py` | 手机号 / 车牌展示脱敏 |
| `stations.py` | A1：`update_device_status`（封装 `usp_A1_UpdateDeviceStatus`）、`list_stations_page` |
| `enterprise.py` | A2 企业客户：`open_enterprise_card`、`bind_card_vehicle`、`set_enterprise_quota`、`submit_service_application`、`list_enterprise_orders_page`、`settle_enterprise_order`、`is_promotion_applicable` |

### 4.11 `tests/` — 测试（17 个 Python 测试文件 + 20 个 SQL 脚本）

**Python（`conftest.py` 提供夹具与库名保护）**

| 文件 | 覆盖 |
|---|---|
| `test_db_connection.py` | 连接与库名 |
| `test_permission.py` | 权限判定 |
| `test_scope.py` | 场站范围过滤 |
| `test_workorder.py` | 派单 |
| `test_order_service.py` | 开单与稳定分页 |
| `test_billing_service.py` | 核价 |
| `test_payment_refund_service.py` | 支付、退款、钱包 |
| `test_settlement.py` | 结算生成 |
| `test_settlement_flow.py` | 差异 → 终审 → 开票 → 红冲全流程 |
| `test_carryover.py` | 跨期结转 |
| `test_monitoring_batch.py` | 批量写入与失败回滚 |
| `test_transaction_concurrency.py` | 事务边界与并发一致性 |
| `test_auth.py` | 加盐哈希、失败锁定、会话超时 |
| `test_crypto.py` | 加解密往返与摘要匹配 |
| `test_masking.py` | 脱敏格式 |
| `test_stations.py` | A1 设备状态变更与场站分页 |
| `test_enterprise.py` | A2 企业开卡、绑定、额度、申请、车队分页、订单结清、券适用判定 |

**SQL（事务内建夹具、自动回滚）**

| 类别 | 文件 |
|---|---|
| 约束（6） | `test_A1_constraints`、`test_A2_constraints`、`test_B_constraints`、`test_B_billingrule_unique`、`test_B_ChargingOrder_checks`、`test_B_sample_command_behavior` |
| 查询（3） | `test_Q01_station_device_statistics`、`test_Q02_period_energy_revenue`、`test_Q03_enterprise_monthly_bill` |
| 过程（2） | `test_usp_A1_UpdateDeviceStatus`、`test_usp_A2_GenerateEnterpriseSettlement` |
| 视图（9） | `test_v_A1AssetCaseTrace`、`test_v_A1GunPileAvailability`、`test_v_A1StationDeviceOverview`、`test_v_A2CouponRedemptionTrace`、`test_v_A2EnterpriseMonthlyDetail`、`test_v_A2MemberWalletSummary`、`test_v_BOrderFeeSegments`、`test_v_BPaymentRefundTrace`、`test_v_OrderSettlementSource` |

### 4.12 `docs/` 与 `scripts/`（仓库根）

| 文件 | 作用 |
|---|---|
| `docs/联调验收.md` | 加载顺序、62 表目标、本机执行步骤、20 笔专用订单清单 |
| `docs/查询执行计划.md` | Q01–Q05 的行数、逻辑读、耗时、主要算子与结论 |
| `docs/安全策略.md` | 密码哈希、失败锁定、会话超时、RBAC、范围过滤、审计保护 + 覆盖自查 |
| `docs/脱敏与加密方案.md` | 哈希+密文双列、密钥对象、主密钥口令、已验证结果 |
| `docs/备份与恢复策略.md` | 周期、RPO/RTO、演练步骤、本机实测与 Express 限制 |
| `docs/plans/Q01~Q05.sqlplan` + `_io.txt` | 执行计划原始证据（10 个文件） |
| `scripts/collect_plans.ps1` / `.py` | 采集执行计划并生成报告 |

---

## 五、安装加载顺序（38 个 `:r`）

```
1) 安全    security/00_crypto_keys → security/usp_encrypt_decrypt   ← 必须早于种子
2) 建表    r_core → c_partition → c_core → d_core → 20_A1 → 20_B → 20_A2
3) 约束    A1/B/A2 各自 foreign_keys+indexes → 31 → 35 → 36 → d_constraints
4) 视图    45_A1 → 46_B → 47_B(结算来源) → 48_A2 → d_views
5) 过程    40_B → 41_A1 → 42_A2 → c_dispatch → d_generate → d_flows → d_register_carryover
6) 种子    r_base → 50 → 51 → 60 → c_base_integration → d_base → 70
```

三个关键点：

1. **跨模块外键必须等父表就绪**，所以拆成 `31/35/36`；
2. **加密密钥必须早于种子**，因为种子写 `*_ciphertext` 要调用加解密过程；
3. **70 号种子放在 `d_base` 之后**，它补的 20 笔企业订单不能进入已生成的结算单。

---

## 六、常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| 错误 1934 `QUOTED_IDENTIFIER` | `sqlcmd` 默认 OFF | 命令加 `-I` |
| 中文乱码 / `N'...'` 语法错 | 脚本 UTF-8，`sqlcmd` 按 GBK 读 | 加 `-f 65001` |
| `CREATE MASTER KEY` 失败 | 未传主密钥口令 | 加 `-v EV_MASTER_KEY_PASSWORD="..."` |
| `:r` 找不到文件 | 不在实施目录执行 | `cd` 到实施目录 |
| 50162 库名不符 | 装到了别的库 | 用 `-d EV_B_TEST` |
| 50163 要求空库 | 库里有残留对象 | 先 `DROP DATABASE` 再重建 |
| 50164 账期未结束 | 系统日期早于 2026-11-01 | 调整系统时间或换库 |
| 50165 数量不符 | 种子未按顺序执行 | 确认 `70` 在 `d_base` 之后 |
| 备份错误 5 拒绝访问 | 备份到用户目录，服务账号无权限 | 用相对文件名（落实例默认备份目录） |
| 备份错误 1844 | Express 版不支持压缩 | 去掉 `WITH COMPRESSION` |
| `paginate_alarms()` 缺参数 | 旧调用点未传 `account_id` | 补传账号参数 |

---

## 七、可选：单独测试 D 线（独立入口）

```powershell
sqlcmd -S "你的实例" -d master -E -b -C -Q "IF DB_ID(N'EV_D_TEST') IS NOT NULL BEGIN ALTER DATABASE EV_D_TEST SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE EV_D_TEST; END; CREATE DATABASE EV_D_TEST;"
cd "04_SQL脚本与数据库实施"
sqlcmd -S "你的实例" -d EV_D_TEST -E -b -C -I -f 65001 -v EV_MASTER_KEY_PASSWORD="Course@2026DbKey" -i install_d_standalone.sql
```

预期结尾：`table_count = 35`、`settlement_count = 25`、`detail_count = 50`、`monitor_count = 40`。

---

# SQL Server 实施说明

目标开发库为 `EV_B_DEV`。脚本使用 SQL Server / SSMS 语法；运行前确认查询窗口连接到该库。

空库安装及结构/行为验收统一使用 `EV_B_TEST`。所有安装命令都通过 `sqlcmd -d EV_B_TEST` 指定目标库；约束脚本不自行切换数据库。

## A1 场站与充电设施

在 A1 七张表已创建后执行：

1. `sql/constraints/30_A1_foreign_keys.sql`：建立 A1 的七条模块内外键。
2. `sql/constraints/30_A1_indexes.sql`：建立物理设计定义的七个非聚集索引。
3. `sql/routines/41_A1_update_device_status.sql`：创建 `dbo.usp_A1_UpdateDeviceStatus`。
4. `tests/test_A1_constraints.sql` 和 `tests/test_usp_A1_UpdateDeviceStatus.sql`：运行 A1 约束与状态过程测试；夹具数据在事务中回滚，脚本拒绝在 `EV_B_TEST` 以外的数据库运行。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\constraints\30_A1_foreign_keys.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\constraints\30_A1_indexes.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\routines\41_A1_update_device_status.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_A1_constraints.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_usp_A1_UpdateDeviceStatus.sql
```

P-A1 只接受桩/枪二选一、物理设计字典内的目标状态和变更来源、非空原因。状态未变化时返回 `NO_CHANGE` 且不写历史；变化时原子更新当前状态与 DeviceStatusHistory。若过程加入调用方事务，会使用保存点；SQL Server 错误若使调用事务不可提交，调用方必须回滚该事务。过程在无外层事务时自行开启并提交事务。应用部署仍需限制该过程的执行权限到受控业务入口。

## Q01 场站设备统计

`sql/queries/Q01_station_device_statistics.sql` 按场站汇总桩数、枪数和 `ChargingGun.status='IDLE'` 的枪数。桩与枪先分别聚合，避免多枪造成桩数重复；没有桩的场站仍会输出。`idle_gun_count` 仅表示枪状态，不代表综合判定后的业务可用量。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\queries\Q01_station_device_statistics.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_Q01_station_device_statistics.sql
```

当前 TEST 没有持久化演示数据时，独立查询返回空集；回归测试在事务中创建两座场站、两根桩和三把枪，断言空站保留以及计数为 `2/3/2`，再回滚夹具。

## V01 场站设备概览

`sql/views/45_A1_views.sql` 创建 `dbo.v_A1StationDeviceOverview`，按场站汇总桩、枪总数及各状态数量。桩和枪分开聚合，空站保留；枪状态只作为设备状态展示，不推导综合业务可用量。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\views\45_A1_views.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_v_A1StationDeviceOverview.sql
```

## V02 桩枪状态明细

同一 `45_A1_views.sql` 还创建 `dbo.v_A1GunPileAvailability`。视图按桩/枪明细输出当前状态、设备上报状态及最近通信时间；无枪桩仍保留，枪列为空。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\views\45_A1_views.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_v_A1GunPileAvailability.sql
```

## V03 资产事项追溯

`45_A1_views.sql` 还创建 `dbo.v_A1AssetCaseTrace`，保留事项提交与审核字段、关联桩枪及当前桩归属场站。由于 A1 物理结构没有提交时的场站快照，`current_station_*` 明确表示查询时从桩关系派生的当前场站；账号以原始 ID 输出，不依赖 R 表。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\views\45_A1_views.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_v_A1AssetCaseTrace.sql
```

## V05/V06 B 侧明细视图

`sql/views/46_B_views.sql` 创建两个 B 侧视图：`dbo.v_BOrderFeeSegments` 按费用段输出费率、分段电量及逐段舍入的派生金额；`dbo.v_BPaymentRefundTrace` 先分别按订单汇总支付与退款，保持一订单一行，并区分成功、处理中、失败和取消退款。费用金额为派生值；支付退款视图保留 `PaymentRecord.refund_amount` 缓存汇总，供与成功退款记录对照。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\views\46_B_views.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_v_BOrderFeeSegments.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_v_BPaymentRefundTrace.sql
```

## V04 D 侧结算来源

`sql/views/47_B_order_settlement_source.sql` 创建 `dbo.v_OrderSettlementSource`，以 `order_id` 为粒度并输出 D `d_generate.sql` 头部声明的 12 列：`order_id`、`station_id`、`settlement_source`、`ended_at`、`settled_at`、`energy_kwh`、`electricity_base`、`service_base`、`minimum_adjustment`、`refund_state_snapshot`、`is_settleable`、`unsettleable_reason`。B 侧快照原列和审计字段仍保留。费用和支付/退款记录先分别聚合；未核价或费用事实不匹配时，结算金额字段返回 `NULL`。

视图另输出 `eligibility_status`、`eligibility_reason` 和 A2 企业回执检查列，便于 D 查询排除项。个人订单只允许无成功/处理中退款的来源行进入 D 快照；FAILED/CANCELLED 退款映射为 `FAILED_CANCELLED`。企业回执须匹配同一企业、成员、车辆、电量、应付金额，并属于订单 `end_time` 所在自然月；回执核对通过时，D 契约列 `is_settleable=1`，同时保留辅助状态 `REVIEW_REQUIRED`，因为物理设计要求 D 另核企业退款。`unsettleable_reason` 对可入来源的行为空；该视图不代替 D 的站月单生成或企业退款复核。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\views\47_B_order_settlement_source.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_v_OrderSettlementSource.sql
```

## V07/V08 A2 用户与优惠券追溯

`sql/views/48_A2_views.sql` 创建 A2 的 `dbo.v_A2MemberWalletSummary` 与 `dbo.v_A2CouponRedemptionTrace`。V07 展示 A2 已出现用户的当前会员等级及 `UserWallet.balance`；V08 以优惠券为粒度，保留未核销券并显示核销订单/用户一致性。R 的 `UserProfile` 不在当前 TEST 中，因此 V07 用户范围仅覆盖 A2 会员或钱包记录中出现的用户。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\views\48_A2_views.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_v_A2MemberWalletSummary.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_v_A2CouponRedemptionTrace.sql
```

## V09 A2 企业月结明细

同一 `48_A2_views.sql` 还创建 `dbo.v_A2EnterpriseMonthlyDetail`。视图以实际订单明细为粒度，输出企业月结主表、订单明细及订单事实，并提供账期是否等于实际 `ChargingOrder.end_time` 所在月、电量/金额快照是否匹配的标记；企业编号直接保留，不依赖 R 档案表。没有明细的零订单月结不会出现在此明细视图中；需要查看零汇总账单时使用 Q03 企业月结汇总查询。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\views\48_A2_views.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_v_A2EnterpriseMonthlyDetail.sql
```

## Q02 时段电量与核价金额

`sql/queries/Q02_period_energy_revenue.sql` 通过订单冻结的计费版本关联费用段和费率，只汇总 `priced_at` 已写入的订单。日期按费用段 `segment_start` 归属，区间为左闭右开；每段电费、折前服务费分别先舍入到分，再扣除已记录的 `free_service_fee`。结果表示已核价金额，不代表实际到账或结算收入。

编辑脚本顶部的 `@StationId`、`@StartInclusive` 和 `@EndExclusive` 后执行。TEST 回归使用已知的两个谷段和一个峰段，以及一笔日期范围外的订单；预期谷段电费为 `0.02`、折后服务费为 `0.01`，峰段电费和折后服务费各为 `0.01`，范围外费用不计入。测试调用正式核价过程并在事务结束时回滚全部夹具。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\queries\Q02_period_energy_revenue.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_Q02_period_energy_revenue.sql
```

## Q03 企业月结汇总

`sql/queries/Q03_enterprise_monthly_bill.sql` 通过 `EnterpriseSettlement`、`EnterpriseSettlementDetail`、`ChargingOrder` 汇总月结快照、明细总量、确认/付款状态，并核对订单实际结束月。查询以月结账头为主表左联明细汇总，因此零订单月份生成的 0 汇总账单仍显示，明细数、电量和金额按 0 展示。当前 TEST 未安装 R 的 `EnterpriseProfile`，查询使用 `enterprise_id` 作为企业标识；待 R 表就绪后可补企业名称展示。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\queries\Q03_enterprise_monthly_bill.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_Q03_enterprise_monthly_bill.sql
```

## A2 用户与会员运营

执行顺序：

1. `sql/schema/20_A2_tables.sql`：创建 A2 的 19 张表及列、主键、唯一约束和 CHECK。
2. `sql/constraints/30_A2_foreign_keys.sql`：创建 A2 模块内部外键。
3. `sql/constraints/30_A2_indexes.sql`：创建 A2 普通索引和过滤唯一索引。
4. `sql/constraints/35_A2_A1B_foreign_keys.sql`：A1 和 B 表已创建后，建立 A2 到 A1/B 的外键。
5. `sql/constraints/36_A2_R_foreign_keys.sql`：R 模块的 `UserProfile`、`EnterpriseProfile`、`SysAccount` 已创建后，建立 A2 到 R 的外键。
6. `tests/test_A2_constraints.sql`：运行 A2 结构与行为检查；全部测试数据在事务中回滚。

`20_A2_tables.sql` 不包含跨模块外键，因此可先于 R 表创建。A2 到 R 的最后 14 条外键须等 R 目标表就绪后执行；不能用占位表替代 R 的正式定义。A2 约束和索引脚本尊重调用方选择的目标数据库。

在 `EV_B_TEST` 安装 A2 时，可按上述顺序逐项运行脚本：

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\constraints\30_A2_foreign_keys.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\constraints\30_A2_indexes.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\constraints\35_A2_A1B_foreign_keys.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_A2_constraints.sql
```

### P-A2 企业月结生成

`sql/routines/42_A2_generate_enterprise_settlement.sql` 创建 `dbo.usp_A2_GenerateEnterpriseSettlement`。调用方提供 `enterprise_settlement_id`、企业和月初日期；过程按订单实际结束月入账，核验历史卡绑定、成员、车辆、企业专属冻结费率版本及订单启动月额度，按 `gross_amount - discount_amount` 生成应付快照。它不依赖企业个人支付记录；零订单月份也生成 0 汇总账单。同企业同自然月重复生成由行范围锁与唯一键拒绝。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\sql\routines\42_A2_generate_enterprise_settlement.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_usp_A2_GenerateEnterpriseSettlement.sql
```

额度月由 `start_time` 决定；月结账期由 `end_time` 决定。过程要求 `energy_kwh > 0`，未把缺少有效计量依据的零电量订单计入企业月结。月结状态由 `confirmed_at`/`paid_at` 快照推导，不新增物理列。

## B 唯一性测试

运行 B 测试前确认目标为 `EV_B_TEST`。四个 B SQL 测试文件都会检查当前数据库并拒绝在其他库运行；写入型测试会在事务中创建临时数据并回滚。`test_B_sample_command_behavior.sql` 在相应 R/C 外键已部署时，需要 `UserProfile`、`SysAccount` 和至少七条 `DeviceReport` 测试记录。使用 `sqlcmd` 执行 UTF-8 脚本时指定 `-d EV_B_TEST -f i:65001`。

```powershell
Set-Location '04_SQL脚本与数据库实施'
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_B_constraints.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_B_ChargingOrder_checks.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_B_billingrule_unique.sql
sqlcmd -S "localhost\SQLEXPRESS" -E -d EV_B_TEST -C -b -f i:65001 -i .\tests\test_B_sample_command_behavior.sql
```

## B 持久层：同枪开单

`src/evplatform/db.py` 提供惰性绑定的 `SessionLocal`、声明式 `Base`，并保留测试可注入连接的 `create_engine_from_env` / `create_session_factory`。`src/evplatform/models.py` 映射 Operator、ChargingStation 和 ChargingOrder。`src/evplatform/order_queries.py` 提供按 `created_at DESC, order_id DESC` 稳定排序的 ORM 分页查询，页码从 1 开始、单页最多 100 条。

`src/evplatform/orders.py` 的 `open_personal_order` 由调用方提供 SQLAlchemy Session 和事务。服务先用 `UPDLOCK, HOLDLOCK` 锁定枪记录，再检查枪状态及未释放订单，最后插入个人订单；提交或回滚由调用方负责。

在 PowerShell 中从仓库根目录运行持久层测试。连接串只需设置在当前终端，且必须指向 `EV_B_TEST`：

```powershell
Set-Location '04_SQL脚本与数据库实施'
$env:PYTHONPATH = "$PWD/src"
$env:EV_DB_ODBC = 'DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost\SQLEXPRESS;DATABASE=EV_B_TEST;Trusted_Connection=yes;TrustServerCertificate=yes'
.\.venv\Scripts\python.exe -m pytest tests -q
```

测试要求对应表已安装。若已启用到 R 的外键，测试库需有可用的 `SysAccount` 和 `UserProfile` 样例。

`src/evplatform/payments.py` 提供 `record_payment`、`request_refund` 和 `complete_refund`，都要求调用方使用同一个 SQLAlchemy 事务。支付只登记成功凭据；允许分次付款，达到 `gross_amount - discount_amount` 时才首次写入 `PAID/settled_at`。渠道流水重试幂等，超额付款拒绝。`BALANCE` 支付会在同一事务扣钱包余额并写 WalletTransaction。

退款请求以 `PROCESSING` 预占退款额度；成功退款更新 PaymentRecord 与 ChargingOrder 累计，失败/取消释放预占。重复终态回调幂等，首次 `settled_at` 不改写。余额支付的成功退款会在同一事务返还钱包并写退款流水。当前 pytest 覆盖分次支付、重复/超额、并发重试、退款预占、成功/失败回调和余额支付/退款原子性。

```powershell
Set-Location '04_SQL脚本与数据库实施'
$env:PYTHONPATH = "$PWD/src"
$env:EV_DB_ODBC = 'DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost\SQLEXPRESS;DATABASE=EV_B_TEST;Trusted_Connection=yes;TrustServerCertificate=yes'
.\.venv\Scripts\python.exe -m pytest tests -q
```

## B 持久层：订单核价

`src/evplatform/billing.py` 的 `price_order` 在调用方事务中调用 `dbo.usp_PriceChargingOrder`。存储过程消费已保存的 `OrderFeeDetail` 分段：每段电费和折前服务费分别按 `ROUND(segment_energy_kwh × 单价, 2)` 计算；`service_base` 为折前服务费合计减去各段 `free_service_fee`；有电量时起步补差为 `max(minimum_amount - electricity_base - service_base, 0)`，零电量补差为 0。订单总额为电费、折后服务费和补差之和。

本阶段 `OrderFeeDetail` 分段电量必须来自明确的测试样例或可信上游结果。系统不根据缺失的边界读数自动插值或估算；缺少费用段或分段电量合计与订单核定电量不符时返回“计费输入不足”，不写订单金额、不设置 `priced_at`。

已有费用段必须连续、无间隙或重叠地覆盖订单起止时间，分段电量之和必须等于订单电量，且全部引用订单冻结的有效计费版本。`free_service_fee` 是上游按计量分段给出的金额，核价会验证它不超过对应服务费；分钟数本身不足以推导货币折抵。优惠核销由调用方在同一个 Session/事务中维护，企业订单核价尚待后续实现。自动采样插值和跨边界电量估算不属于本阶段实现范围。

部署表、外键和索引后执行 `sql/routines/40_B_price_charging_order.sql` 创建核价过程。

## B 订单与计费结构

部署 B 结构时，在 SSMS 中先切换到目标库并确认 `SELECT DB_NAME()` 的结果。按顺序执行 `sql/schema/20_B_tables.sql`、`sql/constraints/30_B_foreign_keys.sql`、`sql/constraints/30_B_indexes.sql` 和 `sql/routines/40_B_price_charging_order.sql`。运行 B 外键脚本前，A1、B、A2 对应的目标表都必须已创建；脚本不会替你切换或创建数据库。

A1、B、A2 建表文件均使用当前连接的数据库上下文。使用 `sqlcmd` 时用 `-d EV_B_TEST` 明确指定目标库；不要依赖 SSMS 上次选中的数据库。

`30_B_foreign_keys.sql` 包含 B 内部、B→A1 和 B→A2 外键。指向 R 的 `EnterpriseProfile`、`UserProfile`、`SysAccount` 以及指向 C 的 `DeviceReport` 外键，须等对应正式表就绪后再添加；不要创建占位表。

`31_A1B_R_C_foreign_keys.sql` 收录 A1/B 字段指向 R/C 的 7 条外键。必须先安装正式的 `SysAccount`、`UserProfile`、`EnterpriseProfile` 和 `DeviceReport`，再执行；脚本使用 `WITH CHECK`，会拒绝既有孤儿数据。

交接演示种子顺序为：先执行 `50_B_demo_settlement_data.sql` 创建 R01/R04/R05 测试账号与个人订单，再执行 `51_B_demo_enterprise_settlement.sql` 创建企业关联数据并通过 A2 过程生成已付款回执。51 号脚本模拟上游已核价/已结清输入，仅供 D 下游来源联调，不构成企业订单生产支付实现。

设置 `EV_DB_ODBC` 和 `PYTHONPATH=src` 后，可执行 `python -m evplatform.db` 检查当前连接库名；`SessionLocal` 首次创建会话时才读取本机连接配置。不要把真实凭据写入仓库。

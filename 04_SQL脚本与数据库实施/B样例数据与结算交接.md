# B 样例数据与结算交接

本文件为 B→D 的首轮联调样例规格。金额示例沿用《B 与 D 职责边界整合版》：电费 `E=2.00`、折抵前服务费 `S=1.00`、起步补差 `A=2.00`、平台承担优惠券 `3.00`、平台服务费率 `20%`。正常样例据此得到用户实付 `2.00`；平台服务费 `0.60`、运营商应结 `4.40` 仍以 D 确认服务费率基数为准。

## 业务编号

| 对象 | 编号 | 说明 |
|---|---|---|
| 运营商 | `B_DEMO_OP01` | B 样例运营商 |
| 场站 | `B_DEMO_ST01` | 四笔订单使用同一场站 |
| 充电桩 | `B_DEMO_PILE01` | 直流桩，额定功率 120 kW |
| 充电枪 | `B_DEMO_GUN01` | 供四笔非重叠会话使用 |
| 车主 | `B_DEMO_USER01` | 50 号 B 种子按 R04 角色创建测试 SysAccount 和 UserProfile |
| 企业 | `B_DEMO_ENT01` | 50 号 B 种子按 R05 角色创建测试 SysAccount 和 EnterpriseProfile |
| 场站通知账号 | `B_DEMO_R01` | 50 号 B 种子按 R01 角色创建测试 SysAccount；密码标记不可登录 |
| 计费版本 | `920260101` / `920260102` | B 固定的测试版本号，不使用正式环境编号；前者最低金额 5 元，后者最低金额 8 元 |
| 企业计费版本 | `920260103` | 51 号测试脚本的企业上游结清快照；最低金额 5 元 |
| 结算账期 | `202610` | 2026 年 10 月；需 D 提供该站点 R03 分派与 20% 费率 |

## 订单样例

| 样例 | 订单业务标识 | 结束时间 | 电量 | 费用构成 | 支付/退款 | 结算预期 |
|---|---|---|---:|---|---|---|
| 正常可结算 | `B-DEMO-202610-NORMAL`（由数据库生成 order_id） | 2026-10-15 10:00 | 1.000 kWh | E=2.00，S=1.00，A=2.00，优惠=3.00 | 实付 2.00，无退款 | 合格；最终服务费与应结金额待 D 确认费率基数 |
| 账期外排除 | `B-DEMO-202610-OUTSIDE`（由数据库生成 order_id） | 2026-09-30 23:00 | 1.000 kWh | E=2.00，S=1.00，A=2.00，无优惠 | 实付 5.00，无退款 | 查询 202610 时不合格；原因 `END_TIME_OUTSIDE_PERIOD` |
| 成功退款凭据 | `B-DEMO-202610-REFUND`（由数据库生成 order_id） | 2026-10-20 12:00 | 2.000 kWh | E=4.00，S=2.00，A=2.00，无优惠 | 实付 8.00；2026-10-25 成功退款 1.00 | 保留成功退款凭据供 D 联调；退款如何进入结算调整由 D 按结算规则核对，不预设跨期净结论 |
| 企业来源联调 | `B-DEMO-202610-ENTERPRISE`（由数据库生成 order_id） | 2026-10-15 10:00 | 1.000 kWh | E=2.00，S=1.00，A=2.00，无优惠 | 51 号测试脚本模拟上游已核价/已结清和 A2 已付款回执 | V04 预期 `is_settleable=1`、`eligibility_status=REVIEW_REQUIRED`；不定义生产企业支付流程 |

`ChargingOrder.order_id` 是 IDENTITY，不包含订单业务编号列。上表的业务标识只用于交接；安装种子后，以 SQL 输出的 `order_id` 作为数据库关联键。四笔订单的 `created_at` 使用固定测试标记时间以便种子脚本重跑时识别，不应复用到其他演示数据。

为使起步补差符合 `A = max(minimum_amount - E - S, 0)`，正常单使用最低金额 5 元版本（2+1+2=5）；退款单使用最低金额 8 元版本（4+2+2=8）。`920260101` 于 `2026-10-20 00:00` 失效，`920260102` 从该时刻生效，因此两个冻结版本的有效期不重叠。退款订单开始于第二版本生效后。账期外样例在 9 月结束，但其冻结版本仍覆盖它的 9 月启动时间。企业订单使用 `920260103`（最低金额 5 元），其已核价/结清状态只作为 D 下游联调输入。

## D 视图调用契约与 SettlementDetail 来源字段

`sql/views/47_B_order_settlement_source.sql` 创建 `dbo.v_OrderSettlementSource`。D 的 12 列调用契约按声明顺序放在视图输出的前 12 列，B 审计字段追加在其后：

`order_id, station_id, settlement_source, ended_at, settled_at, energy_kwh, electricity_base, service_base, minimum_adjustment, refund_state_snapshot, is_settleable, unsettleable_reason`

用于写入物理设计 `SettlementDetail` 的快照字段如下：

| D 快照列 | B 来源与核算 |
|---|---|
| `ended_at_snapshot` | `ChargingOrder.end_time`，D 按该时间筛选账期 |
| `energy_snapshot` | `ChargingOrder.energy_kwh`；仅对已核价、费用段电量匹配且大于 0 的订单输出 |
| `electricity_base` | 对每条费用段按 `ROUND(segment_energy_kwh * electricity_price, 2)` 后求和 |
| `service_base` | 对每条费用段按单价舍入后求和，再扣各段 `free_service_fee` 一次；不含起步补差和优惠券 |
| `minimum_adjustment` | `ChargingOrder.minimum_adjustment`，仅在已核价且费用事实一致时输出 |
| `settled_at_snapshot` | `ChargingOrder.settled_at` |
| `settlement_source` | `ChargingOrder.order_type`：`PERSONAL` / `ENTERPRISE` |
| `eligibility_checked_at` | 视图查询时生成；D 插入快照时应原值写入明细 |
| `refund_state_snapshot` | 个人无退款为 `NONE`，只有失败/取消退款为 `FAILED_CANCELLED`；成功或处理中退款时为空且订单不合格。企业行按物理设计填 `NONE`，企业退款另行核验 |

视图额外输出 `eligibility_status` / `eligibility_reason`，并检查个人成功支付汇总、A2 企业已确认已付款月结明细与订单快照是否一致。企业回执必须属于订单 `end_time` 所在自然月，并匹配订单绑定的企业、成员、车辆、电量和应付金额。企业回执匹配后 D 契约列 `is_settleable=1`，同时保留辅助状态 `REVIEW_REQUIRED`，不会代替企业退款核验；不可入单行的原因通过 `unsettleable_reason` 返回。D 的运营商结算账期筛选、站点分派、R03 资格和结算生成仍由 D 负责。

## 交接边界与依赖

- D 需先安装正式 R 表并初始化 R01、R04、R05 角色。50 号 B 种子按这些角色创建 B 专用测试账号及 UserProfile/EnterpriseProfile，不包含可登录凭据；脚本不创建 R 表或角色。
- 需先在 `EV_B_TEST` 安装 A1、B 表及已就绪的 A1/B 外键；脚本不会创建 D/C 表或占位对象。
- `v_OrderSettlementSource` 暴露 D `d_generate.sql` 声明的 12 列调用契约并对齐物理设计 `SettlementDetail` 快照；D 仍须用真实整合样例核验资格、R03 分派和账期规则。
- D 应按列名读取接口；前 12 列也保持与契约相同的顺序，但写入时仍应显式列出目标列，避免 `SELECT *` 对表结构变化敏感。
- D 需为场站 `B_DEMO_ST01` 准备 `202610` 账期的 R03 分派和 20% 费率。费率必须在 D 的费率表中落地后，运营商应结金额才能完成端到端复核。
- `ChargingMeterSample` 的 report_id 依赖 C 的 `DeviceReport`。本批订单先提供电量与费用段供结算来源联调；采样报文的 START/END/重复投递样例待 C 提供真实 DeviceReport 父记录后另行补充。
- 种子脚本只面向 `EV_B_TEST`，会提交样例数据；如需重置，请重建空测试库后按 README 完整安装，不要在开发库或共享库运行。

## 复核要点

1. 查询 `202610` 的结算来源时，正常订单应恰好一行且合格，账期外订单应排除并说明原因，退款订单应带出成功退款金额 `1.00`。
2. 正常样例核对：`2.00 + 1.00 + 2.00 - 3.00 = 2.00` 用户实付；平台服务费 `3.00 × 20% = 0.60`；运营商应结 `2.00 + 1.00 + 2.00 - 0.60 = 4.40`。
3. 源视图必须按 `order_id` 至多返回一行。退款样例的最终结算调整需与 D 的账期/退款规则共同确认后记录。

## 本轮修正与验证状态（2026-11-21）

- Q03 已使用 `LEFT JOIN` 保留零明细月结，`test_Q03_enterprise_monthly_bill.sql` 在 `EV_B_TEST` 通过；普通月结与零明细账单均返回预期汇总。
- V04 前 12 列按 D 契约顺序输出；`test_v_OrderSettlementSource.sql` 在 `EV_B_TEST` 通过，并验证字段名与列序。
- 全套 `pytest tests -q`：22 项通过。SQL 事务测试均自行回滚。
- 50 号种子已扩展为由 B 按 R01/R04/R05 角色规则创建 B 专用测试账号、车主档案和企业档案；仍需在 R 表与角色安装后执行验证。
- 50 号种子覆盖个人正常、账期外和成功退款；51 号种子提供已标注为模拟上游结清的企业来源行。普通表至少 20 行的数据量要求和企业订单生产 PAID 来源链路仍未完成，不用手工样例冒充生产流程。
- 新增 `sql/seed/51_B_demo_enterprise_settlement.sql`，创建企业关联数据并通过 A2 过程生成已付款月结回执。该脚本模拟上游已核价/结清输入，仅供下游来源联调，不代表生产企业支付流程已实现。

## B 侧补齐状态（2026-11-22）

- 50 号种子现按 R01/R04/R05 角色码创建 B 专用测试账号、车主档案和企业档案；需要正式 R 表与角色种子，未在当前 `EV_B_TEST` 执行。
- 51 号种子新增企业卡/成员/车辆/额度、企业订单及 A2 月结回执，订单的已核价/已结清状态是下游联调夹具。因当前测试库没有 R 表，未执行。
- 新增 `31_A1B_R_C_foreign_keys.sql` 的 7 条外键；C `DeviceReport.report_id` 类型按 V4 数据字典核为 `VARCHAR(50)`。当前没有正式 R/C 父表，因此只做 SQL Server PARSEONLY 语法检查，尚未添加外键或验证历史孤儿行。
- 增加 Operator、ChargingStation、ChargingOrder 的最小 ORM 映射和稳定排序分页查询；测试在 `EV_B_TEST` 通过。共享连接层现提供 D 接口名 `SessionLocal`/`Base`，也保留原工厂函数。
- 对齐依赖 SQLAlchemy 2.0.36、pyodbc 5.3.0、pytest 8.4.2。`python -m evplatform.db` 实连并返回 `EV_B_TEST`；全套 pytest 为 23 passed。SQL Server 驱动对 2025 版本字符串有 SQLAlchemy 警告，但测试通过。
- 普通表每表至少 20 行的数据量、所有核心表 ORM 映射、R/C 外键启用后的 SQL 夹具更新、企业单生产 PAID 链路及 D 结算过程整合验收仍待完成。当前证据不代表跨模块端到端通过。

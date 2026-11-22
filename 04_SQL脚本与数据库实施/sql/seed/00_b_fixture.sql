-- =============================================================
-- 【D 本地自测用】B 线最小夹具（临时）
-- 说明：D 的 C/D 表外键指向 A1/B 的表（场站、桩、枪、订单、退款）。
--       为了让 D 在 B 交付前能独立装库、生成 20 条结算与测试数据，
--       这里按《物理结构设计》建立最小版的这几张表与样例数据。
-- 注意：联调时【删除本文件】，改用 B 的真实建表与种子脚本。
--       本夹具给 ChargingOrder 额外加了 3 个结算基数列（electricity_base /
--       service_base / minimum_adjustment），仅为让 D 的结算演示数据可变，
--       与 B 的真实表结构不同，切勿在合并库中保留。
-- =============================================================
SET NOCOUNT ON;

-- ---------- Operator ----------
CREATE TABLE dbo.Operator (
    operator_id   VARCHAR(20)  NOT NULL PRIMARY KEY,
    operator_name NVARCHAR(100) NOT NULL,
    status        VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    created_at    DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    updated_at    DATETIME2(3) NOT NULL DEFAULT SYSDATETIME()
);

-- ---------- ChargingStation ----------
CREATE TABLE dbo.ChargingStation (
    station_id                 VARCHAR(20)  NOT NULL PRIMARY KEY,
    station_name               NVARCHAR(100) NOT NULL,
    address                    NVARCHAR(255) NOT NULL,
    longitude                  DECIMAL(10,6) NOT NULL,
    latitude                   DECIMAL(9,6)  NOT NULL,
    operator_id                VARCHAR(20)  NOT NULL,
    total_spaces               INT          NOT NULL,
    business_hours             NVARCHAR(100) NOT NULL,
    parking_fee_standard       NVARCHAR(200) NOT NULL,
    status                     VARCHAR(20)  NOT NULL DEFAULT 'OPERATING',
    created_at                 DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    updated_at                 DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    workorder_notice_account_id BIGINT      NULL
);

-- ---------- ChargingPile ----------
CREATE TABLE dbo.ChargingPile (
    pile_id               VARCHAR(20)  NOT NULL PRIMARY KEY,
    station_id            VARCHAR(20)  NOT NULL,
    device_model          NVARCHAR(50) NOT NULL,
    rated_power_kw        DECIMAL(8,2) NOT NULL,
    communication_protocol NVARCHAR(50) NOT NULL,
    commissioned_date     DATE         NOT NULL,
    warranty_end_date     DATE         NOT NULL,
    status                VARCHAR(20)  NOT NULL DEFAULT 'UNKNOWN',
    reported_status       VARCHAR(20)  NULL,
    last_heartbeat_at     DATETIME2(3) NULL,
    created_at            DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    updated_at            DATETIME2(3) NOT NULL DEFAULT SYSDATETIME()
);

-- ---------- ChargingGun ----------
CREATE TABLE dbo.ChargingGun (
    gun_id               VARCHAR(20)  NOT NULL PRIMARY KEY,
    pile_id              VARCHAR(20)  NOT NULL,
    gun_sequence         INT          NOT NULL,
    gun_type             VARCHAR(20)  NOT NULL,
    interface_standard   NVARCHAR(30) NOT NULL,
    max_output_power_kw  DECIMAL(8,2) NOT NULL,
    status               VARCHAR(20)  NOT NULL DEFAULT 'UNKNOWN',
    reported_status      VARCHAR(20)  NULL,
    last_reported_at     DATETIME2(3) NULL,
    created_at           DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    updated_at           DATETIME2(3) NOT NULL DEFAULT SYSDATETIME()
);

-- ---------- ChargingOrder（夹具精简版，含结算基数列）----------
CREATE TABLE dbo.ChargingOrder (
    order_id            BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_type          VARCHAR(20)  NOT NULL DEFAULT 'PERSONAL',
    user_id             VARCHAR(20)  NULL,
    gun_id              VARCHAR(20)  NOT NULL,
    opening_station_id  VARCHAR(20)  NOT NULL,
    start_time          DATETIME2(3) NULL,
    end_time            DATETIME2(3) NULL,
    settled_at          DATETIME2(3) NULL,
    energy_kwh          DECIMAL(10,3) NOT NULL DEFAULT 0,
    status              VARCHAR(20)  NOT NULL DEFAULT 'CREATED',
    electricity_base    DECIMAL(12,2) NOT NULL DEFAULT 0,
    service_base        DECIMAL(12,2) NOT NULL DEFAULT 0,
    minimum_adjustment  DECIMAL(12,2) NOT NULL DEFAULT 0
);

-- ---------- PaymentRecord（精简）----------
CREATE TABLE dbo.PaymentRecord (
    payment_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_id       BIGINT       NOT NULL,
    pay_channel    VARCHAR(20)  NOT NULL DEFAULT 'WECHAT',
    transaction_no VARCHAR(64)  NOT NULL,
    pay_amount     DECIMAL(12,2) NOT NULL,
    pay_time       DATETIME2(3) NOT NULL DEFAULT SYSDATETIME()
);

-- ---------- RefundRecord（精简）----------
CREATE TABLE dbo.RefundRecord (
    refund_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
    payment_id    BIGINT       NOT NULL,
    refund_no     VARCHAR(64)  NOT NULL,
    refund_amount DECIMAL(12,2) NOT NULL,
    status        VARCHAR(20)  NOT NULL DEFAULT 'PROCESSING',
    refunded_at   DATETIME2(3) NULL,
    created_by    BIGINT       NULL,
    created_at    DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
    updated_at    DATETIME2(3) NOT NULL DEFAULT SYSDATETIME()
);
GO

-- ---------- 样例数据 ----------
INSERT INTO dbo.Operator (operator_id, operator_name) VALUES
('OP-001', N'国网电动'), ('OP-002', N'特来电'), ('OP-003', N'星星充电');

INSERT INTO dbo.ChargingStation (station_id, station_name, address, longitude, latitude, operator_id, total_spaces, business_hours, parking_fee_standard, status) VALUES
('ST-001', N'城南充电站', N'和平路 1 号', 120.123456, 30.123456, 'OP-001', 20, N'24 小时', N'充电免停 2 小时', 'OPERATING'),
('ST-002', N'城北快充站', N'建设路 8 号', 120.234567, 30.234567, 'OP-001', 16, N'24 小时', N'充电免停 2 小时', 'OPERATING'),
('ST-003', N'高新区站',   N'科技路 15 号', 120.345678, 30.345678, 'OP-002', 24, N'06:00-24:00', N'前 1 小时免费', 'OPERATING'),
('ST-004', N'机场枢纽站', N'机场路 99 号', 120.456789, 30.456789, 'OP-002', 40, N'24 小时', N'按次 10 元', 'OPERATING'),
('ST-005', N'会展中心站', N'博览路 5 号', 120.567890, 30.567890, 'OP-003', 12, N'08:00-22:00', N'充电免停 3 小时', 'OPERATING');

-- 10 台桩（每站 2 台）
DECLARE @s INT = 1, @p INT = 0;
WHILE @s <= 5
BEGIN
    DECLARE @s2 INT = 1;
    WHILE @s2 <= 2
    BEGIN
        SET @p = @p + 1;
        INSERT INTO dbo.ChargingPile (pile_id, station_id, device_model, rated_power_kw, communication_protocol, commissioned_date, warranty_end_date, status, last_heartbeat_at)
        VALUES ('PILE-' + RIGHT('00' + CAST(@p AS VARCHAR), 3), 'ST-' + RIGHT('00' + CAST(@s AS VARCHAR), 3),
                N'DC-120KW', 120.00, N'OCPP 1.6J', '2025-06-01', '2028-06-01', 'IDLE', SYSDATETIME());
        SET @s2 = @s2 + 1;
    END;
    SET @s = @s + 1;
END;

-- 每台桩 2 把枪
DECLARE @g INT = 1;
WHILE @g <= 10
BEGIN
    INSERT INTO dbo.ChargingGun (gun_id, pile_id, gun_sequence, gun_type, interface_standard, max_output_power_kw, status)
    VALUES ('GUN-' + RIGHT('00' + CAST(@g AS VARCHAR), 3) + '-01', 'PILE-' + RIGHT('00' + CAST(@g AS VARCHAR), 3), 1, 'DC_FAST', N'GB/T 20234', 120.00, 'IDLE');
    INSERT INTO dbo.ChargingGun (gun_id, pile_id, gun_sequence, gun_type, interface_standard, max_output_power_kw, status)
    VALUES ('GUN-' + RIGHT('00' + CAST(@g AS VARCHAR), 3) + '-02', 'PILE-' + RIGHT('00' + CAST(@g AS VARCHAR), 3), 2, 'DC_FAST', N'GB/T 20234', 120.00, 'IDLE');
    SET @g = @g + 1;
END;

-- 50 笔订单（跨 2026-08~2026-12 五个账期，5 个场站，每站每账期 2 笔）
-- 金额口径：E=2.00、S=1.00、A=2.00（与设计演示一致，便于手算）
DECLARE @o INT = 1;
WHILE @o <= 50
BEGIN
    DECLARE @station VARCHAR(20) = 'ST-' + RIGHT('00' + CAST(((@o - 1) % 5) + 1 AS VARCHAR), 3);
    DECLARE @gun VARCHAR(20) = 'GUN-' + RIGHT('00' + CAST(((@o - 1) % 10) + 1 AS VARCHAR), 3) + '-01';
    DECLARE @m INT = ((@o - 1) / 10) + 1;
    DECLARE @month CHAR(6) = CASE @m WHEN 1 THEN '202608' WHEN 2 THEN '202609' WHEN 3 THEN '202610' WHEN 4 THEN '202611' ELSE '202612' END;
    DECLARE @end DATETIME2(3) = DATEADD(day, ((@o - 1) % 10) + 1, CONVERT(datetime2(3), @month + '15', 112));
    INSERT INTO dbo.ChargingOrder (order_type, user_id, gun_id, opening_station_id, start_time, end_time, settled_at, energy_kwh, status,
                                    electricity_base, service_base, minimum_adjustment)
    VALUES ('PERSONAL', 'U-' + RIGHT('000' + CAST(@o AS VARCHAR), 3), @gun, @station,
            DATEADD(minute, -40, @end), @end, @end, 20.000 + @o, 'PAID', 2.00, 1.00, 2.00);
    SET @o = @o + 1;
END;

-- 20 笔支付 + 5 笔退款
DECLARE @pay INT = 1;
WHILE @pay <= 20
BEGIN
    INSERT INTO dbo.PaymentRecord (order_id, pay_channel, transaction_no, pay_amount, pay_time)
    VALUES (@pay, 'WECHAT', 'TXN-' + RIGHT('0000' + CAST(@pay AS VARCHAR), 4), 2.00, DATEADD(day, @pay, '2026-11-01T18:30:00'));
    SET @pay = @pay + 1;
END;
DECLARE @rf INT = 1;
WHILE @rf <= 20
BEGIN
    INSERT INTO dbo.RefundRecord (payment_id, refund_no, refund_amount, status, refunded_at)
    VALUES (@rf, 'RF-' + RIGHT('0000' + CAST(@rf AS VARCHAR), 4), 1.00, 'SUCCESS', DATEADD(day, @rf + 20, '2026-11-01T19:00:00'));
    SET @rf = @rf + 1;
END;
GO

-- ---------- R04 车主 + R05 企业主体夹具（B 域数据，D 自测用）----------
DECLARE @u INT = 1;
WHILE @u <= 20
BEGIN
    INSERT INTO dbo.SysAccount (username, password_hash, role_id)
    VALUES ('user' + RIGHT('000' + CAST(@u AS VARCHAR), 3), 'demo-hash-user', 4);
    INSERT INTO dbo.UserProfile (user_id, account_id, phone_ciphertext, phone_hash, real_name_status, registered_at, status)
    SELECT 'U-' + RIGHT('000' + CAST(@u AS VARCHAR), 3), account_id,
           CONVERT(varbinary(256), 'PHONE-' + RIGHT('000' + CAST(@u AS VARCHAR), 3)),
           REPLICATE('0', 64), 'VERIFIED', SYSDATETIME(), 'ACTIVE'
    FROM dbo.SysAccount WHERE username = 'user' + RIGHT('000' + CAST(@u AS VARCHAR), 3);
    SET @u = @u + 1;
END;

DECLARE @e INT = 1;
WHILE @e <= 3
BEGIN
    INSERT INTO dbo.SysAccount (username, password_hash, role_id)
    VALUES ('ent' + RIGHT('000' + CAST(@e AS VARCHAR), 3), 'demo-hash-ent', 5);
    INSERT INTO dbo.EnterpriseProfile (enterprise_id, account_id, enterprise_name, credit_code, contact_name, contact_phone_ciphertext, status)
    SELECT 'ENT-' + RIGHT('000' + CAST(@e AS VARCHAR), 3), account_id,
           N'测试企业' + CAST(@e AS NVARCHAR), REPLICATE('0', 18),
           N'联系人' + CAST(@e AS NVARCHAR), CONVERT(varbinary(256), 'PHONE-ENT-' + CAST(@e AS VARCHAR)), 'ACTIVE'
    FROM dbo.SysAccount WHERE username = 'ent' + RIGHT('000' + CAST(@e AS VARCHAR), 3);
    SET @e = @e + 1;
END;
GO

-- ---------- v_OrderSettlementSource 占位（D 自测用）----------
CREATE VIEW dbo.v_OrderSettlementSource AS
SELECT
    o.order_id,
    o.opening_station_id AS station_id,
    o.order_type         AS settlement_source,
    o.end_time           AS ended_at,
    o.settled_at,
    o.energy_kwh,
    o.electricity_base,
    o.service_base,
    o.minimum_adjustment,
    CASE WHEN o.status = 'PAID' THEN 'NONE' ELSE 'NONE' END AS refund_state_snapshot,
    CASE WHEN o.status = 'PAID' THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS is_settleable,
    CASE WHEN o.status <> 'PAID' THEN N'订单未结清' ELSE NULL END AS unsettleable_reason
FROM dbo.ChargingOrder o;
GO

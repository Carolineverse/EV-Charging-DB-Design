-- =====================================================
-- B 模块外键：第一批
-- B 内部表及已部署的 A1 / A2 表
-- 执行前：B、A1、A2 的目标表均已创建；先在 SSMS 确认 DB_NAME()。
-- R/C 外键等对应正式表创建后再由后置批次添加。
-- =====================================================

-- 1. BillingRuleVersion -> ChargingStation
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_BillingRuleVersion_ChargingStation')
    ALTER TABLE dbo.BillingRuleVersion WITH CHECK
    ADD CONSTRAINT FK_BillingRuleVersion_ChargingStation
    FOREIGN KEY (station_id)
    REFERENCES dbo.ChargingStation(station_id);
GO

-- 2. BillingRule -> BillingRuleVersion
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_BillingRule_BillingRuleVersion')
    ALTER TABLE dbo.BillingRule WITH CHECK
ADD CONSTRAINT FK_BillingRule_BillingRuleVersion
FOREIGN KEY (rule_version_id)
REFERENCES dbo.BillingRuleVersion(rule_version_id);
GO

-- 3. ChargingOrder -> ChargingGun
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingOrder_ChargingGun')
    ALTER TABLE dbo.ChargingOrder WITH CHECK
ADD CONSTRAINT FK_ChargingOrder_ChargingGun
FOREIGN KEY (gun_id)
REFERENCES dbo.ChargingGun(gun_id);
GO

-- 4. ChargingOrder -> ChargingStation
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingOrder_ChargingStation')
    ALTER TABLE dbo.ChargingOrder WITH CHECK
ADD CONSTRAINT FK_ChargingOrder_ChargingStation
FOREIGN KEY (opening_station_id)
REFERENCES dbo.ChargingStation(station_id);
GO

-- 5. ChargingOrder -> BillingRuleVersion
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingOrder_BillingRuleVersion')
    ALTER TABLE dbo.ChargingOrder WITH CHECK
ADD CONSTRAINT FK_ChargingOrder_BillingRuleVersion
FOREIGN KEY (startup_rule_version_id)
REFERENCES dbo.BillingRuleVersion(rule_version_id);
GO

-- 6. ChargingOrder -> EnterpriseCardBinding (A2)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingOrder_EnterpriseCardBinding')
    ALTER TABLE dbo.ChargingOrder WITH CHECK
    ADD CONSTRAINT FK_ChargingOrder_EnterpriseCardBinding
    FOREIGN KEY (binding_id)
    REFERENCES dbo.EnterpriseCardBinding(binding_id);
GO

-- 7. ChargingOrder -> EnterpriseQuota (A2)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingOrder_EnterpriseQuota')
    ALTER TABLE dbo.ChargingOrder WITH CHECK
    ADD CONSTRAINT FK_ChargingOrder_EnterpriseQuota
    FOREIGN KEY (enterprise_quota_id)
    REFERENCES dbo.EnterpriseQuota(enterprise_quota_id);
GO

-- 8. OrderFeeDetail -> ChargingOrder
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_OrderFeeDetail_ChargingOrder')
    ALTER TABLE dbo.OrderFeeDetail WITH CHECK
ADD CONSTRAINT FK_OrderFeeDetail_ChargingOrder
FOREIGN KEY (order_id)
REFERENCES dbo.ChargingOrder(order_id);
GO

-- 9. OrderFeeDetail -> BillingRule
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_OrderFeeDetail_BillingRule')
    ALTER TABLE dbo.OrderFeeDetail WITH CHECK
ADD CONSTRAINT FK_OrderFeeDetail_BillingRule
FOREIGN KEY (billing_rule_id)
REFERENCES dbo.BillingRule(billing_rule_id);
GO

-- 10. PaymentRecord -> ChargingOrder
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PaymentRecord_ChargingOrder')
    ALTER TABLE dbo.PaymentRecord WITH CHECK
ADD CONSTRAINT FK_PaymentRecord_ChargingOrder
FOREIGN KEY (order_id)
REFERENCES dbo.ChargingOrder(order_id);
GO

-- 11. RefundRecord -> PaymentRecord
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_RefundRecord_PaymentRecord')
    ALTER TABLE dbo.RefundRecord WITH CHECK
ADD CONSTRAINT FK_RefundRecord_PaymentRecord
FOREIGN KEY (payment_id)
REFERENCES dbo.PaymentRecord(payment_id);
GO

-- 12. ChargingMeterSample -> ChargingOrder
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingMeterSample_ChargingOrder')
    ALTER TABLE dbo.ChargingMeterSample WITH CHECK
ADD CONSTRAINT FK_ChargingMeterSample_ChargingOrder
FOREIGN KEY (order_id)
REFERENCES dbo.ChargingOrder(order_id);
GO

-- 13. OrderCommand -> ChargingOrder
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_OrderCommand_ChargingOrder')
    ALTER TABLE dbo.OrderCommand WITH CHECK
ADD CONSTRAINT FK_OrderCommand_ChargingOrder
FOREIGN KEY (order_id)
REFERENCES dbo.ChargingOrder(order_id);
GO

-- =====================================================
-- A2 外键到已安装的 A1 / B 模块
-- 执行前：目标表须已创建，并通过 sqlcmd -d 或 SSMS 选择目标数据库。
-- 本脚本不切换数据库，可重复执行。
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PromotionStation_ChargingStation')
    ALTER TABLE dbo.PromotionStation WITH CHECK
    ADD CONSTRAINT FK_PromotionStation_ChargingStation
    FOREIGN KEY (station_id) REFERENCES dbo.ChargingStation(station_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CouponRedemption_ChargingOrder')
    ALTER TABLE dbo.CouponRedemption WITH CHECK
    ADD CONSTRAINT FK_CouponRedemption_ChargingOrder
    FOREIGN KEY (order_id) REFERENCES dbo.ChargingOrder(order_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_WalletTransaction_ChargingOrder')
    ALTER TABLE dbo.WalletTransaction WITH CHECK
    ADD CONSTRAINT FK_WalletTransaction_ChargingOrder
    FOREIGN KEY (order_id) REFERENCES dbo.ChargingOrder(order_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PersonalInvoiceApplication_ChargingOrder')
    ALTER TABLE dbo.PersonalInvoiceApplication WITH CHECK
    ADD CONSTRAINT FK_PersonalInvoiceApplication_ChargingOrder
    FOREIGN KEY (order_id) REFERENCES dbo.ChargingOrder(order_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseSettlementDetail_ChargingOrder')
    ALTER TABLE dbo.EnterpriseSettlementDetail WITH CHECK
    ADD CONSTRAINT FK_EnterpriseSettlementDetail_ChargingOrder
    FOREIGN KEY (order_id) REFERENCES dbo.ChargingOrder(order_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseServiceApplication_ChargingStation')
    ALTER TABLE dbo.EnterpriseServiceApplication WITH CHECK
    ADD CONSTRAINT FK_EnterpriseServiceApplication_ChargingStation
    FOREIGN KEY (station_id) REFERENCES dbo.ChargingStation(station_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PersonalInvoiceAdjustment_RefundRecord')
    ALTER TABLE dbo.PersonalInvoiceAdjustment WITH CHECK
    ADD CONSTRAINT FK_PersonalInvoiceAdjustment_RefundRecord
    FOREIGN KEY (refund_id) REFERENCES dbo.RefundRecord(refund_id);
GO

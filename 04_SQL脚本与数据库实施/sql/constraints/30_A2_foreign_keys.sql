-- =====================================================
-- A2 模块内外键
-- 执行前：先创建所有 A2 表，并通过 sqlcmd -d 或 SSMS 选择目标数据库。
-- 本脚本不切换数据库，可重复执行。
-- 跨模块外键位于 35_A2_external_foreign_keys.sql。
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_UserMemberLevel_MemberLevel')
    ALTER TABLE dbo.UserMemberLevel WITH CHECK
    ADD CONSTRAINT FK_UserMemberLevel_MemberLevel
    FOREIGN KEY (member_level_id) REFERENCES dbo.MemberLevel(member_level_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseCardBinding_EnterpriseCard')
    ALTER TABLE dbo.EnterpriseCardBinding WITH CHECK
    ADD CONSTRAINT FK_EnterpriseCardBinding_EnterpriseCard
    FOREIGN KEY (enterprise_card_id) REFERENCES dbo.EnterpriseCard(enterprise_card_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseCardBinding_Vehicle')
    ALTER TABLE dbo.EnterpriseCardBinding WITH CHECK
    ADD CONSTRAINT FK_EnterpriseCardBinding_Vehicle
    FOREIGN KEY (vehicle_id) REFERENCES dbo.Vehicle(vehicle_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseCardBinding_FleetMember')
    ALTER TABLE dbo.EnterpriseCardBinding WITH CHECK
    ADD CONSTRAINT FK_EnterpriseCardBinding_FleetMember
    FOREIGN KEY (fleet_member_id) REFERENCES dbo.FleetMember(fleet_member_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseQuota_FleetMember')
    ALTER TABLE dbo.EnterpriseQuota WITH CHECK
    ADD CONSTRAINT FK_EnterpriseQuota_FleetMember
    FOREIGN KEY (fleet_member_id) REFERENCES dbo.FleetMember(fleet_member_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PromotionStation_Promotion')
    ALTER TABLE dbo.PromotionStation WITH CHECK
    ADD CONSTRAINT FK_PromotionStation_Promotion
    FOREIGN KEY (promotion_id) REFERENCES dbo.Promotion(promotion_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PromotionMemberLevel_Promotion')
    ALTER TABLE dbo.PromotionMemberLevel WITH CHECK
    ADD CONSTRAINT FK_PromotionMemberLevel_Promotion
    FOREIGN KEY (promotion_id) REFERENCES dbo.Promotion(promotion_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PromotionMemberLevel_MemberLevel')
    ALTER TABLE dbo.PromotionMemberLevel WITH CHECK
    ADD CONSTRAINT FK_PromotionMemberLevel_MemberLevel
    FOREIGN KEY (member_level_id) REFERENCES dbo.MemberLevel(member_level_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_UserCoupon_Promotion')
    ALTER TABLE dbo.UserCoupon WITH CHECK
    ADD CONSTRAINT FK_UserCoupon_Promotion
    FOREIGN KEY (promotion_id) REFERENCES dbo.Promotion(promotion_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CouponRedemption_UserCoupon')
    ALTER TABLE dbo.CouponRedemption WITH CHECK
    ADD CONSTRAINT FK_CouponRedemption_UserCoupon
    FOREIGN KEY (user_coupon_id) REFERENCES dbo.UserCoupon(user_coupon_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_WalletTransaction_UserWallet')
    ALTER TABLE dbo.WalletTransaction WITH CHECK
    ADD CONSTRAINT FK_WalletTransaction_UserWallet
    FOREIGN KEY (user_id) REFERENCES dbo.UserWallet(user_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseSettlementDetail_EnterpriseSettlement')
    ALTER TABLE dbo.EnterpriseSettlementDetail WITH CHECK
    ADD CONSTRAINT FK_EnterpriseSettlementDetail_EnterpriseSettlement
    FOREIGN KEY (enterprise_settlement_id)
    REFERENCES dbo.EnterpriseSettlement(enterprise_settlement_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseSettlementDetail_FleetMember')
    ALTER TABLE dbo.EnterpriseSettlementDetail WITH CHECK
    ADD CONSTRAINT FK_EnterpriseSettlementDetail_FleetMember
    FOREIGN KEY (fleet_member_id) REFERENCES dbo.FleetMember(fleet_member_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseSettlementDetail_Vehicle')
    ALTER TABLE dbo.EnterpriseSettlementDetail WITH CHECK
    ADD CONSTRAINT FK_EnterpriseSettlementDetail_Vehicle
    FOREIGN KEY (vehicle_id) REFERENCES dbo.Vehicle(vehicle_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PersonalInvoiceAdjustment_InvoiceApplication')
    ALTER TABLE dbo.PersonalInvoiceAdjustment WITH CHECK
    ADD CONSTRAINT FK_PersonalInvoiceAdjustment_InvoiceApplication
    FOREIGN KEY (invoice_application_id)
    REFERENCES dbo.PersonalInvoiceApplication(invoice_application_id);
GO

-- =====================================================
-- A2 用户与会员运营索引
-- 执行前：先创建全部业务表，并通过 sqlcmd -d 或 SSMS 选择目标数据库。
-- 本脚本不切换数据库，可重复执行。
-- =====================================================

SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.UserMemberLevel') AND name = N'IX_UserMemberLevel_01')
    CREATE NONCLUSTERED INDEX IX_UserMemberLevel_01 ON dbo.UserMemberLevel (member_level_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Vehicle') AND name = N'IX_Vehicle_02')
    CREATE NONCLUSTERED INDEX IX_Vehicle_02 ON dbo.Vehicle (user_id, status);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Vehicle') AND name = N'IX_Vehicle_03')
    CREATE NONCLUSTERED INDEX IX_Vehicle_03 ON dbo.Vehicle (enterprise_id, status);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.FleetMember') AND name = N'UX_FleetMember_01')
    CREATE UNIQUE NONCLUSTERED INDEX UX_FleetMember_01 ON dbo.FleetMember (user_id) WHERE left_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.FleetMember') AND name = N'IX_FleetMember_02')
    CREATE NONCLUSTERED INDEX IX_FleetMember_02 ON dbo.FleetMember (enterprise_id, left_at);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.EnterpriseCard') AND name = N'IX_EnterpriseCard_02')
    CREATE NONCLUSTERED INDEX IX_EnterpriseCard_02 ON dbo.EnterpriseCard (enterprise_id, status);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.EnterpriseCardBinding') AND name = N'UX_EnterpriseCardBinding_01')
    CREATE UNIQUE NONCLUSTERED INDEX UX_EnterpriseCardBinding_01 ON dbo.EnterpriseCardBinding (enterprise_card_id) WHERE effective_end_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.EnterpriseCardBinding') AND name = N'UX_EnterpriseCardBinding_02')
    CREATE UNIQUE NONCLUSTERED INDEX UX_EnterpriseCardBinding_02 ON dbo.EnterpriseCardBinding (vehicle_id) WHERE effective_end_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.EnterpriseCardBinding') AND name = N'IX_EnterpriseCardBinding_03')
    CREATE NONCLUSTERED INDEX IX_EnterpriseCardBinding_03 ON dbo.EnterpriseCardBinding (fleet_member_id, effective_start_at DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Promotion') AND name = N'IX_Promotion_01')
    CREATE NONCLUSTERED INDEX IX_Promotion_01 ON dbo.Promotion (status, issue_start_at);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.PromotionStation') AND name = N'IX_PromotionStation_02')
    CREATE NONCLUSTERED INDEX IX_PromotionStation_02 ON dbo.PromotionStation (station_id, promotion_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.UserCoupon') AND name = N'IX_UserCoupon_02')
    CREATE NONCLUSTERED INDEX IX_UserCoupon_02 ON dbo.UserCoupon (user_id, status, valid_end_at);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.WalletTransaction') AND name = N'UX_WalletTransaction_02')
    CREATE UNIQUE NONCLUSTERED INDEX UX_WalletTransaction_02 ON dbo.WalletTransaction (external_transaction_no) WHERE external_transaction_no IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.WalletTransaction') AND name = N'IX_WalletTransaction_03')
    CREATE NONCLUSTERED INDEX IX_WalletTransaction_03 ON dbo.WalletTransaction (user_id, transaction_at DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.WalletTransaction') AND name = N'IX_WalletTransaction_04')
    CREATE NONCLUSTERED INDEX IX_WalletTransaction_04 ON dbo.WalletTransaction (order_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.PersonalInvoiceApplication') AND name = N'IX_PersonalInvoiceApplication_02')
    CREATE NONCLUSTERED INDEX IX_PersonalInvoiceApplication_02 ON dbo.PersonalInvoiceApplication (user_id, applied_at DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.EnterpriseSettlementDetail') AND name = N'IX_EnterpriseSettlementDetail_02')
    CREATE NONCLUSTERED INDEX IX_EnterpriseSettlementDetail_02 ON dbo.EnterpriseSettlementDetail (enterprise_settlement_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.EnterpriseServiceApplication') AND name = N'IX_EnterpriseServiceApplication_01')
    CREATE NONCLUSTERED INDEX IX_EnterpriseServiceApplication_01 ON dbo.EnterpriseServiceApplication (enterprise_id, created_at DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.EnterpriseServiceApplication') AND name = N'IX_EnterpriseServiceApplication_02')
    CREATE NONCLUSTERED INDEX IX_EnterpriseServiceApplication_02 ON dbo.EnterpriseServiceApplication (status, created_at);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.PersonalInvoiceAdjustment') AND name = N'UX_PersonalInvoiceAdjustment_02')
    CREATE UNIQUE NONCLUSTERED INDEX UX_PersonalInvoiceAdjustment_02 ON dbo.PersonalInvoiceAdjustment (red_invoice_no) WHERE red_invoice_no IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.PersonalInvoiceAdjustment') AND name = N'IX_PersonalInvoiceAdjustment_03')
    CREATE NONCLUSTERED INDEX IX_PersonalInvoiceAdjustment_03 ON dbo.PersonalInvoiceAdjustment (invoice_application_id);
GO

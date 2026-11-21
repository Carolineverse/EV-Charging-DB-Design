-- A1/B -> R/C cross-module foreign keys owned by the columns in A1/B.
-- Run after all A1/B tables and the official R/C parent tables are installed.
-- This script refuses to add untrusted constraints or substitute placeholder tables.

IF OBJECT_ID(N'dbo.SysAccount', N'U') IS NULL
   OR OBJECT_ID(N'dbo.UserProfile', N'U') IS NULL
   OR OBJECT_ID(N'dbo.EnterpriseProfile', N'U') IS NULL
   OR OBJECT_ID(N'dbo.DeviceReport', N'U') IS NULL
    THROW 51120, 'Install the official R and C parent tables before the A1/B cross-module foreign keys.', 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingStation_SysAccount_WorkorderNotice')
    ALTER TABLE dbo.ChargingStation WITH CHECK
    ADD CONSTRAINT FK_ChargingStation_SysAccount_WorkorderNotice
    FOREIGN KEY (workorder_notice_account_id) REFERENCES dbo.SysAccount(account_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DeviceAssetCase_SysAccount_SubmittedBy')
    ALTER TABLE dbo.DeviceAssetCase WITH CHECK
    ADD CONSTRAINT FK_DeviceAssetCase_SysAccount_SubmittedBy
    FOREIGN KEY (submitted_by) REFERENCES dbo.SysAccount(account_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DeviceAssetCase_SysAccount_ReviewedBy')
    ALTER TABLE dbo.DeviceAssetCase WITH CHECK
    ADD CONSTRAINT FK_DeviceAssetCase_SysAccount_ReviewedBy
    FOREIGN KEY (reviewed_by) REFERENCES dbo.SysAccount(account_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingOrder_UserProfile')
    ALTER TABLE dbo.ChargingOrder WITH CHECK
    ADD CONSTRAINT FK_ChargingOrder_UserProfile
    FOREIGN KEY (user_id) REFERENCES dbo.UserProfile(user_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_BillingRuleVersion_EnterpriseProfile')
    ALTER TABLE dbo.BillingRuleVersion WITH CHECK
    ADD CONSTRAINT FK_BillingRuleVersion_EnterpriseProfile
    FOREIGN KEY (enterprise_id) REFERENCES dbo.EnterpriseProfile(enterprise_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_RefundRecord_SysAccount_CreatedBy')
    ALTER TABLE dbo.RefundRecord WITH CHECK
    ADD CONSTRAINT FK_RefundRecord_SysAccount_CreatedBy
    FOREIGN KEY (created_by) REFERENCES dbo.SysAccount(account_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingMeterSample_DeviceReport')
    ALTER TABLE dbo.ChargingMeterSample WITH CHECK
    ADD CONSTRAINT FK_ChargingMeterSample_DeviceReport
    FOREIGN KEY (report_id) REFERENCES dbo.DeviceReport(report_id);
GO

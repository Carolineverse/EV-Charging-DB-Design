-- =====================================================
-- A2 外键到 R 模块主体及账号表
-- 执行前：dbo.UserProfile、dbo.EnterpriseProfile、dbo.SysAccount 已创建；
-- 通过 sqlcmd -d 或 SSMS 选择目标数据库。本脚本不切换数据库，可重复执行。
-- =====================================================

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_UserMemberLevel_UserProfile')
    ALTER TABLE dbo.UserMemberLevel WITH CHECK
    ADD CONSTRAINT FK_UserMemberLevel_UserProfile
    FOREIGN KEY (user_id) REFERENCES dbo.UserProfile(user_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Vehicle_UserProfile')
    ALTER TABLE dbo.Vehicle WITH CHECK
    ADD CONSTRAINT FK_Vehicle_UserProfile
    FOREIGN KEY (user_id) REFERENCES dbo.UserProfile(user_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Vehicle_EnterpriseProfile')
    ALTER TABLE dbo.Vehicle WITH CHECK
    ADD CONSTRAINT FK_Vehicle_EnterpriseProfile
    FOREIGN KEY (enterprise_id) REFERENCES dbo.EnterpriseProfile(enterprise_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_FleetMember_EnterpriseProfile')
    ALTER TABLE dbo.FleetMember WITH CHECK
    ADD CONSTRAINT FK_FleetMember_EnterpriseProfile
    FOREIGN KEY (enterprise_id) REFERENCES dbo.EnterpriseProfile(enterprise_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_FleetMember_UserProfile')
    ALTER TABLE dbo.FleetMember WITH CHECK
    ADD CONSTRAINT FK_FleetMember_UserProfile
    FOREIGN KEY (user_id) REFERENCES dbo.UserProfile(user_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseCard_EnterpriseProfile')
    ALTER TABLE dbo.EnterpriseCard WITH CHECK
    ADD CONSTRAINT FK_EnterpriseCard_EnterpriseProfile
    FOREIGN KEY (enterprise_id) REFERENCES dbo.EnterpriseProfile(enterprise_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Promotion_SysAccount')
    ALTER TABLE dbo.Promotion WITH CHECK
    ADD CONSTRAINT FK_Promotion_SysAccount
    FOREIGN KEY (reviewed_by) REFERENCES dbo.SysAccount(account_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_UserCoupon_UserProfile')
    ALTER TABLE dbo.UserCoupon WITH CHECK
    ADD CONSTRAINT FK_UserCoupon_UserProfile
    FOREIGN KEY (user_id) REFERENCES dbo.UserProfile(user_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_UserWallet_UserProfile')
    ALTER TABLE dbo.UserWallet WITH CHECK
    ADD CONSTRAINT FK_UserWallet_UserProfile
    FOREIGN KEY (user_id) REFERENCES dbo.UserProfile(user_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PersonalInvoiceApplication_UserProfile')
    ALTER TABLE dbo.PersonalInvoiceApplication WITH CHECK
    ADD CONSTRAINT FK_PersonalInvoiceApplication_UserProfile
    FOREIGN KEY (user_id) REFERENCES dbo.UserProfile(user_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseSettlement_EnterpriseProfile')
    ALTER TABLE dbo.EnterpriseSettlement WITH CHECK
    ADD CONSTRAINT FK_EnterpriseSettlement_EnterpriseProfile
    FOREIGN KEY (enterprise_id) REFERENCES dbo.EnterpriseProfile(enterprise_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseServiceApplication_EnterpriseProfile')
    ALTER TABLE dbo.EnterpriseServiceApplication WITH CHECK
    ADD CONSTRAINT FK_EnterpriseServiceApplication_EnterpriseProfile
    FOREIGN KEY (enterprise_id) REFERENCES dbo.EnterpriseProfile(enterprise_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EnterpriseServiceApplication_SysAccount')
    ALTER TABLE dbo.EnterpriseServiceApplication WITH CHECK
    ADD CONSTRAINT FK_EnterpriseServiceApplication_SysAccount
    FOREIGN KEY (reviewed_by) REFERENCES dbo.SysAccount(account_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PersonalInvoiceAdjustment_SysAccount')
    ALTER TABLE dbo.PersonalInvoiceAdjustment WITH CHECK
    ADD CONSTRAINT FK_PersonalInvoiceAdjustment_SysAccount
    FOREIGN KEY (handled_by) REFERENCES dbo.SysAccount(account_id);
GO

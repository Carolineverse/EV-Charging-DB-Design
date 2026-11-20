SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- 角色（1~5）
IF NOT EXISTS (SELECT 1 FROM dbo.SysRole)
BEGIN
    INSERT INTO dbo.SysRole (role_id, role_code, role_name, subject_type, role_desc) VALUES
	(1, 'R01', N'管理员',        'STAFF',     N'平台管理、终审'),
	(2, 'R02', N'设备管理员',    'STAFF',     N'设备与资产管理'),
	(3, 'R03', N'客服与结算专员','STAFF',     N'工单、退款、结算经办'),
	(4, 'R04', N'个人用户',      'PERSONAL',  N'个人充电用户'),
	(5, 'R05', N'企业客户',      'ENTERPRISE',N'企业客户');
END
GO

SELECT role_id, role_code, role_name, subject_type FROM dbo.SysRole ORDER BY role_id;
GO
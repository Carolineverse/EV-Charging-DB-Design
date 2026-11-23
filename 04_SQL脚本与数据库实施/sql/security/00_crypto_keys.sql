-- SQLCMD requires EV_MASTER_KEY_PASSWORD from the installer. Keep it outside Git.
IF NOT EXISTS (
    SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##'
)
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(EV_MASTER_KEY_PASSWORD)';
GO

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'Cert_EV_Sensitive')
    CREATE CERTIFICATE Cert_EV_Sensitive WITH SUBJECT = N'EV sensitive fields';
GO

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'Key_EV_Sensitive')
    CREATE SYMMETRIC KEY Key_EV_Sensitive
        WITH ALGORITHM = AES_256
        ENCRYPTION BY CERTIFICATE Cert_EV_Sensitive;
GO

-- Only explicitly authorized SQL principals should receive EXECUTE on these modules.
CREATE OR ALTER PROCEDURE dbo.usp_EncryptSensitive
    @plaintext NVARCHAR(MAX),
    @ciphertext VARBINARY(256) OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET @ciphertext = NULL;
    IF @plaintext IS NULL OR DATALENGTH(@plaintext) NOT BETWEEN 2 AND 128
        THROW 52701, N'Sensitive plaintext must occupy 2 to 128 UTF-16 bytes.', 1;

    DECLARE @opened_here BIT = 0;
    DECLARE @encrypted VARBINARY(8000);
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = N'Key_EV_Sensitive')
        BEGIN
            OPEN SYMMETRIC KEY Key_EV_Sensitive DECRYPTION BY CERTIFICATE Cert_EV_Sensitive;
            SET @opened_here = 1;
        END;
        SET @encrypted = EncryptByKey(Key_GUID(N'Key_EV_Sensitive'), CONVERT(NVARCHAR(64), @plaintext));
        IF @encrypted IS NULL OR DATALENGTH(@encrypted) > 256
            THROW 52702, N'Sensitive encryption failed or exceeded column capacity.', 1;
        SET @ciphertext = @encrypted;
        IF @opened_here = 1
            CLOSE SYMMETRIC KEY Key_EV_Sensitive;
    END TRY
    BEGIN CATCH
        IF @opened_here = 1 AND EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = N'Key_EV_Sensitive')
            CLOSE SYMMETRIC KEY Key_EV_Sensitive;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DecryptSensitive
    @ciphertext VARBINARY(MAX),
    @plaintext NVARCHAR(64) OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET @plaintext = NULL;
    IF @ciphertext IS NULL OR DATALENGTH(@ciphertext) NOT BETWEEN 1 AND 256
        THROW 52703, N'Sensitive ciphertext is missing or exceeds column capacity.', 1;

    DECLARE @opened_here BIT = 0;
    DECLARE @decrypted VARBINARY(8000);
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = N'Key_EV_Sensitive')
        BEGIN
            OPEN SYMMETRIC KEY Key_EV_Sensitive DECRYPTION BY CERTIFICATE Cert_EV_Sensitive;
            SET @opened_here = 1;
        END;
        SET @decrypted = DecryptByKey(@ciphertext);
        IF @decrypted IS NULL OR DATALENGTH(@decrypted) NOT BETWEEN 2 AND 128
           OR DATALENGTH(@decrypted) % 2 <> 0
            THROW 52704, N'Sensitive decryption failed.', 1;
        SET @plaintext = CONVERT(NVARCHAR(64), @decrypted);
        IF @opened_here = 1
            CLOSE SYMMETRIC KEY Key_EV_Sensitive;
    END TRY
    BEGIN CATCH
        IF @opened_here = 1 AND EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = N'Key_EV_Sensitive')
            CLOSE SYMMETRIC KEY Key_EV_Sensitive;
        THROW;
    END CATCH;
END;
GO

-- V07 回归测试：覆盖会员/钱包双有、钱包单有及会员单有的 A2 用户。

SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EV_B_TEST'
    THROW 51900, 'This test must run in EV_B_TEST.', 1;
IF OBJECT_ID(N'dbo.v_A2MemberWalletSummary', N'V') IS NULL
    THROW 51901, 'Install dbo.v_A2MemberWalletSummary before this test.', 1;

DECLARE @Token VARCHAR(10) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10);
DECLARE @LevelId VARCHAR(20) = 'V07LV' + @Token;
DECLARE @UserBoth VARCHAR(20) = 'TST_V07_A' + @Token;
DECLARE @UserWalletOnly VARCHAR(20) = 'TST_V07_B' + @Token;
DECLARE @UserLevelOnly VARCHAR(20) = 'TST_V07_C' + @Token;
DECLARE @LevelName NVARCHAR(30) = N'V07等级' + @Token;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Complete the R-domain parents using the installed roles and this test's own identities.
    DECLARE @FixtureAccounts TABLE (username VARCHAR(50) PRIMARY KEY, account_id BIGINT NOT NULL);
    INSERT INTO dbo.SysAccount (username, password_hash, role_id)
    OUTPUT INSERTED.username, INSERTED.account_id INTO @FixtureAccounts (username, account_id)
    SELECT f.username, 'REPLACE_WITH_REAL_PASSWORD_HASH', r.role_id
    FROM (VALUES
        (@UserBoth, 'R04'),
        (@UserWalletOnly, 'R04'),
        (@UserLevelOnly, 'R04')
    ) f(username, role_code)
    JOIN dbo.SysRole r ON r.role_code = f.role_code;
    IF @@ROWCOUNT <> 3
        THROW 52990, 'Install the required R roles before running this fixture.', 1;

    INSERT INTO dbo.UserProfile
        (user_id, account_id, phone_ciphertext, phone_hash, real_name_status, registered_at, status)
    SELECT f.username, f.account_id, 0x00, CONVERT(CHAR(64), HASHBYTES('SHA2_256', f.username), 2),
           'UNVERIFIED', '2026-01-01', 'ACTIVE'
    FROM @FixtureAccounts f
    WHERE f.username IN (@UserBoth, @UserWalletOnly, @UserLevelOnly);

    INSERT INTO dbo.MemberLevel (member_level_id, level_name, level_sort, status)
    VALUES (@LevelId, @LevelName, 987650000, 'ACTIVE');

    INSERT INTO dbo.UserMemberLevel (user_id, member_level_id)
    VALUES (@UserBoth, @LevelId), (@UserLevelOnly, @LevelId);

    INSERT INTO dbo.UserWallet (user_id, balance, status)
    VALUES (@UserBoth, 13.00, 'ACTIVE'), (@UserWalletOnly, 5.50, 'FROZEN');

    IF (SELECT COUNT(*) FROM dbo.v_A2MemberWalletSummary
        WHERE user_id IN (@UserBoth, @UserWalletOnly, @UserLevelOnly)) <> 3
        THROW 51902, 'V07 did not return the distinct A2 user set.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A2MemberWalletSummary
        WHERE user_id = @UserBoth AND member_level_id = @LevelId
          AND level_name = @LevelName AND wallet_balance = 13.00
          AND wallet_status = 'ACTIVE')
        THROW 51903, 'V07 returned incorrect member or wallet values.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A2MemberWalletSummary
        WHERE user_id = @UserWalletOnly AND member_level_id IS NULL
          AND wallet_balance = 5.50 AND wallet_status = 'FROZEN')
        THROW 51904, 'V07 did not preserve the wallet-only user.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.v_A2MemberWalletSummary
        WHERE user_id = @UserLevelOnly AND member_level_id = @LevelId
          AND wallet_balance IS NULL AND wallet_status IS NULL)
        THROW 51905, 'V07 did not preserve the member-only user.', 1;

    SELECT user_id, member_level_id, level_name, level_sort,
           wallet_balance, wallet_status
    FROM dbo.v_A2MemberWalletSummary
    WHERE user_id IN (@UserBoth, @UserWalletOnly, @UserLevelOnly)
    ORDER BY user_id;
    SELECT N'V07 会员等级与钱包快照' AS test_name, N'通过' AS test_result;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

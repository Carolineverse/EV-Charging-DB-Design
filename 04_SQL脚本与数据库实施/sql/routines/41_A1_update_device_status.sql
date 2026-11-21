CREATE OR ALTER PROCEDURE dbo.usp_A1_UpdateDeviceStatus
    @pile_id VARCHAR(20) = NULL,
    @gun_id VARCHAR(20) = NULL,
    @new_status VARCHAR(20),
    @change_reason NVARCHAR(200),
    @change_source VARCHAR(30),
    @changed_at DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    IF (CASE WHEN @pile_id IS NULL THEN 0 ELSE 1 END
        + CASE WHEN @gun_id IS NULL THEN 0 ELSE 1 END) <> 1
        THROW 52300, 'Specify exactly one of @pile_id or @gun_id.', 1;

    IF @new_status IS NULL OR @new_status NOT IN
       ('UNKNOWN', 'IDLE', 'OCCUPIED', 'FAULT', 'OFFLINE')
        THROW 52301, 'Invalid device status.', 1;

    IF @change_source IS NULL OR @change_source NOT IN
       ('DEVICE_REPORT', 'HEARTBEAT_CHECK', 'DEVICE_MONITOR',
        'CHARGING_ORDER', 'REPAIR_REVIEW', 'MANUAL', 'SYSTEM_RULE')
        THROW 52302, 'Invalid device status change source.', 1;

    IF @change_reason IS NULL OR LEN(LTRIM(RTRIM(@change_reason))) = 0
        THROW 52303, 'A non-empty change reason is required.', 1;

    DECLARE @owns_transaction BIT = 0;
    DECLARE @old_status VARCHAR(20);
    DECLARE @target_found BIT = 0;
    DECLARE @effective_changed_at DATETIME2(3) = COALESCE(@changed_at, SYSDATETIME());

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @owns_transaction = 1;
        END
        ELSE
            SAVE TRANSACTION A1UpdateDeviceStatusSave;

        IF @pile_id IS NOT NULL
        BEGIN
            SELECT @old_status = status, @target_found = 1
            FROM dbo.ChargingPile WITH (UPDLOCK, HOLDLOCK)
            WHERE pile_id = @pile_id;

            IF @target_found = 0
                THROW 52304, 'Charging pile not found.', 1;
        END
        ELSE
        BEGIN
            SELECT @old_status = status, @target_found = 1
            FROM dbo.ChargingGun WITH (UPDLOCK, HOLDLOCK)
            WHERE gun_id = @gun_id;

            IF @target_found = 0
                THROW 52305, 'Charging gun not found.', 1;
        END;

        IF @old_status = @new_status
        BEGIN
            IF @owns_transaction = 1 COMMIT TRANSACTION;
            SELECT 'NO_CHANGE' AS result_code,
                   @old_status AS old_status,
                   @new_status AS new_status,
                   CAST(NULL AS BIGINT) AS history_id;
            RETURN;
        END;

        IF @pile_id IS NOT NULL
            UPDATE dbo.ChargingPile
            SET status = @new_status,
                updated_at = SYSDATETIME()
            WHERE pile_id = @pile_id;
        ELSE
            UPDATE dbo.ChargingGun
            SET status = @new_status,
                updated_at = SYSDATETIME()
            WHERE gun_id = @gun_id;

        INSERT INTO dbo.DeviceStatusHistory
            (pile_id, gun_id, old_status, new_status, changed_at,
             change_reason, change_source)
        VALUES
            (@pile_id, @gun_id, @old_status, @new_status, @effective_changed_at,
             @change_reason, @change_source);

        DECLARE @history_id BIGINT = CONVERT(BIGINT, SCOPE_IDENTITY());

        IF @owns_transaction = 1 COMMIT TRANSACTION;

        SELECT 'UPDATED' AS result_code,
               @old_status AS old_status,
               @new_status AS new_status,
               @history_id AS history_id;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @owns_transaction = 1
                ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1
                ROLLBACK TRANSACTION A1UpdateDeviceStatusSave;
        END;
        THROW;
    END CATCH;
END;
GO

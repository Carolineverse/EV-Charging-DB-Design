-- [C] 工单派发
CREATE PROCEDURE dbo.usp_DispatchWorkOrder
    @alarm_id             BIGINT,
    @engineer_staff_id    VARCHAR(20),
    @dispatcher_account_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @accept_minutes INT;
        DECLARE @now DATETIME2(3) = SYSDATETIME();

        IF NOT EXISTS (SELECT 1 FROM dbo.Alarm WITH (UPDLOCK, HOLDLOCK) WHERE alarm_id = @alarm_id AND status IN ('PENDING','PENDING_VERIFY'))
            THROW 50001, N'告警不存在或状态不可派单', 1;
        IF EXISTS (SELECT 1 FROM dbo.WorkOrder WHERE alarm_id = @alarm_id AND status IN ('PENDING_ACCEPT','PENDING_ARRIVAL','PROCESSING','PENDING_REVIEW'))
            THROW 50002, N'该告警已存在在办工单', 1;
        IF NOT EXISTS (
            SELECT 1 FROM dbo.EngineerDutySchedule d
            JOIN dbo.StaffProfile s ON d.staff_id = s.staff_id
            WHERE d.staff_id = @engineer_staff_id
              AND d.duty_status = 'ACTIVE' AND d.accepting_status = 'ACCEPTING'
              AND @now >= d.duty_start AND @now < d.duty_end
              AND s.employment_status = 'ACTIVE')
            THROW 50003, N'工程师不在可派单状态', 1;

        SELECT @accept_minutes = p.accept_timeout_minutes
        FROM dbo.Alarm a JOIN dbo.AlarmLevelPolicy p ON a.alarm_level = p.alarm_level
        WHERE a.alarm_id = @alarm_id;

        INSERT INTO dbo.WorkOrder (alarm_id, dispatcher_staff_id, engineer_staff_id, assigned_at, status, accept_deadline)
        VALUES (@alarm_id,
                (SELECT staff_id FROM dbo.StaffProfile WHERE account_id = @dispatcher_account_id),
                @engineer_staff_id, @now, 'PENDING_ACCEPT',
                DATEADD(minute, @accept_minutes, @now));

        UPDATE dbo.Alarm SET status = 'PROCESSING', updated_at = @now WHERE alarm_id = @alarm_id;

        INSERT INTO dbo.OperationLog (module_code, object_type, object_id, action_code, actor_type, actor_account_id, occurred_at, after_data)
        VALUES ('C', 'ALARM', CONVERT(varchar(50), @alarm_id), 'DISPATCH_WORKORDER', CASE WHEN @dispatcher_account_id IS NULL THEN 'SYSTEM' ELSE 'HUMAN' END, @dispatcher_account_id, @now, N'{"status":"PROCESSING"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

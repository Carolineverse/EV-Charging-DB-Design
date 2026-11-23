-- C-line procedure success, audit, state transition, and invalid-alarm guard.
SET NOCOUNT ON;
IF DB_NAME()<>N'EV_B_TEST' THROW 52940,N'Choose EV_B_TEST',1;

DECLARE @alarm_id BIGINT;
DECLARE @engineer VARCHAR(20);
DECLARE @dispatcher_account BIGINT;
DECLARE @dispatcher_staff VARCHAR(20);
DECLARE @work_order_id BIGINT;
DECLARE @token VARCHAR(36)=CONVERT(VARCHAR(36),NEWID());
DECLARE @new_alarm TABLE(alarm_id BIGINT);

SELECT TOP (1) @engineer=s.staff_id
FROM dbo.EngineerDutySchedule d
JOIN dbo.StaffProfile s ON s.staff_id=d.staff_id
WHERE d.duty_status='ACTIVE' AND d.accepting_status='ACCEPTING'
  AND SYSDATETIME()>=d.duty_start AND SYSDATETIME()<d.duty_end
  AND s.employment_status='ACTIVE'
ORDER BY d.duty_id;
SELECT @dispatcher_account=account_id FROM dbo.SysAccount WHERE username='demo_admin_r01';
SELECT @dispatcher_staff=staff_id FROM dbo.StaffProfile WHERE account_id=@dispatcher_account;
IF @engineer IS NULL OR @dispatcher_account IS NULL OR @dispatcher_staff IS NULL
    THROW 52941,N'No active C-line engineer/dispatcher test fixture is available.',1;

BEGIN TRANSACTION;
INSERT INTO dbo.Alarm
    (pile_id,alarm_code,alarm_level,alarm_description,alarm_source,occurred_at,status)
OUTPUT INSERTED.alarm_id INTO @new_alarm
VALUES ('B_DEMO_PILE01','AL001',1,N'QATST '+@token,'MANUAL_ENTRY',SYSDATETIME(),'PENDING');
SELECT @alarm_id=alarm_id FROM @new_alarm;

EXEC dbo.usp_DispatchWorkOrder @alarm_id,@engineer,@dispatcher_account;
SELECT @work_order_id=work_order_id FROM dbo.WorkOrder WHERE alarm_id=@alarm_id;
IF @work_order_id IS NULL
    THROW 52942,N'usp_DispatchWorkOrder did not create a work order.',1;
IF NOT EXISTS
(
    SELECT 1 FROM dbo.WorkOrder
    WHERE work_order_id=@work_order_id AND engineer_staff_id=@engineer
      AND dispatcher_staff_id=@dispatcher_staff AND status='PENDING_ACCEPT'
      AND accept_deadline>assigned_at
)
    THROW 52943,N'usp_DispatchWorkOrder wrote incorrect work-order state or deadline.',1;
IF NOT EXISTS (SELECT 1 FROM dbo.Alarm WHERE alarm_id=@alarm_id AND status='PROCESSING')
    THROW 52944,N'usp_DispatchWorkOrder did not advance the alarm state.',1;
IF (SELECT COUNT(*) FROM dbo.OperationLog
    WHERE module_code='C' AND object_type='ALARM'
      AND object_id=CONVERT(VARCHAR(50),@alarm_id)
      AND action_code='DISPATCH_WORKORDER')<>1
    THROW 52945,N'usp_DispatchWorkOrder did not write exactly one audit event.',1;
ROLLBACK TRANSACTION;

DECLARE @error INT=0;
BEGIN TRY
    EXEC dbo.usp_DispatchWorkOrder -1,@engineer,@dispatcher_account;
END TRY
BEGIN CATCH
    SET @error=ERROR_NUMBER();
END CATCH;
IF @error<>50001
    THROW 52946,N'usp_DispatchWorkOrder did not reject an absent/pending-ineligible alarm.',1;

SELECT N'C usp_DispatchWorkOrder' AS test_name,N'passed' AS test_result;

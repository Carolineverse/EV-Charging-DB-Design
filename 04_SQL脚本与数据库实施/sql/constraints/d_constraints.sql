SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
-- =============================================================
-- D 线 · 批次 30：外键 + 索引
-- 依赖：01/02/03 建表完成，且 B 线 34 张表已建
-- 执行顺序：先补 UQ 约束（作外键目标），再加外键，最后加普通/过滤索引
-- =============================================================

-- ---------- 0. 先补遗漏的唯一约束（作为复合外键目标）----------
ALTER TABLE dbo.ServiceCaseAssignment ADD CONSTRAINT UQ_ServiceCaseAssignment_01 UNIQUE (case_type, case_id, effective_from);
ALTER TABLE dbo.NotificationLog         ADD CONSTRAINT UQ_NotificationLog_01 UNIQUE (business_type, business_id, recipient_account_id, event_code);
ALTER TABLE dbo.StaffStationAssignment  ADD CONSTRAINT UQ_StaffStationAssignment_01 UNIQUE (staff_id, station_id, effective_from);
ALTER TABLE dbo.SettlementStatement     ADD CONSTRAINT UQ_SettlementStatement_01 UNIQUE (station_id, period_month);
ALTER TABLE dbo.SettlementDetail        ADD CONSTRAINT UQ_SettlementDetail_01 UNIQUE (settlement_id, order_id);
ALTER TABLE dbo.SettlementCarryoverAdjustment ADD CONSTRAINT UQ_SettlementCarryoverAdjustment_01 UNIQUE (refund_id);
GO

-- =============================================================
-- 1. 外键（按依赖顺序：R → C → D）
-- =============================================================

-- ---- R 线 ----
ALTER TABLE dbo.SysAccount          ADD CONSTRAINT FK_SysAccount_role FOREIGN KEY (role_id) REFERENCES dbo.SysRole(role_id);
ALTER TABLE dbo.StaffProfile        ADD CONSTRAINT FK_StaffProfile_account FOREIGN KEY (account_id) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.UserProfile         ADD CONSTRAINT FK_UserProfile_account FOREIGN KEY (account_id) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.EnterpriseProfile   ADD CONSTRAINT FK_EnterpriseProfile_account FOREIGN KEY (account_id) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.RolePermission      ADD CONSTRAINT FK_RolePermission_role FOREIGN KEY (role_id) REFERENCES dbo.SysRole(role_id);
ALTER TABLE dbo.RolePermission      ADD CONSTRAINT FK_RolePermission_perm FOREIGN KEY (permission_id) REFERENCES dbo.SysPermission(permission_id);
ALTER TABLE dbo.OperationLog        ADD CONSTRAINT FK_OperationLog_actor FOREIGN KEY (actor_account_id) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.ServiceCaseAssignment ADD CONSTRAINT FK_ServiceCaseAssignment_assignee FOREIGN KEY (assigned_account_id) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.ServiceCaseAssignment ADD CONSTRAINT FK_ServiceCaseAssignment_assigner FOREIGN KEY (assigned_by) REFERENCES dbo.SysAccount(account_id);
GO

-- ---- C 线 ----
ALTER TABLE dbo.AlarmCodeDict        ADD CONSTRAINT FK_AlarmCodeDict_level FOREIGN KEY (default_level) REFERENCES dbo.AlarmLevelPolicy(alarm_level);
ALTER TABLE dbo.DeviceReport         ADD CONSTRAINT FK_DeviceReport_pile FOREIGN KEY (pile_id) REFERENCES dbo.ChargingPile(pile_id);
ALTER TABLE dbo.DeviceMonitoringData ADD CONSTRAINT FK_DeviceMonitoringData_report FOREIGN KEY (report_id) REFERENCES dbo.DeviceReport(report_id);
ALTER TABLE dbo.DeviceMonitoringData ADD CONSTRAINT FK_DeviceMonitoringData_pile FOREIGN KEY (pile_id) REFERENCES dbo.ChargingPile(pile_id);
ALTER TABLE dbo.DeviceMonitoringData ADD CONSTRAINT FK_DeviceMonitoringData_gun FOREIGN KEY (gun_id) REFERENCES dbo.ChargingGun(gun_id);
ALTER TABLE dbo.Alarm                ADD CONSTRAINT FK_Alarm_pile FOREIGN KEY (pile_id) REFERENCES dbo.ChargingPile(pile_id);
ALTER TABLE dbo.Alarm                ADD CONSTRAINT FK_Alarm_gun FOREIGN KEY (gun_id) REFERENCES dbo.ChargingGun(gun_id);
ALTER TABLE dbo.Alarm                ADD CONSTRAINT FK_Alarm_code FOREIGN KEY (alarm_code) REFERENCES dbo.AlarmCodeDict(alarm_code);
ALTER TABLE dbo.Alarm                ADD CONSTRAINT FK_Alarm_level FOREIGN KEY (alarm_level) REFERENCES dbo.AlarmLevelPolicy(alarm_level);
ALTER TABLE dbo.WorkOrder            ADD CONSTRAINT FK_WorkOrder_alarm FOREIGN KEY (alarm_id) REFERENCES dbo.Alarm(alarm_id);
ALTER TABLE dbo.WorkOrder            ADD CONSTRAINT FK_WorkOrder_dispatcher FOREIGN KEY (dispatcher_staff_id) REFERENCES dbo.StaffProfile(staff_id);
ALTER TABLE dbo.WorkOrder            ADD CONSTRAINT FK_WorkOrder_engineer FOREIGN KEY (engineer_staff_id) REFERENCES dbo.StaffProfile(staff_id);
ALTER TABLE dbo.StaffStationAssignment ADD CONSTRAINT FK_StaffStationAssignment_staff FOREIGN KEY (staff_id) REFERENCES dbo.StaffProfile(staff_id);
ALTER TABLE dbo.StaffStationAssignment ADD CONSTRAINT FK_StaffStationAssignment_station FOREIGN KEY (station_id) REFERENCES dbo.ChargingStation(station_id);
ALTER TABLE dbo.EngineerDutySchedule ADD CONSTRAINT FK_EngineerDutySchedule_staff FOREIGN KEY (staff_id) REFERENCES dbo.StaffProfile(staff_id);
ALTER TABLE dbo.NotificationLog      ADD CONSTRAINT FK_NotificationLog_recipient FOREIGN KEY (recipient_account_id) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.CustomerFeedback     ADD CONSTRAINT FK_CustomerFeedback_user FOREIGN KEY (user_id) REFERENCES dbo.UserProfile(user_id);
ALTER TABLE dbo.CustomerFeedback     ADD CONSTRAINT FK_CustomerFeedback_station FOREIGN KEY (station_id) REFERENCES dbo.ChargingStation(station_id);
ALTER TABLE dbo.CustomerFeedback     ADD CONSTRAINT FK_CustomerFeedback_pile FOREIGN KEY (pile_id) REFERENCES dbo.ChargingPile(pile_id);
ALTER TABLE dbo.CustomerFeedback     ADD CONSTRAINT FK_CustomerFeedback_gun FOREIGN KEY (gun_id) REFERENCES dbo.ChargingGun(gun_id);
ALTER TABLE dbo.CustomerFeedback     ADD CONSTRAINT FK_CustomerFeedback_order FOREIGN KEY (order_id) REFERENCES dbo.ChargingOrder(order_id);
ALTER TABLE dbo.CustomerFeedback     ADD CONSTRAINT FK_CustomerFeedback_staff FOREIGN KEY (assigned_staff_id) REFERENCES dbo.StaffProfile(staff_id);
ALTER TABLE dbo.FeedbackAlarm        ADD CONSTRAINT FK_FeedbackAlarm_feedback FOREIGN KEY (feedback_id) REFERENCES dbo.CustomerFeedback(feedback_id);
ALTER TABLE dbo.FeedbackAlarm        ADD CONSTRAINT FK_FeedbackAlarm_alarm FOREIGN KEY (alarm_id) REFERENCES dbo.Alarm(alarm_id);
ALTER TABLE dbo.DeviceFaultCodeMapping ADD CONSTRAINT FK_DeviceFaultCodeMapping_code FOREIGN KEY (alarm_code) REFERENCES dbo.AlarmCodeDict(alarm_code);
GO

-- ---- D 线 ----
ALTER TABLE dbo.OperatorSettlementRate ADD CONSTRAINT FK_OperatorSettlementRate_operator FOREIGN KEY (operator_id) REFERENCES dbo.Operator(operator_id);
ALTER TABLE dbo.OperatorSettlementRate ADD CONSTRAINT FK_OperatorSettlementRate_station FOREIGN KEY (station_id) REFERENCES dbo.ChargingStation(station_id);
ALTER TABLE dbo.SettlementStatement    ADD CONSTRAINT FK_SettlementStatement_station FOREIGN KEY (station_id) REFERENCES dbo.ChargingStation(station_id);
ALTER TABLE dbo.SettlementStatement    ADD CONSTRAINT FK_SettlementStatement_assignee FOREIGN KEY (assigned_account_id) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.SettlementStatement    ADD CONSTRAINT FK_SettlementStatement_createdby FOREIGN KEY (created_by) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.SettlementStatement    ADD CONSTRAINT FK_SettlementStatement_confirmedby FOREIGN KEY (confirmed_by) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.SettlementDetail       ADD CONSTRAINT FK_SettlementDetail_statement FOREIGN KEY (settlement_id) REFERENCES dbo.SettlementStatement(settlement_id);
ALTER TABLE dbo.SettlementDetail       ADD CONSTRAINT FK_SettlementDetail_order FOREIGN KEY (order_id) REFERENCES dbo.ChargingOrder(order_id);
ALTER TABLE dbo.ReconciliationDifference ADD CONSTRAINT FK_ReconciliationDifference_detail FOREIGN KEY (settlement_id, order_id) REFERENCES dbo.SettlementDetail(settlement_id, order_id);
ALTER TABLE dbo.ReconciliationDifference ADD CONSTRAINT FK_ReconciliationDifference_order FOREIGN KEY (order_id) REFERENCES dbo.ChargingOrder(order_id);
ALTER TABLE dbo.ReconciliationDifference ADD CONSTRAINT FK_ReconciliationDifference_createdby FOREIGN KEY (created_by) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.ReconciliationDifference ADD CONSTRAINT FK_ReconciliationDifference_reviewedby FOREIGN KEY (reviewed_by) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.ReconciliationDifference ADD CONSTRAINT FK_ReconciliationDifference_refund FOREIGN KEY (refund_id) REFERENCES dbo.RefundRecord(refund_id);
ALTER TABLE dbo.SettlementInvoice      ADD CONSTRAINT FK_SettlementInvoice_statement FOREIGN KEY (settlement_id) REFERENCES dbo.SettlementStatement(settlement_id);
ALTER TABLE dbo.SettlementInvoice      ADD CONSTRAINT FK_SettlementInvoice_original FOREIGN KEY (original_invoice_id) REFERENCES dbo.SettlementInvoice(invoice_id);
ALTER TABLE dbo.SettlementInvoice      ADD CONSTRAINT FK_SettlementInvoice_createdby FOREIGN KEY (created_by) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.SettlementInvoice      ADD CONSTRAINT FK_SettlementInvoice_approvedby FOREIGN KEY (approved_by) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.SettlementCarryoverAdjustment ADD CONSTRAINT FK_Carryover_original FOREIGN KEY (original_settlement_id) REFERENCES dbo.SettlementStatement(settlement_id);
ALTER TABLE dbo.SettlementCarryoverAdjustment ADD CONSTRAINT FK_Carryover_target FOREIGN KEY (target_settlement_id) REFERENCES dbo.SettlementStatement(settlement_id);
ALTER TABLE dbo.SettlementCarryoverAdjustment ADD CONSTRAINT FK_Carryover_refund FOREIGN KEY (refund_id) REFERENCES dbo.RefundRecord(refund_id);
ALTER TABLE dbo.SettlementCarryoverAdjustment ADD CONSTRAINT FK_Carryover_approvedby FOREIGN KEY (approved_by) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.SettlementCarryoverAdjustment ADD CONSTRAINT FK_Carryover_createdby FOREIGN KEY (created_by) REFERENCES dbo.SysAccount(account_id);
ALTER TABLE dbo.SettlementReviewCase    ADD CONSTRAINT FK_SettlementReviewCase_order FOREIGN KEY (order_id) REFERENCES dbo.ChargingOrder(order_id);
ALTER TABLE dbo.SettlementReviewCase    ADD CONSTRAINT FK_SettlementReviewCase_refund FOREIGN KEY (refund_id) REFERENCES dbo.RefundRecord(refund_id);
ALTER TABLE dbo.SettlementReviewCase    ADD CONSTRAINT FK_SettlementReviewCase_assignee FOREIGN KEY (assigned_account_id) REFERENCES dbo.SysAccount(account_id);
GO

-- =============================================================
-- 2. 普通索引 + 过滤唯一索引（UQ 约束已在上方/建表时创建）
-- =============================================================

-- ---- R 线 ----
CREATE INDEX IX_SysAccount_02 ON dbo.SysAccount (role_id, status);
CREATE INDEX IX_UserProfile_02 ON dbo.UserProfile (phone_hash);
CREATE INDEX IX_RolePermission_01 ON dbo.RolePermission (permission_id, role_id);
CREATE INDEX IX_OperationLog_01 ON dbo.OperationLog (module_code, object_type, object_id, occurred_at DESC);
CREATE INDEX IX_OperationLog_02 ON dbo.OperationLog (actor_account_id, occurred_at DESC);
CREATE UNIQUE INDEX UX_ServiceCaseAssignment_02 ON dbo.ServiceCaseAssignment (case_type, case_id) WHERE effective_to IS NULL;
CREATE INDEX IX_ServiceCaseAssignment_03 ON dbo.ServiceCaseAssignment (assigned_account_id, effective_from DESC);

-- ---- C 线 ----
CREATE INDEX IX_Alarm_01 ON dbo.Alarm (pile_id, alarm_code, status);
CREATE INDEX IX_Alarm_02 ON dbo.Alarm (gun_id, occurred_at DESC);
CREATE INDEX IX_WorkOrder_01 ON dbo.WorkOrder (alarm_id, status);
CREATE INDEX IX_WorkOrder_02 ON dbo.WorkOrder (engineer_staff_id, status);
CREATE INDEX IX_WorkOrder_03 ON dbo.WorkOrder (status, accept_deadline);
CREATE INDEX IX_WorkOrder_04 ON dbo.WorkOrder (status, arrival_deadline);
CREATE INDEX IX_StaffStationAssignment_02 ON dbo.StaffStationAssignment (station_id, effective_from);
CREATE INDEX IX_EngineerDutySchedule_01 ON dbo.EngineerDutySchedule (staff_id, duty_start);
CREATE INDEX IX_DeviceReport_01 ON dbo.DeviceReport (pile_id, received_at DESC);
CREATE INDEX IX_NotificationLog_02 ON dbo.NotificationLog (recipient_account_id, created_at DESC);
CREATE INDEX IX_CustomerFeedback_01 ON dbo.CustomerFeedback (user_id, created_at DESC);
CREATE INDEX IX_CustomerFeedback_02 ON dbo.CustomerFeedback (assigned_staff_id, status, created_at);
CREATE INDEX IX_CustomerFeedback_03 ON dbo.CustomerFeedback (order_id);
CREATE INDEX IX_FeedbackAlarm_01 ON dbo.FeedbackAlarm (alarm_id, feedback_id);
CREATE INDEX IX_DeviceFaultCodeMapping_01 ON dbo.DeviceFaultCodeMapping (alarm_code);

-- ---- D 线 ----
CREATE INDEX IX_OperatorSettlementRate_01 ON dbo.OperatorSettlementRate (station_id, effective_from DESC);
CREATE INDEX IX_OperatorSettlementRate_02 ON dbo.OperatorSettlementRate (operator_id, effective_from DESC);
CREATE INDEX IX_SettlementStatement_02 ON dbo.SettlementStatement (assigned_account_id, status);
CREATE INDEX IX_SettlementDetail_02 ON dbo.SettlementDetail (order_id);
CREATE INDEX IX_ReconciliationDifference_01 ON dbo.ReconciliationDifference (settlement_id, order_id, status);
CREATE INDEX IX_ReconciliationDifference_02 ON dbo.ReconciliationDifference (refund_id);
CREATE UNIQUE INDEX UX_SettlementInvoice_01 ON dbo.SettlementInvoice (invoice_no) WHERE invoice_no IS NOT NULL;
CREATE UNIQUE INDEX UX_SettlementInvoice_02 ON dbo.SettlementInvoice (original_invoice_id) WHERE original_invoice_id IS NOT NULL AND status = -1;
CREATE INDEX IX_SettlementInvoice_03 ON dbo.SettlementInvoice (settlement_id, status);
CREATE INDEX IX_SettlementCarryoverAdjustment_02 ON dbo.SettlementCarryoverAdjustment (target_settlement_id, status);
CREATE INDEX IX_SettlementCarryoverAdjustment_03 ON dbo.SettlementCarryoverAdjustment (target_period_month, status);
CREATE UNIQUE INDEX UX_SettlementReviewCase_01 ON dbo.SettlementReviewCase (refund_id) WHERE reason_code = 'POST_LOCK_REFUND' AND refund_id IS NOT NULL;
CREATE UNIQUE INDEX UX_SettlementReviewCase_02 ON dbo.SettlementReviewCase (enterprise_refund_reference, order_id) WHERE reason_code = 'ENTERPRISE_REFUND' AND enterprise_refund_reference IS NOT NULL;
CREATE INDEX IX_SettlementReviewCase_03 ON dbo.SettlementReviewCase (assigned_account_id, status, created_at);
CREATE INDEX IX_SettlementReviewCase_04 ON dbo.SettlementReviewCase (order_id);
GO

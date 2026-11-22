"""D 线业务服务方法：调用存储过程 + 参数化 SQL。"""

from datetime import datetime

from sqlalchemy import select, text

from evplatform.db import SessionLocal
from evplatform.models import Alarm, OperationLog


def log_operation(session, module_code, object_type, object_id, action_code,
                  actor_type="HUMAN", actor_account_id=None, after_data=None):
    """写操作日志，复用业务 Session，随业务一起提交。"""
    session.add(OperationLog(
        module_code=module_code, object_type=object_type, object_id=str(object_id),
        action_code=action_code, actor_type=actor_type, actor_account_id=actor_account_id,
        occurred_at=datetime.now(), after_data=after_data))


def dispatch_workorder(alarm_id, engineer_staff_id, dispatcher_account_id=None):
    with SessionLocal() as s:
        s.execute(text("EXEC dbo.usp_DispatchWorkOrder :a, :e, :d"),
                  {"a": alarm_id, "e": engineer_staff_id, "d": dispatcher_account_id})
        s.commit()


def generate_settlement(station_id, period_month, assigned_account_id, created_by):
    with SessionLocal() as s:
        rid = s.execute(text("EXEC dbo.usp_GenerateSettlement :st, :pm, :aa, :cb"),
                        {"st": station_id, "pm": period_month, "aa": assigned_account_id, "cb": created_by}).scalar_one()
        s.commit()
        return rid


def register_difference(settlement_id, order_id, difference_type, difference_amount, created_by, refund_id=None):
    with SessionLocal() as s:
        s.execute(text("EXEC dbo.usp_RegisterDifference :st, :od, :tp, :am, :rf, :cb"),
                  {"st": settlement_id, "od": order_id, "tp": difference_type, "am": difference_amount,
                   "rf": refund_id, "cb": created_by})
        s.commit()


def close_difference(difference_id, reviewed_by, operator_evidence, resolution):
    with SessionLocal() as s:
        s.execute(text("EXEC dbo.usp_CloseDifference :d, :r, :e, :res"),
                  {"d": difference_id, "r": reviewed_by, "e": operator_evidence, "res": resolution})
        s.commit()


def confirm_settlement(settlement_id, confirmed_by, evidence):
    with SessionLocal() as s:
        s.execute(text("EXEC dbo.usp_ConfirmSettlement :st, :cb, :ev"),
                  {"st": settlement_id, "cb": confirmed_by, "ev": evidence})
        s.commit()


def register_invoice(settlement_id, invoice_no, title, tax_no, amount, created_by):
    with SessionLocal() as s:
        s.execute(text("EXEC dbo.usp_RegisterInvoice :st, :no, :ti, :tax, :am, :cb"),
                  {"st": settlement_id, "no": invoice_no, "ti": title, "tax": tax_no, "am": amount, "cb": created_by})
        s.commit()


def apply_red_flush(original_invoice_id, red_reason, created_by):
    with SessionLocal() as s:
        s.execute(text("EXEC dbo.usp_ApplyRedFlush :o, :r, :cb"),
                  {"o": original_invoice_id, "r": red_reason, "cb": created_by})
        s.commit()


def approve_red_flush(red_application_id, red_invoice_no, approved_by):
    with SessionLocal() as s:
        s.execute(text("EXEC dbo.usp_ApproveRedFlush :a, :no, :by"),
                  {"a": red_application_id, "no": red_invoice_no, "by": approved_by})
        s.commit()


def approve_carryover(carryover_adjustment_id, approved_by):
    with SessionLocal() as s:
        s.execute(text("EXEC dbo.usp_ApproveCarryover :c, :by"),
                  {"c": carryover_adjustment_id, "by": approved_by})
        s.commit()


def apply_carryover(carryover_adjustment_id, target_settlement_id, applied_by):
    with SessionLocal() as s:
        s.execute(text("EXEC dbo.usp_ApplyCarryover :c, :t, :by"),
                  {"c": carryover_adjustment_id, "t": target_settlement_id, "by": applied_by})
        s.commit()


def close_review_case(review_case_id, resolution, resolved_by):
    with SessionLocal() as s:
        s.execute(text("EXEC dbo.usp_CloseReviewCase :c, :res, :by"),
                  {"c": review_case_id, "res": resolution, "by": resolved_by})
        s.commit()


def has_permission(account_id, permission_code):
    """公共权限读取：当前账号是否拥有某权限（仅返回布尔，数据范围由调用方按需解析）。"""
    with SessionLocal() as s:
        n = s.execute(text(
            "SELECT COUNT(*) FROM dbo.RolePermission rp "
            "JOIN dbo.SysAccount a ON a.role_id = rp.role_id "
            "JOIN dbo.SysPermission p ON p.permission_id = rp.permission_id "
            "WHERE a.account_id = :a AND p.permission_code = :pc "
            "AND a.status = 1 AND rp.status = 1 AND p.status = 1"),
            {"a": account_id, "pc": permission_code}).scalar_one()
    return n > 0


def settle_ledger(settlement_id):
    with SessionLocal() as s:
        row = s.execute(text(
            "SELECT gross_amount, platform_fee, adjustment_amount, payable_amount "
            "FROM dbo.v_SettlementLedger WHERE settlement_id=:st"), {"st": settlement_id}).one()
    return dict(zip(("gross_amount", "platform_fee", "adjustment_amount", "payable_amount"), row))


def paginate_alarms(page=1, size=10):
    with SessionLocal() as s:
        stmt = select(Alarm).order_by(Alarm.alarm_id).offset((page - 1) * size).limit(size)
        return s.execute(stmt).scalars().all()

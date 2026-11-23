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


_ACTIVE_GRANT = """
    FROM dbo.SysAccount AS a
    JOIN dbo.SysRole AS r ON r.role_id = a.role_id AND r.status = 1
    JOIN dbo.RolePermission AS rp ON rp.role_id = r.role_id AND rp.status = 1
    JOIN dbo.SysPermission AS p ON p.permission_id = rp.permission_id AND p.status = 1
    WHERE a.account_id = :account_id AND a.status = 1
      AND (a.locked_until IS NULL OR a.locked_until <= SYSDATETIME())
"""

_STATION_SCOPE = {
    "ALL": "1 = 1",
    "PUBLIC": "s.status = 'OPERATING'",
    "ASSIGNED": """
        EXISTS (
            SELECT 1
            FROM dbo.StaffProfile AS f
            JOIN dbo.StaffStationAssignment AS g ON g.staff_id = f.staff_id
            WHERE f.account_id = a.account_id AND f.employment_status = 'ACTIVE'
              AND g.station_id = s.station_id AND g.effective_from <= SYSDATETIME()
              AND (g.effective_to IS NULL OR g.effective_to > SYSDATETIME())
        )
    """,
    "SELF": """
        EXISTS (
            SELECT 1
            FROM dbo.UserProfile AS u
            JOIN dbo.ChargingOrder AS o ON o.user_id = u.user_id
            WHERE u.account_id = a.account_id AND u.status = 'ACTIVE'
              AND o.order_type = 'PERSONAL' AND o.opening_station_id = s.station_id
        )
    """,
    "ENTERPRISE": """
        EXISTS (
            SELECT 1
            FROM dbo.EnterpriseProfile AS e
            JOIN dbo.EnterpriseCard AS c ON c.enterprise_id = e.enterprise_id
            JOIN dbo.EnterpriseCardBinding AS b ON b.enterprise_card_id = c.enterprise_card_id
            JOIN dbo.ChargingOrder AS o ON o.binding_id = b.binding_id
            WHERE e.account_id = a.account_id AND e.status = 'ACTIVE'
              AND o.order_type = 'ENTERPRISE' AND o.opening_station_id = s.station_id
        )
    """,
}


def has_permission(account_id, permission_code):
    """Check an active account, role and permission grant."""
    with SessionLocal() as s:
        return s.execute(
            text(f"SELECT 1 {_ACTIVE_GRANT} AND p.permission_code = :permission_code"),
            {"account_id": account_id, "permission_code": permission_code},
        ).first() is not None


def _station_scope_query(predicate, permission_clause=""):
    return f"""
        SELECT s.station_id FROM dbo.ChargingStation AS s
        WHERE EXISTS (
            SELECT 1 {_ACTIVE_GRANT} AND ({predicate}) {permission_clause}
        )
    """


def filter_by_scope(account_id, scope, *, permission_code=None):
    """Return the station projection of an active grant.

    SELF uses personal order history and ENTERPRISE uses the enterprise's card
    bindings. This projection alone does not authorize individual business records.
    Pass a permission code when exposing a particular operation.
    """
    predicate = _STATION_SCOPE.get(scope)
    if predicate is None:
        return set()
    permission_clause = "AND p.permission_code = :permission_code" if permission_code is not None else ""
    query = _station_scope_query(f"rp.data_scope = :scope AND ({predicate})", permission_clause)
    with SessionLocal() as s:
        return set(s.execute(
            text(query), {"account_id": account_id, "scope": scope, "permission_code": permission_code},
        ).scalars())


def settle_ledger(settlement_id):
    with SessionLocal() as s:
        row = s.execute(text(
            "SELECT gross_amount, platform_fee, adjustment_amount, payable_amount "
            "FROM dbo.v_SettlementLedger WHERE settlement_id=:st"), {"st": settlement_id}).one()
    return dict(zip(("gross_amount", "platform_fee", "adjustment_amount", "payable_amount"), row))


def paginate_alarms(page=1, size=10, *, account_id):
    """Paginate only alarms covered by the account's ALARM_VIEW grant."""
    if page < 1 or size < 1:
        raise ValueError("page and size must be positive")
    stations = _station_scope_query(
        f"rp.data_scope = 'ALL' OR (rp.data_scope = 'ASSIGNED' AND ({_STATION_SCOPE['ASSIGNED']}))",
        "AND p.permission_code = 'ALARM_VIEW'",
    )
    visible_pile = text(f"""
        EXISTS (
            SELECT 1 FROM dbo.ChargingPile AS pile
            WHERE pile.pile_id = dbo.Alarm.pile_id AND pile.station_id IN ({stations})
        )
    """)
    with SessionLocal() as s:
        stmt = select(Alarm).where(visible_pile).order_by(Alarm.alarm_id).offset((page - 1) * size).limit(size)
        return s.execute(stmt, {"account_id": account_id}).scalars().all()

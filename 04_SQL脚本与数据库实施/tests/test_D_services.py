"""Rollback-safe tests for D flows not exercised by the integration seed."""

from uuid import uuid4

import pytest
from sqlalchemy import text


class _RollbackDFlow(Exception):
    pass


def test_red_flush_application_and_approval_are_atomic(session_factory):
    red_invoice_no = f"TST-RED-{uuid4().hex[:16]}"
    with pytest.raises(_RollbackDFlow):
        with session_factory.begin() as session:
            original = session.execute(text("""
                SELECT TOP (1) i.invoice_id, i.settlement_id, s.assigned_account_id,
                       a.account_id AS reviewer_id
                FROM dbo.SettlementInvoice AS i
                JOIN dbo.SettlementStatement AS s ON s.settlement_id=i.settlement_id
                JOIN dbo.SysAccount AS a ON a.username='demo_admin_r01'
                WHERE i.invoice_no='D-DEMO-INV-B_DEMO_ST01-202606' AND i.status=1
            """)).mappings().one()

            session.execute(text("""
                EXEC dbo.usp_ApplyRedFlush :invoice_id,N'rollback-safe integration test',:created_by
            """), {"invoice_id": original["invoice_id"], "created_by": original["assigned_account_id"]})
            red_application = session.execute(text("""
                SELECT TOP (1) invoice_id,status,amount
                FROM dbo.SettlementInvoice
                WHERE original_invoice_id=:original_invoice_id AND status=0
                ORDER BY invoice_id DESC
            """), {"original_invoice_id": original["invoice_id"]}).mappings().one()
            assert red_application["amount"] < 0

            session.execute(text("""
                EXEC dbo.usp_ApproveRedFlush :red_application_id,:red_invoice_no,:approved_by
            """), {"red_application_id": red_application["invoice_id"],
                    "red_invoice_no": red_invoice_no, "approved_by": original["reviewer_id"]})
            approved = session.execute(text("""
                SELECT status,invoice_no,issued_at,approved_at
                FROM dbo.SettlementInvoice WHERE invoice_id=:invoice_id
            """), {"invoice_id": red_application["invoice_id"]}).mappings().one()
            assert approved["status"] == -1
            assert approved["invoice_no"] == red_invoice_no
            assert approved["issued_at"] is not None and approved["approved_at"] is not None
            red_trace = session.execute(text("""
                SELECT v.original_invoice_no,v.status,v.amount,v.payable_amount,
                       v.effective_amount,v.invoice_balance
                FROM dbo.v_InvoiceBalanceAndRed AS v
                WHERE v.invoice_id=:invoice_id
            """), {"invoice_id": red_application["invoice_id"]}).mappings().one()
            assert red_trace["original_invoice_no"] == "D-DEMO-INV-B_DEMO_ST01-202606"
            assert red_trace["status"] == -1 and red_trace["amount"] < 0
            assert red_trace["invoice_balance"] == red_trace["payable_amount"] - red_trace["effective_amount"]
            assert session.execute(text("""
                SELECT COUNT(*) FROM dbo.OperationLog
                WHERE module_code='D' AND action_code IN ('APPLY_RED_FLUSH','APPROVE_RED_FLUSH')
                  AND (object_id=CONVERT(VARCHAR(50),:original_id) OR object_id=:red_invoice_no)
            """), {"original_id": original["invoice_id"], "red_invoice_no": red_invoice_no}).scalar_one() == 2
            raise _RollbackDFlow()

    with session_factory() as session:
        assert session.execute(text("""
            SELECT COUNT(*) FROM dbo.SettlementInvoice
            WHERE invoice_no=:invoice_no
        """), {"invoice_no": red_invoice_no}).scalar_one() == 0


def test_close_review_case_updates_status_and_audit_atomically(session_factory):
    with pytest.raises(_RollbackDFlow):
        with session_factory.begin() as session:
            case = session.execute(text("""
                SELECT TOP (1) review_case_id,assigned_account_id
                FROM dbo.SettlementReviewCase
                WHERE status='PENDING' AND reason_code='POST_LOCK_REFUND'
                ORDER BY review_case_id
            """)).mappings().one()
            session.execute(text("""
                EXEC dbo.usp_CloseReviewCase :review_case_id,N'rollback-safe review test',:resolved_by
            """), {"review_case_id": case["review_case_id"],
                    "resolved_by": case["assigned_account_id"]})
            closed_case = session.execute(text("""
                SELECT status,resolution,resolved_at FROM dbo.SettlementReviewCase
                WHERE review_case_id=:review_case_id
            """), {"review_case_id": case["review_case_id"]}).mappings().one()
            assert closed_case["status"] == "RESOLVED"
            assert closed_case["resolution"] == "rollback-safe review test"
            assert closed_case["resolved_at"] is not None
            assert session.execute(text("""
                SELECT COUNT(*) FROM dbo.OperationLog
                WHERE module_code='D' AND action_code='CLOSE_REVIEW_CASE'
                  AND object_id=CONVERT(VARCHAR(50),:review_case_id)
            """), {"review_case_id": case["review_case_id"]}).scalar_one() == 1
            raise _RollbackDFlow()

    with session_factory() as session:
        assert session.execute(text("""
            SELECT status FROM dbo.SettlementReviewCase WHERE review_case_id=:review_case_id
        """), {"review_case_id": case["review_case_id"]}).scalar_one() == "PENDING"


def test_zero_payable_settlement_confirmation_completes_directly(session_factory):
    with pytest.raises(_RollbackDFlow):
        with session_factory.begin() as session:
            actors = session.execute(text("""
                SELECT (SELECT account_id FROM dbo.SysAccount WHERE username='demo_settlement_r03') AS assignee,
                       (SELECT account_id FROM dbo.SysAccount WHERE username='demo_admin_r01') AS reviewer
            """)).mappings().one()
            settlement_id = session.execute(text("""
                INSERT dbo.SettlementStatement
                    (station_id,period_month,platform_rate,status,assigned_account_id,created_by)
                OUTPUT INSERTED.settlement_id
                VALUES ('B_DEMO_ST01',:month,0.200000,0,:assignee,:assignee)
            """), {**actors, "month": f"2099{(int(uuid4().hex[:2], 16) % 12) + 1:02d}"}).scalar_one()
            session.execute(text("""
                EXEC dbo.usp_ConfirmSettlement :settlement_id,:reviewer,N'zero payable test'
            """), {**actors, "settlement_id": settlement_id})
            state = session.execute(text("""
                SELECT status,confirmed_by,confirmed_at,completed_at
                FROM dbo.SettlementStatement WHERE settlement_id=:settlement_id
            """), {"settlement_id": settlement_id}).mappings().one()
            assert state["status"] == 2
            assert state["confirmed_by"] == actors["reviewer"]
            assert state["confirmed_at"] is not None and state["completed_at"] is not None
            raise _RollbackDFlow()


def test_exact_invoice_balance_completes_settlement(session_factory):
    invoice_no = f"TST-INV-{uuid4().hex[:16]}"
    with pytest.raises(_RollbackDFlow):
        with session_factory.begin() as session:
            statement = session.execute(text("""
                SELECT TOP (1) s.settlement_id,s.assigned_account_id,l.payable_amount
                FROM dbo.SettlementStatement AS s
                JOIN dbo.v_SettlementLedger AS l ON l.settlement_id=s.settlement_id
                WHERE s.station_id='B_DEMO_ST01' AND s.period_month='202606' AND s.status=1
            """)).mappings().one()
            session.execute(text("""
                DELETE dbo.SettlementInvoice WHERE settlement_id=:settlement_id
            """), {"settlement_id": statement["settlement_id"]})
            session.execute(text("""
                EXEC dbo.usp_RegisterInvoice :settlement_id,:invoice_no,N'Test operator',
                    '91110000MA0000000X',:amount,:created_by
            """), {"settlement_id": statement["settlement_id"], "invoice_no": invoice_no,
                    "amount": statement["payable_amount"], "created_by": statement["assigned_account_id"]})
            result = session.execute(text("""
                SELECT s.status,l.payable_amount,
                       (SELECT SUM(i.amount) FROM dbo.SettlementInvoice AS i
                        WHERE i.settlement_id=s.settlement_id AND i.status IN (1,-1)) AS invoiced
                FROM dbo.SettlementStatement AS s
                JOIN dbo.v_SettlementLedger AS l ON l.settlement_id=s.settlement_id
                WHERE s.settlement_id=:settlement_id
            """), {"settlement_id": statement["settlement_id"]}).mappings().one()
            assert result["status"] == 2
            assert result["invoiced"] == result["payable_amount"]
            raise _RollbackDFlow()

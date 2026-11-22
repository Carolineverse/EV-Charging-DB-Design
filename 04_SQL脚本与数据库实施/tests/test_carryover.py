"""Trace a seeded successful refund to its single applied ledger entry."""

from decimal import Decimal

from sqlalchemy import text

from evplatform.db import SessionLocal


def test_seeded_refund_is_applied_and_counted_once():
    with SessionLocal() as session:
        case = session.execute(text("""
            SELECT c.carryover_adjustment_id, c.target_settlement_id, c.adjustment_amount,
                   c.status AS carryover_status, c.approved_at, c.target_period_month,
                   original.station_id AS original_station, original.period_month AS original_period,
                   original.status AS original_status, original.confirmed_at,
                   target.station_id AS target_station, target.period_month AS target_period,
                   r.status AS refund_status, r.refund_amount, r.refunded_at, p.transaction_no,
                   l.gross_amount, l.platform_fee, l.adjustment_amount AS difference_amount,
                   l.carryover_amount, l.payable_amount,
                   (SELECT COUNT(*) FROM dbo.ReconciliationDifference diff
                    WHERE diff.refund_id = r.refund_id AND diff.status = 2
                        AND diff.difference_type = 4) AS closed_refund_differences
            FROM dbo.RefundRecord r
            JOIN dbo.PaymentRecord p ON p.payment_id = r.payment_id
            JOIN dbo.SettlementCarryoverAdjustment c ON c.refund_id = r.refund_id
            JOIN dbo.SettlementStatement original ON original.settlement_id = c.original_settlement_id
            JOIN dbo.SettlementDetail d ON d.settlement_id = original.settlement_id AND d.order_id = p.order_id
            JOIN dbo.SettlementStatement target ON target.settlement_id = c.target_settlement_id
            JOIN dbo.v_SettlementLedger l ON l.settlement_id = target.settlement_id
            WHERE r.refund_no = :refund_no
        """), {"refund_no": "D-DEMO-REF-B_DEMO_ST01-202606"}).mappings().one()

        other_applied = session.execute(text("""
            SELECT COALESCE(SUM(adjustment_amount), 0)
            FROM dbo.SettlementCarryoverAdjustment
            WHERE target_settlement_id = :target AND status = 'APPLIED'
                AND carryover_adjustment_id <> :carryover
        """), {
            "target": case["target_settlement_id"],
            "carryover": case["carryover_adjustment_id"],
        }).scalar_one()

    assert case["transaction_no"] == "D-DEMO-PAY-B_DEMO_ST01-202606"
    assert case["original_station"] == case["target_station"] == "B_DEMO_ST01"
    assert case["original_period"] == "202606"
    assert case["target_period"] == case["target_period_month"] == "202607"
    assert case["original_status"] == 1 and case["confirmed_at"] is not None
    assert case["refund_status"] == "SUCCESS"
    assert case["refunded_at"] > case["confirmed_at"]
    assert case["carryover_status"] == "APPLIED" and case["approved_at"] is not None
    assert case["closed_refund_differences"] == 0
    assert case["refund_amount"] == Decimal("1.00")
    assert case["adjustment_amount"] == Decimal("-0.80")
    applied_total = other_applied + case["adjustment_amount"]
    assert case["carryover_amount"] == applied_total
    assert case["payable_amount"] == (
        case["gross_amount"] - case["platform_fee"] + case["difference_amount"] + applied_total
    )

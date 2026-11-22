"""Validate the completed seed flow with SELECT-only queries."""

from decimal import Decimal

from sqlalchemy import bindparam, text

from evplatform.db import SessionLocal


STATIONS = ("B_DEMO_ST01", "D_DEMO_ST02", "D_DEMO_ST03", "D_DEMO_ST04", "D_DEMO_ST05")
PERIODS = ("202606", "202607", "202608", "202609", "202610")


def test_seeded_settlement_flow():
    with SessionLocal() as session:
        rows = session.execute(text("""
            SELECT l.station_id, l.period_month, l.status, l.confirmed_at, l.detail_count,
                   l.gross_amount, l.platform_fee, l.adjustment_amount, l.carryover_amount,
                   l.payable_amount, diff.closed_count, COALESCE(diff.closed_amount, 0) AS closed_amount,
                   i.amount AS invoice_amount, i.status AS invoice_status, i.issued_at,
                   carry.applied_count, COALESCE(carry.applied_amount, 0) AS applied_amount,
                   review.pending_count
            FROM dbo.v_SettlementLedger l
            OUTER APPLY (
                SELECT COUNT(*) AS closed_count, SUM(difference_amount) AS closed_amount
                FROM dbo.ReconciliationDifference
                WHERE settlement_id = l.settlement_id AND status = 2
            ) diff
            LEFT JOIN dbo.SettlementInvoice i ON i.settlement_id = l.settlement_id
                AND i.invoice_no = 'D-DEMO-INV-' + l.station_id + '-' + l.period_month
            OUTER APPLY (
                SELECT COUNT(*) AS applied_count, SUM(adjustment_amount) AS applied_amount
                FROM dbo.SettlementCarryoverAdjustment
                WHERE target_settlement_id = l.settlement_id AND status = 'APPLIED'
            ) carry
            OUTER APPLY (
                SELECT COUNT(*) AS pending_count
                FROM dbo.SettlementReviewCase q
                JOIN dbo.RefundRecord r ON r.refund_id = q.refund_id
                JOIN dbo.PaymentRecord p ON p.payment_id = r.payment_id AND p.order_id = q.order_id
                JOIN dbo.SettlementDetail d ON d.settlement_id = l.settlement_id AND d.order_id = p.order_id
                WHERE q.period_month = l.period_month AND q.reason_code = 'POST_LOCK_REFUND'
                    AND q.status = 'PENDING' AND r.status = 'SUCCESS'
                    AND r.refunded_at > l.confirmed_at
                    AND r.refund_no = 'D-DEMO-REF-' + l.station_id + '-' + l.period_month
            ) review
            WHERE l.station_id IN :stations AND l.period_month IN :periods
        """).bindparams(
            bindparam("stations", expanding=True), bindparam("periods", expanding=True)
        ), {"stations": STATIONS, "periods": PERIODS}).mappings().all()

    expected = {(station, period) for station in STATIONS for period in PERIODS}
    assert len(rows) == len(expected)
    assert {(row["station_id"], row["period_month"]) for row in rows} == expected
    for row in rows:
        key = (row["station_id"], row["period_month"])
        final_period = row["period_month"] == PERIODS[-1]
        incoming = row["period_month"] != PERIODS[0]

        assert row["detail_count"] >= 1, key
        assert row["status"] == (0 if final_period else 1), key
        assert (row["confirmed_at"] is None) == final_period, key
        assert row["closed_count"] == (4 if final_period else 0), key
        assert row["closed_amount"] == row["adjustment_amount"] == 0, key
        assert row["applied_count"] == int(incoming), key
        assert row["applied_amount"] == row["carryover_amount"], key
        assert row["applied_amount"] == (Decimal("-0.80") if incoming else 0), key
        assert row["pending_count"] == (0 if final_period else 1), key
        assert row["payable_amount"] == (
            row["gross_amount"] - row["platform_fee"] + row["closed_amount"] + row["applied_amount"]
        ), key
        if not final_period:
            assert row["invoice_status"] == 1 and row["issued_at"] is not None, key
            assert row["invoice_amount"] == Decimal("1.00") < row["payable_amount"], key

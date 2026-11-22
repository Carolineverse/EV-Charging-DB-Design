"""Validate the installed June settlement and its duplicate guard."""

from decimal import Decimal, ROUND_HALF_UP

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from evplatform.db import SessionLocal


STATION_MONTH = {"station": "B_DEMO_ST01", "period": "202606"}


def test_existing_settlement_rejects_duplicate_generation():
    with SessionLocal() as session:
        assert session.execute(text("SELECT DB_NAME()")).scalar_one() == "EV_B_TEST"
        assignee = session.execute(text("""
            SELECT assigned_account_id FROM dbo.SettlementStatement
            WHERE station_id = :station AND period_month = :period
        """), STATION_MONTH).scalar_one()

    with SessionLocal() as session, pytest.raises(DBAPIError, match=r"50011"):
        session.execute(
            text("EXEC dbo.usp_GenerateSettlement :station, :period, :assignee, :assignee"),
            {**STATION_MONTH, "assignee": assignee},
        )


def test_existing_settlement_ledger_matches_source_amounts():
    with SessionLocal() as session:
        ledger = session.execute(text("""
            SELECT s.settlement_id, s.platform_rate,
                   s.adjustment_amount AS statement_adjustment, l.detail_count,
                   l.gross_amount, l.platform_fee, l.adjustment_amount,
                   l.carryover_amount, l.payable_amount
            FROM dbo.SettlementStatement s
            JOIN dbo.v_SettlementLedger l ON l.settlement_id = s.settlement_id
            WHERE s.station_id = :station AND s.period_month = :period
        """), STATION_MONTH).mappings().one()
        key = {"settlement_id": ledger["settlement_id"]}
        details = session.execute(text("""
            SELECT electricity_base, service_base, minimum_adjustment
            FROM dbo.SettlementDetail WHERE settlement_id = :settlement_id
        """), key).all()
        closed = session.execute(text("""
            SELECT COALESCE(SUM(difference_amount), 0) FROM dbo.ReconciliationDifference
            WHERE settlement_id = :settlement_id AND status = 2
        """), key).scalar_one()
        applied = session.execute(text("""
            SELECT COALESCE(SUM(adjustment_amount), 0) FROM dbo.SettlementCarryoverAdjustment
            WHERE target_settlement_id = :settlement_id AND status = 'APPLIED'
        """), key).scalar_one()

    assert details
    assert ledger["detail_count"] == len(details)
    gross = sum(electricity + service + minimum for electricity, service, minimum in details)
    # Match SQL Server ROUND: round each detail's fee, with ties away from zero.
    fee = sum(
        ((service + minimum) * ledger["platform_rate"]).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        for _, service, minimum in details
    )
    assert ledger["gross_amount"] == gross
    assert ledger["platform_fee"] == fee
    assert ledger["statement_adjustment"] == ledger["adjustment_amount"] == closed
    assert ledger["carryover_amount"] == applied
    assert ledger["payable_amount"] == gross - fee + closed + applied

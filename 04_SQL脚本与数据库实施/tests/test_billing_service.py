from datetime import datetime
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import text

from evplatform.billing import (
    DiscountInvalid,
    FeeSegmentsInvalid,
    PricingInputInsufficient,
    PricingAlreadyFinalized,
    price_order,
)


@pytest.fixture
def billing_rules(engine, business_fixture):
    version_id = uuid4().int % (2**62) + 1
    with engine.begin() as connection:
        connection.execute(
            text(
                """
                INSERT INTO dbo.BillingRuleVersion
                    (rule_version_id, station_id, enterprise_id, free_minutes,
                     minimum_amount, effective_from, status)
                VALUES (:version_id, :station_id, NULL, 15, 5.00,
                        '2026-01-01T00:00:00', 'ACTIVE');
                """
            ),
            {"version_id": version_id, "station_id": business_fixture["station_id"]},
        )
        first_rule_id = connection.execute(
            text(
                """
                INSERT INTO dbo.BillingRule
                    (rule_version_id, period_type, period_start_time, period_end_time,
                     electricity_price, service_price)
                OUTPUT INSERTED.billing_rule_id
                VALUES (:version_id, N'平', '00:00:00', '10:00:00', 2.0000, 1.0000);
                """
            ),
            {"version_id": version_id},
        ).scalar_one()
        second_rule_id = connection.execute(
            text(
                """
                INSERT INTO dbo.BillingRule
                    (rule_version_id, period_type, period_start_time, period_end_time,
                     electricity_price, service_price)
                OUTPUT INSERTED.billing_rule_id
                VALUES (:version_id, N'峰', '10:00:00', '23:59:00', 1.5000, 0.5000);
                """
            ),
            {"version_id": version_id},
        ).scalar_one()

    try:
        yield {
            "version_id": version_id,
            "first_rule_id": first_rule_id,
            "second_rule_id": second_rule_id,
        }
    finally:
        with engine.begin() as connection:
            connection.execute(
                text("DELETE FROM dbo.BillingRule WHERE rule_version_id = :version_id"),
                {"version_id": version_id},
            )
            connection.execute(
                text("DELETE FROM dbo.BillingRuleVersion WHERE rule_version_id = :version_id"),
                {"version_id": version_id},
            )


@pytest.fixture
def pricing_order(engine, business_fixture, billing_rules):
    start_time = datetime(2026, 10, 15, 9, 0)
    end_time = datetime(2026, 10, 15, 10, 0)

    with engine.begin() as connection:
        order_id = connection.execute(
            text(
                """
                INSERT INTO dbo.ChargingOrder
                    (order_type, user_id, gun_id, start_time, end_time, energy_kwh,
                     status, opening_station_id, startup_rule_version_id)
                OUTPUT INSERTED.order_id
                VALUES ('PERSONAL', :user_id, :gun_id, :start_time, :end_time, 1.000,
                        'CHARGING', :station_id, :version_id);
                """
            ),
            {
                "user_id": business_fixture["user_id"],
                "gun_id": business_fixture["gun_id"],
                "station_id": business_fixture["station_id"],
                "version_id": billing_rules["version_id"],
                "start_time": start_time,
                "end_time": end_time,
            },
        ).scalar_one()
        connection.execute(
            text(
                """
                INSERT INTO dbo.OrderFeeDetail
                    (order_id, billing_rule_id, segment_start, segment_end,
                     segment_energy_kwh, free_service_fee)
                VALUES (:order_id, :rule_id, :start_time, :end_time, 1.000, 0.00);
                """
            ),
            {
                "order_id": order_id,
                "rule_id": billing_rules["first_rule_id"],
                "start_time": start_time,
                "end_time": end_time,
            },
        )

    try:
        yield order_id
    finally:
        with engine.begin() as connection:
            connection.execute(
                text("DELETE FROM dbo.OrderFeeDetail WHERE order_id = :order_id"),
                {"order_id": order_id},
            )
            connection.execute(
                text("DELETE FROM dbo.ChargingOrder WHERE order_id = :order_id"),
                {"order_id": order_id},
            )


def test_prices_order_with_segment_rounding_minimum_and_discount(
    session_factory, pricing_order
):
    with session_factory.begin() as session:
        result = price_order(session, order_id=pricing_order, discount_amount=Decimal("3.00"))

    assert result.electricity_base == Decimal("2.00")
    assert result.service_before_free == Decimal("1.00")
    assert result.free_service_fee == Decimal("0.00")
    assert result.service_base == Decimal("1.00")
    assert result.minimum_adjustment == Decimal("2.00")
    assert result.gross_amount == Decimal("5.00")
    assert result.discount_amount == Decimal("3.00")
    assert result.payable_amount == Decimal("2.00")
    assert result.free_minutes_applied == 15

    with session_factory.begin() as session:
        retry = price_order(session, order_id=pricing_order, discount_amount=Decimal("3.00"))
    assert retry.is_idempotent is True
    assert retry.electricity_base == result.electricity_base
    assert retry.service_base == result.service_base
    assert retry.minimum_adjustment == result.minimum_adjustment
    assert retry.gross_amount == result.gross_amount
    assert retry.payable_amount == result.payable_amount

    with session_factory() as session:
        row = session.execute(
            text(
                """
                SELECT status, gross_amount, minimum_adjustment, discount_amount, priced_at
                FROM dbo.ChargingOrder WHERE order_id = :order_id;
                """
            ),
            {"order_id": pricing_order},
        ).mappings().one()

    assert row["status"] == "PENDING_PAYMENT"
    assert row["gross_amount"] == Decimal("5.00")
    assert row["minimum_adjustment"] == Decimal("2.00")
    assert row["discount_amount"] == Decimal("3.00")
    assert row["priced_at"] is not None


def test_free_service_fee_is_subtracted_once_before_minimum_adjustment(
    engine, session_factory, pricing_order
):
    with engine.begin() as connection:
        connection.execute(
            text("UPDATE dbo.OrderFeeDetail SET free_service_fee = 0.25 WHERE order_id = :order_id"),
            {"order_id": pricing_order},
        )

    with session_factory.begin() as session:
        result = price_order(session, order_id=pricing_order, discount_amount=Decimal("3.00"))

    assert result.service_before_free == Decimal("1.00")
    assert result.free_service_fee == Decimal("0.25")
    assert result.service_base == Decimal("0.75")
    assert result.minimum_adjustment == Decimal("2.25")
    assert result.gross_amount == Decimal("5.00")
    assert result.payable_amount == Decimal("2.00")

    with pytest.raises(PricingAlreadyFinalized):
        with session_factory.begin() as session:
            price_order(session, order_id=pricing_order, discount_amount=Decimal("2.00"))


def test_prices_contiguous_segments_using_their_frozen_rule_rows(
    engine, session_factory, pricing_order, billing_rules
):
    with engine.begin() as connection:
        connection.execute(
            text(
                """
                UPDATE dbo.ChargingOrder
                SET end_time = '2026-10-15T11:00:00', energy_kwh = 2.000
                WHERE order_id = :order_id;
                UPDATE dbo.OrderFeeDetail
                SET segment_energy_kwh = 1.000
                WHERE order_id = :order_id;
                INSERT INTO dbo.OrderFeeDetail
                    (order_id, billing_rule_id, segment_start, segment_end,
                     segment_energy_kwh, free_service_fee)
                VALUES (:order_id, :rule_id, '2026-10-15T10:00:00',
                        '2026-10-15T11:00:00', 1.000, 0.00);
                """
            ),
            {"order_id": pricing_order, "rule_id": billing_rules["second_rule_id"]},
        )

    with session_factory.begin() as session:
        result = price_order(session, order_id=pricing_order)

    assert result.electricity_base == Decimal("3.50")
    assert result.service_before_free == Decimal("1.50")
    assert result.minimum_adjustment == Decimal("0.00")
    assert result.gross_amount == Decimal("5.00")


def test_rounds_each_fee_segment_to_cents(engine, session_factory, pricing_order, billing_rules):
    with engine.begin() as connection:
        connection.execute(
            text(
                """
                UPDATE dbo.BillingRule
                SET electricity_price = 0.0050, service_price = 0.0050
                WHERE billing_rule_id = :rule_id;
                UPDATE dbo.BillingRuleVersion
                SET minimum_amount = 0
                WHERE rule_version_id = :version_id;
                """
            ),
            {
                "rule_id": billing_rules["first_rule_id"],
                "version_id": billing_rules["version_id"],
            },
        )

    with session_factory.begin() as session:
        result = price_order(session, order_id=pricing_order)

    assert result.electricity_base == Decimal("0.01")
    assert result.service_before_free == Decimal("0.01")
    assert result.gross_amount == Decimal("0.02")


def test_reports_insufficient_input_for_an_energy_allocation_mismatch(
    engine, session_factory, pricing_order
):
    with engine.begin() as connection:
        connection.execute(
            text("UPDATE dbo.OrderFeeDetail SET segment_energy_kwh = 0.900 WHERE order_id = :order_id"),
            {"order_id": pricing_order},
        )

    with pytest.raises(PricingInputInsufficient, match="计费输入不足"):
        with session_factory.begin() as session:
            price_order(session, order_id=pricing_order)

    with engine.connect() as connection:
        state = connection.execute(
            text(
                """
                SELECT priced_at, status, gross_amount, minimum_adjustment, discount_amount
                FROM dbo.ChargingOrder WHERE order_id = :order_id;
                """
            ),
            {"order_id": pricing_order},
        ).mappings().one()
    assert state["priced_at"] is None
    assert state["status"] == "CHARGING"
    assert state["gross_amount"] == Decimal("0.00")
    assert state["minimum_adjustment"] == Decimal("0.00")
    assert state["discount_amount"] == Decimal("0.00")


def test_reports_insufficient_input_when_a_cross_period_order_has_no_segments(
    engine, session_factory, pricing_order
):
    with engine.begin() as connection:
        connection.execute(
            text(
                """
                UPDATE dbo.ChargingOrder
                SET end_time = '2026-10-15T11:00:00', energy_kwh = 2.000
                WHERE order_id = :order_id;
                DELETE FROM dbo.OrderFeeDetail WHERE order_id = :order_id;
                """
            ),
            {"order_id": pricing_order},
        )

    with pytest.raises(PricingInputInsufficient, match="计费输入不足"):
        with session_factory.begin() as session:
            price_order(session, order_id=pricing_order)

    with engine.connect() as connection:
        state = connection.execute(
            text("SELECT priced_at, gross_amount FROM dbo.ChargingOrder WHERE order_id = :order_id"),
            {"order_id": pricing_order},
        ).mappings().one()
    assert state["priced_at"] is None
    assert state["gross_amount"] == Decimal("0.00")


@pytest.mark.parametrize(
    ("first_end", "second_start"),
    [
        (datetime(2026, 10, 15, 9, 40), datetime(2026, 10, 15, 9, 41)),
        (datetime(2026, 10, 15, 9, 40), datetime(2026, 10, 15, 9, 30)),
    ],
    ids=["gap", "overlap"],
)
def test_rejects_discontinuous_or_overlapping_segments(
    engine, session_factory, pricing_order, billing_rules, first_end, second_start
):
    with engine.begin() as connection:
        connection.execute(
            text("DELETE FROM dbo.OrderFeeDetail WHERE order_id = :order_id"),
            {"order_id": pricing_order},
        )
        connection.execute(
            text(
                """
                INSERT INTO dbo.OrderFeeDetail
                    (order_id, billing_rule_id, segment_start, segment_end,
                     segment_energy_kwh, free_service_fee)
                VALUES
                    (:order_id, :rule_id, '2026-10-15T09:00:00', :first_end, 0.500, 0.00),
                    (:order_id, :rule_id, :second_start, '2026-10-15T10:00:00', 0.500, 0.00);
                """
            ),
            {
                "order_id": pricing_order,
                "rule_id": billing_rules["first_rule_id"],
                "first_end": first_end,
                "second_start": second_start,
            },
        )

    with pytest.raises(FeeSegmentsInvalid):
        with session_factory.begin() as session:
            price_order(session, order_id=pricing_order)


def test_rejects_a_discount_above_gross_without_finalizing(session_factory, pricing_order):
    with pytest.raises(DiscountInvalid):
        with session_factory.begin() as session:
            price_order(session, order_id=pricing_order, discount_amount=Decimal("5.01"))


def test_zero_energy_has_no_minimum_adjustment(engine, session_factory, pricing_order):
    with engine.begin() as connection:
        connection.execute(
            text("UPDATE dbo.ChargingOrder SET energy_kwh = 0 WHERE order_id = :order_id"),
            {"order_id": pricing_order},
        )
        connection.execute(
            text("DELETE FROM dbo.OrderFeeDetail WHERE order_id = :order_id"),
            {"order_id": pricing_order},
        )

    with session_factory.begin() as session:
        result = price_order(session, order_id=pricing_order)

    assert result.electricity_base == Decimal("0.00")
    assert result.service_base == Decimal("0.00")
    assert result.minimum_adjustment == Decimal("0.00")
    assert result.gross_amount == Decimal("0.00")

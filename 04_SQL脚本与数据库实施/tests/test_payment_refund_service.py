from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from decimal import Decimal
from threading import Barrier
from uuid import uuid4

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from evplatform.payments import (
    OrderNotPayable,
    PaymentConflict,
    PaymentLimitExceeded,
    RefundLimitExceeded,
    WalletUnavailable,
    complete_refund,
    record_payment,
    request_refund,
)


@pytest.fixture
def payment_order(engine, business_fixture):
    with engine.begin() as connection:
        order_id = connection.execute(
            text(
                """
                INSERT INTO dbo.ChargingOrder
                    (order_type, user_id, gun_id, start_time, end_time, energy_kwh,
                     status, gross_amount, discount_amount, opening_station_id, priced_at)
                OUTPUT INSERTED.order_id
                VALUES ('PERSONAL', :user_id, :gun_id, '2026-10-15T10:00:00',
                        '2026-10-15T11:00:00', 1.000, 'PENDING_PAYMENT',
                        10.00, 0.00, :station_id, '2026-10-15T11:01:00');
                """
            ),
            {
                "user_id": business_fixture["user_id"],
                "gun_id": business_fixture["gun_id"],
                "station_id": business_fixture["station_id"],
            },
        ).scalar_one()
    return int(order_id)


@pytest.fixture
def active_wallet(engine, business_fixture):
    with engine.begin() as connection:
        connection.execute(
            text(
                "INSERT INTO dbo.UserWallet (user_id, balance, status) "
                "VALUES (:user_id, 20.00, 'ACTIVE')"
            ),
            {"user_id": business_fixture["user_id"]},
        )
    try:
        yield business_fixture["user_id"]
    finally:
        with engine.begin() as connection:
            connection.execute(
                text(
                    "DELETE FROM dbo.WalletTransaction WHERE user_id = :user_id "
                    "AND (transaction_no LIKE 'PAY:%' OR transaction_no LIKE 'REF:%')"
                ),
                {"user_id": business_fixture["user_id"]},
            )
            connection.execute(
                text("DELETE FROM dbo.UserWallet WHERE user_id = :user_id"),
                {"user_id": business_fixture["user_id"]},
            )


def test_partial_payment_is_idempotent_and_settles_once(
    session_factory, engine, payment_order
):
    first_time = datetime(2026, 10, 15, 11, 5)
    with session_factory.begin() as session:
        first = record_payment(
            session,
            order_id=payment_order,
            pay_channel="WECHAT",
            transaction_no="PAYMENT-PARTIAL-1",
            pay_amount=Decimal("4.00"),
            pay_time=first_time,
        )
    assert first.order_status == "PENDING_PAYMENT"
    assert first.paid_amount == Decimal("4.00")
    assert first.settled_at is None

    with session_factory.begin() as session:
        retry = record_payment(
            session,
            order_id=payment_order,
            pay_channel="WECHAT",
            transaction_no="PAYMENT-PARTIAL-1",
            pay_amount=Decimal("4.00"),
            pay_time=first_time,
        )
    assert retry.is_idempotent is True
    assert retry.payment_id == first.payment_id

    with pytest.raises(PaymentLimitExceeded):
        with session_factory.begin() as session:
            record_payment(
                session,
                order_id=payment_order,
                pay_channel="OTHER",
                transaction_no="PAYMENT-OVERPAY-PENDING",
                pay_amount=Decimal("6.01"),
            )

    settled_time = datetime(2026, 10, 15, 11, 10)
    with session_factory.begin() as session:
        final = record_payment(
            session,
            order_id=payment_order,
            pay_channel="ALIPAY",
            transaction_no="PAYMENT-PARTIAL-2",
            pay_amount=Decimal("6.00"),
            pay_time=settled_time,
        )
    assert final.order_status == "PAID"
    assert final.paid_amount == Decimal("10.00")
    assert final.settled_at == settled_time

    with pytest.raises(OrderNotPayable):
        with session_factory.begin() as session:
            record_payment(
                session,
                order_id=payment_order,
                pay_channel="OTHER",
                transaction_no="PAYMENT-AFTER-SETTLEMENT",
                pay_amount=Decimal("0.01"),
            )

    with engine.connect() as connection:
        order = connection.execute(
            text("SELECT paid_amount, status, settled_at FROM dbo.ChargingOrder WHERE order_id=:id"),
            {"id": payment_order},
        ).one()
        payment_count = connection.execute(
            text("SELECT COUNT(*) FROM dbo.PaymentRecord WHERE order_id=:id"),
            {"id": payment_order},
        ).scalar_one()
    assert order.paid_amount == Decimal("10.00")
    assert order.status == "PAID"
    assert order.settled_at == settled_time
    assert payment_count == 2


def test_refund_reserves_capacity_and_finalizes_idempotently(
    session_factory, engine, payment_order
):
    with session_factory.begin() as session:
        payment = record_payment(
            session,
            order_id=payment_order,
            pay_channel="WECHAT",
            transaction_no="REFUND-PAYMENT-1",
            pay_amount=Decimal("10.00"),
            pay_time=datetime(2026, 10, 15, 11, 5),
        )

    with session_factory.begin() as session:
        processing = request_refund(
            session,
            payment_id=payment.payment_id,
            refund_no="REFUND-REQUEST-1",
            refund_amount=Decimal("4.00"),
            reason="test reservation",
        )
    assert processing.status == "PROCESSING"

    with pytest.raises(RefundLimitExceeded):
        with session_factory.begin() as session:
            request_refund(
                session,
                payment_id=payment.payment_id,
                refund_no="REFUND-REQUEST-OVER",
                refund_amount=Decimal("7.00"),
            )

    with session_factory.begin() as session:
        failed = complete_refund(
            session, refund_id=processing.refund_id, final_status="FAILED"
        )
    assert failed.status == "FAILED"

    with session_factory.begin() as session:
        retry_request = request_refund(
            session,
            payment_id=payment.payment_id,
            refund_no="REFUND-REQUEST-1",
            refund_amount=Decimal("4.00"),
        )
    assert retry_request.is_idempotent is True
    assert retry_request.status == "FAILED"

    with session_factory.begin() as session:
        successful_request = request_refund(
            session,
            payment_id=payment.payment_id,
            refund_no="REFUND-REQUEST-2",
            refund_amount=Decimal("7.00"),
        )
    success_time = datetime(2026, 10, 16, 9, 0)
    with session_factory.begin() as session:
        success = complete_refund(
            session,
            refund_id=successful_request.refund_id,
            final_status="SUCCESS",
            refunded_at=success_time,
        )
    assert success.payment_refund_amount == Decimal("7.00")
    assert success.order_refund_amount == Decimal("7.00")

    with session_factory.begin() as session:
        retry_success = complete_refund(
            session,
            refund_id=successful_request.refund_id,
            final_status="SUCCESS",
            refunded_at=success_time,
        )
    assert retry_success.is_idempotent is True

    with pytest.raises(RefundLimitExceeded):
        with session_factory.begin() as session:
            request_refund(
                session,
                payment_id=payment.payment_id,
                refund_no="REFUND-REQUEST-OVER-REMAINING",
                refund_amount=Decimal("4.00"),
            )

    with engine.connect() as connection:
        order = connection.execute(
            text("SELECT refund_amount, settled_at FROM dbo.ChargingOrder WHERE order_id=:id"),
            {"id": payment_order},
        ).one()
        payment_row = connection.execute(
            text("SELECT refund_amount FROM dbo.PaymentRecord WHERE payment_id=:id"),
            {"id": payment.payment_id},
        ).one()
        refund_row = connection.execute(
            text("SELECT status, refunded_at FROM dbo.RefundRecord WHERE refund_id=:id"),
            {"id": successful_request.refund_id},
        ).one()
    assert order.refund_amount == Decimal("7.00")
    assert order.settled_at == datetime(2026, 10, 15, 11, 5)
    assert payment_row.refund_amount == Decimal("7.00")
    assert refund_row.status == "SUCCESS"
    assert refund_row.refunded_at == success_time


def test_balance_payment_and_refund_update_wallet_with_ledger_atomically(
    session_factory, engine, payment_order, active_wallet
):
    with session_factory.begin() as session:
        payment = record_payment(
            session,
            order_id=payment_order,
            pay_channel="BALANCE",
            transaction_no="BALANCE-PAYMENT-1",
            pay_amount=Decimal("10.00"),
            pay_time=datetime(2026, 10, 15, 11, 5),
        )
    assert payment.order_status == "PAID"

    with session_factory.begin() as session:
        refund = request_refund(
            session,
            payment_id=payment.payment_id,
            refund_no="BALANCE-REFUND-1",
            refund_amount=Decimal("4.00"),
        )
    with session_factory.begin() as session:
        result = complete_refund(
            session,
            refund_id=refund.refund_id,
            final_status="SUCCESS",
            refunded_at=datetime(2026, 10, 16, 9, 0),
        )
    assert result.order_refund_amount == Decimal("4.00")

    with session_factory.begin() as session:
        retry = complete_refund(
            session,
            refund_id=refund.refund_id,
            final_status="SUCCESS",
            refunded_at=datetime(2026, 10, 16, 9, 0),
        )
    assert retry.is_idempotent is True

    with engine.connect() as connection:
        wallet = connection.execute(
            text("SELECT balance FROM dbo.UserWallet WHERE user_id=:user_id"),
            {"user_id": active_wallet},
        ).scalar_one()
        ledger = connection.execute(
            text(
                """
                SELECT transaction_type, amount, balance_before, external_transaction_no
                FROM dbo.WalletTransaction
                WHERE user_id = :user_id AND order_id = :order_id
                ORDER BY wallet_transaction_id;
                """
            ),
            {"user_id": active_wallet, "order_id": payment_order},
        ).all()
    assert wallet == Decimal("14.00")
    assert len(ledger) == 2
    assert ledger[0].transaction_type == "CHARGE_PAYMENT"
    assert ledger[0].balance_before == Decimal("20.00")
    assert ledger[0].external_transaction_no == f"BALANCE:PAY:{payment.payment_id}"
    assert ledger[1].transaction_type == "REFUND"
    assert ledger[1].balance_before == Decimal("10.00")
    assert ledger[1].external_transaction_no == f"BALANCE:REFUND:{refund.refund_id}"


def test_wallet_payment_rejects_frozen_or_insufficient_wallet(
    session_factory, engine, payment_order, business_fixture
):
    with engine.begin() as connection:
        connection.execute(
            text("INSERT INTO dbo.UserWallet (user_id, balance, status) VALUES (:user_id, 5, 'FROZEN')"),
            {"user_id": business_fixture["user_id"]},
        )
    try:
        with pytest.raises(WalletUnavailable):
            with session_factory.begin() as session:
                record_payment(
                    session,
                    order_id=payment_order,
                    pay_channel="BALANCE",
                    transaction_no="BALANCE-FROZEN-1",
                    pay_amount=Decimal("10.00"),
                )
        with engine.connect() as connection:
            count = connection.execute(
                text("SELECT COUNT(*) FROM dbo.PaymentRecord WHERE order_id=:id"),
                {"id": payment_order},
            ).scalar_one()
        assert count == 0
    finally:
        with engine.begin() as connection:
            connection.execute(
                text("DELETE FROM dbo.UserWallet WHERE user_id=:user_id"),
                {"user_id": business_fixture["user_id"]},
            )


def test_wallet_ledger_failure_rolls_back_payment_and_balance(
    session_factory, engine, payment_order, active_wallet
):
    trigger_name = f"TR_test_wallet_failure_{uuid4().hex[:16]}"
    create_trigger = f"""
        CREATE TRIGGER dbo.[{trigger_name}]
        ON dbo.WalletTransaction
        AFTER INSERT
        AS
        BEGIN
            SET NOCOUNT ON;
            IF EXISTS
               (SELECT 1 FROM inserted WHERE transaction_type = 'CHARGE_PAYMENT')
                RAISERROR ('Injected wallet ledger failure.', 16, 1);
        END;
    """
    with engine.begin() as connection:
        connection.exec_driver_sql(create_trigger)

    try:
        with pytest.raises(DBAPIError):
            with session_factory.begin() as session:
                record_payment(
                    session,
                    order_id=payment_order,
                    pay_channel="BALANCE",
                    transaction_no="BALANCE-ROLLBACK-1",
                    pay_amount=Decimal("10.00"),
                )

        with engine.connect() as connection:
            wallet_balance = connection.execute(
                text("SELECT balance FROM dbo.UserWallet WHERE user_id=:user_id"),
                {"user_id": active_wallet},
            ).scalar_one()
            order = connection.execute(
                text("SELECT paid_amount, status FROM dbo.ChargingOrder WHERE order_id=:order_id"),
                {"order_id": payment_order},
            ).one()
            payment_count = connection.execute(
                text(
                    "SELECT COUNT(*) FROM dbo.PaymentRecord "
                    "WHERE order_id=:order_id AND transaction_no='BALANCE-ROLLBACK-1'"
                ),
                {"order_id": payment_order},
            ).scalar_one()
            ledger_count = connection.execute(
                text("SELECT COUNT(*) FROM dbo.WalletTransaction WHERE order_id=:order_id"),
                {"order_id": payment_order},
            ).scalar_one()
        assert wallet_balance == Decimal("20.00")
        assert order.paid_amount == Decimal("0.00")
        assert order.status == "PENDING_PAYMENT"
        assert payment_count == 0
        assert ledger_count == 0
    finally:
        with engine.begin() as connection:
            connection.exec_driver_sql(f"DROP TRIGGER dbo.[{trigger_name}]")


def test_concurrent_payment_retry_creates_one_channel_transaction(
    session_factory, engine, payment_order
):
    barrier = Barrier(2)

    def submit_payment():
        with session_factory.begin() as session:
            barrier.wait(timeout=10)
            return record_payment(
                session,
                order_id=payment_order,
                pay_channel="WECHAT",
                transaction_no="PAYMENT-CONCURRENT-RETRY",
                pay_amount=Decimal("10.00"),
                pay_time=datetime(2026, 10, 15, 11, 5),
            )

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(submit_payment) for _ in range(2)]
    results = [future.result() for future in futures]

    assert sorted(result.is_idempotent for result in results) == [False, True]
    assert results[0].payment_id == results[1].payment_id
    with engine.connect() as connection:
        count = connection.execute(
            text(
                """
                SELECT COUNT(*) FROM dbo.PaymentRecord
                WHERE order_id = :order_id AND pay_channel = 'WECHAT'
                  AND transaction_no = 'PAYMENT-CONCURRENT-RETRY';
                """
            ),
            {"order_id": payment_order},
        ).scalar_one()
    assert count == 1

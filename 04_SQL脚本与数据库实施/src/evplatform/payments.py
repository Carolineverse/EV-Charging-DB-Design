from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, InvalidOperation

from sqlalchemy import text
from sqlalchemy.orm import Session


class PaymentError(Exception):
    pass


class PaymentOrderNotFound(PaymentError):
    pass


class OrderNotPayable(PaymentError):
    pass


class PaymentConflict(PaymentError):
    pass


class PaymentLimitExceeded(PaymentError):
    pass


class WalletUnavailable(PaymentError):
    pass


class RefundNotFound(PaymentError):
    pass


class RefundConflict(PaymentError):
    pass


class RefundLimitExceeded(PaymentError):
    pass


@dataclass(frozen=True)
class PaymentResult:
    payment_id: int
    paid_amount: Decimal
    payable_amount: Decimal
    order_status: str
    settled_at: datetime | None
    is_idempotent: bool


@dataclass(frozen=True)
class RefundRequestResult:
    refund_id: int
    payment_id: int
    refund_amount: Decimal
    status: str
    is_idempotent: bool


@dataclass(frozen=True)
class RefundCompletionResult:
    refund_id: int
    status: str
    payment_refund_amount: Decimal
    order_refund_amount: Decimal
    is_idempotent: bool


_PAY_CHANNELS = {"WECHAT", "ALIPAY", "BALANCE", "OTHER"}
_REFUND_TERMINAL_STATES = {"SUCCESS", "FAILED", "CANCELLED"}
_CENT = Decimal("0.01")


def _amount(value: Decimal, name: str) -> Decimal:
    if not isinstance(value, Decimal) or not value.is_finite() or value <= 0:
        raise ValueError(f"{name} must be a finite positive Decimal.")
    try:
        quantized = value.quantize(_CENT)
    except InvalidOperation as error:
        raise ValueError(f"{name} must fit the database money precision.") from error
    if quantized != value:
        raise ValueError(f"{name} must have at most two decimal places.")
    return quantized


def _require_transaction(session: Session) -> None:
    if not session.in_transaction():
        raise RuntimeError("Call payment and refund methods inside a caller-managed transaction.")


def _order_for_update(session: Session, order_id: int):
    order = session.execute(
        text(
            """
            SELECT order_id, order_type, status, priced_at, gross_amount,
                   discount_amount, paid_amount, refund_amount, settled_at, user_id
            FROM dbo.ChargingOrder WITH (UPDLOCK, HOLDLOCK)
            WHERE order_id = :order_id;
            """
        ),
        {"order_id": order_id},
    ).mappings().first()
    if order is None:
        raise PaymentOrderNotFound(f"Charging order {order_id} does not exist.")
    return order


def record_payment(
    session: Session,
    *,
    order_id: int,
    pay_channel: str,
    transaction_no: str,
    pay_amount: Decimal,
    pay_time: datetime | None = None,
) -> PaymentResult:
    """Record a successful personal payment inside the caller's transaction."""
    _require_transaction(session)
    amount = _amount(pay_amount, "pay_amount")
    channel = pay_channel.upper() if isinstance(pay_channel, str) else ""
    if channel not in _PAY_CHANNELS:
        raise ValueError("pay_channel must be WECHAT, ALIPAY, BALANCE, or OTHER.")
    if not transaction_no or len(transaction_no.strip()) == 0 or len(transaction_no) > 64:
        raise ValueError("transaction_no must contain 1 to 64 non-whitespace characters.")

    order = _order_for_update(session, order_id)
    prior = session.execute(
        text(
            """
            SELECT payment_id, order_id, pay_amount
            FROM dbo.PaymentRecord WITH (UPDLOCK, HOLDLOCK)
            WHERE pay_channel = :pay_channel AND transaction_no = :transaction_no;
            """
        ),
        {"pay_channel": channel, "transaction_no": transaction_no},
    ).mappings().first()
    if prior is not None:
        if prior["order_id"] != order_id or prior["pay_amount"] != amount:
            raise PaymentConflict("The payment key already belongs to different payment facts.")
        return PaymentResult(
            payment_id=prior["payment_id"],
            paid_amount=order["paid_amount"],
            payable_amount=order["gross_amount"] - order["discount_amount"],
            order_status=order["status"],
            settled_at=order["settled_at"],
            is_idempotent=True,
        )

    if order["order_type"] != "PERSONAL":
        raise OrderNotPayable("Personal PaymentRecord cannot be used for enterprise orders.")
    if order["status"] != "PENDING_PAYMENT" or order["priced_at"] is None:
        raise OrderNotPayable("The order must be priced and pending payment.")

    payable = order["gross_amount"] - order["discount_amount"]
    new_paid_amount = order["paid_amount"] + amount
    if new_paid_amount > payable:
        raise PaymentLimitExceeded("The payment would exceed the order payable amount.")

    wallet = None
    if channel == "BALANCE":
        wallet = session.execute(
            text(
                """
                SELECT balance, status
                FROM dbo.UserWallet WITH (UPDLOCK, HOLDLOCK)
                WHERE user_id = :user_id;
                """
            ),
            {"user_id": order["user_id"]},
        ).mappings().first()
        if wallet is None or wallet["status"] != "ACTIVE":
            raise WalletUnavailable("An active wallet is required for balance payment.")
        if wallet["balance"] < amount:
            raise WalletUnavailable("Wallet balance is insufficient.")

    payment_id = session.execute(
        text(
            """
            INSERT INTO dbo.PaymentRecord
                (order_id, pay_channel, transaction_no, pay_amount, pay_time)
            OUTPUT INSERTED.payment_id
            VALUES (:order_id, :pay_channel, :transaction_no, :pay_amount,
                    COALESCE(:pay_time, SYSDATETIME()));
            """
        ),
        {
            "order_id": order_id,
            "pay_channel": channel,
            "transaction_no": transaction_no,
            "pay_amount": amount,
            "pay_time": pay_time,
        },
    ).scalar_one()

    if wallet is not None:
        session.execute(
            text(
                """
                UPDATE dbo.UserWallet
                SET balance = balance - :amount, updated_at = SYSDATETIME()
                WHERE user_id = :user_id;
                """
            ),
            {
                "amount": amount,
                "user_id": order["user_id"],
            },
        )
        session.execute(
            text(
                """
                INSERT INTO dbo.WalletTransaction
                    (transaction_no, user_id, transaction_type, amount, balance_before,
                     order_id, external_transaction_no, remark, transaction_at)
                VALUES
                    (:wallet_transaction_no, :user_id, 'CHARGE_PAYMENT', :amount, :balance_before,
                     :order_id, :external_transaction_no, N'订单余额支付',
                     COALESCE(:pay_time, SYSDATETIME()));
                """
            ),
            {
                "amount": amount,
                "user_id": order["user_id"],
                "wallet_transaction_no": f"PAY:{payment_id}",
                "balance_before": wallet["balance"],
                "order_id": order_id,
                "external_transaction_no": f"BALANCE:PAY:{payment_id}",
                "pay_time": pay_time,
            },
        )

    now_paid = new_paid_amount >= payable
    settled_at = order["settled_at"]
    if now_paid and settled_at is None:
        settled_at = pay_time
    session.execute(
        text(
            """
            UPDATE dbo.ChargingOrder
            SET paid_amount = :paid_amount,
                status = CASE WHEN :is_paid = 1 THEN 'PAID' ELSE status END,
                settled_at = CASE
                    WHEN :is_paid = 1 AND settled_at IS NULL
                    THEN COALESCE(:pay_time, SYSDATETIME())
                    ELSE settled_at END,
                updated_at = SYSDATETIME()
            WHERE order_id = :order_id;
            """
        ),
        {
            "paid_amount": new_paid_amount,
            "is_paid": now_paid,
            "pay_time": pay_time,
            "order_id": order_id,
        },
    )
    if now_paid and settled_at is None:
        settled_at = session.execute(
            text("SELECT settled_at FROM dbo.ChargingOrder WHERE order_id = :order_id"),
            {"order_id": order_id},
        ).scalar_one()

    return PaymentResult(
        payment_id=payment_id,
        paid_amount=new_paid_amount,
        payable_amount=payable,
        order_status="PAID" if now_paid else order["status"],
        settled_at=settled_at,
        is_idempotent=False,
    )


def request_refund(
    session: Session,
    *,
    payment_id: int,
    refund_no: str,
    refund_amount: Decimal,
    reason: str | None = None,
) -> RefundRequestResult:
    """Reserve refund capacity and create a processing refund request."""
    _require_transaction(session)
    amount = _amount(refund_amount, "refund_amount")
    if not refund_no or len(refund_no.strip()) == 0 or len(refund_no) > 64:
        raise ValueError("refund_no must contain 1 to 64 non-whitespace characters.")

    payment_key = session.execute(
        text("SELECT order_id FROM dbo.PaymentRecord WHERE payment_id = :payment_id"),
        {"payment_id": payment_id},
    ).scalar_one_or_none()
    if payment_key is None:
        raise PaymentOrderNotFound(f"Payment {payment_id} does not exist.")
    order = _order_for_update(session, payment_key)
    if order["order_type"] != "PERSONAL" or order["status"] != "PAID":
        raise OrderNotPayable("Only a settled personal order can be refunded.")

    payment = session.execute(
        text(
            """
            SELECT payment_id, order_id, pay_channel, pay_amount, refund_amount
            FROM dbo.PaymentRecord WITH (UPDLOCK, HOLDLOCK)
            WHERE payment_id = :payment_id AND order_id = :order_id;
            """
        ),
        {"payment_id": payment_id, "order_id": payment_key},
    ).mappings().one()
    prior = session.execute(
        text(
            """
            SELECT refund_id, payment_id, refund_amount, status
            FROM dbo.RefundRecord WITH (UPDLOCK, HOLDLOCK)
            WHERE refund_no = :refund_no;
            """
        ),
        {"refund_no": refund_no},
    ).mappings().first()
    if prior is not None:
        if prior["payment_id"] != payment_id or prior["refund_amount"] != amount:
            raise RefundConflict("The refund key already belongs to different refund facts.")
        return RefundRequestResult(
            refund_id=prior["refund_id"],
            payment_id=payment_id,
            refund_amount=amount,
            status=prior["status"],
            is_idempotent=True,
        )

    reserved = session.execute(
        text(
            """
            SELECT COALESCE(SUM(refund_amount), 0)
            FROM dbo.RefundRecord WITH (UPDLOCK, HOLDLOCK)
            WHERE payment_id = :payment_id AND status = 'PROCESSING';
            """
        ),
        {"payment_id": payment_id},
    ).scalar_one()
    if payment["refund_amount"] + reserved + amount > payment["pay_amount"]:
        raise RefundLimitExceeded("Successful and processing refunds would exceed this payment.")

    refund_id = session.execute(
        text(
            """
            INSERT INTO dbo.RefundRecord
                (payment_id, refund_no, refund_amount, status, reason)
            OUTPUT INSERTED.refund_id
            VALUES (:payment_id, :refund_no, :refund_amount, 'PROCESSING', :reason);
            """
        ),
        {
            "payment_id": payment_id,
            "refund_no": refund_no,
            "refund_amount": amount,
            "reason": reason,
        },
    ).scalar_one()
    return RefundRequestResult(
        refund_id=refund_id,
        payment_id=payment_id,
        refund_amount=amount,
        status="PROCESSING",
        is_idempotent=False,
    )


def complete_refund(
    session: Session,
    *,
    refund_id: int,
    final_status: str,
    refunded_at: datetime | None = None,
) -> RefundCompletionResult:
    """Finalize a refund callback; successful balance refunds credit the wallet atomically."""
    _require_transaction(session)
    state = final_status.upper() if isinstance(final_status, str) else ""
    if state not in _REFUND_TERMINAL_STATES:
        raise ValueError("final_status must be SUCCESS, FAILED, or CANCELLED.")

    refund_key = session.execute(
        text(
            """
            SELECT r.payment_id, p.order_id
            FROM dbo.RefundRecord AS r
            JOIN dbo.PaymentRecord AS p ON p.payment_id = r.payment_id
            WHERE r.refund_id = :refund_id;
            """
        ),
        {"refund_id": refund_id},
    ).mappings().first()
    if refund_key is None:
        raise RefundNotFound(f"Refund {refund_id} does not exist.")

    order = _order_for_update(session, refund_key["order_id"])
    payment = session.execute(
        text(
            """
            SELECT payment_id, order_id, pay_channel, pay_amount, refund_amount
            FROM dbo.PaymentRecord WITH (UPDLOCK, HOLDLOCK)
            WHERE payment_id = :payment_id AND order_id = :order_id;
            """
        ),
        {"payment_id": refund_key["payment_id"], "order_id": order["order_id"]},
    ).mappings().one()
    refund = session.execute(
        text(
            """
            SELECT refund_id, payment_id, refund_amount, status, refunded_at
            FROM dbo.RefundRecord WITH (UPDLOCK, HOLDLOCK)
            WHERE refund_id = :refund_id;
            """
        ),
        {"refund_id": refund_id},
    ).mappings().one()

    if refund["status"] != "PROCESSING":
        if refund["status"] != state:
            raise RefundConflict("A finalized refund cannot change to a different outcome.")
        return RefundCompletionResult(
            refund_id=refund_id,
            status=state,
            payment_refund_amount=payment["refund_amount"],
            order_refund_amount=order["refund_amount"],
            is_idempotent=True,
        )

    if state == "SUCCESS":
        if payment["refund_amount"] + refund["refund_amount"] > payment["pay_amount"]:
            raise RefundLimitExceeded("Successful refunds would exceed this payment.")

        wallet = None
        if payment["pay_channel"] == "BALANCE":
            wallet = session.execute(
                text(
                    """
                    SELECT balance, status
                    FROM dbo.UserWallet WITH (UPDLOCK, HOLDLOCK)
                    WHERE user_id = :user_id;
                    """
                ),
                {"user_id": order["user_id"]},
            ).mappings().first()
            if wallet is None or wallet["status"] == "CLOSED":
                raise WalletUnavailable("The order user's wallet cannot accept a refund.")

        session.execute(
            text(
                """
                UPDATE dbo.RefundRecord
                SET status = 'SUCCESS',
                    refunded_at = COALESCE(:refunded_at, SYSDATETIME()),
                    updated_at = SYSDATETIME()
                WHERE refund_id = :refund_id;
                """
            ),
            {
                "refunded_at": refunded_at,
                "refund_id": refund_id,
            },
        )
        session.execute(
            text(
                """
                UPDATE dbo.PaymentRecord
                SET refund_amount = refund_amount + :refund_amount,
                    updated_at = SYSDATETIME()
                WHERE payment_id = :payment_id;
                """
            ),
            {
                "refund_amount": refund["refund_amount"],
                "payment_id": payment["payment_id"],
            },
        )

        if wallet is not None:
            session.execute(
                text(
                    """
                    UPDATE dbo.UserWallet
                    SET balance = balance + :amount, updated_at = SYSDATETIME()
                    WHERE user_id = :user_id;
                    """
                ),
                {"amount": refund["refund_amount"], "user_id": order["user_id"]},
            )
            session.execute(
                text(
                    """
                    INSERT INTO dbo.WalletTransaction
                        (transaction_no, user_id, transaction_type, amount, balance_before,
                         order_id, external_transaction_no, remark, transaction_at)
                    VALUES
                        (:transaction_no, :user_id, 'REFUND', :amount, :balance_before,
                         :order_id, :external_transaction_no, N'订单余额退款',
                         COALESCE(:refunded_at, SYSDATETIME()));
                    """
                ),
                {
                    "amount": refund["refund_amount"],
                    "user_id": order["user_id"],
                    "transaction_no": f"REF:{refund_id}",
                    "balance_before": wallet["balance"],
                    "order_id": order["order_id"],
                    "external_transaction_no": f"BALANCE:REFUND:{refund_id}",
                    "refunded_at": refunded_at,
                },
            )

        order_refund_amount = session.execute(
            text(
                """
                SELECT COALESCE(SUM(refund_amount), 0)
                FROM dbo.PaymentRecord
                WHERE order_id = :order_id;
                """
            ),
            {"order_id": order["order_id"]},
        ).scalar_one()
        session.execute(
            text(
                """
                UPDATE dbo.ChargingOrder
                SET refund_amount = :refund_amount, updated_at = SYSDATETIME()
                WHERE order_id = :order_id;
                """
            ),
            {"refund_amount": order_refund_amount, "order_id": order["order_id"]},
        )
        payment_refund_amount = payment["refund_amount"] + refund["refund_amount"]
    else:
        session.execute(
            text(
                """
                UPDATE dbo.RefundRecord
                SET status = :status, refunded_at = NULL, updated_at = SYSDATETIME()
                WHERE refund_id = :refund_id;
                """
            ),
            {"status": state, "refund_id": refund_id},
        )
        payment_refund_amount = payment["refund_amount"]
        order_refund_amount = order["refund_amount"]

    return RefundCompletionResult(
        refund_id=refund_id,
        status=state,
        payment_refund_amount=payment_refund_amount,
        order_refund_amount=order_refund_amount,
        is_idempotent=False,
    )

from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy import text
from sqlalchemy.orm import Session


class PricingError(Exception):
    pass


class OrderNotFound(PricingError):
    pass


class OrderNotReady(PricingError):
    pass


class PricingAlreadyFinalized(PricingError):
    pass


class FeeSegmentsInvalid(PricingError):
    pass


class PricingInputInsufficient(PricingError):
    pass


class PricingRuleMismatch(PricingError):
    pass


class UnsupportedOrderType(PricingError):
    pass


class DiscountInvalid(PricingError):
    pass


@dataclass(frozen=True)
class PriceBreakdown:
    electricity_base: Decimal
    service_before_free: Decimal
    free_service_fee: Decimal
    service_base: Decimal
    minimum_adjustment: Decimal
    gross_amount: Decimal
    discount_amount: Decimal
    payable_amount: Decimal
    free_minutes_applied: int
    is_idempotent: bool


_ERROR_TYPES = {
    "ORDER_NOT_FOUND": OrderNotFound,
    "ORDER_NOT_READY": OrderNotReady,
    "PRICING_ALREADY_FINALIZED": PricingAlreadyFinalized,
    "FEE_SEGMENTS_INVALID": FeeSegmentsInvalid,
    "PRICING_INPUT_INSUFFICIENT": PricingInputInsufficient,
    "PRICING_RULE_MISMATCH": PricingRuleMismatch,
    "UNSUPPORTED_ORDER_TYPE": UnsupportedOrderType,
    "DISCOUNT_INVALID": DiscountInvalid,
}


def price_order(
    session: Session,
    *,
    order_id: int,
    discount_amount: Decimal = Decimal("0.00"),
) -> PriceBreakdown:
    """Run the canonical SQL pricing procedure in the caller's transaction."""
    if not session.in_transaction():
        raise RuntimeError("Call price_order inside a caller-managed transaction.")

    result = session.execute(
        text(
            "EXEC dbo.usp_PriceChargingOrder "
            "@order_id = :order_id, @discount_amount = :discount_amount"
        ),
        {"order_id": order_id, "discount_amount": discount_amount},
    ).mappings().one()

    result_code = result["result_code"]
    if result_code != "OK":
        error_type = _ERROR_TYPES.get(result_code, PricingError)
        raise error_type(result["message"])

    return PriceBreakdown(
        electricity_base=result["electricity_base"],
        service_before_free=result["service_before_free"],
        free_service_fee=result["free_service_fee"],
        service_base=result["service_base"],
        minimum_adjustment=result["minimum_adjustment"],
        gross_amount=result["gross_amount"],
        discount_amount=result["discount_amount"],
        payable_amount=result["payable_amount"],
        free_minutes_applied=result["free_minutes_applied"],
        is_idempotent=bool(result["is_idempotent"]),
    )

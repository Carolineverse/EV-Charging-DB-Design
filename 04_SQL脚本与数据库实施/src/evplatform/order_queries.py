from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from evplatform.models import ChargingOrder


@dataclass(frozen=True)
class OrderPage:
    items: tuple[ChargingOrder, ...]
    total: int
    page: int
    page_size: int


def list_orders_page(
    session: Session,
    *,
    page: int = 1,
    page_size: int = 20,
    user_id: str | None = None,
) -> OrderPage:
    """Return a stable, one-based page of orders, optionally scoped to a user."""
    if page < 1:
        raise ValueError("page must be at least 1")
    if page_size < 1 or page_size > 100:
        raise ValueError("page_size must be between 1 and 100")

    criteria = []
    if user_id is not None:
        criteria.append(ChargingOrder.user_id == user_id)

    count_statement = select(func.count()).select_from(ChargingOrder)
    statement = select(ChargingOrder)
    if criteria:
        count_statement = count_statement.where(*criteria)
        statement = statement.where(*criteria)

    total = session.scalar(count_statement) or 0
    items = session.scalars(
        statement.order_by(ChargingOrder.created_at.desc(), ChargingOrder.order_id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()
    return OrderPage(tuple(items), total, page, page_size)

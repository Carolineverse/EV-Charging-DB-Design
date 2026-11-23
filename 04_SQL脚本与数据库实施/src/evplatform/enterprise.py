"""A2 用户与会员运营业务的持久层操作。

覆盖任务书 2.1.4 / 2.2.5 的核心动作：企业卡开卡、绑定车辆、设置用车人额度、
申请对公结算 / 专属价格、车队充电明细分页，以及企业订单结清与优惠券适用判定。

业务口径（与联调种子一致）：

- 企业客户走对公月结，不逐单支付：充电结束即视为对公付款成立，
  ``settle_enterprise_order`` 把订单置 ``PAID``、``settled_at = end_time``、
  ``paid_amount = gross_amount - discount_amount``。
- ``target_audience`` 为展示标签，不参与判定；定向发券的判定依据为
  ``PromotionStation``（适用场站）+ ``PromotionMemberLevel``（适用等级）
  与 ``member_level_scope``（是否限定等级），见 ``is_promotion_applicable``。
"""
from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Optional
from uuid import uuid4

from sqlalchemy import text
from sqlalchemy.orm import Session

APPLICATION_TYPES = ("CORPORATE", "ENTERPRISE_PRICE")


class EnterpriseError(Exception):
    """企业业务操作的基类异常。"""


class EnterpriseNotFound(EnterpriseError):
    pass


class CardNotFound(EnterpriseError):
    pass


class CardInactive(EnterpriseError):
    pass


class VehicleNotFound(EnterpriseError):
    pass


class VehicleBound(EnterpriseError):
    pass


class FleetMemberNotFound(EnterpriseError):
    pass


class MembershipMismatch(EnterpriseError):
    """卡、车辆、用车人分属不同企业。"""


class QuotaConflict(EnterpriseError):
    pass


class InvalidApplicationType(EnterpriseError):
    pass


class OrderNotFound(EnterpriseError):
    pass


class OrderNotEnterprise(EnterpriseError):
    pass


class OrderNotSettleable(EnterpriseError):
    pass


def _new_id(prefix: str) -> str:
    return prefix + uuid4().hex[: 20 - len(prefix)].upper()


def _enterprise_exists(session: Session, enterprise_id: str) -> bool:
    return (
        session.execute(
            text("SELECT 1 FROM dbo.EnterpriseProfile WHERE enterprise_id = :e"),
            {"e": enterprise_id},
        ).scalar_one_or_none()
        is not None
    )


def open_enterprise_card(
    session: Session,
    *,
    enterprise_id: str,
    card_no: str,
    enterprise_card_id: Optional[str] = None,
) -> str:
    """为企业开一张卡，返回 ``enterprise_card_id``。

    未显式提供 ``enterprise_card_id`` 时自动生成；``card_no`` 全库唯一。
    """
    if not enterprise_id or len(enterprise_id) > 20:
        raise ValueError("enterprise_id must contain 1 to 20 characters.")
    if not card_no or len(card_no) > 40:
        raise ValueError("card_no must contain 1 to 40 characters.")
    if not _enterprise_exists(session, enterprise_id):
        raise EnterpriseNotFound(f"Enterprise {enterprise_id!r} does not exist.")

    if enterprise_card_id is None:
        enterprise_card_id = _new_id("EC")
    session.execute(
        text(
            """
            INSERT INTO dbo.EnterpriseCard (enterprise_card_id, enterprise_id, card_no)
            VALUES (:cid, :eid, :card_no);
            """
        ),
        {"cid": enterprise_card_id, "eid": enterprise_id, "card_no": card_no},
    )
    return enterprise_card_id


def bind_card_vehicle(
    session: Session,
    *,
    enterprise_card_id: str,
    vehicle_id: str,
    fleet_member_id: str,
    effective_start_at: Optional[datetime] = None,
    effective_end_at: Optional[datetime] = None,
) -> int:
    """把一辆车绑定到企业卡（卡—车辆—用车人三方一致），返回 ``binding_id``。

    卡、车辆、用车人必须属于同一企业；同一车辆不允许存在时间重叠的有效绑定。
    """
    card = session.execute(
        text(
            "SELECT enterprise_id, status FROM dbo.EnterpriseCard "
            "WHERE enterprise_card_id = :c"
        ),
        {"c": enterprise_card_id},
    ).mappings().first()
    if card is None:
        raise CardNotFound(f"Enterprise card {enterprise_card_id!r} does not exist.")
    if card["status"] != "ACTIVE":
        raise CardInactive(f"Enterprise card {enterprise_card_id!r} is not ACTIVE.")

    vehicle = session.execute(
        text("SELECT enterprise_id FROM dbo.Vehicle WHERE vehicle_id = :v"),
        {"v": vehicle_id},
    ).mappings().first()
    if vehicle is None:
        raise VehicleNotFound(f"Vehicle {vehicle_id!r} does not exist.")

    member = session.execute(
        text("SELECT enterprise_id FROM dbo.FleetMember WHERE fleet_member_id = :m"),
        {"m": fleet_member_id},
    ).mappings().first()
    if member is None:
        raise FleetMemberNotFound(f"Fleet member {fleet_member_id!r} does not exist.")

    if not (
        card["enterprise_id"] == vehicle["enterprise_id"] == member["enterprise_id"]
    ):
        raise MembershipMismatch(
            "Card, vehicle, and fleet member must belong to the same enterprise."
        )

    start = effective_start_at or datetime.now()
    overlap = session.execute(
        text(
            """
            SELECT TOP (1) binding_id
            FROM dbo.EnterpriseCardBinding
            WHERE vehicle_id = :v
              AND (effective_end_at IS NULL OR effective_end_at > :start);
            """
        ),
        {"v": vehicle_id, "start": start},
    ).scalar_one_or_none()
    if overlap is not None:
        raise VehicleBound(f"Vehicle {vehicle_id!r} already has an active binding.")

    binding_id = session.execute(
        text(
            """
            INSERT INTO dbo.EnterpriseCardBinding
                (enterprise_card_id, vehicle_id, fleet_member_id,
                 effective_start_at, effective_end_at)
            OUTPUT INSERTED.binding_id
            VALUES (:c, :v, :m, :start, :end);
            """
        ),
        {
            "c": enterprise_card_id,
            "v": vehicle_id,
            "m": fleet_member_id,
            "start": start,
            "end": effective_end_at,
        },
    ).scalar_one()
    return int(binding_id)


def set_enterprise_quota(
    session: Session,
    *,
    fleet_member_id: str,
    quota_month: date,
    quota_amount,
    enterprise_quota_id: Optional[str] = None,
) -> str:
    """为用车人设置某月额度（``quota_month`` 必须是当月首日），返回额度编号。"""
    if not isinstance(quota_month, date) or quota_month.day != 1:
        raise ValueError("quota_month must be the first day of a month.")
    if quota_amount < 0:
        raise ValueError("quota_amount must be >= 0.")

    member = session.execute(
        text("SELECT 1 FROM dbo.FleetMember WHERE fleet_member_id = :m"),
        {"m": fleet_member_id},
    ).scalar_one_or_none()
    if member is None:
        raise FleetMemberNotFound(f"Fleet member {fleet_member_id!r} does not exist.")

    existing = session.execute(
        text(
            "SELECT 1 FROM dbo.EnterpriseQuota "
            "WHERE fleet_member_id = :m AND quota_month = :q"
        ),
        {"m": fleet_member_id, "q": quota_month},
    ).scalar_one_or_none()
    if existing is not None:
        raise QuotaConflict(
            f"Quota for member {fleet_member_id!r} in {quota_month} already exists."
        )

    if enterprise_quota_id is None:
        enterprise_quota_id = _new_id("Q")
    session.execute(
        text(
            """
            INSERT INTO dbo.EnterpriseQuota
                (enterprise_quota_id, fleet_member_id, quota_month, quota_amount)
            VALUES (:qid, :m, :q, :amount);
            """
        ),
        {
            "qid": enterprise_quota_id,
            "m": fleet_member_id,
            "q": quota_month,
            "amount": quota_amount,
        },
    )
    return enterprise_quota_id


def submit_service_application(
    session: Session,
    *,
    enterprise_id: str,
    application_type: str,
    request_details: str,
    station_id: Optional[str] = None,
) -> int:
    """提交企业服务申请（对公结算 CORPORATE / 专属价格 ENTERPRISE_PRICE）。"""
    if application_type not in APPLICATION_TYPES:
        raise InvalidApplicationType(
            f"application_type must be one of {APPLICATION_TYPES}."
        )
    if application_type == "ENTERPRISE_PRICE" and not station_id:
        raise ValueError("station_id is required for ENTERPRISE_PRICE application.")
    if not request_details or not request_details.strip():
        raise ValueError("request_details must be non-empty.")
    if not _enterprise_exists(session, enterprise_id):
        raise EnterpriseNotFound(f"Enterprise {enterprise_id!r} does not exist.")

    application_id = session.execute(
        text(
            """
            INSERT INTO dbo.EnterpriseServiceApplication
                (enterprise_id, application_type, station_id, request_details)
            OUTPUT INSERTED.application_id
            VALUES (:e, :t, :s, :d);
            """
        ),
        {
            "e": enterprise_id,
            "t": application_type,
            "s": station_id,
            "d": request_details,
        },
    ).scalar_one()
    return int(application_id)


class EnterpriseOrderPage:
    """车队充电明细分页结果。"""

    def __init__(self, items, page, size, total):
        self.items = items
        self.page = page
        self.size = size
        self.total = total


def list_enterprise_orders_page(
    session: Session,
    *,
    enterprise_id: str,
    period_month: Optional[str] = None,
    page: int = 1,
    size: int = 20,
) -> EnterpriseOrderPage:
    """分页查询某企业的车队充电明细；``period_month`` 形如 ``202610``。"""
    if page < 1:
        raise ValueError("page must be >= 1.")
    if size < 1 or size > 200:
        raise ValueError("size must be between 1 and 200.")

    params = {"enterprise_id": enterprise_id}
    period_filter = ""
    if period_month is not None:
        if len(period_month) != 6 or not period_month.isdigit():
            raise ValueError("period_month must be a 6-digit YYYYMM string.")
        year, month = int(period_month[:4]), int(period_month[4:])
        period_start = date(year, month, 1)
        next_start = period_start + timedelta(days=32)
        next_start = next_start.replace(day=1)
        period_filter = "AND o.end_time >= :ps AND o.end_time < :pe"
        params["ps"] = period_start
        params["pe"] = next_start

    base_where = (
        "c.enterprise_id = :enterprise_id AND o.order_type = 'ENTERPRISE' "
        + period_filter
    )
    total = session.execute(
        text(
            f"""
            SELECT COUNT(*)
            FROM dbo.ChargingOrder AS o
            JOIN dbo.EnterpriseCardBinding AS b ON b.binding_id = o.binding_id
            JOIN dbo.EnterpriseCard AS c ON c.enterprise_card_id = b.enterprise_card_id
            WHERE {base_where};
            """
        ),
        params,
    ).scalar_one()

    rows = session.execute(
        text(
            f"""
            SELECT o.order_id, o.user_id, o.gun_id, o.start_time, o.end_time,
                   o.energy_kwh, o.status, o.gross_amount, o.paid_amount
            FROM dbo.ChargingOrder AS o
            JOIN dbo.EnterpriseCardBinding AS b ON b.binding_id = o.binding_id
            JOIN dbo.EnterpriseCard AS c ON c.enterprise_card_id = b.enterprise_card_id
            WHERE {base_where}
            ORDER BY o.end_time DESC, o.order_id DESC
            OFFSET :offset ROWS FETCH NEXT :size ROWS ONLY;
            """
        ),
        {**params, "offset": (page - 1) * size, "size": size},
    ).mappings().all()

    return EnterpriseOrderPage(
        items=[dict(r) for r in rows],
        page=page,
        size=size,
        total=int(total),
    )


def settle_enterprise_order(session: Session, *, order_id: int) -> int:
    """结清一笔企业订单：置 ``PAID``，``settled_at = end_time``，``paid_amount``
    按“毛额减优惠”计算。对公月结下充电结束即视为对公付款成立。

    仅接受 ``order_type='ENTERPRISE'`` 且状态为 ``CHARGING`` / ``PENDING_PAYMENT``、
    ``end_time`` 非空的订单；已 ``PAID`` 的订单幂等返回。
    """
    row = session.execute(
        text(
            """
            SELECT order_type, status, end_time, gross_amount, discount_amount
            FROM dbo.ChargingOrder WITH (UPDLOCK, HOLDLOCK)
            WHERE order_id = :oid;
            """
        ),
        {"oid": order_id},
    ).mappings().first()
    if row is None:
        raise OrderNotFound(f"Charging order {order_id} does not exist.")
    if row["order_type"] != "ENTERPRISE":
        raise OrderNotEnterprise(f"Charging order {order_id} is not an enterprise order.")
    if row["status"] == "PAID":
        return order_id
    if row["status"] not in ("CHARGING", "PENDING_PAYMENT") or row["end_time"] is None:
        raise OrderNotSettleable(
            f"Charging order {order_id} is not ready to settle "
            f"(status={row['status']!r}, end_time={row['end_time']!r})."
        )

    payable = (row["gross_amount"] or 0) - (row["discount_amount"] or 0)
    session.execute(
        text(
            """
            UPDATE dbo.ChargingOrder
            SET status = 'PAID',
                settled_at = :settled,
                paid_amount = :paid,
                updated_at = SYSDATETIME()
            WHERE order_id = :oid;
            """
        ),
        {"settled": row["end_time"], "paid": payable, "oid": order_id},
    )
    return order_id


def is_promotion_applicable(
    session: Session,
    *,
    promotion_id: str,
    user_id: str,
    station_id: str,
    at: Optional[datetime] = None,
) -> bool:
    """判断某活动对“某用户在某场站”是否适用。

    判定依据：活动 ``ACTIVE`` 且时间窗口覆盖 ``at``（默认当前时间）、场站在
    ``PromotionStation`` 内、会员等级命中 ``member_level_scope`` /
    ``PromotionMemberLevel``。``target_audience`` 仅作展示，不参与判定。
    """
    now = at or datetime.now()
    promo = session.execute(
        text(
            """
            SELECT member_level_scope, valid_start_at, valid_end_at, status
            FROM dbo.Promotion WHERE promotion_id = :p;
            """
        ),
        {"p": promotion_id},
    ).mappings().first()
    if promo is None:
        return False
    if promo["status"] != "ACTIVE":
        return False
    if not (promo["valid_start_at"] <= now <= promo["valid_end_at"]):
        return False

    station_ok = session.execute(
        text(
            "SELECT 1 FROM dbo.PromotionStation "
            "WHERE promotion_id = :p AND station_id = :s"
        ),
        {"p": promotion_id, "s": station_id},
    ).scalar_one_or_none()
    if station_ok is None:
        return False

    if promo["member_level_scope"] == "ALL":
        return True

    level = session.execute(
        text("SELECT member_level_id FROM dbo.UserMemberLevel WHERE user_id = :u"),
        {"u": user_id},
    ).scalar_one_or_none()
    if level is None:
        return False
    in_scope = session.execute(
        text(
            "SELECT 1 FROM dbo.PromotionMemberLevel "
            "WHERE promotion_id = :p AND member_level_id = :l"
        ),
        {"p": promotion_id, "l": level},
    ).scalar_one_or_none()
    return in_scope is not None

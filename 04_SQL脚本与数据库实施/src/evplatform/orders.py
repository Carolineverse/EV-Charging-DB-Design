from sqlalchemy import text
from sqlalchemy.orm import Session


class GunNotFound(Exception):
    pass


class GunUnavailable(Exception):
    pass


class GunOccupied(Exception):
    pass


class TransactionRequired(RuntimeError):
    pass


def open_personal_order(session: Session, *, user_id: str, gun_id: str) -> int:
    """Create an order inside the caller's transaction while serializing on its gun."""
    if not session.in_transaction():
        raise TransactionRequired("Call open_personal_order inside a caller-managed transaction.")
    if not user_id or len(user_id) > 20:
        raise ValueError("user_id must contain 1 to 20 characters.")
    if not gun_id or len(gun_id) > 20:
        raise ValueError("gun_id must contain 1 to 20 characters.")

    gun = session.execute(
        text(
            """
            SELECT g.status AS gun_status, p.station_id
            FROM dbo.ChargingGun AS g WITH (UPDLOCK, HOLDLOCK)
            JOIN dbo.ChargingPile AS p WITH (HOLDLOCK)
              ON p.pile_id = g.pile_id
            WHERE g.gun_id = :gun_id;
            """
        ),
        {"gun_id": gun_id},
    ).mappings().first()

    if gun is None:
        raise GunNotFound(f"Charging gun {gun_id!r} does not exist.")
    if gun["gun_status"] != "IDLE":
        raise GunUnavailable(f"Charging gun {gun_id!r} is not IDLE.")

    active_order = session.execute(
        text(
            """
            SELECT TOP (1) order_id
            FROM dbo.ChargingOrder WITH (UPDLOCK, HOLDLOCK)
            WHERE gun_id = :gun_id
              AND (
                    status IN ('CREATED', 'CHARGING')
                    OR (status = 'ABNORMAL' AND device_released_at IS NULL)
              );
            """
        ),
        {"gun_id": gun_id},
    ).scalar_one_or_none()

    if active_order is not None:
        raise GunOccupied(f"Charging gun {gun_id!r} is held by order {active_order}.")

    order_id = session.execute(
        text(
            """
            INSERT INTO dbo.ChargingOrder
                (order_type, user_id, gun_id, opening_station_id)
            OUTPUT INSERTED.order_id
            VALUES ('PERSONAL', :user_id, :gun_id, :station_id);
            """
        ),
        {
            "user_id": user_id,
            "gun_id": gun_id,
            "station_id": gun["station_id"],
        },
    ).scalar_one()

    return int(order_id)

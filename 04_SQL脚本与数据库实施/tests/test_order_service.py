from concurrent.futures import ThreadPoolExecutor
from datetime import date
from threading import Barrier

import pytest
from sqlalchemy import text

from evplatform.orders import GunOccupied, GunUnavailable, open_personal_order


def _insert_order(connection, fixture_data, *, status, released_at=None):
    return connection.execute(
        text(
            """
            INSERT INTO dbo.ChargingOrder
                (order_type, user_id, gun_id, opening_station_id, status, device_released_at)
            OUTPUT INSERTED.order_id
            VALUES ('PERSONAL', :user_id, :gun_id, :station_id, :status, :released_at);
            """
        ),
        {
            "user_id": fixture_data["user_id"],
            "gun_id": fixture_data["gun_id"],
            "station_id": fixture_data["station_id"],
            "status": status,
            "released_at": released_at,
        },
    ).scalar_one()


@pytest.mark.parametrize("status", ["CREATED", "CHARGING", "ABNORMAL"])
def test_open_order_rejects_a_gun_with_an_active_order(engine, session_factory, business_fixture, status):
    with engine.begin() as connection:
        _insert_order(connection, business_fixture, status=status)

    with pytest.raises(GunOccupied):
        with session_factory.begin() as session:
            open_personal_order(
                session,
                user_id=business_fixture["user_id"],
                gun_id=business_fixture["gun_id"],
            )


def test_open_order_allows_a_released_abnormal_order(session_factory, engine, business_fixture):
    with engine.begin() as connection:
        _insert_order(
            connection,
            business_fixture,
            status="ABNORMAL",
            released_at=date.today(),
        )

    with session_factory.begin() as session:
        new_order_id = open_personal_order(
            session,
            user_id=business_fixture["user_id"],
            gun_id=business_fixture["gun_id"],
        )

    assert new_order_id > 0


def test_open_order_rejects_a_non_idle_gun(engine, session_factory, business_fixture):
    with engine.begin() as connection:
        connection.execute(
            text("UPDATE dbo.ChargingGun SET status = 'FAULT' WHERE gun_id = :gun_id"),
            {"gun_id": business_fixture["gun_id"]},
        )

    with pytest.raises(GunUnavailable):
        with session_factory.begin() as session:
            open_personal_order(
                session,
                user_id=business_fixture["user_id"],
                gun_id=business_fixture["gun_id"],
            )


def test_concurrent_open_order_allows_only_one_order(session_factory, engine, business_fixture):
    barrier = Barrier(2)

    def open_order():
        with session_factory.begin() as session:
            barrier.wait(timeout=10)
            return open_personal_order(
                session,
                user_id=business_fixture["user_id"],
                gun_id=business_fixture["gun_id"],
            )

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(open_order) for _ in range(2)]

    created = 0
    occupied = 0
    for future in futures:
        try:
            assert future.result() > 0
            created += 1
        except GunOccupied:
            occupied += 1

    assert (created, occupied) == (1, 1)
    with engine.connect() as connection:
        active_count = connection.execute(
            text(
                """
                SELECT COUNT(*)
                FROM dbo.ChargingOrder
                WHERE gun_id = :gun_id
                  AND (status IN ('CREATED', 'CHARGING')
                       OR (status = 'ABNORMAL' AND device_released_at IS NULL));
                """
            ),
            {"gun_id": business_fixture["gun_id"]},
        ).scalar_one()

    assert active_count == 1

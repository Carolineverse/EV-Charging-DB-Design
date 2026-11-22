import os
from datetime import date, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import text

from evplatform.db import create_engine_from_env, create_session_factory


def _has_fk(connection, parent_table, parent_column, referenced_table):
    return connection.execute(
        text(
            """
            SELECT 1
            FROM sys.foreign_key_columns AS fkc
            JOIN sys.columns AS c
              ON c.object_id = fkc.parent_object_id
             AND c.column_id = fkc.parent_column_id
            WHERE fkc.parent_object_id = OBJECT_ID(:parent_table)
              AND fkc.referenced_object_id = OBJECT_ID(:referenced_table)
              AND c.name = :parent_column;
            """
        ),
        {
            "parent_table": f"dbo.{parent_table}",
            "parent_column": parent_column,
            "referenced_table": f"dbo.{referenced_table}",
        },
    ).first() is not None


@pytest.fixture(scope="module")
def engine():
    if not os.environ.get("EV_DB_ODBC"):
        pytest.skip("Set EV_DB_ODBC to a connection string targeting EV_B_TEST.")

    test_engine = create_engine_from_env()
    try:
        with test_engine.connect() as connection:
            database = connection.execute(text("SELECT DB_NAME()")).scalar_one()
        if database not in {"EV_B_TEST", "EV_D_TEST", "EV_INTEGRATION_TEST"}:
            pytest.fail(
                f"Refusing to run database tests in {database!r}; "
                "use EV_B_TEST, EV_D_TEST, or EV_INTEGRATION_TEST."
            )
        yield test_engine
    finally:
        test_engine.dispose()


@pytest.fixture
def session_factory(engine):
    return create_session_factory(engine)


@pytest.fixture
def business_fixture(engine):
    token = uuid4().hex.upper()
    operator_id = f"O{token[:19]}"
    station_id = f"S{token[:19]}"
    pile_id = f"P{token[:19]}"
    gun_id = f"G{token[:19]}"
    user_id = f"U{token[:19]}"
    notice_account_id = 1

    with engine.begin() as connection:
        if _has_fk(connection, "ChargingStation", "workorder_notice_account_id", "SysAccount"):
            notice_account_id = connection.execute(
                text("SELECT TOP (1) account_id FROM dbo.SysAccount ORDER BY account_id")
            ).scalar_one_or_none()
            if notice_account_id is None:
                pytest.skip("Seed a shared SysAccount before testing the A1-to-R foreign key.")

        if _has_fk(connection, "ChargingOrder", "user_id", "UserProfile"):
            user_id = connection.execute(
                text("SELECT TOP (1) user_id FROM dbo.UserProfile ORDER BY user_id")
            ).scalar_one_or_none()
            if user_id is None:
                pytest.skip("Seed a shared UserProfile before testing the B-to-R foreign key.")

        connection.execute(
            text("INSERT INTO dbo.Operator (operator_id, operator_name) VALUES (:id, :name)"),
            {"id": operator_id, "name": f"Concurrency test {token[:8]}"},
        )
        connection.execute(
            text(
                """
                INSERT INTO dbo.ChargingStation
                    (station_id, station_name, address, longitude, latitude, operator_id,
                     total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id)
                VALUES
                    (:station_id, :name, N'Test address', 0, 0, :operator_id,
                     1, N'00:00-24:00', N'Test', :notice_account_id);
                """
            ),
            {
                "station_id": station_id,
                "name": f"Concurrency test {token[:8]}",
                "operator_id": operator_id,
                "notice_account_id": notice_account_id,
            },
        )
        connection.execute(
            text(
                """
                INSERT INTO dbo.ChargingPile
                    (pile_id, station_id, device_model, rated_power_kw,
                     communication_protocol, commissioned_date, warranty_end_date)
                VALUES (:pile_id, :station_id, N'Test', 60, N'OCPP', :commissioned, :warranty);
                """
            ),
            {
                "pile_id": pile_id,
                "station_id": station_id,
                "commissioned": date.today(),
                "warranty": date.today() + timedelta(days=365),
            },
        )
        connection.execute(
            text(
                """
                INSERT INTO dbo.ChargingGun
                    (gun_id, pile_id, gun_sequence, gun_type, interface_standard,
                     max_output_power_kw, status)
                VALUES (:gun_id, :pile_id, 1, 'DC_FAST', N'GB/T', 60, 'IDLE');
                """
            ),
            {"gun_id": gun_id, "pile_id": pile_id},
        )

    fixture_data = {
        "operator_id": operator_id,
        "station_id": station_id,
        "pile_id": pile_id,
        "gun_id": gun_id,
        "user_id": user_id,
    }
    try:
        yield fixture_data
    finally:
        with engine.begin() as connection:
            connection.execute(
                text(
                    """
                    DELETE FROM dbo.RefundRecord
                    WHERE payment_id IN (SELECT payment_id FROM dbo.PaymentRecord WHERE order_id IN
                        (SELECT order_id FROM dbo.ChargingOrder WHERE gun_id = :gun_id));
                    """
                ),
                {"gun_id": gun_id},
            )
            connection.execute(
                text(
                    "DELETE FROM dbo.PaymentRecord WHERE order_id IN "
                    "(SELECT order_id FROM dbo.ChargingOrder WHERE gun_id = :gun_id);"
                ),
                {"gun_id": gun_id},
            )
            for table in ("OrderCommand", "ChargingMeterSample", "OrderFeeDetail"):
                connection.execute(
                    text(f"DELETE FROM dbo.{table} WHERE order_id IN "
                         "(SELECT order_id FROM dbo.ChargingOrder WHERE gun_id = :gun_id);"),
                    {"gun_id": gun_id},
                )
            connection.execute(
                text("DELETE FROM dbo.ChargingOrder WHERE gun_id = :gun_id"),
                {"gun_id": gun_id},
            )
            connection.execute(
                text("DELETE FROM dbo.ChargingGun WHERE gun_id = :gun_id"),
                {"gun_id": gun_id},
            )
            connection.execute(
                text("DELETE FROM dbo.ChargingPile WHERE pile_id = :pile_id"),
                {"pile_id": pile_id},
            )
            connection.execute(
                text("DELETE FROM dbo.ChargingStation WHERE station_id = :station_id"),
                {"station_id": station_id},
            )
            connection.execute(
                text("DELETE FROM dbo.Operator WHERE operator_id = :operator_id"),
                {"operator_id": operator_id},
            )


@pytest.fixture(autouse=True)
def guard_test_db():
    if not os.environ.get("EV_DB_ODBC"):
        pytest.skip("Set EV_DB_ODBC to a connection string targeting a course test database.")

    from evplatform.db import SessionLocal

    with SessionLocal() as session:
        database = session.execute(text("SELECT DB_NAME()")).scalar_one()
    if database not in {"EV_D_TEST", "EV_B_TEST", "EV_INTEGRATION_TEST"}:
        pytest.fail(f"仅允许在课设测试库运行，当前连接到 {database}")

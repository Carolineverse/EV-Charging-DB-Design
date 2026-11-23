"""A2 用户与会员运营（企业客户侧）持久层测试。"""
from datetime import date, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import text

from evplatform.db import create_session_factory
from evplatform.enterprise import (
    InvalidApplicationType,
    bind_card_vehicle,
    is_promotion_applicable,
    list_enterprise_orders_page,
    open_enterprise_card,
    set_enterprise_quota,
    settle_enterprise_order,
    submit_service_application,
)


@pytest.fixture(scope="module")
def enterprise_chain(engine):
    tok = uuid4().hex[:12].upper()

    def mk(prefix):
        return f"{prefix}{tok}"

    ids = {
        "operator_id": mk("O"),
        "station_id": mk("S"),
        "pile_id": mk("P"),
        "gun_id": mk("G"),
        "user_id": mk("U"),
        "enterprise_id": mk("E"),
        "fleet_member_id": mk("FM"),
        "vehicle_id": mk("V"),
        "card_id": mk("C"),
        "quota_id": mk("Q"),
        "promotion_id": mk("PR"),
    }
    notice_account_id = None
    with engine.begin() as conn:
        notice_account_id = conn.execute(
            text("SELECT TOP (1) account_id FROM dbo.SysAccount ORDER BY account_id")
        ).scalar_one()

        user_account_id = conn.execute(
            text(
                "INSERT INTO dbo.SysAccount (username, password_hash, role_id) "
                "OUTPUT INSERTED.account_id "
                "VALUES (:u, :h, 4)"
            ),
            {"u": mk("UACC"), "h": "pbkdf2_sha256$100000$00$00"},
        ).scalar_one()

        ent_account_id = conn.execute(
            text(
                "INSERT INTO dbo.SysAccount (username, password_hash, role_id) "
                "OUTPUT INSERTED.account_id "
                "VALUES (:u, :h, 5)"
            ),
            {"u": mk("EACC"), "h": "pbkdf2_sha256$100000$00$00"},
        ).scalar_one()

        ids["user_account_id"] = user_account_id
        ids["ent_account_id"] = ent_account_id

        conn.execute(
            text(
                "INSERT INTO dbo.UserProfile "
                "(user_id, account_id, phone_ciphertext, phone_hash, "
                " real_name_status, registered_at, status) "
                "VALUES (:u, :a, :cipher, :hash, 'UNVERIFIED', SYSDATETIME(), 'ACTIVE')"
            ),
            {
                "u": ids["user_id"],
                "a": user_account_id,
                "cipher": bytes(16),
                "hash": (uuid4().hex * 2)[:64],
            },
        )

        conn.execute(
            text(
                "INSERT INTO dbo.EnterpriseProfile "
                "(enterprise_id, account_id, enterprise_name, credit_code, "
                " contact_name, contact_phone_ciphertext, status) "
                "VALUES (:e, :a, N'TST enterprise', :cc, N'TST contact', :cipher, 'ACTIVE')"
            ),
            {
                "e": ids["enterprise_id"],
                "a": ent_account_id,
                "cc": f"C{tok[:17]}",
                "cipher": bytes(16),
            },
        )

        conn.execute(
            text(
                "INSERT INTO dbo.FleetMember "
                "(fleet_member_id, enterprise_id, user_id, member_no) "
                "VALUES (:m, :e, :u, :no)"
            ),
            {"m": ids["fleet_member_id"], "e": ids["enterprise_id"],
             "u": ids["user_id"], "no": f"M{tok[:10]}"},
        )

        conn.execute(
            text(
                "INSERT INTO dbo.Vehicle "
                "(vehicle_id, enterprise_id, plate_ciphertext, plate_hash, "
                " vehicle_model, battery_capacity_kwh, max_charging_power_kw) "
                "VALUES (:v, :e, :cipher, :hash, N'TST', 60, 120)"
            ),
            {
                "v": ids["vehicle_id"],
                "e": ids["enterprise_id"],
                "cipher": bytes(16),
                "hash": (uuid4().hex * 2)[:64],
            },
        )

        conn.execute(
            text(
                "INSERT INTO dbo.Operator (operator_id, operator_name) VALUES (:o, N'TST')"
            ),
            {"o": ids["operator_id"]},
        )
        conn.execute(
            text(
                "INSERT INTO dbo.ChargingStation "
                "(station_id, station_name, address, longitude, latitude, operator_id, "
                " total_spaces, business_hours, parking_fee_standard, workorder_notice_account_id) "
                "VALUES (:s, N'TST', N'addr', 0, 0, :o, 1, N'00:00-24:00', N'TST', :n)"
            ),
            {"s": ids["station_id"], "o": ids["operator_id"], "n": notice_account_id},
        )
        conn.execute(
            text(
                "INSERT INTO dbo.ChargingPile "
                "(pile_id, station_id, device_model, rated_power_kw, "
                " communication_protocol, commissioned_date, warranty_end_date) "
                "VALUES (:p, :s, N'TST', 120, N'OCPP', '2026-01-01', '2028-01-01')"
            ),
            {"p": ids["pile_id"], "s": ids["station_id"]},
        )
        conn.execute(
            text(
                "INSERT INTO dbo.ChargingGun "
                "(gun_id, pile_id, gun_sequence, gun_type, interface_standard, "
                " max_output_power_kw, status) "
                "VALUES (:g, :p, 1, 'DC_FAST', N'GB/T', 120, 'IDLE')"
            ),
            {"g": ids["gun_id"], "p": ids["pile_id"]},
        )

    # 用持久层函数建卡、绑定、额度，再直接插入一笔企业订单
    session_factory = create_session_factory(engine)
    with session_factory() as session:
        with session.begin():
            open_enterprise_card(
                session, enterprise_id=ids["enterprise_id"], card_no=mk("CARD"),
                enterprise_card_id=ids["card_id"],
            )
            ids["binding_id"] = bind_card_vehicle(
                session,
                enterprise_card_id=ids["card_id"],
                vehicle_id=ids["vehicle_id"],
                fleet_member_id=ids["fleet_member_id"],
            )
            set_enterprise_quota(
                session,
                fleet_member_id=ids["fleet_member_id"],
                quota_month=date(2026, 10, 1),
                quota_amount=500,
                enterprise_quota_id=ids["quota_id"],
            )
            ids["order_id"] = session.execute(
                text(
                    "INSERT INTO dbo.ChargingOrder "
                    "(order_type, user_id, gun_id, binding_id, enterprise_quota_id, "
                    " start_time, end_time, energy_kwh, status, gross_amount, "
                    " discount_amount, opening_station_id) "
                    "OUTPUT INSERTED.order_id "
                    "VALUES ('ENTERPRISE', :u, :g, :b, :q, :start, :end, 1.0, "
                    "        'PENDING_PAYMENT', 5.00, 0.00, :s)"
                ),
                {
                    "u": ids["user_id"], "g": ids["gun_id"],
                    "b": ids["binding_id"], "q": ids["quota_id"],
                    "start": datetime(2026, 10, 1, 9, 0, 0),
                    "end": datetime(2026, 10, 1, 10, 0, 0),
                    "s": ids["station_id"],
                },
            ).scalar_one()

            # 优惠活动 + 场站 + 等级 + 用户等级（供 is_promotion_applicable）
            session.execute(
                text(
                    "INSERT INTO dbo.Promotion "
                    "(promotion_id, promotion_name, promotion_type, face_value, min_spend, "
                    " issue_start_at, issue_end_at, valid_start_at, valid_end_at, "
                    " issue_quantity, member_level_scope, target_audience, redemption_rule, "
                    " status, reviewed_by, reviewed_at, review_result) "
                    "VALUES (:p, N'TST promo', 'GENERAL', 3, 5, "
                    "        :past, :future, :past, :future, 1, 'SPECIFIED', 'MEMBER', "
                    "        N'TST rule', 'ACTIVE', :reviewer, SYSDATETIME(), 'APPROVED')"
                ),
                {
                    "p": ids["promotion_id"],
                    "past": datetime.now() - timedelta(days=1),
                    "future": datetime.now() + timedelta(days=1),
                    "reviewer": ent_account_id,
                },
            )
            session.execute(
                text(
                    "INSERT INTO dbo.PromotionStation (promotion_id, station_id) "
                    "VALUES (:p, :s)"
                ),
                {"p": ids["promotion_id"], "s": ids["station_id"]},
            )
            session.execute(
                text(
                    "INSERT INTO dbo.PromotionMemberLevel (promotion_id, member_level_id) "
                    "VALUES (:p, 'L01')"
                ),
                {"p": ids["promotion_id"]},
            )
            session.execute(
                text(
                    "INSERT INTO dbo.UserMemberLevel (user_id, member_level_id) "
                    "VALUES (:u, 'L01')"
                ),
                {"u": ids["user_id"]},
            )

    yield ids

    with engine.begin() as conn:
        for stmt in (
            "DELETE FROM dbo.UserMemberLevel WHERE user_id = :u",
            "DELETE FROM dbo.PromotionMemberLevel WHERE promotion_id = :p",
            "DELETE FROM dbo.PromotionStation WHERE promotion_id = :p",
            "DELETE FROM dbo.Promotion WHERE promotion_id = :p",
            "DELETE FROM dbo.ChargingOrder WHERE order_id = :oid",
            "DELETE FROM dbo.EnterpriseQuota WHERE enterprise_quota_id = :q",
            "DELETE FROM dbo.EnterpriseCardBinding WHERE binding_id = :b",
            "DELETE FROM dbo.EnterpriseCard WHERE enterprise_card_id = :c",
            "DELETE FROM dbo.Vehicle WHERE vehicle_id = :v",
            "DELETE FROM dbo.FleetMember WHERE fleet_member_id = :m",
            "DELETE FROM dbo.ChargingGun WHERE gun_id = :g",
            "DELETE FROM dbo.ChargingPile WHERE pile_id = :p2",
            "DELETE FROM dbo.ChargingStation WHERE station_id = :s",
            "DELETE FROM dbo.Operator WHERE operator_id = :o",
            "DELETE FROM dbo.EnterpriseProfile WHERE enterprise_id = :e",
            "DELETE FROM dbo.UserProfile WHERE user_id = :u",
            "DELETE FROM dbo.SysAccount WHERE account_id IN (:ua, :ea)",
        ):
            conn.execute(
                text(stmt),
                {
                    "u": ids["user_id"], "p": ids["promotion_id"],
                    "oid": ids["order_id"], "q": ids["quota_id"],
                    "b": ids["binding_id"], "c": ids["card_id"],
                    "v": ids["vehicle_id"], "m": ids["fleet_member_id"],
                    "g": ids["gun_id"], "p2": ids["pile_id"],
                    "s": ids["station_id"], "o": ids["operator_id"],
                    "e": ids["enterprise_id"],
                    "ua": ids["user_account_id"], "ea": ids["ent_account_id"],
                },
            )


def test_settle_enterprise_order(enterprise_chain, session_factory):
    with session_factory() as session:
        session.begin()
        try:
            settle_enterprise_order(session, order_id=enterprise_chain["order_id"])
            paid = session.execute(
                text(
                    "SELECT status, paid_amount FROM dbo.ChargingOrder WHERE order_id = :o"
                ),
                {"o": enterprise_chain["order_id"]},
            ).mappings().first()
        finally:
            session.rollback()
    assert paid["status"] == "PAID"
    assert float(paid["paid_amount"]) == 5.00


def test_list_enterprise_orders_page(enterprise_chain, session_factory):
    with session_factory() as session:
        page = list_enterprise_orders_page(
            session, enterprise_id=enterprise_chain["enterprise_id"], size=200
        )
    assert page.total >= 1
    assert enterprise_chain["order_id"] in {r["order_id"] for r in page.items}


def test_is_promotion_applicable(enterprise_chain, session_factory):
    with session_factory() as session:
        assert is_promotion_applicable(
            session,
            promotion_id=enterprise_chain["promotion_id"],
            user_id=enterprise_chain["user_id"],
            station_id=enterprise_chain["station_id"],
        )
        assert not is_promotion_applicable(
            session,
            promotion_id=enterprise_chain["promotion_id"],
            user_id=enterprise_chain["user_id"],
            station_id="NONEXISTENT",
        )


def test_open_card_and_submit_application(enterprise_chain, session_factory):
    with session_factory() as session:
        session.begin()
        try:
            new_card = open_enterprise_card(
                session,
                enterprise_id=enterprise_chain["enterprise_id"],
                card_no="TST_EXTRA_" + uuid4().hex[:8],
            )
            assert new_card
            application_id = submit_service_application(
                session,
                enterprise_id=enterprise_chain["enterprise_id"],
                application_type="CORPORATE",
                request_details="test",
            )
            assert application_id > 0
        finally:
            session.rollback()


def test_submit_application_rejects_bad_type(enterprise_chain, session_factory):
    with session_factory() as session:
        with pytest.raises(InvalidApplicationType):
            submit_service_application(
                session,
                enterprise_id=enterprise_chain["enterprise_id"],
                application_type="BAD_TYPE",
                request_details="test",
            )

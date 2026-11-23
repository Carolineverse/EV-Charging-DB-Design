from sqlalchemy import text

from evplatform.services import filter_by_scope, paginate_alarms


DEMO_STATIONS = {"B_DEMO_ST01", "D_DEMO_ST02", "D_DEMO_ST03", "D_DEMO_ST04", "D_DEMO_ST05"}


def _account_id(session, username):
    return session.execute(text("SELECT account_id FROM dbo.SysAccount WHERE username = :name"),
                           {"name": username}).scalar_one()


def test_r01_can_see_all_stations(session_factory):
    with session_factory() as session:
        account_id = _account_id(session, "demo_admin_r01")
        expected = set(session.execute(text("SELECT station_id FROM dbo.ChargingStation")).scalars())
    assert DEMO_STATIONS <= expected
    assert filter_by_scope(account_id, "ALL", permission_code="STATION_VIEW") == expected


def test_r02_sees_only_assigned_stations(session_factory):
    with session_factory() as session:
        account_id = _account_id(session, "demo_engineer_r02")
        non_assignment = session.execute(text(
            "SELECT station_id FROM dbo.ChargingStation WHERE station_id = 'BLK_ST_01'"
        )).scalar_one()
    visible = filter_by_scope(account_id, "ASSIGNED", permission_code="ALARM_VIEW")
    assert DEMO_STATIONS <= visible
    assert non_assignment not in visible
    with session_factory() as session:
        expected_alarms = set(session.execute(text("""
            SELECT a.alarm_id FROM dbo.Alarm AS a
            JOIN dbo.ChargingPile AS p ON p.pile_id = a.pile_id
            JOIN dbo.StaffStationAssignment AS g ON g.station_id = p.station_id
            JOIN dbo.StaffProfile AS f ON f.staff_id = g.staff_id
            WHERE f.account_id = :account_id AND f.employment_status = 'ACTIVE'
              AND g.effective_from <= SYSDATETIME()
              AND (g.effective_to IS NULL OR g.effective_to > SYSDATETIME())
        """), {"account_id": account_id}).scalars())
    page = paginate_alarms(size=20, account_id=account_id)
    assert page
    assert [alarm.alarm_id for alarm in page] == sorted(expected_alarms)[:20]


def test_unauthorized_queries_return_empty(session_factory):
    with session_factory() as session:
        engineer = _account_id(session, "demo_engineer_r02")
        personal = _account_id(session, "B_DEMO_USER01")
        unassigned = _account_id(session, "BLK_STAFF_01")
    assert filter_by_scope(engineer, "ALL", permission_code="ALARM_VIEW") == set()
    assert filter_by_scope(unassigned, "ASSIGNED", permission_code="ALARM_VIEW") == set()
    assert filter_by_scope(personal, "PUBLIC", permission_code="ALARM_VIEW") == set()
    assert paginate_alarms(account_id=personal) == []
    assert paginate_alarms(account_id=unassigned) == []


def test_personal_enterprise_and_public_station_scopes(session_factory):
    with session_factory() as session:
        personal = _account_id(session, "BLK_USER_01")
        enterprise = _account_id(session, "BLK_ENT_01")
        public = set(session.execute(text("""
            SELECT station_id FROM dbo.ChargingStation WHERE status = 'OPERATING'
        """)).scalars())
    assert filter_by_scope(personal, "SELF", permission_code="ORDER_VIEW") == set()
    assert filter_by_scope(enterprise, "ENTERPRISE", permission_code="FLEET_ORDER_VIEW") == {"BLK_ST_01"}
    assert filter_by_scope(personal, "PUBLIC", permission_code="STATION_VIEW") == public

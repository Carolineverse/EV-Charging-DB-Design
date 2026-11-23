"""Integration regressions for settlement transaction boundaries on EV_B_TEST."""

from concurrent.futures import ThreadPoolExecutor
import re
from threading import Barrier
from uuid import uuid4

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError


GENERATE = text("EXEC dbo.usp_GenerateSettlement :key, '202606', :agent, :agent")


@pytest.fixture
def settlement_case(engine):
    key = "TST_" + uuid4().hex[:16]
    # All identity keys are resolved from fixture-owned records.
    with engine.begin() as connection:
        assert connection.execute(text("SELECT DB_NAME()")).scalar_one() == "EV_B_TEST"
        for username, role in ((key + "_R01", "R01"), (key + "_R03", "R03"), (key + "_R04", "R04")):
            connection.execute(text("""
                INSERT dbo.SysAccount (username,password_hash,role_id)
                SELECT :username,'REPLACE_WITH_REAL_PASSWORD_HASH',role_id
                FROM dbo.SysRole WHERE role_code=:role
            """), {"username": username, "role": role})
        accounts = dict(connection.execute(text("""
            SELECT username,account_id FROM dbo.SysAccount WHERE username IN (:admin,:agent,:user)
        """), {"admin": key + "_R01", "agent": key + "_R03", "user": key + "_R04"}).all())
        params = {"key": key, "admin": accounts[key + "_R01"], "agent": accounts[key + "_R03"],
                  "user": accounts[key + "_R04"]}
        connection.execute(text("""
            INSERT dbo.UserProfile (user_id,account_id,phone_ciphertext,phone_hash,real_name_status,registered_at,status)
            VALUES (:key,:user,0x00,CONVERT(CHAR(64),HASHBYTES('SHA2_256',:key),2),'UNVERIFIED','20260601','ACTIVE');
            INSERT dbo.Operator (operator_id,operator_name) VALUES (:key,N'Test operator');
            INSERT dbo.ChargingStation (station_id,station_name,address,longitude,latitude,operator_id,total_spaces,
                business_hours,parking_fee_standard,workorder_notice_account_id)
            VALUES (:key,N'Test station',N'Synthetic',0,0,:key,1,N'Always',N'Free',:admin);
            INSERT dbo.ChargingPile (pile_id,station_id,device_model,rated_power_kw,communication_protocol,
                commissioned_date,warranty_end_date,status)
            VALUES (:key,:key,N'Test',60,N'OCPP','20260101','20280101','IDLE');
            INSERT dbo.ChargingGun (gun_id,pile_id,gun_sequence,gun_type,interface_standard,max_output_power_kw,status)
            VALUES (:key,:key,1,'DC_FAST',N'Test',60,'IDLE');
            INSERT dbo.OperatorSettlementRate (station_id,platform_rate,effective_from,status)
            VALUES (:key,0.20,'20260601','ACTIVE');
        """), params)
        # Allocate below existing positive rule IDs. A transaction-held table lock
        # serializes allocation even if two test fixtures are initialized together.
        version = connection.execute(text("""
            SELECT COALESCE(MIN(CASE WHEN rule_version_id < 0 THEN rule_version_id END),0)-1
            FROM dbo.BillingRuleVersion WITH (TABLOCKX,HOLDLOCK)
        """)).scalar_one()
        params["version"] = version
        connection.execute(text("""
            INSERT dbo.BillingRuleVersion (rule_version_id,station_id,free_minutes,minimum_amount,effective_from,status)
            VALUES (:version,:key,0,5,'20260601','ACTIVE')
        """), params)
        rule = connection.execute(text("""
            INSERT dbo.BillingRule (rule_version_id,period_type,period_start_time,period_end_time,electricity_price,service_price)
            OUTPUT inserted.billing_rule_id
            VALUES (:version,N'平','00:00:00','23:59:00',2,1)
        """), params).scalar_one()
        order = connection.execute(text("""
            INSERT dbo.ChargingOrder (user_id,gun_id,start_time,end_time,energy_kwh,status,gross_amount,
                minimum_adjustment,paid_amount,opening_station_id,settled_at,startup_rule_version_id,priced_at,
                device_released_at,created_at)
            OUTPUT inserted.order_id
            VALUES (:key,:key,'2026-06-10T09:00:00','2026-06-10T10:00:00',1,'PAID',5,2,5,:key,
                '2026-06-10T10:00:05',:version,'2026-06-10T10:00:04','2026-06-10T10:00:03','2026-06-10T08:59:59.123')
        """), params).scalar_one()
        params.update(order=order, rule=rule)
        connection.execute(text("""
            INSERT dbo.OrderFeeDetail (order_id,billing_rule_id,segment_start,segment_end,segment_energy_kwh,free_service_fee)
            VALUES (:order,:rule,'2026-06-10T09:00:00','2026-06-10T10:00:00',1,0);
            INSERT dbo.PaymentRecord (order_id,pay_channel,transaction_no,pay_amount,pay_time)
            VALUES (:order,'OTHER',:key,5,'2026-06-10T10:00:05');
        """), params)
        assert connection.execute(text("""
            SELECT is_settleable FROM dbo.v_OrderSettlementSource WHERE order_id=:order
        """), params).scalar_one()

    try:
        yield params
    finally:
        with engine.begin() as connection:
            # The production audit trigger blocks even targeted deletes. Restore
            # its definition/state inside the same transaction as this cleanup.
            predicate = """
                actor_account_id=:agent AND module_code='D' AND object_type='SETTLEMENT'
                AND action_code='GENERATE_SETTLEMENT'
                AND object_id IN (SELECT CONVERT(VARCHAR(50),settlement_id)
                                  FROM dbo.SettlementStatement WHERE station_id=:key)
            """
            log_count = connection.execute(
                text("SELECT COUNT(*) FROM dbo.OperationLog WHERE " + predicate), params
            ).scalar_one()
            if log_count:
                trigger_disabled = connection.execute(text("""
                    SELECT is_disabled FROM sys.triggers
                    WHERE object_id=OBJECT_ID(N'dbo.trg_OperationLog_Protect', N'TR')
                      AND parent_id=OBJECT_ID(N'dbo.OperationLog', N'U')
                """)).scalar_one()
                assert not trigger_disabled, "EV_B_TEST audit trigger must be enabled before cleanup"
                connection.execute(text("DISABLE TRIGGER dbo.trg_OperationLog_Protect ON dbo.OperationLog"))
                connection.execute(text("DELETE dbo.OperationLog WHERE " + predicate), params)
                connection.execute(text("ENABLE TRIGGER dbo.trg_OperationLog_Protect ON dbo.OperationLog"))
            connection.execute(text("""
                DELETE dbo.SettlementDetail WHERE order_id=:order;
                DELETE dbo.SettlementStatement WHERE station_id=:key;
                DELETE dbo.ServiceCaseAssignment WHERE case_type='SETTLEMENT_GENERATE' AND case_id=:key+'|202606';
                DELETE dbo.PaymentRecord WHERE order_id=:order;
                DELETE dbo.OrderFeeDetail WHERE order_id=:order;
                DELETE dbo.ChargingOrder WHERE order_id=:order AND user_id=:key;
                DELETE dbo.BillingRule WHERE billing_rule_id=:rule;
                DELETE dbo.BillingRuleVersion WHERE rule_version_id=:version AND station_id=:key;
                DELETE dbo.OperatorSettlementRate WHERE station_id=:key;
                DELETE dbo.ChargingGun WHERE gun_id=:key;
                DELETE dbo.ChargingPile WHERE pile_id=:key;
                DELETE dbo.ChargingStation WHERE station_id=:key;
                DELETE dbo.Operator WHERE operator_id=:key;
                DELETE dbo.UserProfile WHERE user_id=:key;
                DELETE dbo.SysAccount WHERE account_id IN (:admin,:agent,:user);
            """), params)


def _assign(engine, case):
    with engine.begin() as connection:
        connection.execute(text("""
            INSERT dbo.ServiceCaseAssignment (case_type,case_id,assigned_account_id,assigned_by,effective_from)
            VALUES ('SETTLEMENT_GENERATE',:key+'|202606',:agent,:admin,'20260601')
        """), case)


def _generate(connection, case):
    return connection.execute(GENERATE, case).scalar_one()


def _assert_empty(engine, case):
    with engine.connect() as connection:
        assert connection.execute(text("""
            SELECT COUNT(*) FROM dbo.SettlementStatement WHERE station_id=:key AND period_month='202606'
        """), case).scalar_one() == 0
        assert connection.execute(text("""
            SELECT COUNT(*) FROM dbo.SettlementDetail WHERE order_id=:order
        """), case).scalar_one() == 0


def test_generation_rejects_unassigned_station_without_writes(engine, settlement_case):
    with engine.connect().execution_options(isolation_level="AUTOCOMMIT") as connection:
        with pytest.raises(DBAPIError, match=r"\b50014\b"):
            _generate(connection, settlement_case)
    _assert_empty(engine, settlement_case)


def test_generation_rolls_back_header_and_detail_after_insert(engine, settlement_case):
    _assign(engine, settlement_case)
    trigger = settlement_case["key"] + "_FAIL_DETAIL"
    order_id = int(settlement_case["order"])
    with engine.begin() as connection:
        connection.exec_driver_sql(f"""
            CREATE TRIGGER dbo.[{trigger}] ON dbo.SettlementDetail
            AFTER INSERT AS
            BEGIN
                SET NOCOUNT ON;
                IF EXISTS (SELECT 1 FROM inserted WHERE order_id={order_id})
                    THROW 59999, N'Test-only failure after settlement detail insert', 1;
            END;
        """)
    try:
        with engine.connect().execution_options(isolation_level="AUTOCOMMIT") as connection:
            with pytest.raises(DBAPIError, match=r"\b59999\b"):
                _generate(connection, settlement_case)
        _assert_empty(engine, settlement_case)
    finally:
        with engine.begin() as connection:
            connection.exec_driver_sql(f"DROP TRIGGER IF EXISTS dbo.[{trigger}]")


def test_concurrent_generation_commits_exactly_one_settlement(engine, settlement_case):
    _assign(engine, settlement_case)
    barrier = Barrier(2, timeout=15)

    def attempt():
        with engine.connect().execution_options(isolation_level="AUTOCOMMIT") as connection:
            barrier.wait()
            try:
                return _generate(connection, settlement_case), None
            except DBAPIError as error:
                if not re.search(r"\b50011\b", str(error)):
                    raise
                return None, 50011

    with ThreadPoolExecutor(max_workers=2) as workers:
        attempts = [workers.submit(attempt) for _ in range(2)]
        outcomes = [attempt.result(timeout=45) for attempt in attempts]
    winners = [statement for statement, error in outcomes if error is None]
    assert len(winners) == 1 and outcomes.count((None, 50011)) == 1
    with engine.connect() as connection:
        statement = connection.execute(text("""
            SELECT settlement_id FROM dbo.SettlementStatement WHERE station_id=:key AND period_month='202606'
        """), settlement_case).scalar_one()
        assert statement == winners[0]
        details = connection.execute(text("""
            SELECT settlement_id,order_id FROM dbo.SettlementDetail
            WHERE settlement_id=:statement OR order_id=:order
        """), {"statement": statement, "order": settlement_case["order"]}).all()
    assert details == [(statement, settlement_case["order"])]


class _RollbackSupplement(Exception):
    pass


def test_supplement_detail_adds_eligible_source_and_audit_atomically(engine, settlement_case):
    with engine.begin() as connection:
        settlement_id = connection.execute(text("""
            INSERT dbo.SettlementStatement
                (station_id,period_month,platform_rate,status,assigned_account_id,created_by)
            OUTPUT INSERTED.settlement_id
            VALUES (:key,'202606',0.200000,0,:agent,:agent)
        """), settlement_case).scalar_one()

    with pytest.raises(_RollbackSupplement):
        with engine.begin() as connection:
            connection.exec_driver_sql("BEGIN TRANSACTION")
            connection.execute(text("""
                EXEC dbo.usp_SupplementDetail :settlement_id,:order,:agent
            """), {**settlement_case, "settlement_id": settlement_id})
            assert connection.execute(text("""
                SELECT COUNT(*) FROM dbo.SettlementDetail
                WHERE settlement_id=:settlement_id AND order_id=:order
            """), {**settlement_case, "settlement_id": settlement_id}).scalar_one() == 1
            assert connection.execute(text("""
                SELECT COUNT(*) FROM dbo.OperationLog
                WHERE module_code='D' AND action_code='SUPPLEMENT_DETAIL'
                  AND object_id=CONVERT(VARCHAR(50),:settlement_id)
            """), {"settlement_id": settlement_id}).scalar_one() == 1
            connection.exec_driver_sql("ROLLBACK TRANSACTION")
            raise _RollbackSupplement()

    with engine.connect() as connection:
        assert connection.execute(text("""
            SELECT COUNT(*) FROM dbo.SettlementStatement WHERE settlement_id=:settlement_id
        """), {"settlement_id": settlement_id}).scalar_one() == 1
        assert connection.execute(text("""
            SELECT COUNT(*) FROM dbo.SettlementDetail WHERE settlement_id=:settlement_id
        """), {"settlement_id": settlement_id}).scalar_one() == 0
        assert connection.execute(text("""
            SELECT COUNT(*) FROM dbo.OperationLog
            WHERE module_code='D' AND action_code='SUPPLEMENT_DETAIL'
              AND object_id=CONVERT(VARCHAR(50),:settlement_id)
        """), {"settlement_id": settlement_id}).scalar_one() == 0

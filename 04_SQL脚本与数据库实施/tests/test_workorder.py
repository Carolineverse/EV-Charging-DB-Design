from sqlalchemy import text
from evplatform.db import SessionLocal
from evplatform.services import dispatch_workorder

def test_dispatch_creates_workorder_and_updates_alarm():
    with SessionLocal() as s:
        # 造一条告警
        aid = s.execute(text(
            "INSERT INTO dbo.Alarm (pile_id, alarm_code, alarm_level, alarm_description, alarm_source, occurred_at, status) "
            "OUTPUT inserted.alarm_id "
            "VALUES ('PILE-001','AL001',2,N'测试告警','MANUAL_ENTRY',SYSDATETIME(),'PENDING')"
        )).scalar_one()
        s.commit()
    try:
        dispatch_workorder(aid, "STF-DEMO-R02", None)
        with SessionLocal() as s:
            st = s.execute(text("SELECT status FROM dbo.Alarm WHERE alarm_id=:a"), {"a": aid}).scalar_one()
            wn = s.execute(text("SELECT COUNT(*) FROM dbo.WorkOrder WHERE alarm_id=:a"), {"a": aid}).scalar_one()
        assert st == "PROCESSING"
        assert wn == 1
    finally:
        with SessionLocal() as s:
            s.execute(text("DELETE FROM dbo.WorkOrder WHERE alarm_id=:a"), {"a": aid})
            s.execute(text("DELETE FROM dbo.Alarm WHERE alarm_id=:a"), {"a": aid})
            s.commit()

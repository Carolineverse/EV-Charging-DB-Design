"""Validate the alarm and work order already created by the integration seed."""

from datetime import timedelta

from sqlalchemy import text

from evplatform.db import SessionLocal


def test_seeded_workorder_progress():
    with SessionLocal() as session:
        work = session.execute(text("""
            SELECT p.station_id, w.engineer_staff_id, w.dispatcher_staff_id, a.occurred_at,
                   progress.alarm_code, progress.alarm_status, progress.workorder_status,
                   progress.assigned_at, progress.accept_deadline
            FROM dbo.Alarm a
            JOIN dbo.ChargingPile p ON p.pile_id = a.pile_id
            JOIN dbo.WorkOrder w ON w.alarm_id = a.alarm_id
            JOIN dbo.v_WorkOrderProgress progress ON progress.work_order_id = w.work_order_id
            WHERE a.pile_id = :pile AND a.alarm_description = :description
        """), {"pile": "B_DEMO_PILE01", "description": "演示告警 1"}).mappings().one()

    assert work["station_id"] == "B_DEMO_ST01"
    assert work["engineer_staff_id"] == "STF-DEMO-R02"
    assert work["dispatcher_staff_id"] == "STF-DEMO-R01"
    assert work["alarm_code"] == "AL001"
    assert work["alarm_status"] == "PENDING"
    assert work["workorder_status"] == "PENDING_ARRIVAL"
    assert work["assigned_at"] == work["occurred_at"] + timedelta(minutes=10)
    assert work["accept_deadline"] == work["assigned_at"] + timedelta(minutes=30)

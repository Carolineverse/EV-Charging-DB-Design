"""Verify monitoring executemany against the installed SQL Server foreign key."""

from dataclasses import replace
from datetime import datetime, timedelta
from decimal import Decimal
from hashlib import sha256
from uuid import uuid4

import pytest
from sqlalchemy import bindparam, text
from sqlalchemy.exc import IntegrityError

from evplatform.monitoring import MonitoringSample, insert_monitoring_batch


@pytest.fixture
def monitoring_case(session_factory):
    token = "TST_MON_" + uuid4().hex
    owned_ids = (token + "_0", token + "_1")
    missing_id = token + "_MISSING"
    collected_at = datetime(2027, 1, 15, 9, 0, 0, 123000)

    with session_factory.begin() as session:
        assert session.execute(text("SELECT DB_NAME()")).scalar_one() == "EV_B_TEST"
        pile_id = session.execute(text("""
            SELECT pile_id FROM dbo.ChargingPile WHERE pile_id = 'B_DEMO_PILE01'
        """)).scalar_one()
        session.execute(
            text("""
                INSERT INTO dbo.DeviceReport
                    (report_id, pile_id, generated_at, received_at, payload_hash, report_type)
                VALUES
                    (:report_id, :pile_id, :collected_at, :collected_at, :payload_hash, 'MINUTE_MONITOR')
            """),
            [
                {
                    "report_id": report_id,
                    "pile_id": pile_id,
                    "collected_at": collected_at + timedelta(minutes=index),
                    "payload_hash": sha256(report_id.encode("ascii")).hexdigest(),
                }
                for index, report_id in enumerate(owned_ids)
            ],
        )
        assert session.execute(text("""
            SELECT COUNT(*) FROM dbo.DeviceReport WHERE report_id = :report_id
        """), {"report_id": missing_id}).scalar_one() == 0

    samples = [
        MonitoringSample(
            report_id=report_id,
            pile_id=pile_id,
            collected_at=collected_at + timedelta(minutes=index),
            output_voltage=Decimal("220.25") if index == 0 else None,
            output_current=Decimal("32.50"),
        )
        for index, report_id in enumerate(owned_ids)
    ]
    try:
        yield samples, missing_id
    finally:
        with session_factory.begin() as session:
            session.execute(text("""
                DELETE FROM dbo.DeviceMonitoringData WHERE report_id IN :report_ids
            """).bindparams(bindparam("report_ids", expanding=True)),
                {"report_ids": (*owned_ids, missing_id)},
            )
            session.execute(text("""
                DELETE FROM dbo.DeviceReport WHERE report_id IN :report_ids
            """).bindparams(bindparam("report_ids", expanding=True)), {"report_ids": owned_ids})


def _read_samples(session_factory, report_ids):
    with session_factory() as session:
        return session.execute(text("""
            SELECT report_id, pile_id, collected_at, output_voltage, output_current
            FROM dbo.DeviceMonitoringData WHERE report_id IN :report_ids
        """).bindparams(bindparam("report_ids", expanding=True)), {"report_ids": report_ids}).all()


def test_monitoring_batch_commits_multiple_samples(session_factory, monitoring_case):
    samples, _ = monitoring_case
    insert_monitoring_batch(samples)

    rows = _read_samples(session_factory, [sample.report_id for sample in samples])
    assert len(rows) == len(samples)
    results = {row.report_id: row for row in rows}
    for sample in samples:
        row = results[sample.report_id]
        assert row.pile_id == sample.pile_id
        assert row.collected_at == sample.collected_at
        assert row.output_voltage == sample.output_voltage
        assert row.output_current == sample.output_current


def test_monitoring_batch_rolls_back_on_missing_report(session_factory, monitoring_case):
    samples, missing_id = monitoring_case
    invalid = replace(samples[1], report_id=missing_id)
    batch = [samples[0], invalid, samples[1]]

    with pytest.raises(IntegrityError, match=r"FK_DeviceMonitoringData_report") as error:
        insert_monitoring_batch(batch)

    assert "(547)" in str(error.value.orig)
    assert _read_samples(session_factory, [sample.report_id for sample in batch]) == []

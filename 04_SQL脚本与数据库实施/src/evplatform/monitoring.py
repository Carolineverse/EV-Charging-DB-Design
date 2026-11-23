"""Atomic persistence for batches of device monitoring samples."""

from dataclasses import asdict, dataclass
from datetime import datetime
from decimal import Decimal
from typing import Iterable, Optional

from sqlalchemy import text

from evplatform.db import SessionLocal


@dataclass(frozen=True)
class MonitoringSample:
    pile_id: str
    collected_at: datetime
    report_id: Optional[str] = None
    gun_id: Optional[str] = None
    output_voltage: Optional[Decimal] = None
    output_current: Optional[Decimal] = None
    power: Optional[Decimal] = None
    module_temperature: Optional[Decimal] = None
    offline_duration_seconds: Optional[int] = None
    raw_fault_code: Optional[str] = None


_INSERT_SAMPLE = text("""
    INSERT INTO dbo.DeviceMonitoringData (
        report_id, pile_id, gun_id, collected_at, output_voltage, output_current,
        power, module_temperature, offline_duration_seconds, raw_fault_code
    ) VALUES (
        :report_id, :pile_id, :gun_id, :collected_at, :output_voltage, :output_current,
        :power, :module_temperature, :offline_duration_seconds, :raw_fault_code
    )
""")


def insert_monitoring_batch(samples: Iterable[MonitoringSample]) -> None:
    """Insert a batch in its own transaction; propagate errors after rollback."""
    parameters = [asdict(sample) for sample in samples]
    if not parameters:
        return

    with SessionLocal.begin() as session:
        session.execute(_INSERT_SAMPLE, parameters)

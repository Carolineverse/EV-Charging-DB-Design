"""A1 场站与充电设施业务的持久层操作。

覆盖任务书 2.1.1 的核心动作：设备状态变更（并写历史）与场站分页查询。
设备状态变更复用数据库存储过程 ``usp_A1_UpdateDeviceStatus``，保证“状态与
历史原子写入”在数据库层仍由单一入口实现。
"""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

VALID_DEVICE_STATUSES = ("UNKNOWN", "IDLE", "OCCUPIED", "FAULT", "OFFLINE")
VALID_CHANGE_SOURCES = (
    "DEVICE_REPORT",
    "HEARTBEAT_CHECK",
    "DEVICE_MONITOR",
    "CHARGING_ORDER",
    "REPAIR_REVIEW",
    "MANUAL",
    "SYSTEM_RULE",
)


class DeviceStatusError(Exception):
    """设备状态操作的基类异常。"""


def update_device_status(
    session: Session,
    *,
    pile_id: Optional[str] = None,
    gun_id: Optional[str] = None,
    new_status: str,
    change_source: str,
    change_reason: str,
    changed_at: Optional[datetime] = None,
) -> dict:
    """变更充电桩或充电枪的状态，并写入状态历史。

    复用 ``dbo.usp_A1_UpdateDeviceStatus``：过程内使用行锁（UPDLOCK/HOLDLOCK）
    读取旧状态、原子更新当前状态并写 ``DeviceStatusHistory``；状态未变化时
    返回 ``NO_CHANGE`` 且不写历史。

    ``pile_id`` 与 ``gun_id`` 必须二选一（恰好一个非空）。
    """
    if (pile_id is None) == (gun_id is None):
        raise ValueError("Specify exactly one of pile_id or gun_id.")
    if new_status not in VALID_DEVICE_STATUSES:
        raise ValueError(f"new_status must be one of {VALID_DEVICE_STATUSES}.")
    if change_source not in VALID_CHANGE_SOURCES:
        raise ValueError(f"change_source must be one of {VALID_CHANGE_SOURCES}.")
    if not change_reason or not change_reason.strip():
        raise ValueError("change_reason must be non-empty.")

    row = session.execute(
        text(
            """
            EXEC dbo.usp_A1_UpdateDeviceStatus
                @pile_id = :pile_id,
                @gun_id = :gun_id,
                @new_status = :new_status,
                @change_reason = :change_reason,
                @change_source = :change_source,
                @changed_at = :changed_at;
            """
        ),
        {
            "pile_id": pile_id,
            "gun_id": gun_id,
            "new_status": new_status,
            "change_reason": change_reason,
            "change_source": change_source,
            "changed_at": changed_at,
        },
    ).mappings().first()

    return {
        "result_code": row["result_code"],
        "old_status": row["old_status"],
        "new_status": row["new_status"],
        "history_id": None if row["history_id"] is None else int(row["history_id"]),
    }


class StationPage:
    """场站分页结果。"""

    def __init__(self, items, page, size, total):
        self.items = items
        self.page = page
        self.size = size
        self.total = total


def list_stations_page(
    session: Session,
    *,
    operator_id: Optional[str] = None,
    status: Optional[str] = None,
    page: int = 1,
    size: int = 20,
) -> StationPage:
    """按场站编号稳定排序分页查询场站，可按运营商与状态过滤。"""
    if page < 1:
        raise ValueError("page must be >= 1.")
    if size < 1 or size > 200:
        raise ValueError("size must be between 1 and 200.")

    filters = []
    params = {}
    if operator_id:
        filters.append("s.operator_id = :operator_id")
        params["operator_id"] = operator_id
    if status:
        filters.append("s.status = :status")
        params["status"] = status
    where = (" WHERE " + " AND ".join(filters)) if filters else ""

    total = session.execute(
        text(f"SELECT COUNT(*) FROM dbo.ChargingStation AS s{where}"), params
    ).scalar_one()

    rows = session.execute(
        text(
            f"""
            SELECT s.station_id, s.station_name, s.address, s.operator_id,
                   s.total_spaces, s.business_hours, s.status
            FROM dbo.ChargingStation AS s{where}
            ORDER BY s.station_id
            OFFSET :offset ROWS FETCH NEXT :size ROWS ONLY;
            """
        ),
        {**params, "offset": (page - 1) * size, "size": size},
    ).mappings().all()

    return StationPage(
        items=[dict(r) for r in rows],
        page=page,
        size=size,
        total=int(total),
    )

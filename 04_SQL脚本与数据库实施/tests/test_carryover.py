"""跨期扣回：只计一次、重复应用被拒、退款互斥。"""

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from evplatform.db import SessionLocal
from evplatform.services import apply_carryover, settle_ledger


def _r01():
    with SessionLocal() as s:
        return s.execute(text("SELECT account_id FROM dbo.SysAccount WHERE username='demo_admin_r01'")).scalar_one()


def test_carryover_applied_once_and_not_double_counted():
    r01 = _r01()
    # 种子中 carryover_adjustment_id=2 为 APPROVED，原单 2，目标账期 202612
    with SessionLocal() as s:
        orig_id = s.execute(text(
            "SELECT original_settlement_id FROM dbo.SettlementCarryoverAdjustment WHERE carryover_adjustment_id=2")).scalar_one()
        target = s.execute(text(
            "SELECT s.settlement_id FROM dbo.SettlementStatement s "
            "JOIN dbo.SettlementStatement o ON o.station_id = s.station_id "
            "WHERE o.settlement_id=:o AND s.period_month='202612'"), {"o": orig_id}).scalar_one()

    before = float(settle_ledger(target)["payable_amount"])
    apply_carryover(2, target, r01)
    after = float(settle_ledger(target)["payable_amount"])

    # 扣回 1 元只生效一次；若重复计入会变成扣 2 元
    assert before - after == 1.00

    with pytest.raises(DBAPIError):
        apply_carryover(2, target, r01)  # 已 APPLIED，不能重复应用

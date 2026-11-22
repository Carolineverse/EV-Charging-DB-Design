import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from evplatform.db import SessionLocal
from evplatform.services import generate_settlement, settle_ledger


def _settle_accounts():
    with SessionLocal() as s:
        r03 = s.execute(text("SELECT account_id FROM dbo.SysAccount WHERE username='demo_settlement_r03'")).scalar_one()
    return r03


def _cleanup():
    """删除 ST-001|202611 的结算单及其从表，保证测试可重复运行。"""
    with SessionLocal() as s:
        sid = s.execute(text(
            "SELECT settlement_id FROM dbo.SettlementStatement WHERE station_id='ST-001' AND period_month='202611'"
        )).scalar_one_or_none()
        if not sid:
            s.commit()
            return
        s.execute(text("DELETE FROM dbo.ReconciliationDifference WHERE settlement_id=:s"), {"s": sid})
        s.execute(text("DELETE FROM dbo.SettlementInvoice WHERE settlement_id=:s"), {"s": sid})
        s.execute(text("DELETE FROM dbo.SettlementCarryoverAdjustment WHERE original_settlement_id=:s OR target_settlement_id=:s"), {"s": sid})
        s.execute(text("DELETE FROM dbo.SettlementDetail WHERE settlement_id=:s"), {"s": sid})
        s.execute(text("DELETE FROM dbo.SettlementStatement WHERE settlement_id=:s"), {"s": sid})
        s.commit()


def test_generate_settlement_once_then_reject_duplicate():
    r03 = _settle_accounts()
    _cleanup()

    sid = generate_settlement("ST-001", "202611", r03, r03)
    assert sid > 0

    with pytest.raises(DBAPIError) as ei:
        generate_settlement("ST-001", "202611", r03, r03)
    assert "50011" in str(ei.value) or "已生成结算单" in str(ei.value)

    # 金额核对：ST-001 在 202611 有 2 笔订单，E=2/S=1/A=2、费率 20% → 每单应结 4.40，合计 8.80
    ledger = settle_ledger(sid)
    assert float(ledger["payable_amount"]) == 8.80

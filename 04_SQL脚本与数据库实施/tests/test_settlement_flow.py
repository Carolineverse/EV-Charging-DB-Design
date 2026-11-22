"""结算完整链路：生成 → 差异登记与关闭 → 终审 → 开票 → 红冲申请/审批。"""

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from evplatform.db import SessionLocal
from evplatform.services import (generate_settlement, register_difference, close_difference,
                                 confirm_settlement, register_invoice, apply_red_flush,
                                 approve_red_flush, settle_ledger)


def _ids():
    with SessionLocal() as s:
        r03 = s.execute(text("SELECT account_id FROM dbo.SysAccount WHERE username='demo_settlement_r03'")).scalar_one()
        r01 = s.execute(text("SELECT account_id FROM dbo.SysAccount WHERE username='demo_admin_r01'")).scalar_one()
    return r03, r01


def _cleanup():
    with SessionLocal() as s:
        sid = s.execute(text(
            "SELECT settlement_id FROM dbo.SettlementStatement WHERE station_id='ST-001' AND period_month='202611'"
        )).scalar_one_or_none()
        if sid:
            s.execute(text("DELETE FROM dbo.ReconciliationDifference WHERE settlement_id=:s"), {"s": sid})
            s.execute(text("DELETE FROM dbo.SettlementInvoice WHERE settlement_id=:s"), {"s": sid})
            s.execute(text("DELETE FROM dbo.SettlementCarryoverAdjustment WHERE original_settlement_id=:s OR target_settlement_id=:s"), {"s": sid})
            s.execute(text("DELETE FROM dbo.SettlementDetail WHERE settlement_id=:s"), {"s": sid})
            s.execute(text("DELETE FROM dbo.SettlementStatement WHERE settlement_id=:s"), {"s": sid})
            s.commit()


def test_full_settlement_flow():
    r03, r01 = _ids()
    _cleanup()

    sid = generate_settlement("ST-001", "202611", r03, r03)
    with SessionLocal() as s:
        oid = s.execute(text("SELECT MIN(order_id) FROM dbo.SettlementDetail WHERE settlement_id=:s"), {"s": sid}).scalar_one()

    # 1) 登记差异 + R01 审批关闭（调减 1 元）
    register_difference(sid, oid, 2, -1.00, r03)
    with SessionLocal() as s:
        did = s.execute(text("SELECT MAX(difference_id) FROM dbo.ReconciliationDifference WHERE settlement_id=:s"), {"s": sid}).scalar_one()
    close_difference(did, r01, '运营商确认调减1元', '价格不符，调减1元')

    # 2) 终审锁定
    confirm_settlement(sid, r01, '运营商已确认')

    # 3) 开票：先部分开票 3.80（剩 4.00），再尝试超额 5.00，应触发 50055 余额校验
    ledger = settle_ledger(sid)
    assert float(ledger["payable_amount"]) == 7.80
    register_invoice(sid, 'INV-TEST-01', '平台单位', '91110000MA0000000X', 3.80, r03)
    with pytest.raises(DBAPIError) as ei:
        register_invoice(sid, 'INV-TEST-02', '平台单位', '91110000MA0000000X', 5.00, r03)
    assert '50055' in str(ei.value) or '超出可开票余额' in str(ei.value)

    # 4) 红冲：专员申请（status=0）→ R01 审批（status=-1，写红票号）
    with SessionLocal() as s:
        iid = s.execute(text("SELECT MAX(invoice_id) FROM dbo.SettlementInvoice WHERE settlement_id=:s AND status=1"), {"s": sid}).scalar_one()
        original_amount = s.execute(text("SELECT amount FROM dbo.SettlementInvoice WHERE invoice_id=:i"), {"i": iid}).scalar_one()

    apply_red_flush(iid, '票面金额有误，整张红冲', r03)
    with SessionLocal() as s:
        red_id = s.execute(text(
            "SELECT MAX(invoice_id) FROM dbo.SettlementInvoice WHERE original_invoice_id=:i AND status=0"), {"i": iid}).scalar_one()

    approve_red_flush(red_id, 'RED-2026-0001', r01)

    with SessionLocal() as s:
        red = s.execute(text(
            "SELECT amount, status, invoice_no FROM dbo.SettlementInvoice WHERE invoice_id=:r"), {"r": red_id}).one()
    assert red[1] == -1
    assert float(red[0]) == -float(original_amount)
    assert red[2] == 'RED-2026-0001'

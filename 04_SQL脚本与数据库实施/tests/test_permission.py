from sqlalchemy import text
from evplatform.db import SessionLocal

def test_five_roles_seeded():
    with SessionLocal() as s:
        n = s.execute(text("SELECT COUNT(*) FROM dbo.SysRole")).scalar_one()
    assert n == 5

def test_admin_account_exists():
    with SessionLocal() as s:
        n = s.execute(text("SELECT COUNT(*) FROM dbo.SysAccount WHERE username='demo_admin_r01'")).scalar_one()
    assert n == 1

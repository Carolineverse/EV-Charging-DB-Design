from sqlalchemy import text
from evplatform.db import SessionLocal

def test_connection_uses_test_db():
    with SessionLocal() as s:
        db = s.execute(text("SELECT DB_NAME()")).scalar_one()
    assert db in {"EV_D_TEST", "EV_B_TEST", "EV_INTEGRATION_TEST"}

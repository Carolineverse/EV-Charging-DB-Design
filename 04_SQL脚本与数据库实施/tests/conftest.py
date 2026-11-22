import pytest
from sqlalchemy import text
from evplatform.db import SessionLocal

@pytest.fixture(autouse=True)
def guard_test_db():
    with SessionLocal() as session:
        database = session.execute(text("SELECT DB_NAME()")).scalar_one()
    if database not in {"EV_D_TEST", "EV_B_TEST", "EV_INTEGRATION_TEST"}:
        pytest.fail(f"仅允许在课设测试库运行，当前连接到 {database}")

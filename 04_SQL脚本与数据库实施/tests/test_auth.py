from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import text

from evplatform.auth import (
    AccountLocked, InvalidCredentials, generate_salt, hash_password, login,
    session_expired, set_password, verify_password,
)


PASSWORD = "TST-auth-password"


@pytest.fixture(autouse=True)
def guard_test_db():
    """Database cases use the guarded session_factory; pure cases need no database."""


@pytest.fixture
def account(session_factory):
    username = f"TST_AUTH_{uuid4().hex}"
    with session_factory.begin() as session:
        account_id = session.execute(text("""
            INSERT INTO dbo.SysAccount (username, password_hash, role_id)
            OUTPUT inserted.account_id
            SELECT :username, 'TST_PENDING', role_id FROM dbo.SysRole WHERE role_code = 'R04'
        """), {"username": username}).scalar_one()
        set_password(session, account_id, PASSWORD)
    try:
        yield username, account_id
    finally:
        with session_factory.begin() as session:
            session.execute(text("DELETE FROM dbo.SysAccount WHERE account_id = :id AND username = :name"),
                            {"id": account_id, "name": username})


def _account_state(session_factory, account_id):
    with session_factory() as session:
        return session.execute(text("""
            SELECT status, failed_login_count, last_login_at
            FROM dbo.SysAccount WHERE account_id = :id
        """), {"id": account_id}).one()


def test_correct_password_login(account, session_factory):
    username, account_id = account
    with session_factory() as session:
        assert login(session, username, PASSWORD) == account_id
    state = _account_state(session_factory, account_id)
    assert state.status == 1
    assert state.failed_login_count == 0
    assert state.last_login_at is not None


def test_bad_password_increments_failure_count(account, session_factory):
    username, account_id = account
    with session_factory() as session:
        with pytest.raises(InvalidCredentials) as error:
            login(session, username, "wrong")
        assert type(error.value) is InvalidCredentials
    state = _account_state(session_factory, account_id)
    assert (state.status, state.failed_login_count, state.last_login_at) == (1, 1, None)


def test_fifth_failure_locks_account(account, session_factory):
    username, account_id = account
    for attempts in range(1, 6):
        with session_factory() as session:
            expected = AccountLocked if attempts == 5 else InvalidCredentials
            with pytest.raises(expected) as error:
                login(session, username, "wrong")
            assert type(error.value) is expected
        state = _account_state(session_factory, account_id)
        assert (state.status, state.failed_login_count) == (int(attempts < 5), attempts)
    with session_factory() as session:
        with pytest.raises(AccountLocked):
            login(session, username, PASSWORD)
    assert _account_state(session_factory, account_id).failed_login_count == 5


def test_success_resets_failure_count(account, session_factory):
    username, account_id = account
    with session_factory() as session:
        with pytest.raises(InvalidCredentials):
            login(session, username, "wrong")
        assert login(session, username, PASSWORD) == account_id
    state = _account_state(session_factory, account_id)
    assert state.failed_login_count == 0
    assert state.last_login_at is not None


def test_session_timeout():
    now = datetime.now(timezone.utc)
    assert not session_expired(now - timedelta(minutes=29))
    assert session_expired(now - timedelta(minutes=30))
    assert session_expired(now - timedelta(minutes=10), timeout_minutes=5)
    assert session_expired(None)


def test_password_hash_format_and_verification():
    salt = generate_salt()
    stored = hash_password(PASSWORD, salt)
    assert len(salt) == 16
    assert stored.split("$")[:3] == ["pbkdf2_sha256", "100000", salt.hex()]
    assert len(stored.split("$")[-1]) == 64
    assert verify_password(PASSWORD, stored)
    assert not verify_password("wrong", stored)
    assert not verify_password(PASSWORD, "REPLACE_WITH_REAL_PASSWORD_HASH")

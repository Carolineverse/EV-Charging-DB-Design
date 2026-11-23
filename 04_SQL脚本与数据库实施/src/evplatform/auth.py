"""Password authentication for the existing SysAccount schema."""

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy import text


_ITERATIONS = 100_000
_SALT_BYTES = 16
_MAX_FAILURES = 5
_PREFIX = f"pbkdf2_sha256${_ITERATIONS}"
_DUMMY_HASH = f"{_PREFIX}${'00' * _SALT_BYTES}${'00' * 32}"


class InvalidCredentials(Exception):
    """The username or password was rejected."""


class AccountLocked(InvalidCredentials):
    """The account is locked after repeated authentication failures."""


def generate_salt() -> bytes:
    return secrets.token_bytes(_SALT_BYTES)


def hash_password(password: str, salt: bytes) -> str:
    if len(salt) != _SALT_BYTES:
        raise ValueError("PBKDF2 requires a 16-byte salt")
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _ITERATIONS)
    return f"{_PREFIX}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    parts = (stored or "").split("$")
    if len(parts) != 4:
        return False
    algorithm, iterations, salt_hex, digest_hex = parts
    if (algorithm != "pbkdf2_sha256" or iterations != str(_ITERATIONS)
            or len(salt_hex) != 2 * _SALT_BYTES or len(digest_hex) != 64):
        return False
    try:
        salt = bytes.fromhex(salt_hex)
        digest = bytes.fromhex(digest_hex)
    except ValueError:
        return False
    if len(salt) != _SALT_BYTES or len(digest) != 32:
        return False
    computed = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _ITERATIONS)
    return hmac.compare_digest(computed, digest)


def set_password(session, account_id: int, password: str) -> None:
    """Replace the hash in the caller's transaction, without unlocking the account."""
    if not password:
        raise ValueError("Password must not be empty")
    result = session.execute(
        text("""
            UPDATE dbo.SysAccount
            SET password_hash = :password_hash, updated_at = SYSDATETIME()
            OUTPUT inserted.account_id
            WHERE account_id = :account_id
        """),
        {"account_id": account_id, "password_hash": hash_password(password, generate_salt())},
    )
    if result.scalar_one_or_none() is None:
        raise LookupError("Account does not exist")


def login(session, username: str, password: str) -> int:
    """Authenticate in a dedicated transaction and commit failure counters before raising."""
    if session.in_transaction():
        raise ValueError("login requires a session without an active transaction")

    error = InvalidCredentials("Invalid username or password")
    with session.begin():
        account = session.execute(
            text("""
                SELECT a.account_id, a.password_hash, a.status, a.failed_login_count,
                       r.status AS role_status,
                       CASE WHEN a.locked_until > SYSDATETIME() THEN 1 ELSE 0 END AS temporarily_locked
                FROM dbo.SysAccount AS a WITH (UPDLOCK, HOLDLOCK)
                JOIN dbo.SysRole AS r ON r.role_id = a.role_id
                WHERE a.username = :username
            """),
            {"username": username},
        ).mappings().one_or_none()
        if account is None:
            verify_password(password, _DUMMY_HASH)
        elif account.temporarily_locked or (not account.status and account.failed_login_count >= _MAX_FAILURES):
            error = AccountLocked("Account is locked")
        elif account.status and account.role_status:
            params = {"account_id": account.account_id}
            if verify_password(password, account.password_hash):
                session.execute(text("""
                    UPDATE dbo.SysAccount
                    SET failed_login_count = 0, locked_until = NULL,
                        last_login_at = SYSDATETIME(), updated_at = SYSDATETIME()
                    WHERE account_id = :account_id
                """), params)
                return account.account_id

            failures = min(account.failed_login_count + 1, _MAX_FAILURES)
            session.execute(text("""
                UPDATE dbo.SysAccount
                SET failed_login_count = :failures,
                    status = CASE WHEN :failures >= :max_failures THEN 0 ELSE status END,
                    updated_at = SYSDATETIME()
                WHERE account_id = :account_id
            """), dict(params, failures=failures, max_failures=_MAX_FAILURES))
            if failures >= _MAX_FAILURES:
                error = AccountLocked("Account is locked")
    raise error


def session_expired(last_login_at: Optional[datetime], timeout_minutes: int = 30) -> bool:
    if timeout_minutes <= 0:
        raise ValueError("timeout_minutes must be positive")
    if last_login_at is None:
        return True
    now = datetime.now(last_login_at.tzinfo)
    return now >= last_login_at + timedelta(minutes=timeout_minutes)

import hashlib

import pytest
from sqlalchemy import text


@pytest.mark.parametrize("value", ["13800001234", "京A12345"])
def test_sensitive_encryption_round_trip(session_factory, value):
    with session_factory() as session:
        ciphertext, decrypted = session.execute(text("""
            DECLARE @cipher VARBINARY(256), @plain NVARCHAR(64);
            EXEC dbo.usp_EncryptSensitive :value, @cipher OUTPUT;
            EXEC dbo.usp_DecryptSensitive @cipher, @plain OUTPUT;
            SELECT @cipher, @plain;
        """), {"value": value}).one()
        assert 0 < len(ciphertext) <= 256
        assert bytes(ciphertext) != value.encode("utf-16le")
        assert decrypted == value
        assert session.execute(text("""
            SELECT COUNT(*) FROM sys.openkeys WHERE key_name = N'Key_EV_Sensitive'
        """)).scalar_one() == 0


def test_seeded_phone_hash_matches_plaintext(session_factory):
    phone = "13800001234"
    lookup_hash = hashlib.sha256(phone.encode("utf-16le")).hexdigest().upper()
    with session_factory() as session:
        user_id, decrypted = session.execute(text("""
            DECLARE @cipher VARBINARY(256), @phone NVARCHAR(64), @id VARCHAR(20);
            SELECT @id = user_id, @cipher = phone_ciphertext
            FROM dbo.UserProfile
            WHERE phone_hash = :lookup_hash AND user_id = 'B_DEMO_USER01';
            IF @id IS NULL THROW 52705, N'Encrypted B demo user was not found by phone_hash.', 1;
            EXEC dbo.usp_DecryptSensitive @cipher, @phone OUTPUT;
            SELECT @id, @phone;
        """), {"lookup_hash": lookup_hash}).one()
    assert (user_id, decrypted) == ("B_DEMO_USER01", phone)

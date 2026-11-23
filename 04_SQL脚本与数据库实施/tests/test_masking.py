import pytest

from evplatform.masking import mask_phone, mask_plate


@pytest.fixture(autouse=True)
def guard_test_db():
    """Masking is independent of the database."""


def test_phone_mask_keeps_prefix_and_suffix():
    assert mask_phone("13800001234") == "138****1234"


@pytest.mark.parametrize(("value", "expected"), [
    ("京A12345", "京A***45"),
    ("京AD12345", "京A****45"),
])
def test_plate_mask_keeps_region_and_suffix(value, expected):
    assert mask_plate(value) == expected


@pytest.mark.parametrize(("mask", "value"), [(mask_phone, "1234"), (mask_plate, "12345")])
def test_invalid_values_do_not_return_unmasked_text(mask, value):
    with pytest.raises(ValueError):
        mask(value)

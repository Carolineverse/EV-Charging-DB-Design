"""Display masks for normalized phone numbers and vehicle plates."""

import re


def mask_phone(phone: str) -> str:
    if not re.fullmatch(r"[0-9]{11}", phone):
        raise ValueError("Expected an 11-digit phone number")
    return phone[:3] + "****" + phone[-4:]


def mask_plate(plate: str) -> str:
    if not re.fullmatch(r"[\u4e00-\u9fff][A-Z][A-Z0-9]{5,6}", plate):
        raise ValueError("Expected a normalized 7- or 8-character plate")
    return plate[:2] + "*" * (len(plate) - 4) + plate[-2:]

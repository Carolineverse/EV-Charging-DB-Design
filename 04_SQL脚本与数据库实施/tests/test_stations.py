"""A1 场站设施持久层测试。"""
import pytest

from evplatform.stations import list_stations_page, update_device_status


def test_list_stations_page_includes_fixture_station(session_factory, business_fixture):
    with session_factory() as session:
        page = list_stations_page(session, size=200)
    station_ids = {row["station_id"] for row in page.items}
    assert business_fixture["station_id"] in station_ids
    assert page.total >= 1


def test_list_stations_page_filters_by_operator(session_factory, business_fixture):
    with session_factory() as session:
        page = list_stations_page(
            session, operator_id=business_fixture["operator_id"], size=200
        )
    assert page.total >= 1
    assert all(r["operator_id"] == business_fixture["operator_id"] for r in page.items)


def test_update_device_status_changes_pile(session_factory, business_fixture):
    with session_factory() as session:
        session.begin()
        try:
            result = update_device_status(
                session,
                pile_id=business_fixture["pile_id"],
                new_status="FAULT",
                change_source="MANUAL",
                change_reason="integration test",
            )
        finally:
            session.rollback()
    assert result["result_code"] in ("UPDATED", "NO_CHANGE")
    assert result["new_status"] == "FAULT"


def test_update_device_status_requires_exactly_one_target(session_factory):
    with session_factory() as session:
        with pytest.raises(ValueError):
            update_device_status(
                session,
                pile_id="P1",
                gun_id="G1",
                new_status="FAULT",
                change_source="MANUAL",
                change_reason="bad",
            )
        with pytest.raises(ValueError):
            update_device_status(
                session,
                new_status="FAULT",
                change_source="MANUAL",
                change_reason="bad",
            )

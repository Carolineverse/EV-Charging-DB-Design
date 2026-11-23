"""Task-book SQL-injection regression for parameterized persistence filters."""

from evplatform.enterprise import list_enterprise_orders_page
from evplatform.order_queries import list_orders_page
from evplatform.stations import list_stations_page


def test_injection_payloads_are_treated_as_filter_values(session_factory):
    payload = "' OR 1=1;--"
    with session_factory() as session:
        stations = list_stations_page(session, operator_id=payload, status=payload)
        orders = list_orders_page(session, user_id=payload)
        enterprise_orders = list_enterprise_orders_page(
            session, enterprise_id=payload
        )

    assert stations.total == 0 and stations.items == []
    assert orders.total == 0 and orders.items == ()
    assert enterprise_orders.total == 0 and enterprise_orders.items == []

import os

from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from sqlalchemy.orm import sessionmaker


def create_engine_from_env():
    odbc_connect = os.environ.get("EV_DB_ODBC")
    if not odbc_connect:
        raise RuntimeError("EV_DB_ODBC must contain the local SQL Server ODBC connection string.")

    url = URL.create(
        "mssql+pyodbc",
        query={"odbc_connect": odbc_connect},
    )
    return create_engine(url, pool_pre_ping=True)


def create_session_factory(engine):
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

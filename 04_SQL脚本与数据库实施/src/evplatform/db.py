import os
from threading import Lock

from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from sqlalchemy.orm import DeclarativeBase, sessionmaker


class Base(DeclarativeBase):
    pass


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


class _LazySessionMaker(sessionmaker):
    _bind_lock = Lock()

    def __call__(self, **local_kw):
        if self.kw.get("bind") is None:
            with self._bind_lock:
                if self.kw.get("bind") is None:
                    self.configure(bind=create_engine_from_env())
        return super().__call__(**local_kw)


SessionLocal = _LazySessionMaker(autoflush=False, expire_on_commit=False)


if __name__ == "__main__":
    from sqlalchemy import text

    with SessionLocal() as session:
        print(session.execute(text("SELECT DB_NAME()")).scalar_one())

import os
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL
from sqlalchemy.orm import sessionmaker, DeclarativeBase

def _odbc_url():
    return URL.create(
        "mssql+pyodbc",
        query={"odbc_connect": os.environ["EV_DB_ODBC"]},
    )

engine = create_engine(_odbc_url(), future=True)
SessionLocal = sessionmaker(bind=engine, future=True, expire_on_commit=False)

class Base(DeclarativeBase):
    pass

if __name__ == "__main__":
    with SessionLocal() as session:
        print(session.execute(text("SELECT DB_NAME()")).scalar_one())

from datetime import datetime

from sqlalchemy import BigInteger, String, Unicode
from sqlalchemy.dialects.mssql import DATETIME2
from sqlalchemy.orm import Mapped, mapped_column

from evplatform.db import Base


class Operator(Base):
    __tablename__ = "Operator"
    __table_args__ = {"schema": "dbo"}

    operator_id: Mapped[str] = mapped_column(String(20), primary_key=True)
    operator_name: Mapped[str] = mapped_column(Unicode(100), nullable=False)


class ChargingStation(Base):
    __tablename__ = "ChargingStation"
    __table_args__ = {"schema": "dbo"}

    station_id: Mapped[str] = mapped_column(String(20), primary_key=True)
    station_name: Mapped[str] = mapped_column(Unicode(100), nullable=False)
    operator_id: Mapped[str] = mapped_column(String(20), nullable=False)


class ChargingOrder(Base):
    __tablename__ = "ChargingOrder"
    __table_args__ = {"schema": "dbo"}

    order_id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(20), nullable=False)
    gun_id: Mapped[str] = mapped_column(String(20), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DATETIME2(precision=3), nullable=False)

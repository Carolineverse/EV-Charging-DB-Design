from datetime import datetime

from sqlalchemy import BigInteger, Column, DateTime, ForeignKey, Numeric, SmallInteger, String, Unicode
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


class SysAccount(Base):
    __tablename__ = "SysAccount"
    __table_args__ = {"schema": "dbo"}
    account_id = Column(BigInteger, primary_key=True, autoincrement=True)
    username = Column(String(50), nullable=False)
    role_id = Column(SmallInteger, nullable=False)
    status = Column(SmallInteger, nullable=False, default=1)


class OperationLog(Base):
    __tablename__ = "OperationLog"
    __table_args__ = {"schema": "dbo"}
    log_id = Column(BigInteger, primary_key=True, autoincrement=True)
    module_code = Column(String(30), nullable=False)
    object_type = Column(String(40), nullable=False)
    object_id = Column(String(50), nullable=False)
    action_code = Column(String(50), nullable=False)
    actor_type = Column(String(10), nullable=False)
    actor_account_id = Column(BigInteger, nullable=True)
    occurred_at = Column(DateTime, nullable=False)
    after_data = Column(String, nullable=True)


class Alarm(Base):
    __tablename__ = "Alarm"
    __table_args__ = {"schema": "dbo"}
    alarm_id = Column(BigInteger, primary_key=True, autoincrement=True)
    pile_id = Column(String(20), nullable=False)
    gun_id = Column(String(20), nullable=True)
    alarm_code = Column(String(20), nullable=False)
    alarm_level = Column(SmallInteger, nullable=False)
    alarm_description = Column(String(500), nullable=False)
    alarm_source = Column(String(20), nullable=False)
    occurred_at = Column(DateTime, nullable=False)
    status = Column(String(20), nullable=False)


class WorkOrder(Base):
    __tablename__ = "WorkOrder"
    __table_args__ = {"schema": "dbo"}
    work_order_id = Column(BigInteger, primary_key=True, autoincrement=True)
    alarm_id = Column(BigInteger, ForeignKey("dbo.Alarm.alarm_id"), nullable=False)
    engineer_staff_id = Column(String(20), nullable=False)
    assigned_at = Column(DateTime, nullable=False)
    status = Column(String(20), nullable=False)
    accept_deadline = Column(DateTime, nullable=False)


class SettlementStatement(Base):
    __tablename__ = "SettlementStatement"
    __table_args__ = {"schema": "dbo"}
    settlement_id = Column(BigInteger, primary_key=True, autoincrement=True)
    station_id = Column(String(20), nullable=False)
    period_month = Column(String(6), nullable=False)
    platform_rate = Column(Numeric(7, 6), nullable=False)
    status = Column(SmallInteger, nullable=False, default=0)


class SettlementDetail(Base):
    __tablename__ = "SettlementDetail"
    __table_args__ = {"schema": "dbo"}
    detail_id = Column(BigInteger, primary_key=True, autoincrement=True)
    settlement_id = Column(BigInteger, ForeignKey("dbo.SettlementStatement.settlement_id"), nullable=False)
    order_id = Column(BigInteger, nullable=False)
    electricity_base = Column(Numeric(12, 2), nullable=False)
    service_base = Column(Numeric(12, 2), nullable=False)
    minimum_adjustment = Column(Numeric(12, 2), nullable=False, default=0)


class ReconciliationDifference(Base):
    __tablename__ = "ReconciliationDifference"
    __table_args__ = {"schema": "dbo"}
    difference_id = Column(BigInteger, primary_key=True, autoincrement=True)
    settlement_id = Column(BigInteger, nullable=False)
    order_id = Column(BigInteger, nullable=False)
    difference_type = Column(SmallInteger, nullable=False)
    difference_amount = Column(Numeric(12, 2), nullable=False)
    status = Column(SmallInteger, nullable=False, default=0)

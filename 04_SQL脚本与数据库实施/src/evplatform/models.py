from sqlalchemy import (Column, BigInteger, SmallInteger, Integer, String,
                        DateTime, Numeric, ForeignKey)
from evplatform.db import Base

class SysAccount(Base):
    __tablename__ = "SysAccount"
    account_id = Column(BigInteger, primary_key=True, autoincrement=True)
    username = Column(String(50), nullable=False)
    role_id = Column(SmallInteger, nullable=False)
    status = Column(SmallInteger, nullable=False, default=1)

class OperationLog(Base):
    __tablename__ = "OperationLog"
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
    work_order_id = Column(BigInteger, primary_key=True, autoincrement=True)
    alarm_id = Column(BigInteger, ForeignKey("Alarm.alarm_id"), nullable=False)
    engineer_staff_id = Column(String(20), nullable=False)
    assigned_at = Column(DateTime, nullable=False)
    status = Column(String(20), nullable=False)
    accept_deadline = Column(DateTime, nullable=False)

class SettlementStatement(Base):
    __tablename__ = "SettlementStatement"
    settlement_id = Column(BigInteger, primary_key=True, autoincrement=True)
    station_id = Column(String(20), nullable=False)
    period_month = Column(String(6), nullable=False)
    platform_rate = Column(Numeric(7, 6), nullable=False)
    status = Column(SmallInteger, nullable=False, default=0)

class SettlementDetail(Base):
    __tablename__ = "SettlementDetail"
    detail_id = Column(BigInteger, primary_key=True, autoincrement=True)
    settlement_id = Column(BigInteger, ForeignKey("SettlementStatement.settlement_id"), nullable=False)
    order_id = Column(BigInteger, nullable=False)
    electricity_base = Column(Numeric(12, 2), nullable=False)
    service_base = Column(Numeric(12, 2), nullable=False)
    minimum_adjustment = Column(Numeric(12, 2), nullable=False, default=0)

class ReconciliationDifference(Base):
    __tablename__ = "ReconciliationDifference"
    difference_id = Column(BigInteger, primary_key=True, autoincrement=True)
    settlement_id = Column(BigInteger, nullable=False)
    order_id = Column(BigInteger, nullable=False)
    difference_type = Column(SmallInteger, nullable=False)
    difference_amount = Column(Numeric(12, 2), nullable=False)
    status = Column(SmallInteger, nullable=False, default=0)

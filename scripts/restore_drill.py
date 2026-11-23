"""Run a full + differential restore drill in an isolated temporary database.

The source EV_B_TEST database is only read by BACKUP. The generated restore
database is removed after DBCC CHECKDB and row-count checks. Backup files stay
in the SQL Server instance's backup directory as drill evidence.
"""

from __future__ import annotations

import uuid

import pyodbc


SERVER = r".\SQLEXPRESS"
SOURCE_DATABASE = "EV_B_TEST"


def quote_identifier(value: str) -> str:
    return "[" + value.replace("]", "]]") + "]"


def quote_literal(value: str) -> str:
    return "N'" + value.replace("'", "''") + "'"


def run() -> None:
    suffix = uuid.uuid4().hex[:10].upper()
    restore_database = f"EV_B_RESTORE_DRILL_{suffix}"
    connection_string = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={SERVER};DATABASE=master;Trusted_Connection=yes;"
        "TrustServerCertificate=yes;"
    )
    full_backup: str | None = None
    diff_backup: str | None = None
    data_file: str | None = None
    log_file: str | None = None

    with pyodbc.connect(connection_string, autocommit=True, timeout=30) as connection:
        cursor = connection.cursor()
        source = cursor.execute(
            """
            SELECT CONVERT(NVARCHAR(4000), SERVERPROPERTY('InstanceDefaultBackupPath')),
                   CONVERT(NVARCHAR(4000), SERVERPROPERTY('InstanceDefaultDataPath')),
                   name, type_desc
            FROM sys.master_files
            WHERE database_id=DB_ID(?)
            ORDER BY type_desc DESC
            """,
            SOURCE_DATABASE,
        ).fetchall()
        if not source:
            raise RuntimeError(f"Source database {SOURCE_DATABASE} is missing.")
        # Keep SERVERPROPERTY paths as returned. The SQL Server service account
        # owns this directory; the client user may not have filesystem access.
        backup_dir = source[0][0].rstrip("\\/")
        data_dir = source[0][1].rstrip("\\/")
        logical_data = next(row[2] for row in source if row[3] == "ROWS")
        logical_log = next(row[2] for row in source if row[3] == "LOG")
        exists = cursor.execute(
            "SELECT DB_ID(?)", restore_database
        ).fetchone()[0]
        if exists is not None:
            raise RuntimeError(f"Refusing to overwrite existing {restore_database}.")

        full_backup = backup_dir + "\\" + f"{restore_database}_full.bak"
        diff_backup = backup_dir + "\\" + f"{restore_database}_diff.bak"
        data_file = data_dir + "\\" + f"{restore_database}.mdf"
        log_file = data_dir + "\\" + f"{restore_database}_log.ldf"

        try:
            cursor.execute(
                f"BACKUP DATABASE {quote_identifier(SOURCE_DATABASE)} "
                f"TO DISK={quote_literal(str(full_backup))} WITH CHECKSUM"
            )
            while cursor.nextset():
                pass
            cursor.execute(
                f"RESTORE VERIFYONLY FROM DISK={quote_literal(str(full_backup))} WITH CHECKSUM"
            )
            while cursor.nextset():
                pass
            cursor.execute(
                f"BACKUP DATABASE {quote_identifier(SOURCE_DATABASE)} "
                f"TO DISK={quote_literal(str(diff_backup))} WITH DIFFERENTIAL,CHECKSUM"
            )
            while cursor.nextset():
                pass
            cursor.execute(
                f"RESTORE VERIFYONLY FROM DISK={quote_literal(str(diff_backup))} WITH CHECKSUM"
            )
            while cursor.nextset():
                pass
            cursor.execute(
                f"RESTORE DATABASE {quote_identifier(restore_database)} "
                f"FROM DISK={quote_literal(str(full_backup))} WITH NORECOVERY,CHECKSUM,"
                f"MOVE {quote_literal(logical_data)} TO {quote_literal(str(data_file))},"
                f"MOVE {quote_literal(logical_log)} TO {quote_literal(str(log_file))}"
            )
            while cursor.nextset():
                pass
            cursor.execute(
                f"RESTORE DATABASE {quote_identifier(restore_database)} "
                f"FROM DISK={quote_literal(str(diff_backup))} WITH RECOVERY,CHECKSUM"
            )
            while cursor.nextset():
                pass

            check = cursor.execute(
                f"DBCC CHECKDB ({quote_literal(restore_database)}) WITH NO_INFOMSGS"
            )
            while check.nextset():
                pass
            restored_tables = cursor.execute(
                f"SELECT COUNT(*) FROM {quote_identifier(restore_database)}.sys.tables t "
                f"JOIN {quote_identifier(restore_database)}.sys.schemas s "
                "ON s.schema_id=t.schema_id WHERE s.name=N'dbo'"
            ).fetchone()[0]
            if restored_tables != 62:
                raise RuntimeError(
                    f"Restored database has {restored_tables} dbo tables; expected 62."
                )
            print(
                f"restore_drill=PASS database={restore_database} dbo_tables={restored_tables} "
                f"full_backup={full_backup} diff_backup={diff_backup}"
            )
        finally:
            db_id = cursor.execute(
                "SELECT DB_ID(?)", restore_database
            ).fetchone()[0]
            if db_id is not None:
                cursor.execute(
                    f"ALTER DATABASE {quote_identifier(restore_database)} "
                    "SET SINGLE_USER WITH ROLLBACK IMMEDIATE"
                )
                cursor.execute(f"DROP DATABASE {quote_identifier(restore_database)}")
            print(
                f"cleanup=PASS database={restore_database}; backup files retained for evidence: "
                f"{full_backup}, {diff_backup}"
            )


if __name__ == "__main__":
    run()

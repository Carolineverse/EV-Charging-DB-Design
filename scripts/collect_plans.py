"""Collect actual SQL Server plans and produce the Q01-Q05 report."""

from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
import re
import subprocess
import sys
from xml.etree import ElementTree as ET

import pyodbc


ROOT = Path(__file__).resolve().parent.parent
QUERIES = ROOT / "04_SQL脚本与数据库实施" / "sql" / "queries"
DOCS = ROOT / "docs"
PLANS = DOCS / "plans"
SERVER = r".\SQLEXPRESS"
DATABASE = "EV_B_TEST"
FILES = {
    "Q01": "Q01_station_device_statistics.sql",
    "Q02": "Q02_period_energy_revenue.sql",
    "Q03": "Q03_enterprise_monthly_bill.sql",
    "Q04": "q04.sql",
    "Q05": "q05.sql",
}
NS = {"p": "http://schemas.microsoft.com/sqlserver/2004/07/showplan"}


def read_query(path):
    source = path.read_text(encoding="utf-8-sig")
    # GO is a SQL client separator. The five sources each contain one batch.
    query = re.sub(r"(?im)^\s*GO\s*\Z", "", source).strip()
    tokens = re.sub(r"'(?:''|[^'])*'|--[^\n]*|/\*.*?\*/", " ", query, flags=re.S)
    if re.search(r"\b(INSERT|UPDATE|DELETE|MERGE|CREATE|ALTER|DROP|TRUNCATE|EXEC(?:UTE)?|INTO|GO)\b", tokens, re.I):
        raise ValueError(f"Unexpected statement in read-only source {path}")
    return query


def capture_io(sqlcmd, query, output):
    batch = "SET LANGUAGE us_english;\nSET NOCOUNT OFF;\nSET STATISTICS IO ON;\nSET STATISTICS TIME ON;\n" + query
    process = subprocess.run(
        [sqlcmd, "-S", SERVER, "-d", DATABASE, "-E", "-b", "-C", "-f", "65001",
         "-w", "4096", "-l", "10", "-t", "60", "-Q", batch],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=75,
    )
    if process.returncode:
        raise RuntimeError(process.stdout.decode("utf-8-sig", errors="replace"))
    output.write_bytes(process.stdout)
    return parse_io(output)


def parse_io(output):
    # sqlcmd 在中文 Windows 上可能按 GBK 写出结果集里的中文数据，
    # 先按 UTF-8 读，失败再回退 GBK，避免解码失败中断采集。
    raw = output.read_bytes()
    try:
        rendered = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        rendered = raw.decode("gbk", errors="replace")
    rows = re.findall(r"(?im)^\s*\((\d+)\s*(?:rows?\s+affected|\u884c\u53d7\u5f71\u54cd)\)\s*$", rendered)
    cpu_elapsed = re.findall(
        r"SQL Server Execution Times:\s*CPU time = (\d+) ms,\s*elapsed time = (\d+) ms", rendered, re.I
    )
    reads = re.findall(r"(?im)^Table '(.+?)'\. Scan count \d+, logical reads (\d+)", rendered)
    if len(rows) != 1 or not cpu_elapsed:
        raise ValueError(f"Could not isolate the result rows and execution time in {output}")
    cpu, elapsed = map(int, cpu_elapsed[-1])
    return int(rows[0]), reads, cpu, elapsed


def capture_plan(connection, query):
    cursor = connection.cursor()
    cursor.execute("SET NOCOUNT ON; SET STATISTICS XML ON;\n" + query)
    sets = []
    while True:
        if cursor.description:
            sets.append(cursor.fetchall())
        if not cursor.nextset():
            break
    cursor.close()
    if len(sets) != 2 or len(sets[1]) != 1 or len(sets[1][0]) != 1:
        raise ValueError("Expected one query result set followed by one XML plan result set")
    xml = sets[1][0][0]
    root = ET.fromstring(xml)
    if root.tag != "{" + NS["p"] + "}ShowPlanXML" or root.find(".//p:RunTimeCountersPerThread", NS) is None:
        raise ValueError("SQL Server did not return an actual ShowPlanXML")
    return len(sets[0]), xml, root


def children(operator):
    for element in operator:
        if element.tag.endswith("}RelOp"):
            yield element
        else:
            yield from children(element)


def plan_metrics(root, xml):
    top = root.find(".//p:QueryPlan/p:RelOp", NS)
    if top is None:
        raise ValueError("Plan has no root operator")
    operators = top.findall(".//p:RelOp", NS)
    operators.insert(0, top)

    def subtree(operator):
        return float(operator.attrib["EstimatedTotalSubtreeCost"])

    own_cost = {
        op.attrib["NodeId"]: max(0, subtree(op) - sum(subtree(child) for child in children(op)))
        for op in operators
    }
    most_expensive = max(operators, key=lambda op: own_cost[op.attrib["NodeId"]])
    chain = []
    node = top
    while node is not None:
        chain.append(node.attrib["PhysicalOp"])
        node = max(children(node), key=subtree, default=None)
    types = Counter(op.attrib["PhysicalOp"] for op in operators)
    # SQL Server can describe a Key Lookup as an Index Seek with Lookup=true.
    lookups = sum(
        1 for op in operators
        if op.attrib["PhysicalOp"] == "Key Lookup"
        or any(item.get("Lookup") in ("1", "true") for item in op.findall("./p:IndexScan", NS))
    )
    tables = {
        (obj.get("Database"), obj.get("Schema"), obj.get("Table"))
        for obj in top.findall(".//p:Object", NS)
        if obj.get("Table") and obj.get("Schema")
    }
    return top, operators, chain, most_expensive, own_cost, types, lookups, tables, "CONVERT_IMPLICIT" in xml.upper()


def actual_count(operator, attribute):
    counters = operator.findall("./p:RunTimeInformation/p:RunTimeCountersPerThread", NS)
    if not counters:
        return "无计数"
    counts = [counter.get(attribute) for counter in counters if counter.get(attribute) is not None]
    return str(sum(map(int, counts))) if counts else "无计数"


def clean(markdown):
    return markdown.replace("|", r"\|")


def write_report(version, stamp, results):
    notes = {
        "Q01": "按场站汇总桩枪，保留无设备场站。",
        "Q02": "默认查询十月全部场站，结果是核价金额。",
        "Q03": "默认查询十月全部企业，比对账单快照与订单明细。",
        "Q04": "默认场站为 B_DEMO_ST01。",
        "Q05": "默认账期为 202610。",
    }
    body = [
        "# Q01–Q05 实际执行计划",
        "",
        f"- SQL Server `{version}`，实例 `{SERVER}`，数据库 `{DATABASE}`。",
        f"- 采集时间 `{stamp}` （北京时间）。",
        "- 每条查询先用 sqlcmd 采集 STATISTICS IO/TIME，再用独立 pyodbc 连接采集 STATISTICS XML。保留原查询参数，不清理缓存。",
        "- 逻辑读统计默认 logical reads，含输出中的 Worktable/Workfile。CPU 和总耗时取 sqlcmd 中最后一组 SQL Server Execution Times，单位 ms，排除编译时间。两次执行的返回行数必须一致。",
        "- 表数由计划的数据库、架构、对象去重得出，包含视图展开的底表。最贵算子占比为估算子树成本扣除直接子树后除以根成本，属优化器估算。实际行数汇总运行线程，包括重复执行，无计数的节点保留标记。",
        "",
    ]
    summary = []
    for name, rows, io, cpu, elapsed, xml, root in results:
        top, operators, chain, expensive, costs, types, lookups, tables, implicit = plan_metrics(root, xml)
        reads = sum(int(value) for _, value in io)
        scans = [name for name in ("Table Scan", "Clustered Index Scan", "Index Scan") if types[name]]
        scan_text = "、".join(f"{typ} ({types[typ]})" for typ in scans) or "无"
        root_cost = float(top.attrib["EstimatedTotalSubtreeCost"])
        share = f'{100 * costs[expensive.attrib["NodeId"]] / root_cost:.1f}%' if root_cost else "不适用"
        conclusion = notes[name]
        if name == "Q04" and rows == 0 and all(
            actual_count(op, "ActualExecutions") == "0"
            for op in operators if "Scan" in op.attrib["PhysicalOp"]
        ):
            conclusion += "计划中的扫描节点均未执行。"
        if rows == 0:
            conclusion += "当前参数下实际返回 0 行，该计划仅代表此次空结果。"
        else:
            conclusion += f"返回 {rows} 行，部署数据量变化后应复测。"
        body += [
            f"## {name}",
            "",
            f"- 返回 **{rows} 行**，逻辑读 **{reads}**，CPU **{cpu} ms**，总耗时 **{elapsed} ms**。",
            "- IO 明细（名称 / 逻辑读）" + ("、".join(f"`{clean(table)}` / {value}" for table, value in io) or "无表 IO 统计") + "。",
            "- 主算子链（估算成本最高分支） " + " → ".join(f"`{op}`" for op in chain) + "。",
            f'- 最贵算子 `{expensive.attrib["PhysicalOp"]}` 节点 {expensive.attrib["NodeId"]}，估算占比 **{share}**。',
            f'- 底表 {len(tables)} 个，扫描 {scan_text}，Key Lookup {lookups}，CONVERT_IMPLICIT {"有" if implicit else "无"}。',
            f"- 结论 {conclusion}",
            f"- 原件 [IO](plans/{name}_io.txt) · [实际计划](plans/{name}.sqlplan)",
            "",
            "| NodeId | PhysicalOp | EstimateRows | ActualRows | ActualExecutions |",
            "|---:|---|---:|---:|---:|",
        ]
        for op in sorted(operators, key=lambda op: int(op.attrib["NodeId"])):
            body.append(f'| {op.attrib["NodeId"]} | {op.attrib["PhysicalOp"]} | {op.attrib["EstimateRows"]} | {actual_count(op, "ActualRows")} | {actual_count(op, "ActualExecutions")} |')
        body.append("")
        summary.append(f"| {name} | {len(tables)} | {rows} | {reads} | {elapsed} | {scan_text} | {conclusion} |")
        print(f"{name}: tables={len(tables)} rows={rows} reads={reads} cpu_ms={cpu} elapsed_ms={elapsed}")
    body += [
        "## 建议",
        "",
        "- 若要评估 Q04 有数据时的告警与工单联接，可经人工确认另选一个有告警的场站，保留本次默认参数采集作为对照。",
        "- 复测 Q01 时可优先检查 Table Spool 的重复执行及 Worktable 读数。小样本扫描和 0 ms 统计需结合更大数据量判读。",
        "",
        "## 汇总",
        "",
        "| 查询 | 底表数 | 行数 | 逻辑读 | 总耗时 ms | 扫描 | 结论 |",
        "|---|---:|---:|---:|---:|---|---|",
        *summary,
    ]
    (DOCS / "查询执行计划.md").write_text("\n".join(body) + "\n", encoding="utf-8")


def main(sqlcmd):
    PLANS.mkdir(parents=True, exist_ok=True)
    connect = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};"
        "Trusted_Connection=yes;TrustServerCertificate=yes;"
    )
    stamp = datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds")
    results = []
    version = None
    for name, filename in FILES.items():
        query = read_query(QUERIES / filename)
        rows, io, cpu, elapsed = capture_io(sqlcmd, query, PLANS / f"{name}_io.txt")
        with pyodbc.connect(connect, autocommit=True, timeout=10) as connection:
            connection.timeout = 60
            if version is None:
                database, version = connection.execute(
                    "SELECT DB_NAME(), CONVERT(varchar(40),SERVERPROPERTY('ProductVersion'))"
                ).fetchone()
                if database != DATABASE:
                    raise RuntimeError(f"Wrong database: {database}")
            xml_rows, xml, root = capture_plan(connection, query)
        connection.close()
        if xml_rows != rows:
            raise RuntimeError(f"{name}: sqlcmd and plan row counts differ: {rows} vs {xml_rows}")
        encoding = "utf-16" if re.match(r'<\?xml[^>]*encoding=["\x27]utf-16', xml, re.I) else "utf-8"
        (PLANS / f"{name}.sqlplan").write_bytes(xml.encode(encoding))
        results.append((name, rows, io, cpu, elapsed, xml, root))
    write_report(version, stamp, results)


if __name__ == "__main__":
    main(sys.argv[1])

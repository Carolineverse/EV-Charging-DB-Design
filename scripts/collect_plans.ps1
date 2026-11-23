$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$python = Join-Path $repo '04_SQL脚本与数据库实施/.venv/Scripts/python.exe'
$sqlcmd = (Get-Command sqlcmd -CommandType Application).Source

& $python -B (Join-Path $PSScriptRoot 'collect_plans.py') $sqlcmd
if ($LASTEXITCODE -ne 0) {
    throw "Plan collection failed (exit code $LASTEXITCODE)."
}

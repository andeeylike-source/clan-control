# Claude Code local model router (PowerShell)
# Usage:
#   .claude\router.ps1 "fix typo in button"
#   "redesign auth schema" | .claude\router.ps1
#
# Routing: heavy > normal > cheap, default = sonnet
# Calls the real claude application directly — safe to use when `claude` is
# redefined as a function in $PROFILE (no recursion).

param([Parameter(ValueFromRemainingArguments=$true)] [string[]]$TaskArgs)

if ($TaskArgs) {
    $task = $TaskArgs -join " "
} else {
    $task = $input | Out-String
}
$task = $task.Trim()

$heavy = 'architect|system design|schema|security audit|full refactor|overhaul|migrate|audit|design decision|rewrite|restructure|redesign'
$cheap = 'typo|rename|update text|update label|color|padding|margin|quick fix|simple|one.?line|css variable|spelling|wording'

if ($task -match $heavy) {
    $model = "claude-opus-4-6"
} elseif ($task -match $cheap) {
    $model = "claude-haiku-4-5-20251001"
} else {
    $model = "claude-sonnet-4-6"
}

Write-Host "-> routing to: $model" -ForegroundColor Cyan

# Resolve real claude binary by type=Application — bypasses any `claude` function in $PROFILE
$claudeExe = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $claudeExe) {
    Write-Error "claude application not found in PATH"
    exit 1
}

& $claudeExe --model $model -p $task

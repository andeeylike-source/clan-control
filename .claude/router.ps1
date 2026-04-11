# Claude Code local model router (PowerShell) — batch/headless only.
# Interactive sessions always run Sonnet (model cannot be changed mid-session).
#
# Usage:
#   .claude/router.ps1 "fix typo in button"            # auto-route by keyword
#   .claude/router.ps1 --cheap  "rename variable"      # force Haiku
#   .claude/router.ps1 --normal "debug login flow"     # force Sonnet
#   .claude/router.ps1 --heavy  "redesign auth schema" # force Opus

param([Parameter(ValueFromRemainingArguments=$true)] [string[]]$TaskArgs)

$forceModel = ''
if ($TaskArgs.Count -gt 0 -and $TaskArgs[0] -in '--cheap','--normal','--heavy') {
    switch ($TaskArgs[0]) {
        '--cheap'  { $forceModel = 'claude-haiku-4-5-20251001' }
        '--normal' { $forceModel = 'claude-sonnet-4-6' }
        '--heavy'  { $forceModel = 'claude-opus-4-6' }
    }
    $TaskArgs = $TaskArgs[1..($TaskArgs.Count-1)]
}

$task = if ($TaskArgs) { $TaskArgs -join ' ' } else { $input | Out-String }
$task = $task.Trim()

if ($forceModel) {
    $model = $forceModel
} else {
    $heavy = 'architect|system design|schema|security audit|full refactor|overhaul|migrate|audit|design decision|rewrite|restructure|redesign'
    $cheap = 'typo|rename|update text|update label|color|padding|margin|quick fix|simple|one.?line|css variable|spelling|wording'
    if ($task -match $heavy) {
        $model = 'claude-opus-4-6'
    } elseif ($task -match $cheap) {
        $model = 'claude-haiku-4-5-20251001'
    } else {
        $model = 'claude-sonnet-4-6'
    }
}

Write-Host "-> routing to: $model" -ForegroundColor Cyan

$claudeExe = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $claudeExe) { Write-Error "claude not found in PATH"; exit 1 }

if ([string]::IsNullOrWhiteSpace($task)) {
    & $claudeExe --model $model
    exit $LASTEXITCODE
}

& $claudeExe --model $model -p $task
exit $LASTEXITCODE

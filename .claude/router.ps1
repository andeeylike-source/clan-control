# Claude Code model router (PowerShell)
# Interactive: shows model-choice menu (Sonnet / Opus)
# Batch/headless: defaults to Sonnet (no menu)
# Explicit --model arg: passed through unchanged
#
# Usage:
#   claude                         # interactive menu -> choose model
#   claude --model claude-opus-4-6 # explicit model, no menu
#   claude -p "fix typo"           # headless, defaults to Sonnet

param([Parameter(ValueFromRemainingArguments=$true)] [string[]]$PassArgs)

$claudeExe = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue |
              Select-Object -First 1).Source
if (-not $claudeExe) { Write-Error "claude not found in PATH"; exit 1 }

# If --model already present — pass everything through unchanged
if ($PassArgs -contains '--model') {
    & $claudeExe @PassArgs
    exit $LASTEXITCODE
}

# Detect non-interactive (piped input or -p flag)
$isHeadless = [Console]::IsInputRedirected -or ($PassArgs -contains '-p')

if ($isHeadless) {
    $model = 'claude-sonnet-4-6'
} else {
    Write-Host ""
    Write-Host "  Select model:" -ForegroundColor Cyan
    Write-Host "  1) Sonnet 4.6"
    Write-Host "  2) Opus 4.6"
    Write-Host ""
    $choice = Read-Host "  Enter 1 or 2 [default: 1]"
    $model = if ($choice -eq '2') { 'claude-opus-4-6' } else { 'claude-sonnet-4-6' }
    Write-Host "  -> $model" -ForegroundColor Cyan
    Write-Host ""
}

& $claudeExe --model $model @PassArgs
exit $LASTEXITCODE

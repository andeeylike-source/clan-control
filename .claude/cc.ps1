# cc.ps1 - DEFAULT ENTRYPOINT for Claude Code session auto-routing.
#
# THIS file is the real entry point. router.ps1 is kept only for batch/headless (-p) use.
#
# What it does:
#   1. Reads task from CLI arg
#   2. Classifies: cheap (Haiku) / normal (Sonnet) / heavy (Opus)
#   3. Starts a NEW Claude interactive session with the selected model
#      - default: in current shell (most reliable, no quoting issues)
#      - optional: --new-window opens a new PowerShell window
#
# NOTE: a running session cannot switch models mid-session.
#       This launcher must be called BEFORE starting Claude, not from inside it.
#
# Usage:
#   cc "rename variable"                # auto-route -> cheap (Haiku)
#   cc "debug login flow"               # auto-route -> normal (Sonnet)
#   cc "redesign auth schema"           # auto-route -> heavy (Opus)
#   cc --cheap  "task"                  # force Haiku
#   cc --normal "task"                  # force Sonnet
#   cc --heavy  "task"                  # force Opus
#   cc --new-window "task"              # same routing + open new PowerShell window

param([Parameter(ValueFromRemainingArguments=$true)] [string[]]$TaskArgs)

# --- parse flags ---
$forceModel = ''
$newWindow  = $false

$filtered = [System.Collections.Generic.List[string]]::new()
foreach ($a in $TaskArgs) {
    switch ($a) {
        '--cheap'      { $forceModel = 'claude-haiku-4-5-20251001' }
        '--normal'     { $forceModel = 'claude-sonnet-4-6'         }
        '--heavy'      { $forceModel = 'claude-opus-4-6'           }
        '--new-window' { $newWindow  = $true                       }
        default        { $filtered.Add($a)                         }
    }
}
$task = ($filtered -join ' ').Trim()

# --- route ---
if ($forceModel) {
    $model = $forceModel
} else {
    $heavy = 'architect|system design|schema|security audit|full refactor|overhaul|migrate|audit|design decision|rewrite|restructure|redesign'
    $cheap = 'typo|rename|update text|update label|color|padding|margin|quick fix|simple|one.?line|css variable|spelling|wording'
    if     ($task -match $heavy) { $model = 'claude-opus-4-6'           }
    elseif ($task -match $cheap) { $model = 'claude-haiku-4-5-20251001' }
    else                         { $model = 'claude-sonnet-4-6'         }
}

$tier = switch ($model) {
    'claude-haiku-4-5-20251001' { 'cheap  (Haiku)'  }
    'claude-sonnet-4-6'         { 'normal (Sonnet)' }
    'claude-opus-4-6'           { 'heavy  (Opus)'   }
}
Write-Host "cc: $tier" -ForegroundColor Cyan

# --- find claude ---
$claudeExe = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue |
              Select-Object -First 1).Source
if (-not $claudeExe) { Write-Error "claude not found in PATH"; exit 1 }

# --- launch ---
if ($newWindow) {
    # Prefer pwsh (PowerShell 7+); fall back to Windows PowerShell; fail honestly otherwise.
    $shell = (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue |
              Select-Object -First 1).Source
    if (-not $shell) {
        $shell = (Get-Command powershell -CommandType Application -ErrorAction SilentlyContinue |
                  Select-Object -First 1).Source
    }
    if (-not $shell) {
        Write-Error "cc: no PowerShell host found (need pwsh or powershell.exe for --new-window)"
        exit 1
    }

    $escapedTask = $task.Replace("'", "''")
    $escapedExe  = $claudeExe.Replace("'", "''")
    if ($task) {
        $cmd = "& '$escapedExe' --model $model '$escapedTask'"
    } else {
        $cmd = "& '$escapedExe' --model $model"
    }

    $proc = $null
    try {
        $proc = Start-Process -FilePath $shell `
            -ArgumentList @('-NoExit', '-NoProfile', '-Command', $cmd) `
            -PassThru -ErrorAction Stop
    } catch {
        Write-Error "cc: failed to launch new window: $($_.Exception.Message)"
        exit 1
    }

    if (-not $proc -or -not $proc.Id) {
        Write-Error "cc: new window failed to start"
        exit 1
    }

    $shellName = [System.IO.Path]::GetFileName($shell)
    Write-Host "cc: new window launched (pid $($proc.Id), shell $shellName)" -ForegroundColor Green
    exit 0
} else {
    # claude "task" without -p = interactive session with task as opening message
    if ($task) {
        & $claudeExe --model $model $task
    } else {
        & $claudeExe --model $model
    }
    exit $LASTEXITCODE
}

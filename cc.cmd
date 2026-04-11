@echo off
:: cc.cmd — thin wrapper around .claude/cc.ps1
:: Place this file (or its directory) in PATH to use "cc" from anywhere.
::
:: Usage:
::   cc "переименуй переменную"
::   cc "debug login flow"
::   cc "redesign auth schema"
::   cc --new-window "задача"
::   cc --cheap "задача"   cc --normal "задача"   cc --heavy "задача"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.claude\cc.ps1" %*

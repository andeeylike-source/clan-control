#!/usr/bin/env bash
# Claude Code model router — batch/headless only (-p flag).
# For interactive session auto-routing on Windows use cc.cmd / .claude/cc.ps1.
# A running session cannot switch models mid-session — selection must happen before start.
#
# Usage (batch/headless):
#   bash .claude/router.sh "fix typo in button"            # auto-route by keyword
#   bash .claude/router.sh --cheap  "rename variable"      # force Haiku
#   bash .claude/router.sh --normal "debug login flow"     # force Sonnet
#   bash .claude/router.sh --heavy  "redesign auth schema" # force Opus

FORCE_MODEL=""
if [[ "$1" == "--cheap" ]];  then FORCE_MODEL="claude-haiku-4-5-20251001"; shift; fi
if [[ "$1" == "--normal" ]]; then FORCE_MODEL="claude-sonnet-4-6";          shift; fi
if [[ "$1" == "--heavy" ]];  then FORCE_MODEL="claude-opus-4-6";            shift; fi

TASK="${*:-$(cat)}"

if [[ -n "$FORCE_MODEL" ]]; then
  MODEL="$FORCE_MODEL"
else
  HEAVY='architect|system design|schema|security audit|full refactor|overhaul|migrate|audit|design decision|rewrite|restructure|redesign'
  CHEAP='typo|rename|update text|update label|color|padding|margin|quick fix|simple|one.?line|css variable|spelling|wording'
  if echo "$TASK" | grep -qiE "$HEAVY"; then
    MODEL="claude-opus-4-6"
  elif echo "$TASK" | grep -qiE "$CHEAP"; then
    MODEL="claude-haiku-4-5-20251001"
  else
    MODEL="claude-sonnet-4-6"
  fi
fi

echo "→ routing to: $MODEL" >&2
claude --model "$MODEL" -p "$TASK"

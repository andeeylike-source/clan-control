#!/usr/bin/env bash
# Claude Code local model router
# Usage:
#   .claude/router.sh "fix typo in button"
#   echo "redesign auth schema" | .claude/router.sh
#
# Routing: heavy > normal > cheap, default = sonnet
# No swarm, no memory, no external deps.

TASK="${*:-$(cat)}"

HEAVY='architect|system design|schema|security audit|full refactor|overhaul|migrate|audit|design decision|rewrite|restructure|redesign'
CHEAP='typo|rename|update text|update label|color|padding|margin|quick fix|simple|one.?line|css variable|spelling|wording'

if echo "$TASK" | grep -qiE "$HEAVY"; then
  MODEL="claude-opus-4-6"
elif echo "$TASK" | grep -qiE "$CHEAP"; then
  MODEL="claude-haiku-4-5-20251001"
else
  MODEL="claude-sonnet-4-6"
fi

echo "→ routing to: $MODEL" >&2
claude --model "$MODEL" -p "$TASK"

#!/usr/bin/env bash
# Claude Code model router (bash)
# Interactive: shows model-choice menu (Sonnet / Opus)
# Batch/headless: defaults to Sonnet (no menu)
# Explicit --model arg: passed through unchanged

# If --model already in args — pass everything through
for a in "$@"; do
  if [[ "$a" == "--model" ]]; then
    exec claude "$@"
  fi
done

# Detect headless: stdin is not a terminal, or -p flag present
is_headless=0
if ! [ -t 0 ]; then is_headless=1; fi
for a in "$@"; do
  if [[ "$a" == "-p" ]]; then is_headless=1; fi
done

if [[ "$is_headless" -eq 1 ]]; then
  model="claude-sonnet-4-6"
else
  echo ""
  echo "  Select model:"
  echo "  1) Sonnet 4.6"
  echo "  2) Opus 4.6"
  echo ""
  read -rp "  Enter 1 or 2 [default: 1]: " choice
  if [[ "$choice" == "2" ]]; then
    model="claude-opus-4-6"
  else
    model="claude-sonnet-4-6"
  fi
  echo "  -> $model"
  echo ""
fi

exec claude --model "$model" "$@"

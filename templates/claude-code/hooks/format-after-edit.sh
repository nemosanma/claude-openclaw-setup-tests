#!/usr/bin/env bash
# PostToolUse hook for Edit|Write: formats the changed file with whatever
# formatter is installed. Never blocks (always exits 0). Requires: jq.
set -u
input="$(cat)"
f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -z "$f" ] || [ ! -f "$f" ] && exit 0
case "$f" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md|*.yaml|*.yml)
    if [ -x "./node_modules/.bin/prettier" ]; then ./node_modules/.bin/prettier --write "$f" >/dev/null 2>&1; fi ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then ruff format "$f" >/dev/null 2>&1
    elif command -v black >/dev/null 2>&1; then black -q "$f" >/dev/null 2>&1; fi ;;
  *.go)
    command -v gofmt >/dev/null 2>&1 && gofmt -w "$f" >/dev/null 2>&1 ;;
esac
exit 0

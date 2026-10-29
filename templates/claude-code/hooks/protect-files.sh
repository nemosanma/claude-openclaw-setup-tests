#!/usr/bin/env bash
# PreToolUse hook for Edit|Write: refuses edits to secrets, lockfiles and git internals.
# Requires: jq. Exit 2 blocks the edit and tells Claude why.
set -u
input="$(cat)"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
[ -z "$path" ] && exit 0
base="$(basename -- "$path")"

case "$base" in
  .env|.env.*|*.pem|*.key|id_rsa*|id_ed25519*|credentials|credentials.json)
    echo "Blocked by protect-files.sh: '$base' looks like a secret file. Edit it yourself." >&2; exit 2 ;;
  package-lock.json|pnpm-lock.yaml|yarn.lock|poetry.lock|uv.lock)
    echo "Blocked by protect-files.sh: do not hand-edit lockfiles; run the package manager instead." >&2; exit 2 ;;
esac
case "$path" in
  */.git/*|.git/*)
    echo "Blocked by protect-files.sh: never write inside .git/." >&2; exit 2 ;;
esac
exit 0

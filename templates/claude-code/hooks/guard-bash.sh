#!/usr/bin/env bash
# PreToolUse hook for the Bash tool: blocks a short list of high-risk command
# patterns even if a permission rule would allow them. Defense in depth only —
# keep your deny rules too. Requires: jq.
# Exit 0 = no decision (normal permission flow). Exit 2 = block; stderr goes to Claude.
set -u
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

block() {
  echo "Blocked by guard-bash.sh: $1. Ask the user to run this manually if it is really needed." >&2
  exit 2
}

# Normalise whitespace for matching
c="$(printf '%s' "$cmd" | tr -s '[:space:]' ' ')"

printf '%s' "$c" | grep -Eq 'rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*("?(/|/\*|~|~/|\$HOME|\$HOME/)"?)([[:space:]]|$)' && block "recursive delete of / or your home folder"
printf '%s' "$c" | grep -Eq 'rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*/(etc|usr|bin|sbin|var|lib|opt|boot|System|Library)(/|[[:space:]]|$)' && block "recursive delete of a system folder"
printf '%s' "$c" | grep -Eq '(curl|wget)[^|;&]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh\b' && block "piping a download straight into a shell"
printf '%s' "$c" | grep -Eq 'base64[[:space:]]+(-d|-D|--decode)[^|]*\|[[:space:]]*(ba|z)?sh\b' && block "decoding base64 into a shell (common malware pattern)"
printf '%s' "$c" | grep -Eq '(^|[;&|[:space:]])sudo[[:space:]]' && block "sudo"
printf '%s' "$c" | grep -Eq 'git[[:space:]]+push[[:space:]].*(--force|-f\b|--force-with-lease)' && block "force push"
printf '%s' "$c" | grep -Eq 'chmod[[:space:]]+(-R[[:space:]]+)?777' && block "chmod 777"
printf '%s' "$c" | grep -Eq '(^|[;&|[:space:]])(mkfs|dd[[:space:]]+if=.*of=/dev/)' && block "disk-level write"
printf '%s' "$c" | grep -Eq '(cat|less|head|tail|cp|scp)[[:space:]].*(\.ssh/id_|\.aws/credentials|\.openclaw/.*credential)' && block "reading credential files"
exit 0

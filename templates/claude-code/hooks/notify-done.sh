#!/usr/bin/env bash
# Stop hook: desktop notification when Claude finishes a turn.
# macOS: osascript. Linux: notify-send. WSL: powershell.exe toast fallback. Else: terminal bell.
cat >/dev/null   # drain stdin
msg="Claude Code finished — your turn."
if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$msg\" with title \"Claude Code\"" >/dev/null 2>&1
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "Claude Code" "$msg" >/dev/null 2>&1
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command "[console]::beep(880,200)" >/dev/null 2>&1
else
  printf '\a' >/dev/tty 2>/dev/null
fi
exit 0

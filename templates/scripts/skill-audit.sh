#!/usr/bin/env bash
# Quick red-flag scan for a skill or plugin folder BEFORE you install it.
# Not a malware scanner — it catches the patterns used in the 2026 ClawHub
# malware waves (fake "prerequisites", base64 droppers, curl|bash, raw IPs).
# Usage: ./skill-audit.sh <folder>      Exit 0 = no red flags, 1 = review needed.
set -uo pipefail
dir="${1:-}"
[ -d "$dir" ] || { echo "usage: $0 <skill-folder>" >&2; exit 64; }
flags=0
check() { # label regex [exclude-regex]
  local hits
  hits="$(grep -RInE --binary-files=without-match "$2" "$dir" 2>/dev/null | { if [ -n "${3:-}" ]; then grep -vE "$3"; else cat; fi; } | head -5)"
  if [ -n "$hits" ]; then echo "RED FLAG: $1"; echo "$hits" | sed 's/^/    /'; flags=$((flags+1)); fi
}
check "download piped into a shell"            '(curl|wget|iwr|Invoke-WebRequest)[^|]*\|[[:space:]]*(ba|z)?sh|\|[[:space:]]*iex'
check "base64 decode (possible hidden payload)" 'base64[[:space:]]+(-d|-D|--decode)|FromBase64String|atob\('
check "raw IP address URL (non-local)"          'https?://([0-9]{1,3}\.){3}[0-9]{1,3}' 'https?://(127\.|0\.0\.0\.0|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'
check "paste/file-sharing host"                 '(glot\.io|rentry\.co|pastebin\.com|transfer\.sh|anonfiles|mega\.nz)'
check "password-protected archive"              '(password|pass)[[:space:]]*[:=][[:space:]]*["'\''A-Za-z0-9]+.*\.(zip|7z|rar)|\.(zip|7z|rar).*(password|pass)'
check "'prerequisite' installer language"       '(install|download).{0,40}(prerequisite|required (helper|core|provider))|openclaw-core|OpenClawProvider'
check "reads browser/keychain/wallet data"      '(Login Data|Cookies\.binarycookies|keychain|wallet\.dat|\.ssh/id_|seed phrase|private key)'
check "persistence (cron/launchd/registry Run)" '(crontab[[:space:]]+-|LaunchAgents|launchctl[[:space:]]+load|CurrentVersion\\Run|systemctl[[:space:]]+--user[[:space:]]+enable)'
check "exfil to chat/webhook APIs"              '(api\.telegram\.org/bot|discord(app)?\.com/api/webhooks|hooks\.slack\.com)'
check "eval of dynamic code"                    '(eval[[:space:]]*\(|exec[[:space:]]*\(|new Function\(|python[0-9]?[[:space:]]+-c[[:space:]]+["'\''].*(urllib|requests|base64))'
if [ "$flags" -eq 0 ]; then
  echo "No red flags found in $dir. Still read SKILL.md and any scripts yourself before installing."
  exit 0
fi
echo "$flags red-flag group(s). Do NOT install until you understand every hit."
exit 1

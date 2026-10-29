#!/usr/bin/env bash
# Read-only health check for a Claude Code + OpenClaw setup. Changes nothing.
# Usage: ./verify-setup.sh        Exit code = number of FAILs.
set -u
pass=0; warn=0; fail=0
ok()   { echo "  PASS  $*"; pass=$((pass+1)); }
wn()   { echo "  WARN  $*"; warn=$((warn+1)); }
bad()  { echo "  FAIL  $*"; fail=$((fail+1)); }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

echo "== System"
uname -sm
if grep -qi microsoft /proc/version 2>/dev/null; then ok "running inside WSL"; fi
for b in git jq curl; do command -v "$b" >/dev/null && ok "$b found" || bad "$b missing (needed by hooks/scripts)"; done
command -v rg >/dev/null && ok "ripgrep found" || wn "ripgrep missing (Claude Code bundles one; fine)"

echo "== Claude Code"
if command -v claude >/dev/null; then
  ok "claude on PATH: $(command -v claude)"
  v="$(claude --version 2>/dev/null | awk '{print $1}')"; [ -n "$v" ] && ok "claude --version = $v" || bad "claude --version failed"
  n="$(type -a claude 2>/dev/null | grep -c 'claude is')"; [ "${n:-1}" -gt 1 ] && wn "more than one 'claude' on PATH (type -a claude) — remove the old one"
else
  bad "claude not on PATH (native installer puts it in ~/.local/bin)"
fi
for f in "$HOME/.claude/settings.json" ".claude/settings.json" ".claude/settings.local.json"; do
  [ -f "$f" ] || continue
  if jq empty "$f" 2>/dev/null; then ok "valid JSON: $f"; else bad "invalid JSON: $f"; fi
  if jq -e '.permissions.defaultMode=="bypassPermissions"' "$f" >/dev/null 2>&1; then wn "$f sets bypassPermissions"; fi
done
if [ -d .claude/hooks ]; then
  for h in .claude/hooks/*.sh; do [ -x "$h" ] && ok "hook executable: $h" || bad "hook not executable: $h (chmod +x)"; done
fi
[ -n "${ANTHROPIC_API_KEY:-}" ] && wn "ANTHROPIC_API_KEY is set in this shell — Claude Code will bill the API key, not your subscription, if you approve it"

echo "== Node / OpenClaw"
if command -v node >/dev/null; then
  nv="$(node -v | tr -d v)"
  if { [ "${nv%%.*}" = 24 ] && ver_ge "$nv" 24.22.1; } || ver_ge "$nv" 26.12.1; then ok "node $nv (meets OpenClaw requirement)"; else wn "node $nv — OpenClaw needs >=24.22.1 <25 or >=26.12.1"; fi
else
  wn "node not found (needed for OpenClaw npm install)"
fi
if command -v openclaw >/dev/null; then
  ok "openclaw: $(openclaw --version 2>/dev/null | head -1)"
  if openclaw config validate >/dev/null 2>&1; then ok "openclaw config validate"; else bad "openclaw config validate failed — run: openclaw config validate"; fi
  cfg="$(openclaw config file 2>/dev/null | tail -1)"
  if [ -f "$cfg" ]; then
    perms="$(stat -c %a "$cfg" 2>/dev/null || stat -f %Lp "$cfg" 2>/dev/null)"
    [ "$perms" = 600 ] && ok "config permissions 600" || wn "config permissions $perms — run: chmod 600 $cfg"
    grep -Eq 'bind:[[:space:]]*"?(lan|custom|auto)|"bind":[[:space:]]*"(lan|custom|auto)"' "$cfg" && bad "gateway.bind is not loopback — read the exposure runbook first"
    grep -Eq 'dmPolicy:[[:space:]]*"open"|"dmPolicy":[[:space:]]*"open"' "$cfg" && bad "a channel uses dmPolicy \"open\" — anyone can message your agent"
    grep -Eq '"profile":[[:space:]]*"full"|profile:[[:space:]]*"full"' "$cfg" && wn "tools.profile is \"full\" — consider \"messaging\" or \"coding\""
  fi
  [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ] && [ "${#OPENCLAW_GATEWAY_TOKEN}" -lt 32 ] && wn "OPENCLAW_GATEWAY_TOKEN is short (<32 chars)"
else
  wn "openclaw not installed (skip if you only use Claude Code)"
fi

echo "== Result: $pass pass, $warn warn, $fail fail"
exit "$fail"

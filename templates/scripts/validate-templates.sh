#!/usr/bin/env bash
# Lints every template in this pack: JSON parses, settings match the published
# Claude Code schema (if python3 + jsonschema are available), SKILL.md/agent
# frontmatter is valid YAML with name+description, hooks pass their self-test,
# and OpenClaw JSON5 configs pass `openclaw config validate` (if installed).
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0; pass=0
ok(){ echo "  PASS  $*"; pass=$((pass+1)); }
bad(){ echo "  FAIL  $*"; fail=$((fail+1)); }

echo "== JSON files"
while IFS= read -r f; do
  if jq empty "$f" 2>/dev/null; then ok "${f#$root/}"; else bad "${f#$root/} is not valid JSON"; fi
done < <(find "$root" -name '*.json' -not -path '*/node_modules/*' | sort)

echo "== Claude Code settings vs schema"
if command -v python3 >/dev/null && python3 -c 'import jsonschema' 2>/dev/null; then
  schema="${CLAUDE_SETTINGS_SCHEMA:-}"
  if [ -z "$schema" ]; then schema="$(mktemp)"; curl -fsSL https://json.schemastore.org/claude-code-settings.json -o "$schema" || schema=""; fi
  if [ -n "$schema" ]; then
    for f in "$root"/claude-code/settings/*.json; do
      if python3 - "$schema" "$f" <<'PY'
import json,sys,jsonschema
s=json.load(open(sys.argv[1])); d=json.load(open(sys.argv[2]))
errs=list(jsonschema.Draft7Validator(s).iter_errors(d))
for e in errs: print("     ", "/".join(map(str,e.path)), e.message[:160])
sys.exit(1 if errs else 0)
PY
      then ok "schema: ${f#$root/}"; else bad "schema: ${f#$root/}"; fi
    done
  else echo "  SKIP  could not download schema"; fi
else
  echo "  SKIP  python3 jsonschema not installed (pip install jsonschema)"
fi

echo "== Frontmatter (skills + subagents)"
python3 -c "import yaml" 2>/dev/null || echo "  NOTE  pyyaml not installed - using basic frontmatter check (pip install pyyaml for a full YAML parse)"
while IFS= read -r f; do
  if python3 - "$f" <<'PY'
import sys,re
t=open(sys.argv[1],encoding="utf-8").read()
m=re.match(r"^---\n(.*?)\n---\n",t,re.S)
if not m: print("      no frontmatter"); sys.exit(1)
try:
    import yaml
    d=yaml.safe_load(m.group(1))
except ImportError:
    # basic fallback: top-level "key: value" lines only
    d={k:v.strip() for k,v in re.findall(r"^([A-Za-z_-]+):[ \t]*(.*)$",m.group(1),re.M)}
miss=[k for k in("name","description") if not d.get(k)]
if miss: print("      missing",miss); sys.exit(1)
if not re.fullmatch(r"[a-z0-9-]+",d["name"]): print("      bad name",d["name"]); sys.exit(1)
PY
  then ok "${f#$root/}"; else bad "${f#$root/}"; fi
done < <(find "$root" \( -name SKILL.md -o -path '*/agents/*.md' \) | sort)

echo "== Hook self-test"
if bash "$root/claude-code/hooks/test-hooks.sh" >/tmp/hooktest.$$ 2>&1; then ok "test-hooks.sh ($(grep -c '^ok' /tmp/hooktest.$$) cases)"; else bad "test-hooks.sh"; cat /tmp/hooktest.$$; fi
rm -f /tmp/hooktest.$$

echo "== Shell syntax"
for s in "$root"/scripts/*.sh "$root"/claude-code/hooks/*.sh "$root"/claude-code/statusline/*.sh; do
  bash -n "$s" && ok "bash -n ${s#$root/}" || bad "bash -n ${s#$root/}"
done
if command -v shellcheck >/dev/null; then
  shellcheck -S error "$root"/scripts/*.sh "$root"/claude-code/hooks/*.sh "$root"/claude-code/statusline/*.sh && ok "shellcheck (errors)" || bad "shellcheck"
fi

echo "== OpenClaw configs"
if command -v openclaw >/dev/null; then
  export OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-validate-only-placeholder-token-0000000000000000}"
  tmp="$(mktemp -d)"
  for f in "$root"/openclaw/*.json5; do
    cp "$f" "$tmp/openclaw.json"
    if OPENCLAW_CONFIG_PATH="$tmp/openclaw.json" OPENCLAW_STATE_DIR="$tmp/state" openclaw config validate >"$tmp/out" 2>&1; then ok "openclaw config validate ${f#$root/}"; else bad "${f#$root/}"; sed 's/^/      /' "$tmp/out"; fi
  done
  rm -rf "$tmp"
else
  echo "  SKIP  openclaw not installed"
fi

echo "== Result: $pass pass, $fail fail"
exit "$fail"

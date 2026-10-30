#!/usr/bin/env bash
# Copies a settings preset + hooks + subagents + skills into a project's .claude/ folder.
# Usage: ./apply-claude-preset.sh <strict|balanced|power> <project-dir>
# Never overwrites an existing file unless you pass FORCE=1.
set -euo pipefail
preset="${1:-}"; proj="${2:-}"
here="$(cd "$(dirname "$0")/.." && pwd)"
case "$preset" in strict|balanced|power) ;; *) echo "usage: $0 <strict|balanced|power> <project-dir>" >&2; exit 64;; esac
[ -d "$proj" ] || { echo "project dir not found: $proj" >&2; exit 66; }
dst="$proj/.claude"
mkdir -p "$dst/hooks" "$dst/agents" "$dst/skills"

copy() { # src dst
  if [ -e "$2" ] && [ "${FORCE:-0}" != "1" ]; then echo "skip (exists): $2"; else cp -R "$1" "$2"; echo "wrote: $2"; fi
}
copy "$here/claude-code/settings/project-$preset.json" "$dst/settings.json"
for h in "$here"/claude-code/hooks/*.sh; do copy "$h" "$dst/hooks/$(basename "$h")"; done
chmod +x "$dst"/hooks/*.sh
for a in "$here"/claude-code/agents/*.md; do copy "$a" "$dst/agents/$(basename "$a")"; done
for s in "$here"/claude-code/skills/*/; do copy "${s%/}" "$dst/skills/$(basename "$s")"; done

# keep personal files out of git
gi="$proj/.gitignore"
for line in ".claude/settings.local.json" "CLAUDE.local.md"; do
  grep -qxF "$line" "$gi" 2>/dev/null || echo "$line" >> "$gi"
done
echo "Done. Next: copy a CLAUDE.md template into $proj and edit the Commands section."
command -v jq >/dev/null 2>&1 || echo "WARNING: jq not found — the hooks need it (brew install jq / sudo apt install jq)."

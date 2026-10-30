#!/usr/bin/env bash
# Claude Code status line: model | context used | session cost estimate.
# Install: copy to ~/.claude/statusline.sh, chmod +x, and add the "statusLine"
# block from settings/user-settings.json. Requires: jq.
input="$(cat)"
model="$(printf '%s' "$input" | jq -r '.model.display_name // "?"')"
ctx="$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)"
cost="$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // 0')"
dir="$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""')"
warn=""
[ "${ctx:-0}" -ge 70 ] 2>/dev/null && warn=" ⚠ consider /compact or /clear"
printf '[%s] %s | ctx %s%% | ~$%.2f%s\n' "$model" "$(basename "$dir")" "$ctx" "$cost" "$warn"

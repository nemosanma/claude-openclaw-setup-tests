# Templates pack: Claude Code + OpenClaw, 60-Minute Secure Setup

Companion files for the PDF guide. Tested 2026-10-29 with Claude Code 2.1.312 and OpenClaw 2026.10.8.

## Quick use

```bash
# from the folder that contains templates/
bash templates/scripts/validate-templates.sh          # lint everything (optional: pip install jsonschema pyyaml)
bash templates/scripts/apply-claude-preset.sh balanced ~/code/my-app
openclaw config patch --file templates/openclaw/openclaw.safe-baseline.json5 --dry-run
bash templates/scripts/verify-setup.sh                # read-only health check
```

| Folder | What |
|---|---|
| `claude-code/claude-md/` | CLAUDE.md templates: global, web app, Python, research/writing, local |
| `claude-code/settings/` | `user-settings.json` (~/.claude) + project presets strict / balanced / power |
| `claude-code/hooks/` | guard-bash, protect-files, format-after-edit, notify-done + `test-hooks.sh` |
| `claude-code/statusline/` | model · context % · estimated cost |
| `claude-code/agents/` | code-reviewer, researcher (haiku), test-runner |
| `claude-code/skills/` | research-brief, repo-maintenance, daily-digest, release-notes |
| `claude-code/mcp/` | example `.mcp.json` (env-var secrets, approval required) |
| `openclaw/` | safe-baseline and telegram-assistant configs (JSON5), `.env.example`, AGENTS safety addendum, 4 workspace skills |
| `scripts/` | verify-setup, validate-templates, apply-claude-preset, gen-gateway-token, skill-audit |
| `workflows/` | the 10 workflows as copy-paste prompts |

Requirements: bash, jq, git. Windows users: run in WSL 2.

License: MIT (see LICENSE) for everything in this folder. Not affiliated with Anthropic or the OpenClaw project.

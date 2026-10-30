---
name: repo-maintenance
description: Weekly repository hygiene pass - outdated dependencies, failing checks, stale branches, and TODO triage - reported as a checklist. Use when the user asks for repo maintenance or a health check.
disable-model-invocation: true
---

# Repository maintenance pass

Work through these steps and write the result to `MAINTENANCE.md` (overwrite):

1. **Checks** — run the lint, type check, and test commands from CLAUDE.md. Record pass/fail.
2. **Dependencies** — run the read-only outdated command (`npm outdated`, `uv pip list --outdated`, or `pip list --outdated`). List major-version bumps separately; do **not** upgrade anything.
3. **Security** — run `npm audit --omit=dev` or `pip-audit` if installed. Summarise high/critical only.
4. **Branches** — `git branch --merged` (excluding main/master) → candidates to delete. Do not delete.
5. **TODOs** — `rg -n "TODO|FIXME|HACK"` → group by file, flag any older than the last release tag if dates are present.
6. **Summary** — a checklist of suggested actions ordered by risk, each with the exact command the user can run.

This skill is read-only: never commit, push, delete branches, or upgrade packages.

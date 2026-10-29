---
name: release-notes
description: Draft user-facing release notes from git history since the last tag. Use when the user is preparing a release or asks what changed since the last version.
disable-model-invocation: true
---

# Release notes

1. Find the last tag: `git describe --tags --abbrev=0` (if none, use the first commit).
2. Collect commits: `git log <tag>..HEAD --pretty=format:'%h %s' --no-merges`.
   Run each git command on its own, with the tag typed in literally. Don't nest commands with `$(...)`: Claude Code asks for approval before running nested commands, and in headless (`-p`) mode that means they're refused.
3. Group into **New**, **Improved**, **Fixed**, **Breaking changes**, **Internal** (internal = refactors, CI, chores; keep it short).
4. Rewrite each item for users: what they can now do, not how the code changed.
5. Write to `RELEASE_NOTES_DRAFT.md`. Do not create tags, releases, or commits.

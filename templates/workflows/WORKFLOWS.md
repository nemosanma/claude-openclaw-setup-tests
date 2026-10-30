# 10 workflows: copy-paste prompts

See the guide, Chapter 9, for setup, safety notes and cost notes.

1. **Daily digest** (Claude Code)
   `/daily-digest  Use ~/inbox as the input folder.`

2. **Weekly repo maintenance** (Claude Code)
   `/repo-maintenance`

3. **Research brief** (Claude Code or OpenClaw)
   `/research-brief  <your question>. Audience: <who>. Use 3-5 primary sources.`

4. **Review before commit** (Claude Code)
   `Use the code-reviewer subagent on my staged changes.`

5. **Test failure triage** (Claude Code)
   `Use the test-runner subagent: run the tests and tell me the smallest set of failures and their likely causes. Don't fix anything yet.`

6. **Release notes** (Claude Code)
   `/release-notes`

7. **Inbox triage** (OpenClaw on Telegram)
   `/inbox-triage` and then paste or forward the messages. Approve drafts with "send 2", or edit them with "edit 3: …".

8. **Weekly review** (OpenClaw)
   `/weekly-review`

9. **Nightly headless report with a budget** (Claude Code + cron)
   ```cron
   0 7 * * * cd $HOME/code/my-app && $HOME/.local/bin/claude -p "Summarise yesterday's commits (git log --since=yesterday) and any TODOs added. Write to reports/$(date +\%F).md" --max-turns 8 --max-budget-usd 0.40 --permission-mode dontAsk --allowedTools "Read,Grep,Glob,Write,Bash(git log *)" >> $HOME/claude-cron.log 2>&1
   ```

10. **Codebase onboarding tour** (Claude Code)
    `Use the researcher subagent to map this repository: entry points, main modules, data flow, where config is loaded, and how tests are organised. Then write ARCHITECTURE.md (under 150 lines) with path references, and propose 5 additions to CLAUDE.md.`

# Claude Code + OpenClaw setup tests

Public test harness and MIT-licensed templates for the setup guide **Claude Code + OpenClaw: The 60-Minute Secure Setup**.

This repository is an independent project. It is **not affiliated with, endorsed by, or maintained by Anthropic PBC or the OpenClaw project**. Trademarks belong to their owners.

The guide text itself is not in this repository. What is here:

- `templates/` — the MIT-licensed template pack (Claude Code settings presets, hooks, CLAUDE.md files, OpenClaw safe config, starter skills, and the template validator).
- `.github/workflows/setup-guide.yml` — installs Claude Code and OpenClaw the way the guide describes, on `ubuntu-latest`, `macos-latest`, and `windows-latest`, with no API keys and no repository secrets.

## What CI checks

On each operating system the workflow follows that platform's install path from the guide:

1. Prerequisites (`git`, `curl`, `jq`; Node via Homebrew on macOS, and via the OpenClaw installer on Linux and Windows).
2. Claude Code's official native installer (`install.sh` on macOS/Linux, `install.ps1` on Windows).
3. `claude --version` and `claude doctor`, without logging in.
4. OpenClaw's official installer (`--no-onboard` on Unix; `OPENCLAW_NO_ONBOARD=1` on Windows so the wizard does not wait for a terminal).
5. A generated gateway token, then non-interactive `openclaw onboard` with `--auth-choice skip`.
6. `openclaw config patch` of `templates/openclaw/openclaw.safe-baseline.json5`, then `openclaw config validate`.
7. Gateway start, `gateway status`, `health`, `status`, `security audit`, then stop.
8. `openclaw doctor` only after the gateway is stopped.
9. `templates/scripts/validate-templates.sh` and `templates/claude-code/hooks/test-hooks.sh` (25 cases).

Each job writes `test-summary.md` into the job summary and uploads it as the artifact `setup-summary-<os>`. The summary lists pass/fail per step and the tool versions that were actually installed.

## CI adaptations (not extra guide steps)

Runners have no TTY and no browser login. The workflow therefore:

- Passes `--no-prompt` to the Unix OpenClaw installer. The guide documents that flag for automation.
- Sets `OPENCLAW_NO_ONBOARD=1` before the Windows one-liner `iwr -useb https://openclaw.ai/install.ps1 | iex`, because that one-liner cannot take `-NoOnboard` and would start the interactive wizard.
- Refreshes `PATH` in the same shell after an installer. On a laptop the guide says to open a new terminal.
- Unsets `NPM_CONFIG_PREFIX` when the runner has one, which is the gotcha in guide section 1.4.
- On macOS, prepends Homebrew's `bin` so `brew install node` is the `node` on `PATH`. GitHub-hosted macOS images also put a toolcache Node on `PATH`.
- On native Windows, runs the Bash hook suite and `validate-templates.sh` with Git Bash when it is available, and records that as a port. The guide tells Windows readers to use WSL 2 for these scripts.
- Probes `wsl --status` on the Windows runner and records the result. It does not run `wsl --install` (that needs a reboot and a hypervisor).

No `*_API_KEY` variables are set. Jobs do not use repository secrets.

## What this does not test

Signing in to Claude, any real model call, a real Telegram/WhatsApp/Discord bot, ClawHub installs, `openclaw gateway install` as a system service, Docker sandboxing, and Tailscale. Those need credentials or machine features these runners do not have.

## License

MIT. See [LICENSE](LICENSE) and [templates/LICENSE](templates/LICENSE).

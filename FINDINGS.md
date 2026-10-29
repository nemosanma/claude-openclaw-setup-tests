# Findings from the cross-platform CI runs

Run that produced these failures: https://github.com/nemosanma/claude-openclaw-setup-tests/actions/runs/40855165275 (2026-10-29).

Claude Code **2.1.312** installed with the guide's native installer and `claude doctor` reported no invalid settings on Ubuntu, macOS, and Windows, with no API key. The failures below are OpenClaw's Node requirement, the Windows PATH note, and one template script that assumes a UTF-8 locale.

Hook self-tests were **25 cases, 0 failed** on Ubuntu and on macOS (system `grep`, including the `\b` patterns). On Windows, Git Bash also reported `test-hooks.sh (25 cases)` inside `validate-templates.sh` before the schema step crashed (see below).

## macOS: `brew install node` installed Node 26.12.0, which OpenClaw 2026.10.8 rejects

Exact commands (guide sections 1.4 and 5.1):

```bash
brew install git jq node
node -v
curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard --no-prompt
```

`node -v` was **v26.12.0** at `/opt/homebrew/bin/node` (Homebrew bottle `node 26.12.0`, macOS arm64 runner, 2026-10-29). The installer found that Node, then npm failed:

```text
npm error [openclaw] error: this OpenClaw release requires Node >=24.22.1 <25 || >=26.12.1.
npm error [openclaw] detected Node 26.12.0 (exec: /opt/homebrew/Cellar/node/26.12.0/bin/node).
npm error [openclaw] install Node: https://nodejs.org/en/download
npm error [openclaw] upgrade Node, then retry the OpenClaw update.
```

`verify-setup.sh` warned the same way: `node 26.12.0 — OpenClaw needs >=24.22.1 <25 or >=26.12.1`.

Suggested replacement for the macOS prerequisite block in section 1.4:

```bash
brew install git jq
# Homebrew's "node" formula tracks the current release, not a pinned LTS.
# On 2026-10-29 it installed 26.12.0. OpenClaw 2026.10.8 requires
# >=24.22.1 on the 24.x line, or >=26.12.1. 26.12.0 is not enough.
brew install node
node -v
```

Add this gotcha next to the `NPM_CONFIG_PREFIX` note:

> **Found in testing (macOS, 2026-10-29):** `brew install node` produced **v26.12.0**. The OpenClaw installer then stopped with `this OpenClaw release requires Node >=24.22.1 <25 || >=26.12.1` and `detected Node 26.12.0`. If `node -v` is outside that range, install Node 24 from https://nodejs.org/en/download (24.22.2 was current that day) or `nvm install 24`, and put that `bin` directory ahead of `/opt/homebrew/bin` on `PATH`. Do not assume the Homebrew `node` bottle is new enough.

## Linux: the OpenClaw installer does not install Node when nvm is already present

Exact command (guide section 5.1, plus the guide's automation flag):

```bash
curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard --no-prompt
```

GitHub-hosted Ubuntu already had **Node v22.23.4** at `/usr/local/bin/node` and an nvm directory. The installer exited 1 immediately:

```text
Node.js v22.23.4 found, upgrading to a supported version
! Existing nvm detected; no compatible Node.js runtime is available
Load your existing nvm in your shell, then run:
  nvm install 26
  nvm use 26
nvm install can refresh LTS aliases; check your default with: nvm version default
Then rerun the installer. Shell profiles will not be changed.
✗ Installation stopped without changing Node.js; run the nvm commands above to continue
```

Section 1.4 says the installer "provisions Node 24 LTS on Linux when missing". That happens only when `node` is absent and nvm is not installed. If `~/.nvm` exists, a non-interactive run (no TTY, or `--no-prompt`) does not install Node 24 and does not run `nvm install` for you. It tells you to install **Node 26**, not Node 24.

Suggested replacement for the Node sentence in section 1.4:

> Check `node -v` before installing OpenClaw. You need **24.22.1 or newer on the 24.x line, or 26.12.1 or newer**. On Linux the OpenClaw installer installs Node 24 from NodeSource only when `node` is missing and nvm is not installed. If `~/.nvm` exists and the active Node is too old, the installer stops and prints `nvm install 26` and `nvm use 26`. It will not change your Node unless you are at an interactive terminal and answer yes. In a script, install a supported Node first (`nvm install 24 && nvm use 24`, or the NodeSource Node 24 setup), then rerun `curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard --no-prompt`.

## Windows: the native Claude Code installer does not put `claude` on PATH

Exact command (guide section 2.1):

```powershell
irm https://claude.ai/install.ps1 | iex
```

The installer succeeded (Claude Code 2.1.312 at `C:\Users\runneradmin\.local\bin\claude.exe`) and printed:

```text
Native installation exists but C:\Users\runneradmin\.local\bin is not in your PATH.
Add it by opening: System Properties → Environment Variables → Edit User PATH → New → Add the path above. Then restart your terminal.
```

The troubleshooting table only shows `export PATH="$HOME/.local/bin:$PATH"` in `~/.bashrc` or `~/.zshrc`. That does not apply to the PowerShell installer.

Suggested addition under the Windows PowerShell block in section 2.1:

```powershell
# If `claude` is not recognized, the installer used %USERPROFILE%\.local\bin and did not put it on PATH.
$claudeBin = Join-Path $env:USERPROFILE ".local\bin"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$claudeBin*") {
  [Environment]::SetEnvironmentVariable("Path", "$claudeBin;$userPath", "User")
}
$env:Path = "$claudeBin;$env:Path"
claude --version
```

The Windows OpenClaw installer (`iwr -useb https://openclaw.ai/install.ps1 | iex` with `OPENCLAW_NO_ONBOARD=1`) did install OpenClaw 2026.10.8. It replaced the runner's Node 22.23.4 with **Node 26.13.0** via `winget install OpenJS.NodeJS.LTS`, which meets the floor. The guide's one-liner cannot take `-NoOnboard`; without `OPENCLAW_NO_ONBOARD=1` it starts the interactive wizard.

## Windows: `openclaw.cmd` fails with `'"node"' is not recognized` when started from `cmd /c`

After `iwr -useb https://openclaw.ai/install.ps1 | iex` with `OPENCLAW_NO_ONBOARD=1`, OpenClaw 2026.10.8 was installed. Running the npm shim through another `cmd.exe /c` (what many automation hosts do) failed every time:

```text
'"node"' is not recognized as an internal or external command,
operable program or batch file.
```

The quotes are part of the program name. npm's generated `openclaw.cmd` uses an `endlocal & goto` trick that breaks when the shim is not `CALL`ed from an interactive prompt. In a normal PowerShell window, `openclaw --version` can still work. From a script that goes through `cmd /c`, it does not.

The CI run that went green calls the package entry with `node.exe` instead of the shim:

```text
node "%APPDATA%\npm\node_modules\openclaw\<bin from package.json>" --version
```

Suggested addition to the Windows OpenClaw install note:

> If `openclaw` prints `'"node"' is not recognized`, you are hitting the npm cmd shim from inside `cmd /c`. Open a new PowerShell window and try again. From a script, run `node` on the package entry under `%APPDATA%\npm\node_modules\openclaw\` (the `bin` field in its `package.json`) instead of `openclaw.cmd`.

## Windows: `validate-templates.sh` schema check crashes under Windows Python

`templates/scripts/validate-templates.sh` opens the settings schema with `json.load(open(path))` and no encoding. Under Git Bash on the Windows runner, Python 3.12 used cp1252 and the SchemaStore file failed:

```text
UnicodeDecodeError: 'charmap' codec can't decode byte 0x90 in position 76522
FAIL  schema: claude-code/settings/project-balanced.json
FAIL  schema: claude-code/settings/project-power.json
FAIL  schema: claude-code/settings/project-strict.json
FAIL  schema: claude-code/settings/user-settings.json
```

The same files passed `claude doctor` and the schema check on Ubuntu (UTF-8). The guide tells Windows readers to run these scripts in WSL 2, where the locale is UTF-8, so this does not show up on the recommended path.

Suggested change inside the schema Python in `templates/scripts/validate-templates.sh`:

```python
s=json.load(open(sys.argv[1], encoding="utf-8"))
d=json.load(open(sys.argv[2], encoding="utf-8"))
```

## What hosted runners could not test

- **WSL 2 Ubuntu.** `wsl.exe --status` on `windows-latest` reports Windows Subsystem for Linux, and `wsl -e uname` fails with `Windows Subsystem for Linux has no installed distributions.` `wsl --install -d Ubuntu` needs a reboot and a hypervisor, so the guide's recommended Windows path was not executed. Native PowerShell was tested instead. Bash hooks were run with Git Bash, which is not the guide's supported Windows path.
- Signing in to Claude, any real model call, real Telegram/WhatsApp/Discord pairing, ClawHub installs, `openclaw gateway install` as a system service, Docker/Podman sandboxing, and Tailscale.
- `chmod 700` / `chmod 600` have no guide equivalent for native NTFS. The scripts that use them are bash and are specified for WSL.

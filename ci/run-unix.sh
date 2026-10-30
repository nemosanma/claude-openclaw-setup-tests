#!/usr/bin/env bash
# Reproduce the Claude Code + OpenClaw setup guide on Linux and macOS.
# Windows uses ci/run-windows.ps1. No API keys. Exit code = number of failed steps.
#
# Guide commands this script runs (automation flags the guide already documents
# are called out in the summary notes):
#   brew install git jq node                          (macOS, section 1.4)
#   sudo apt install git curl jq                      (Linux, section 1.4)
#   curl -fsSL https://claude.ai/install.sh | bash   (section 2.1)
#   claude --version && claude doctor                (section 2.3)
#   curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard --no-prompt
#   templates/scripts/gen-gateway-token.sh            (section 5.2)
#   openclaw onboard --non-interactive ...            (section 5.3)
#   openclaw config patch --file ...safe-baseline.json5
#   openclaw gateway run / status / health / doctor / security audit
#   templates/claude-code/hooks/test-hooks.sh
#   templates/scripts/validate-templates.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

logdir="$ROOT/ci-logs"
mkdir -p "$logdir"
: >"$logdir/results.tsv"
: >"$logdir/failure-blocks.md"
: >"$logdir/notes.md"

fail_count=0
step_n=0
summary_done=0
GW_PID=""
OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"

uname_s="$(uname -s)"
case "$uname_s" in
  Darwin) platform="macos" ;;
  Linux) platform="linux" ;;
  *) platform="other" ;;
esac

note() { printf '%s\n' "- $*" >>"$logdir/notes.md"; }

oneline() {
  printf '%s' "$1" | tr '\n\r\t|' '    ' | sed 's/  */ /g' | cut -c1-500
}

mklog() {
  printf '%s/%02d-%s.log' "$logdir" "$1" "$(printf '%s' "$2" | tr -c 'A-Za-z0-9' '-' | cut -c1-50)"
}

append_result() {
  n="$1"
  status="$2"
  name="$3"
  detail="$4"
  if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    detail="$(printf '%s' "$detail" | sed "s/${OPENCLAW_GATEWAY_TOKEN}/***REDACTED***/g")"
  fi
  printf '%s\t%s\t%s\t%s\n' "$n" "$status" "$name" "$(oneline "$detail")" >>"$logdir/results.tsv"
  printf '[%s] %02d %s\n' "$status" "$n" "$name"
  if [ "$status" = "FAIL" ]; then
    fail_count=$((fail_count + 1))
    {
      printf '\n### %s (step %s)\n\n```\n' "$name" "$n"
      printf '%s\n' "$detail" | tail -c 2500
      printf '\n```\n'
    } >>"$logdir/failure-blocks.md"
  fi
}

# Portable command timeout. Exit 124 on timeout, 127 if the command is missing.
run_with_timeout() {
  _to="$1"
  shift
  python3 - "$_to" "$@" <<'PY'
import subprocess, sys
timeout = int(sys.argv[1])
cmd = sys.argv[2:]
try:
    completed = subprocess.run(cmd, timeout=timeout)
except subprocess.TimeoutExpired:
    sys.exit(124)
except FileNotFoundError:
    sys.stderr.write("command not found: %s\n" % (cmd[0] if cmd else ""))
    sys.exit(127)
code = completed.returncode
if code is None:
    code = 1
if code < 0:
    code = 128 + (-code)
sys.exit(code)
PY
}

run_step() {
  name="$1"
  timeout="$2"
  shift 2
  step_n=$((step_n + 1))
  log="$(mklog "$step_n" "$name")"
  printf '+ (%ss) %s\n' "$timeout" "$*" >"$log"
  run_with_timeout "$timeout" "$@" >>"$log" 2>&1
  ec=$?
  detail="$(tail -c 1500 "$log" 2>/dev/null || true)"
  if [ "$ec" -eq 0 ]; then
    append_result "$step_n" PASS "$name" "exit 0. $detail"
  else
    append_result "$step_n" FAIL "$name" "exit $ec. $detail"
  fi
}

run_optional() {
  name="$1"
  timeout="$2"
  shift 2
  step_n=$((step_n + 1))
  log="$(mklog "$step_n" "$name")"
  printf '+ (%ss) %s\n' "$timeout" "$*" >"$log"
  run_with_timeout "$timeout" "$@" >>"$log" 2>&1
  ec=$?
  detail="$(tail -c 800 "$log" 2>/dev/null || true)"
  if [ "$ec" -eq 0 ]; then
    append_result "$step_n" PASS "$name" "exit 0. $detail"
  else
    append_result "$step_n" SKIP "$name" "optional; exit $ec. $detail"
  fi
}

prepend_path() {
  dir="${1%/}"
  if [ -n "$dir" ] && [ -d "$dir" ]; then
    PATH="$dir:$PATH"
    export PATH
  fi
}

adopt_tool_paths() {
  if command -v brew >/dev/null 2>&1; then
    bp="$(brew --prefix 2>/dev/null || true)"
    if [ -n "${bp:-}" ]; then
      prepend_path "$bp/bin"
      prepend_path "$bp/opt/node/bin"
    fi
  fi
  prepend_path "$HOME/.openclaw/tools/node/bin"
  hash -r 2>/dev/null || true
  if command -v npm >/dev/null 2>&1; then
    np="$(npm prefix -g 2>/dev/null || true)"
    if [ -n "${np:-}" ]; then
      prepend_path "$np/bin"
    fi
  fi
  prepend_path "$HOME/.local/bin"
  # Official Node unpacked by ensure_supported_node must stay ahead of Homebrew's node.
  prepend_path "$HOME/.local/node/bin"
  hash -r 2>/dev/null || true
}

# OpenClaw 2026.10.8 accepts only Node >=24.22.1 <25 or >=26.12.1.
node_meets_openclaw() {
  command -v node >/dev/null 2>&1 || return 1
  node -e 'const p=process.versions.node.split(".").map(Number); const [M,m,pat]=p; const t=(M*1000000)+(m*1000)+pat; const ok=(M===24 && t>=24022001) || t>=26012001; process.exit(ok?0:1)'
}

install_official_node_24() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) plat="linux-x64" ;;
    Linux-aarch64|Linux-arm64) plat="linux-arm64" ;;
    Darwin-arm64) plat="darwin-arm64" ;;
    Darwin-x86_64) plat="darwin-x64" ;;
    *) echo "no official Node build for $(uname -s)-$(uname -m)"; return 1 ;;
  esac
  sums="$(curl -fsSL https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt)"
  file="$(printf '%s\n' "$sums" | awk -v p="$plat" 'index($2, p ".tar.gz") {print $2; exit}')"
  ver="$(printf '%s' "$file" | sed -E 's/^node-v([0-9.]+)-.*/\1/')"
  if [ -z "$ver" ] || [ -z "$file" ]; then
    echo "could not resolve latest Node 24 tarball"
    return 1
  fi
  echo "downloading https://nodejs.org/dist/v${ver}/${file}"
  curl -fsSL "https://nodejs.org/dist/v${ver}/${file}" -o "/tmp/${file}"
  rm -rf "$HOME/.local/node"
  mkdir -p "$HOME/.local/node"
  tar -xzf "/tmp/${file}" -C "$HOME/.local/node" --strip-components=1
  prepend_path "$HOME/.local/node/bin"
  hash -r 2>/dev/null || true
  echo "official node now $(node -v) ($(command -v node))"
}

stop_gateway() {
  if [ -n "${GW_PID:-}" ]; then
    pkill -P "$GW_PID" 2>/dev/null || true
    kill "$GW_PID" 2>/dev/null || true
    sleep 2
    kill -9 "$GW_PID" 2>/dev/null || true
    i=0
    while [ "$i" -lt 15 ]; do
      if ! kill -0 "$GW_PID" 2>/dev/null; then
        break
      fi
      sleep 1
      i=$((i + 1))
    done
  fi
  if command -v openclaw >/dev/null 2>&1; then
    openclaw gateway stop >"$logdir/gateway-stop.txt" 2>&1 || true
  fi
  GW_PID=""
}

scrub_logs() {
  if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    return 0
  fi
  python3 - "$logdir" "$OPENCLAW_GATEWAY_TOKEN" <<'PY'
import os, sys
root, tok = sys.argv[1], sys.argv[2]
for dirpath, _, files in os.walk(root):
    for name in files:
        path = os.path.join(dirpath, name)
        try:
            data = open(path, "r", errors="replace").read()
        except OSError:
            continue
        if tok in data:
            open(path, "w").write(data.replace(tok, "***REDACTED***"))
PY
}

write_summary() {
  if [ "$summary_done" -eq 1 ]; then
    return 0
  fi
  summary_done=1
  scrub_logs || true
  {
    command -v git >/dev/null 2>&1 && git --version
    command -v node >/dev/null 2>&1 && { echo "node $(node -v) $(command -v node)"; }
    command -v npm >/dev/null 2>&1 && { echo "npm $(npm -v) $(command -v npm)"; echo "npm prefix -g: $(npm prefix -g 2>/dev/null || true)"; }
    command -v jq >/dev/null 2>&1 && jq --version
    command -v claude >/dev/null 2>&1 && claude --version
    command -v openclaw >/dev/null 2>&1 && openclaw --version
    echo "uname: $(uname -sm)"
    echo "runner: ${RUNNER_OS:-} ${RUNNER_ARCH:-} ${ImageOS:-} ${ImageVersion:-}"
  } >"$logdir/versions.txt" 2>&1 || true
  scrub_logs || true

  out="$ROOT/test-summary.md"
  {
    printf '# Setup guide test summary\n\n'
    printf -- '- Platform: `%s`\n' "$platform"
    printf -- '- When: `%s`\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
    printf -- '- Result: **%s** (%s failed)\n\n' "$([ "$fail_count" -eq 0 ] && printf PASS || printf FAIL)" "$fail_count"
    printf '## Tool versions\n\n```\n'
    cat "$logdir/versions.txt" 2>/dev/null || true
    printf '```\n\n## Steps\n\n'
    printf '| # | Result | Step | Detail |\n|---|---|---|---|\n'
    if [ -s "$logdir/results.tsv" ]; then
      while IFS="$(printf '\t')" read -r n status name detail; do
        [ -n "${n:-}" ] || continue
        printf '| %s | %s | %s | %s |\n' "$n" "$status" "$name" "$detail"
      done <"$logdir/results.tsv"
    fi
    printf '\n## CI notes\n\n'
    cat "$logdir/notes.md" 2>/dev/null || true
    if [ -s "$logdir/failure-blocks.md" ]; then
      printf '\n## Failure excerpts\n'
      cat "$logdir/failure-blocks.md"
    fi
  } >"$out"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat "$out" >>"$GITHUB_STEP_SUMMARY"
  fi
}

on_exit() {
  stop_gateway
  write_summary || true
}
trap on_exit EXIT

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
export NPM_CONFIG_FUND="${NPM_CONFIG_FUND:-false}"
export NPM_CONFIG_AUDIT="${NPM_CONFIG_AUDIT:-false}"
export NPM_CONFIG_UPDATE_NOTIFIER="${NPM_CONFIG_UPDATE_NOTIFIER:-false}"
if [ "$platform" = "macos" ]; then
  export HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"
  export HOMEBREW_NO_INSTALL_CLEANUP="${HOMEBREW_NO_INSTALL_CLEANUP:-1}"
  export HOMEBREW_NO_ENV_HINTS="${HOMEBREW_NO_ENV_HINTS:-1}"
  note "macOS: HOMEBREW_NO_AUTO_UPDATE=1 so brew does not spend the job updating itself. The install command is still \`brew install git jq node\`."
  note "macOS: after Homebrew installs Node, its bin directory is prepended to PATH. GitHub-hosted macOS images also prepend a toolcache Node; a normal Homebrew shell (\`brew shellenv\`) has Homebrew first."
fi
note "OpenClaw installer is run with \`--no-onboard --no-prompt\`. The guide's tested install is \`--no-onboard\`; \`--no-prompt\` is the guide's flag for CI/automation (section 5.1) and these runners have no TTY."
note "PATH is updated in this shell after each installer. The guide's fix for \`command not found\` is to open a new terminal after editing ~/.bashrc or ~/.zshrc."
note "Onboarding uses \`--auth-choice skip\` and a generated gateway token. No API key is set."
note "The gateway is started in the background (the guide runs it in a second terminal) and stopped before \`openclaw doctor\`."
note "If \`node -v\` is outside OpenClaw's range (>=24.22.1 on the 24.x line, or >=26.12.1), the harness downloads the current Node 24 tarball from nodejs.org into ~/.local/node and puts it first on PATH before the OpenClaw installer. The guide commands that produced the wrong Node are recorded in FINDINGS.md."

# Drop inherited API keys and a stray npm prefix (guide 1.4). Never print values.
key_names="$(env | awk -F= '/_API_KEY=/ {print $1}' | tr '\n' ' ' || true)"
if [ -n "${key_names:-}" ]; then
  # shellcheck disable=SC2086
  unset $key_names
  note "Unset inherited *_API_KEY variables before installing: ${key_names}"
fi
if [ -n "${NPM_CONFIG_PREFIX:-}${npm_config_prefix:-}" ]; then
  note "Unsetting NPM_CONFIG_PREFIX (was ${NPM_CONFIG_PREFIX:-${npm_config_prefix:-}}) per guide section 1.4."
  unset NPM_CONFIG_PREFIX
  unset npm_config_prefix || true
fi

step_n=$((step_n + 1))
if env | awk -F= '/_API_KEY=/ {found=1} END {exit !found}'; then
  append_result "$step_n" FAIL "no API keys in the environment" "a *_API_KEY variable is still set"
else
  append_result "$step_n" PASS "no API keys in the environment" "no *_API_KEY variables"
fi

if [ "$platform" = "macos" ]; then
  run_step "Prerequisites: brew install git jq node" 1800 brew install git jq node
  adopt_tool_paths
elif [ "$platform" = "linux" ]; then
  run_step "Prerequisites: apt-get update && apt-get install git curl jq" 600 bash -c 'sudo apt-get update && sudo apt-get install -y git curl jq ca-certificates'
else
  step_n=$((step_n + 1))
  append_result "$step_n" FAIL "Prerequisites" "unsupported uname: $uname_s"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "tool versions after prerequisites")"
{
  git --version 2>&1 || true
  jq --version 2>&1 || true
  curl --version 2>&1 | head -1 || true
  node -v 2>&1 || echo "node: not installed yet"
  command -v node 2>&1 || true
  npm -v 2>&1 || true
  npm prefix -g 2>&1 || true
} >"$log" 2>&1
append_result "$step_n" PASS "tool versions after prerequisites" "$(cat "$log")"

if [ "$platform" = "linux" ]; then
  run_optional "Validator extras: shellcheck python3-jsonschema python3-yaml" 300 sudo apt-get install -y shellcheck python3 python3-jsonschema python3-yaml
elif [ "$platform" = "macos" ]; then
  run_optional "Validator extras: brew install shellcheck" 600 brew install shellcheck
  run_optional "Validator extras: pip install jsonschema pyyaml" 300 python3 -m pip install --user --break-system-packages jsonschema pyyaml
fi

# --- Claude Code native installer (guide 2.1) ---
run_step "Claude Code native installer" 600 bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
adopt_tool_paths

step_n=$((step_n + 1))
log="$(mklog "$step_n" "claude version")"
printf '+ claude --version\n' >"$log"
if command -v claude >/dev/null 2>&1; then
  claude --version >>"$log" 2>&1
  ec=$?
  if [ "$ec" -eq 0 ]; then
    append_result "$step_n" PASS "claude --version" "$(cat "$log")"
  else
    append_result "$step_n" FAIL "claude --version" "exit $ec. $(cat "$log")"
  fi
else
  append_result "$step_n" FAIL "claude --version" "claude not on PATH after native install. PATH=$PATH"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "claude doctor")"
printf '+ claude doctor\n' >"$log"
run_with_timeout 180 claude doctor >>"$log" 2>&1
ec=$?
detail="$(tail -c 1500 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ] && ! grep -q 'Invalid settings' "$log"; then
  append_result "$step_n" PASS "claude doctor" "exit 0. $detail"
else
  append_result "$step_n" FAIL "claude doctor" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "claude auth status")"
printf '+ claude auth status\n' >"$log"
run_with_timeout 120 claude auth status >>"$log" 2>&1 || true
detail="$(cat "$log" 2>/dev/null || true)"
if printf '%s' "$detail" | grep -q 'loggedIn' && printf '%s' "$detail" | grep -q 'false'; then
  append_result "$step_n" PASS "claude auth status (expect logged out)" "$detail"
elif printf '%s' "$detail" | grep -q 'loggedIn' && printf '%s' "$detail" | grep -q 'true'; then
  append_result "$step_n" FAIL "claude auth status (expect logged out)" "unexpected login: $detail"
else
  append_result "$step_n" FAIL "claude auth status (expect logged out)" "$detail"
fi

# Guide 3.2
step_n=$((step_n + 1))
log="$(mklog "$step_n" "user settings")"
{
  echo "+ mkdir ~/.claude && cp user-settings.json statusline CLAUDE.md && claude doctor"
  mkdir -p "$HOME/.claude"
  cp templates/claude-code/settings/user-settings.json "$HOME/.claude/settings.json"
  cp templates/claude-code/statusline/statusline.sh "$HOME/.claude/statusline.sh"
  chmod +x "$HOME/.claude/statusline.sh"
  cp templates/claude-code/claude-md/CLAUDE.global.md "$HOME/.claude/CLAUDE.md"
} >"$log" 2>&1
run_with_timeout 180 claude doctor >>"$log" 2>&1
ec=$?
detail="$(tail -c 1500 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ] && ! grep -q 'Invalid settings' "$log"; then
  append_result "$step_n" PASS "user settings + claude doctor" "exit 0, no Invalid settings. $detail"
else
  append_result "$step_n" FAIL "user settings + claude doctor" "exit $ec. $detail"
fi

# The guide's own Node install can leave a version OpenClaw rejects (see FINDINGS.md).
# Put a Node 24 build from nodejs.org first on PATH, then run the installer unchanged.
step_n=$((step_n + 1))
log="$(mklog "$step_n" "node before openclaw")"
{
  echo "node before: $(node -v 2>/dev/null || echo missing) ($(command -v node 2>/dev/null || echo none))"
  if node_meets_openclaw; then
    echo "already meets OpenClaw >=24.22.1 <25 or >=26.12.1"
  else
    echo "installing official Node 24 because the guide's Node is outside OpenClaw's range"
    install_official_node_24
  fi
  echo "node after: $(node -v 2>/dev/null || echo missing) ($(command -v node 2>/dev/null || echo none))"
} >"$log" 2>&1
if node_meets_openclaw; then
  append_result "$step_n" PASS "Node meets OpenClaw before install" "$(cat "$log")"
else
  append_result "$step_n" FAIL "Node meets OpenClaw before install" "$(cat "$log")"
fi

# --- OpenClaw (guide 5.1) ---
run_step "OpenClaw installer --no-onboard --no-prompt" 1500 bash -c 'curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard --no-prompt'
adopt_tool_paths

step_n=$((step_n + 1))
log="$(mklog "$step_n" "openclaw version")"
printf '+ openclaw --version\n' >"$log"
if command -v openclaw >/dev/null 2>&1; then
  openclaw --version >>"$log" 2>&1
  ec=$?
  if [ "$ec" -eq 0 ]; then
    append_result "$step_n" PASS "openclaw --version" "$(cat "$log")"
  else
    append_result "$step_n" FAIL "openclaw --version" "exit $ec. $(cat "$log")"
  fi
else
  append_result "$step_n" FAIL "openclaw --version" "openclaw not on PATH. npm prefix -g=$(npm prefix -g 2>/dev/null || echo missing). PATH=$PATH"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "node meets guide")"
python3 - <<'PY' >"$log" 2>&1
import os, shutil, subprocess, sys
node = shutil.which("node")
if not node:
    print("node not on PATH")
    sys.exit(1)
ver = subprocess.check_output([node, "-v"], text=True).strip().lstrip("v")
parts = [int(x) for x in ver.split(".")[:3]]
while len(parts) < 3:
    parts.append(0)
major, minor, patch = parts
ok = (major == 24 and (minor, patch) >= (22, 1)) or (major > 26) or (major == 26 and (minor, patch) >= (12, 1))
print(f"node {ver} at {node}")
print("guide requirement: 24.22.1+ on the 24.x line, or >= 26.12.1")
print("meets guide text:" , "yes" if ok else "no")
sys.exit(0 if ok else 1)
PY
ec=$?
if [ "$ec" -eq 0 ]; then
  append_result "$step_n" PASS "node version meets the guide" "$(cat "$log")"
else
  append_result "$step_n" FAIL "node version meets the guide" "$(cat "$log")"
fi

# Guide 5.2
step_n=$((step_n + 1))
log="$(mklog "$step_n" "gateway token")"
{
  echo "+ gen-gateway-token.sh >> ~/.openclaw/.env && set -a; . ~/.openclaw/.env; set +a"
  mkdir -p "$HOME/.openclaw"
  chmod 700 "$HOME/.openclaw"
  bash templates/scripts/gen-gateway-token.sh >>"$HOME/.openclaw/.env"
  chmod 600 "$HOME/.openclaw/.env"
} >"$log" 2>&1
set -a
# shellcheck disable=SC1090
. "$HOME/.openclaw/.env"
set +a
tok_len="${#OPENCLAW_GATEWAY_TOKEN}"
if [ "$tok_len" -eq 64 ]; then
  append_result "$step_n" PASS "gateway token (length only)" "OPENCLAW_GATEWAY_TOKEN length=$tok_len; ~/.openclaw is 700; .env is 600"
else
  append_result "$step_n" FAIL "gateway token (length only)" "expected length 64, got $tok_len"
fi

# Guide 5.3
step_n=$((step_n + 1))
log="$(mklog "$step_n" "onboard")"
printf '+ openclaw onboard --non-interactive --accept-risk ...\n' >"$log"
run_with_timeout 300 openclaw onboard --non-interactive --accept-risk \
  --mode local --flow manual --auth-choice skip \
  --gateway-auth token --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
  --gateway-bind loopback --gateway-port 18789 \
  --no-install-daemon --skip-channels --skip-skills --skip-search --skip-ui --json \
  >>"$log" 2>&1
ec=$?
detail="$(tail -c 1500 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ] && printf '%s' "$detail" | grep -Eq '"ok"[[:space:]]*:[[:space:]]*true'; then
  append_result "$step_n" PASS "openclaw onboard --non-interactive" "exit 0 and ok:true. $detail"
else
  append_result "$step_n" FAIL "openclaw onboard --non-interactive" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "security audit before baseline")"
printf '+ openclaw security audit (before baseline)\n' >"$log"
run_with_timeout 180 openclaw security audit >>"$log" 2>&1
ec=$?
detail="$(tail -c 1500 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ]; then
  append_result "$step_n" PASS "openclaw security audit (before baseline)" "$detail"
else
  append_result "$step_n" FAIL "openclaw security audit (before baseline)" "exit $ec. $detail"
fi

# Guide 6.2
step_n=$((step_n + 1))
log="$(mklog "$step_n" "config patch dry-run")"
printf '+ openclaw config patch --file templates/openclaw/openclaw.safe-baseline.json5 --dry-run\n' >"$log"
if [ -f "$HOME/.openclaw/openclaw.json" ]; then
  cp "$HOME/.openclaw/openclaw.json" "$HOME/.openclaw/openclaw.json.bak"
fi
run_with_timeout 180 openclaw config patch --file templates/openclaw/openclaw.safe-baseline.json5 --dry-run >>"$log" 2>&1
ec=$?
detail="$(tail -c 1500 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ]; then
  append_result "$step_n" PASS "openclaw config patch --dry-run (safe baseline)" "$detail"
else
  append_result "$step_n" FAIL "openclaw config patch --dry-run (safe baseline)" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "config patch")"
printf '+ openclaw config patch --file templates/openclaw/openclaw.safe-baseline.json5\n' >"$log"
run_with_timeout 180 openclaw config patch --file templates/openclaw/openclaw.safe-baseline.json5 >>"$log" 2>&1
ec=$?
detail="$(tail -c 1200 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ]; then
  append_result "$step_n" PASS "openclaw config patch (safe baseline)" "$detail"
else
  append_result "$step_n" FAIL "openclaw config patch (safe baseline)" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "config validate")"
printf '+ openclaw config validate && chmod 600\n' >"$log"
run_with_timeout 120 openclaw config validate >>"$log" 2>&1
ec=$?
chmod 600 "$HOME/.openclaw/openclaw.json" 2>>"$log" || true
detail="$(cat "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ] && ! printf '%s' "$detail" | grep -Eqi 'unrecognized key|invalid option'; then
  append_result "$step_n" PASS "openclaw config validate" "$detail"
else
  append_result "$step_n" FAIL "openclaw config validate" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "permissions")"
python3 - "$HOME/.openclaw" "$HOME/.openclaw/openclaw.json" "$HOME/.openclaw/.env" <<'PY' >"$log" 2>&1
import os, stat, sys
def mode(path):
    return oct(os.stat(path).st_mode & 0o777)[2:]
home, cfg, env = sys.argv[1:]
print(f"dir {home} {mode(home)}")
print(f"cfg {cfg} {mode(cfg)}")
print(f"env {env} {mode(env)}")
bad = []
if mode(home) != "700":
    bad.append("dir")
if mode(cfg) != "600":
    bad.append("config")
if mode(env) != "600":
    bad.append("env")
sys.exit(1 if bad else 0)
PY
ec=$?
if [ "$ec" -eq 0 ]; then
  append_result "$step_n" PASS "openclaw directory and file modes 700/600" "$(cat "$log")"
else
  append_result "$step_n" FAIL "openclaw directory and file modes 700/600" "$(cat "$log")"
fi

# Gateway lifecycle (guide 5.4)
step_n=$((step_n + 1))
printf '+ openclaw gateway run (background)\n' >"$logdir/gateway.log"
openclaw gateway run >>"$logdir/gateway.log" 2>&1 &
GW_PID=$!
echo "$GW_PID" >"$logdir/gateway.pid"
  healthy=0
  i=0
  while [ "$i" -lt 40 ]; do
    if run_with_timeout 20 openclaw health >"$logdir/gateway-health.txt" 2>&1; then
      healthy=1
      break
    fi
    if ! kill -0 "$GW_PID" 2>/dev/null; then
      break
    fi
    i=$((i + 1))
    sleep 3
  done
if [ "$healthy" -eq 1 ]; then
  append_result "$step_n" PASS "openclaw health" "$(cat "$logdir/gateway-health.txt")"
else
  append_result "$step_n" FAIL "openclaw health" "not healthy after ~$((i * 3))s. $(tail -c 1500 "$logdir/gateway.log" 2>/dev/null || true)"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "gateway status")"
run_with_timeout 90 openclaw gateway status >"$log" 2>&1
ec=$?
detail="$(cat "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ] && printf '%s' "$detail" | grep -q '18789'; then
  append_result "$step_n" PASS "openclaw gateway status" "$detail"
else
  append_result "$step_n" FAIL "openclaw gateway status" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "openclaw status")"
run_with_timeout 90 openclaw status >"$log" 2>&1
ec=$?
detail="$(tail -c 1500 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ]; then
  append_result "$step_n" PASS "openclaw status" "$detail"
else
  append_result "$step_n" FAIL "openclaw status" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "models status")"
run_with_timeout 90 openclaw models status >"$log" 2>&1
ec=$?
detail="$(tail -c 1200 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 124 ] || [ "$ec" -eq 127 ]; then
  append_result "$step_n" FAIL "openclaw models status" "exit $ec. $detail"
elif printf '%s' "$detail" | grep -Eqi 'missing auth|no auth|not authenticated|indeterminate|auth'; then
  append_result "$step_n" PASS "openclaw models status (expect missing auth)" "exit $ec. $detail"
elif [ "$ec" -eq 0 ]; then
  append_result "$step_n" PASS "openclaw models status (expect missing auth)" "$detail"
else
  append_result "$step_n" FAIL "openclaw models status (expect missing auth)" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "security audit after")"
run_with_timeout 180 openclaw security audit >"$log" 2>&1
ec=$?
detail="$(tail -c 1800 "$log" 2>/dev/null || true)"
if [ "$ec" -ne 0 ]; then
  append_result "$step_n" FAIL "openclaw security audit (after baseline)" "exit $ec. $detail"
elif printf '%s' "$detail" | grep -Eqi '[1-9][0-9]* critical'; then
  append_result "$step_n" FAIL "openclaw security audit (after baseline)" "critical findings. $detail"
else
  append_result "$step_n" PASS "openclaw security audit (after baseline)" "$detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "security audit deep")"
run_with_timeout 180 openclaw security audit --deep >"$log" 2>&1
ec=$?
detail="$(tail -c 1800 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ]; then
  append_result "$step_n" PASS "openclaw security audit --deep" "$detail"
elif printf '%s' "$detail" | grep -Eqi 'probe_failed|missing scope: operator.read'; then
  append_result "$step_n" PASS "openclaw security audit --deep" "exit $ec matches the guide's documented probe_failed / operator.read note. $detail"
else
  append_result "$step_n" FAIL "openclaw security audit --deep" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "workspace skills")"
{
  echo "+ cp workspace-skills && openclaw skills list"
  mkdir -p "$HOME/.openclaw/workspace/skills"
  cp -R templates/openclaw/workspace-skills/. "$HOME/.openclaw/workspace/skills/"
  openclaw skills list
} >"$log" 2>&1
ec=$?
detail="$(cat "$log" 2>/dev/null || true)"
missing=""
for skill in research-brief daily-digest weekly-review inbox-triage; do
  if ! printf '%s' "$detail" | grep -q "$skill"; then
    missing="$missing $skill"
  fi
done
if [ "$ec" -eq 0 ] && [ -z "$missing" ]; then
  append_result "$step_n" PASS "openclaw skills list (4 workspace skills)" "$detail"
else
  append_result "$step_n" FAIL "openclaw skills list (4 workspace skills)" "exit $ec missing:${missing:-none}. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "automations")"
run_with_timeout 90 openclaw automations list >"$log" 2>&1
ec=$?
detail="$(cat "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ] && printf '%s' "$detail" | grep -Eqi '4h|heartbeat'; then
  append_result "$step_n" PASS "openclaw automations list" "$detail"
else
  append_result "$step_n" FAIL "openclaw automations list" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "usage-cost")"
run_with_timeout 90 openclaw gateway usage-cost --days 7 >"$log" 2>&1
ec=$?
detail="$(tail -c 1200 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ]; then
  append_result "$step_n" PASS "openclaw gateway usage-cost --days 7" "$detail"
else
  append_result "$step_n" FAIL "openclaw gateway usage-cost --days 7" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
stop_gateway
sleep 2
if [ -s "$logdir/gateway.pid" ] && kill -0 "$(cat "$logdir/gateway.pid")" 2>/dev/null; then
  append_result "$step_n" FAIL "stop gateway before doctor" "process $(cat "$logdir/gateway.pid") still running. $(tail -c 400 "$logdir/gateway-stop.txt" 2>/dev/null || true)"
else
  append_result "$step_n" PASS "stop gateway before doctor" "gateway process stopped. $(tail -c 400 "$logdir/gateway-stop.txt" 2>/dev/null || true)"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "openclaw doctor")"
printf '+ openclaw doctor\n' >"$log"
run_with_timeout 180 openclaw doctor >>"$log" 2>&1
ec=$?
detail="$(tail -c 1800 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 124 ] || [ "$ec" -eq 127 ]; then
  append_result "$step_n" FAIL "openclaw doctor (gateway stopped)" "exit $ec. $detail"
elif printf '%s' "$detail" | grep -q 'state database is busy'; then
  append_result "$step_n" FAIL "openclaw doctor (gateway stopped)" "state database is busy. $detail"
elif [ -z "$detail" ]; then
  append_result "$step_n" FAIL "openclaw doctor (gateway stopped)" "no output, exit $ec"
else
  append_result "$step_n" PASS "openclaw doctor (gateway stopped)" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "backup")"
printf '+ openclaw backup create\n' >"$log"
run_with_timeout 180 openclaw backup create >>"$log" 2>&1
ec=$?
detail="$(tail -c 800 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ]; then
  append_result "$step_n" PASS "openclaw backup create" "$detail"
else
  append_result "$step_n" FAIL "openclaw backup create" "exit $ec. $detail"
fi

# Hooks: 25 cases. Timeout so a blocking desktop notification cannot hang the job.
step_n=$((step_n + 1))
log="$(mklog "$step_n" "hooks")"
printf '+ bash templates/claude-code/hooks/test-hooks.sh\n' >"$log"
run_with_timeout 120 bash templates/claude-code/hooks/test-hooks.sh >>"$log" 2>&1
ec=$?
detail="$(cat "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ] && printf '%s' "$detail" | grep -q '25 cases, 0 failed'; then
  append_result "$step_n" PASS "hook tests (25 cases)" "$detail"
else
  append_result "$step_n" FAIL "hook tests (25 cases)" "exit $ec. $detail"
fi

run_step "validate-templates.sh" 300 bash templates/scripts/validate-templates.sh

step_n=$((step_n + 1))
log="$(mklog "$step_n" "skill audit")"
bash templates/scripts/skill-audit.sh templates/openclaw/workspace-skills >"$log" 2>&1
ec1=$?
bash templates/scripts/skill-audit.sh templates/claude-code/skills >>"$log" 2>&1
ec2=$?
detail="$(cat "$log" 2>/dev/null || true)"
if [ "$ec1" -eq 0 ] && [ "$ec2" -eq 0 ]; then
  append_result "$step_n" PASS "skill-audit.sh on pack skills" "$detail"
else
  append_result "$step_n" FAIL "skill-audit.sh on pack skills" "exit $ec1/$ec2. $detail"
fi

# Guide 3.3: balanced preset is the documented command; strict and power are the other shipped presets.
for preset in strict balanced power; do
  if [ "$preset" = "balanced" ]; then
    proj="$HOME/code/my-app"
  else
    proj="$HOME/code/preset-$preset"
  fi
  step_n=$((step_n + 1))
  log="$(mklog "$step_n" "preset $preset")"
  {
    echo "+ apply-claude-preset.sh $preset $proj && claude doctor"
    mkdir -p "$proj"
    bash templates/scripts/apply-claude-preset.sh "$preset" "$proj"
    cp templates/claude-code/claude-md/CLAUDE.webapp.md "$proj/CLAUDE.md"
  } >"$log" 2>&1
  run_with_timeout 180 bash -c "cd \"$proj\" && claude doctor" >>"$log" 2>&1
  ec=$?
  detail="$(tail -c 1200 "$log" 2>/dev/null || true)"
  if [ "$ec" -eq 0 ] && ! printf '%s' "$detail" | grep -q 'Invalid settings'; then
    append_result "$step_n" PASS "apply $preset preset + claude doctor" "$detail"
  else
    append_result "$step_n" FAIL "apply $preset preset + claude doctor" "exit $ec. $detail"
  fi
done

step_n=$((step_n + 1))
log="$(mklog "$step_n" "preset no overwrite")"
FORCE=0 bash templates/scripts/apply-claude-preset.sh balanced "$HOME/code/my-app" >"$log" 2>&1
ec=$?
detail="$(cat "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ] && printf '%s' "$detail" | grep -q 'skip (exists)'; then
  append_result "$step_n" PASS "apply preset does not overwrite" "$detail"
else
  append_result "$step_n" FAIL "apply preset does not overwrite" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "plugin validate")"
{
  echo "+ claude plugin validate agents && skills"
  claude plugin validate templates/claude-code/agents
  echo "agents exit $?"
  claude plugin validate templates/claude-code/skills
  echo "skills exit $?"
} >"$log" 2>&1
ec=$?
detail="$(tail -c 1500 "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ] && ! printf '%s' "$detail" | grep -Eq 'agents exit [^0]|skills exit [^0]'; then
  append_result "$step_n" PASS "claude plugin validate agents and skills" "$detail"
else
  append_result "$step_n" FAIL "claude plugin validate agents and skills" "exit $ec. $detail"
fi

step_n=$((step_n + 1))
log="$(mklog "$step_n" "verify-setup")"
bash templates/scripts/verify-setup.sh >"$log" 2>&1
ec=$?
detail="$(cat "$log" 2>/dev/null || true)"
if [ "$ec" -eq 0 ]; then
  append_result "$step_n" PASS "verify-setup.sh" "$detail"
else
  append_result "$step_n" FAIL "verify-setup.sh" "exit $ec. $detail"
fi

# macOS portability probe for the template's GNU-only sort -V. Recorded either way.
if [ "$platform" = "macos" ] || [ "$platform" = "linux" ]; then
  step_n=$((step_n + 1))
  log="$(mklog "$step_n" "sort -V")"
  printf 'sort version line: ' >"$log"
  sort --version >>"$log" 2>&1 || true
  if printf '1\n' | sort -V >/dev/null 2>>"$log"; then
    append_result "$step_n" PASS "sort -V (used by verify-setup.sh)" "$(cat "$log")"
  else
    append_result "$step_n" FAIL "sort -V (used by verify-setup.sh)" "$(cat "$log")"
  fi
fi

exit "$fail_count"

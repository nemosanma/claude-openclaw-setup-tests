# Reproduce the Claude Code + OpenClaw setup guide on native Windows PowerShell.
# Bash hooks are ported through Git Bash when it exists; WSL is probed and not installed.
# No API keys. Exit code = number of failed steps.
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

$LogDir = Join-Path $Root "ci-logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$script:Results = New-Object System.Collections.Generic.List[object]
$script:Fail = 0
$script:Step = 0
$script:Token = ""
$script:SummaryWritten = $false
$script:GatewayProc = $null
$script:Notes = New-Object System.Collections.Generic.List[string]

function Add-Note([string]$Text) { $script:Notes.Add("- $Text") | Out-Null }

function Redact([string]$Text) {
    if (-not $Text) { return "" }
    if ($script:Token) { return $Text.Replace($script:Token, "***REDACTED***") }
    return $Text
}

function Add-Result([string]$Status, [string]$Name, [string]$Detail) {
    $script:Step++
    $raw = Redact $Detail
    $clean = ($raw -replace "[\r\n\t|]+", " ")
    if ($clean.Length -gt 500) { $clean = $clean.Substring(0, 500) }
    $script:Results.Add([pscustomobject]@{
        N = $script:Step; Status = $Status; Name = $Name; Detail = $clean; Raw = $raw
    }) | Out-Null
    if ($Status -eq "FAIL") { $script:Fail++ }
    Write-Host ("[{0}] {1:d2} {2}" -f $Status, $script:Step, $Name)
    $slug = ($Name -replace "[^A-Za-z0-9]+", "-").Trim("-")
    if ($slug.Length -gt 50) { $slug = $slug.Substring(0, 50) }
    $path = Join-Path $LogDir ("{0:d2}-{1}.log" -f $script:Step, $slug)
    Set-Content -Path $path -Value $raw -Encoding utf8
}

function Invoke-Step([string]$Name, [scriptblock]$Action) {
    try {
        $result = & $Action
        $status = "PASS"
        $detail = ""
        if ($result -is [System.Collections.IDictionary]) {
            if ($result.ContainsKey("Status")) { $status = [string]$result.Status }
            elseif ($result.ContainsKey("Ok") -and -not $result.Ok) { $status = "FAIL" }
            if ($result.ContainsKey("Detail")) { $detail = [string]$result.Detail }
        } else {
            $detail = [string]$result
        }
        Add-Result $status $Name $detail
    } catch {
        Add-Result "FAIL" $Name ($_ | Out-String)
    }
}

function Update-SessionPath {
    # Rebuild PATH from the registry every time. Prepending onto $env:Path
    # on each openclaw call grows it without bound; CreateProcess then fails
    # with "Not enough memory resources are available".
    $seen = @{}
    $ordered = New-Object System.Collections.Generic.List[string]
    $extras = @(
        (Join-Path $env:USERPROFILE ".local\bin"),
        (Join-Path $env:LOCALAPPDATA "OpenClaw\deps\portable-node"),
        (Join-Path $env:APPDATA "npm"),
        "C:\Program Files\nodejs"
    )
    $base = @(
        [Environment]::GetEnvironmentVariable("Path", "Machine"),
        [Environment]::GetEnvironmentVariable("Path", "User")
    ) -join ";"
    foreach ($dir in @($extras + ($base -split ";"))) {
        if (-not $dir) { continue }
        $trim = $dir.Trim()
        if (-not $trim) { continue }
        $key = $trim.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $ordered.Add($trim) | Out-Null
    }
    $env:Path = ($ordered -join ";")
}

function Resolve-Launch([string]$Name, [string[]]$UserArgs) {
    # npm on Windows also drops an extensionless shell script named "openclaw".
    # Start-Process cannot execute that file (%1 is not a valid Win32 application).
    $candidates = @()
    foreach ($c in @(Get-Command $Name -All -ErrorAction SilentlyContinue)) { $candidates += $c.Source }
    $candidates += (Join-Path $env:USERPROFILE ".local\bin\$Name.exe")
    $candidates += (Join-Path $env:APPDATA "npm\$Name.cmd")
    $candidates += (Join-Path $env:USERPROFILE ".local\bin\$Name.cmd")
    $chosen = $null
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c) -and ($c -like "*.exe")) { $chosen = $c; break }
    }
    if (-not $chosen) {
        foreach ($c in $candidates) {
            if ($c -and (Test-Path -LiteralPath $c) -and ($c -like "*.cmd" -or $c -like "*.bat")) { $chosen = $c; break }
        }
    }
    if (-not $chosen) {
        throw "Could not find an .exe or .cmd for $Name. Saw: $($candidates -join ' | ')"
    }
    if ($chosen -like "*.exe") {
        return @{ File = $chosen; Args = $UserArgs; ArgumentString = $null }
    }
    # npm's cmd shim must be invoked with CALL. A bare `cmd /c openclaw.cmd`
    # hits the shim's `endlocal & goto` trick and tries to execute `"node"`.
    if ($chosen -match '\s') { $tail = '"' + $chosen + '"' } else { $tail = $chosen }
    foreach ($arg in $UserArgs) {
        if ($null -eq $arg -or $arg -eq "") { continue }
        if ($arg -match '[\s"]') { $tail += ' "' + ($arg -replace '"', '""') + '"' }
        else { $tail += " $arg" }
    }
    return @{ File = $env:ComSpec; Args = @(); ArgumentString = "/d /c call $tail" }
}

function Invoke-Captured {
    param(
        [Parameter(Mandatory)][string]$File,
        [string[]]$ArgumentList = @(),
        [string]$ArgumentString = "",
        [int]$TimeoutSec = 180,
        [string]$WorkingDirectory = $Root
    )
    # One argument string so a bash script or cmd /c line is not split on spaces.
    if ($ArgumentString) {
        $argLine = $ArgumentString
    } else {
        $quoted = @()
        foreach ($a in $ArgumentList) {
            if ($null -eq $a) { continue }
            if ($a -match '[\s"]') { $quoted += '"' + ($a.Replace('"', '""')) + '"' }
            else { $quoted += $a }
        }
        $argLine = ($quoted -join " ")
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = $argLine
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    # Read stderr asynchronously so a full pipe cannot deadlock the child.
    $errTask = $proc.StandardError.ReadToEndAsync()
    $outText = $proc.StandardOutput.ReadToEnd()
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill($true) } catch { try { $proc.Kill() } catch {} }
        $proc.Dispose()
        return @{ Exit = 124; Text = "TIMEOUT after ${TimeoutSec}s`n$outText" }
    }
    $proc.WaitForExit()
    $errText = $errTask.GetAwaiter().GetResult()
    $code = $proc.ExitCode
    if ($null -eq $code) { $code = 1 }
    $proc.Dispose()
    return @{ Exit = $code; Text = ($outText + $errText) }
}

function Invoke-GitBashFile([string]$Body, [int]$TimeoutSec = 120) {
    $bash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
    $path = Join-Path $LogDir ("bash-" + [guid]::NewGuid().ToString("N") + ".sh")
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $text = ($Body -replace "`r`n", "`n").TrimEnd() + "`n"
    [System.IO.File]::WriteAllText($path, $text, $utf8)
    $unix = (& $bash --noprofile --norc -lc "cygpath -u '$path'").Trim()
    return Invoke-Captured -File $bash -ArgumentList @("--noprofile", "--norc", $unix) -TimeoutSec $TimeoutSec
}

function Get-OpenClawEntry {
    $root = Join-Path $env:APPDATA "npm\node_modules\openclaw"
    $pkgPath = Join-Path $root "package.json"
    if (-not (Test-Path $pkgPath)) { return $null }
    $pkg = Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $rel = $null
    if ($pkg.bin -is [string]) { $rel = [string]$pkg.bin }
    elseif ($pkg.bin.openclaw) { $rel = [string]$pkg.bin.openclaw }
    if (-not $rel) { return $null }
    $entry = Join-Path $root ($rel -replace "/", "\")
    if (Test-Path -LiteralPath $entry) { return $entry }
    return $null
}

function Invoke-Tool([string]$Name, [string[]]$UserArgs, [int]$TimeoutSec = 180, [string]$WorkingDirectory = $Root) {
    # The npm-generated openclaw.cmd shim runs `"node"` (quotes included) when
    # started from another cmd.exe. Call the package entry with node.exe instead.
    if ($Name -eq "openclaw") {
        Update-SessionPath
        $node = Get-Command node.exe -ErrorAction SilentlyContinue
        $entry = Get-OpenClawEntry
        if ($node -and $entry) {
            return Invoke-Captured -File $node.Source -ArgumentList (@($entry) + $UserArgs) -TimeoutSec $TimeoutSec -WorkingDirectory $WorkingDirectory
        }
    }
    $launch = Resolve-Launch $Name $UserArgs
    if ($launch.ArgumentString) {
        return Invoke-Captured -File $launch.File -ArgumentString $launch.ArgumentString -TimeoutSec $TimeoutSec -WorkingDirectory $WorkingDirectory
    }
    return Invoke-Captured -File $launch.File -ArgumentList $launch.Args -TimeoutSec $TimeoutSec -WorkingDirectory $WorkingDirectory
}

function Stop-GatewayProcess {
    if ($script:GatewayProc -and -not $script:GatewayProc.HasExited) {
        try { Stop-Process -Id $script:GatewayProc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    try {
        Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object { $_.Name -match "node|openclaw" -and $_.CommandLine -match "gateway" } |
            ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
    } catch {}
    $script:GatewayProc = $null
}

function Write-Summary {
    if ($script:SummaryWritten) { return }
    $script:SummaryWritten = $true
    $versionLog = Join-Path $LogDir "versions.txt"
    $versionLines = @()
    foreach ($pair in @(
        @("git", "--version"),
        @("node", "-v"),
        @("npm", "-v"),
        @("jq", "--version"),
        @("claude", "--version"),
        @("openclaw", "--version")
    )) {
        try {
            $ran = Invoke-Tool $pair[0] @($pair[1]) 30
            $versionLines += ("{0}: exit {1} {2}" -f $pair[0], $ran.Exit, (($ran.Text -replace "[\r\n]+", " ").Trim()))
        } catch {
            $versionLines += ("{0}: not installed" -f $pair[0])
        }
    }
    $versionLines += "runner: $env:RUNNER_OS $env:RUNNER_ARCH $env:ImageOS $env:ImageVersion"
    $versionLines += "powershell: $($PSVersionTable.PSVersion)"
    Set-Content -Path $versionLog -Value ($versionLines -join "`n") -Encoding utf8

    $lines = @()
    $lines += "# Setup guide test summary"
    $lines += ""
    $lines += "- Platform: ``windows``"
    $lines += "- When: ``$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mmZ'))``"
    $resultWord = "FAIL"
    if ($script:Fail -eq 0) { $resultWord = "PASS" }
    $lines += "- Result: **$resultWord** ($($script:Fail) failed)"
    $lines += ""
    $lines += "## Tool versions"
    $lines += ""
    $lines += '```'
    $lines += $versionLines
    $lines += '```'
    $lines += ""
    $lines += "## Steps"
    $lines += ""
    $lines += "| # | Result | Step | Detail |"
    $lines += "|---|---|---|---|"
    foreach ($row in $script:Results) {
        $lines += "| $($row.N) | $($row.Status) | $($row.Name) | $($row.Detail) |"
    }
    $lines += ""
    $lines += "## CI notes"
    $lines += ""
    $lines += $script:Notes
    $failed = @($script:Results | Where-Object { $_.Status -eq "FAIL" })
    if ($failed.Count -gt 0) {
        $lines += ""
        $lines += "## Failure excerpts"
        foreach ($row in $failed) {
            $excerpt = $row.Raw
            if ($excerpt.Length -gt 2000) { $excerpt = $excerpt.Substring($excerpt.Length - 2000) }
            $lines += ""
            $lines += "### $($row.Name) (step $($row.N))"
            $lines += ""
            $lines += '```'
            $lines += $excerpt
            $lines += '```'
        }
    }
    $summaryPath = Join-Path $Root "test-summary.md"
    $text = ($lines -join "`n") + "`n"
    if ($script:Token) { $text = $text.Replace($script:Token, "***REDACTED***") }
    Set-Content -Path $summaryPath -Value $text -Encoding utf8
    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $text -Encoding utf8
    }
}

Add-Note "Windows job uses native PowerShell. The guide's recommended Windows path is WSL 2; this runner is probed for WSL and then follows the native installers."
Add-Note "Claude Code: ``irm https://claude.ai/install.ps1 | iex`` (guide section 2.1)."
Add-Note "OpenClaw: ``iwr -useb https://openclaw.ai/install.ps1 | iex`` with OPENCLAW_NO_ONBOARD=1. The guide's one-liner cannot take -NoOnboard; without the variable the installer starts the interactive wizard and CI would hang. The installer documents this variable."
Add-Note "PATH is re-read from the user and machine environment after installers. The guide's equivalent is opening a new terminal."
Add-Note "Bash hooks and validate-templates.sh are run with Git Bash when Git for Windows is present. Native PowerShell cannot run them. The guide tells Windows readers to use WSL 2 for the template scripts."
Add-Note "No API key is set. Onboarding uses --auth-choice skip and a generated gateway token."

try {
    # Drop inherited API keys. Do not print values.
    $keyNames = @()
    Get-ChildItem Env: | Where-Object { $_.Name -like "*_API_KEY" } | ForEach-Object { $keyNames += $_.Name }
    foreach ($name in $keyNames) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    if ($env:NPM_CONFIG_PREFIX) {
        Add-Note "Unsetting NPM_CONFIG_PREFIX (was $($env:NPM_CONFIG_PREFIX)) per guide section 1.4."
        Remove-Item Env:NPM_CONFIG_PREFIX -ErrorAction SilentlyContinue
    }
    if ($env:npm_config_prefix) { Remove-Item Env:npm_config_prefix -ErrorAction SilentlyContinue }

    Invoke-Step "no API keys in the environment" {
        $left = @(Get-ChildItem Env: | Where-Object { $_.Name -like "*_API_KEY" } | ForEach-Object { $_.Name })
        if ($left.Count -eq 0) { @{ Ok = $true; Detail = "no *_API_KEY variables" } }
        else { @{ Ok = $false; Detail = ("still set: " + ($left -join " ")) } }
    }

    Invoke-Step "WSL probe (guide recommends WSL 2)" {
        $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
        if (-not $wsl) {
            return @{ Status = "SKIP"; Detail = "wsl.exe is not on this runner. GitHub-hosted windows-latest does not ship a usable WSL 2 distro (installing one needs Hyper-V and a reboot). Native PowerShell is what this job tests. The guide's template scripts are not claimed to run in native PowerShell." }
        }
        $ran = Invoke-Captured -File $wsl.Source -ArgumentList @("--status") -TimeoutSec 30
        $text = $ran.Text
        $list = Invoke-Captured -File $wsl.Source -ArgumentList @("-l", "-v") -TimeoutSec 30
        $text += "`n" + $list.Text
        $ranEcho = Invoke-Captured -File $wsl.Source -ArgumentList @("-e", "uname", "-a") -TimeoutSec 40
        $text += "`nuname exit $($ranEcho.Exit): $($ranEcho.Text)"
        if ($ranEcho.Exit -eq 0 -and $ranEcho.Text -match "Linux") {
            return @{ Status = "PASS"; Detail = "WSL executed uname. $text" }
        }
        return @{ Status = "SKIP"; Detail = "WSL is not usable on this hosted runner, so the guide's WSL 2 path was not executed. Probe output: $text" }
    }

    Invoke-Step "Prerequisites present (git, curl)" {
        $bits = @()
        $ok = $true
        foreach ($tool in @("git", "curl.exe", "curl")) {
            $c = Get-Command $tool -ErrorAction SilentlyContinue
            if ($c) { $bits += "$tool=$($c.Source)" }
        }
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $ok = $false }
        @{ Ok = $ok; Detail = ($bits -join "; ") }
    }

    Invoke-Step "jq for the hook port (harness download)" {
        $dir = Join-Path $LogDir "bin"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $dest = Join-Path $dir "jq.exe"
        if (-not (Test-Path $dest)) {
            curl.exe -fsSL -o $dest "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-windows-amd64.exe"
            if ($LASTEXITCODE -ne 0) { return @{ Ok = $false; Detail = "curl jq failed exit $LASTEXITCODE" } }
        }
        $env:Path = "$dir;$env:Path"
        $ran = Invoke-Tool "jq" @("--version") 20
        @{ Ok = ($ran.Exit -eq 0); Detail = "Downloaded jq 1.7.1 for Git Bash hook tests. The native Windows guide does not install jq; hooks are Bash and the guide sends Windows readers to WSL 2. $($ran.Text)" }
    }

    Invoke-Step "Claude Code native installer" {
        $logBase = Join-Path $LogDir "claude-install"
        $ran = Invoke-Captured -File (Get-Command pwsh).Source -TimeoutSec 900 -ArgumentList @(
            "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command",
            "irm https://claude.ai/install.ps1 | iex"
        )
        Set-Content -Path "$logBase.log" -Value $ran.Text -Encoding utf8
        Update-SessionPath
        @{ Ok = ($ran.Exit -eq 0); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Update-SessionPath

    Invoke-Step "claude --version" {
        Update-SessionPath
        $ran = Invoke-Tool "claude" @("--version") 60
        @{ Ok = ($ran.Exit -eq 0 -and $ran.Text.Trim().Length -gt 0); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "claude doctor" {
        $ran = Invoke-Tool "claude" @("doctor") 180
        $bad = $ran.Text -match "Invalid settings"
        @{ Ok = ($ran.Exit -eq 0 -and -not $bad); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "claude auth status (expect logged out)" {
        $ran = Invoke-Tool "claude" @("auth", "status") 120
        $loggedOut = ($ran.Text -match "loggedIn") -and ($ran.Text -match "false")
        $loggedIn = ($ran.Text -match "loggedIn") -and ($ran.Text -match "true") -and -not $loggedOut
        if ($loggedIn) { return @{ Ok = $false; Detail = "unexpected login. $($ran.Text)" } }
        @{ Ok = $loggedOut; Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "user settings + claude doctor" {
        $destDir = Join-Path $env:USERPROFILE ".claude"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Copy-Item (Join-Path $Root "templates\claude-code\settings\user-settings.json") (Join-Path $destDir "settings.json") -Force
        Copy-Item (Join-Path $Root "templates\claude-code\statusline\statusline.sh") (Join-Path $destDir "statusline.sh") -Force
        Copy-Item (Join-Path $Root "templates\claude-code\claude-md\CLAUDE.global.md") (Join-Path $destDir "CLAUDE.md") -Force
        $ran = Invoke-Tool "claude" @("doctor") 180
        $bad = $ran.Text -match "Invalid settings"
        @{ Ok = ($ran.Exit -eq 0 -and -not $bad); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "OpenClaw installer (OPENCLAW_NO_ONBOARD=1)" {
        $env:OPENCLAW_NO_ONBOARD = "1"
        $ran = Invoke-Captured -File (Get-Command pwsh).Source -TimeoutSec 1500 -ArgumentList @(
            "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command",
            "iwr -useb https://openclaw.ai/install.ps1 | iex"
        )
        Update-SessionPath
        @{ Ok = ($ran.Exit -eq 0); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Update-SessionPath

    Invoke-Step "openclaw --version" {
        Update-SessionPath
        $ran = Invoke-Tool "openclaw" @("--version") 60
        @{ Ok = ($ran.Exit -eq 0 -and $ran.Text.Trim().Length -gt 0); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "node version meets the guide" {
        Update-SessionPath
        $ran = Invoke-Tool "node" @("-v") 30
        $verText = ($ran.Text.Trim() -replace "^v", "")
        $match = [regex]::Match($verText, "(\d+)\.(\d+)\.(\d+)")
        $ok = $false
        $explain = "could not parse node version from: $($ran.Text)"
        if ($match.Success) {
            $major = [int]$match.Groups[1].Value
            $minor = [int]$match.Groups[2].Value
            $patch = [int]$match.Groups[3].Value
            $on24 = ($major -eq 24) -and (($minor -gt 22) -or ($minor -eq 22 -and $patch -ge 1))
            $on26 = ($major -eq 26) -and (($minor -gt 12) -or ($minor -eq 12 -and $patch -ge 1))
            $newer = $major -gt 26
            $ok = $on24 -or $on26 -or $newer
            $explain = "node $major.$minor.$patch at $((Get-Command node -ErrorAction SilentlyContinue).Source). guide: 24.22.1+ on 24.x, or >= 26.12.1. meets=$ok"
        }
        @{ Ok = $ok; Detail = $explain }
    }

    Invoke-Step "gateway token (length only)" {
        $dir = Join-Path $env:USERPROFILE ".openclaw"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $bash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
        $tokenLine = ""
        $how = ""
        if (Test-Path $bash) {
            $ran = Invoke-GitBashFile "bash templates/scripts/gen-gateway-token.sh" 30
            $how = "gen-gateway-token.sh via Git Bash, exit $($ran.Exit). "
            $match = [regex]::Match([string]$ran.Text, "OPENCLAW_GATEWAY_TOKEN=([0-9a-fA-F]{64})")
            if ($match.Success) { $tokenLine = $match.Groups[1].Value }
        }
        if (-not $tokenLine -or $tokenLine.Length -ne 64) {
            $bytes = New-Object byte[] 32
            [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
            $tokenLine = -join ($bytes | ForEach-Object { $_.ToString("x2") })
            $utf8 = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText((Join-Path $dir ".env"), "OPENCLAW_GATEWAY_TOKEN=$tokenLine`n", $utf8)
            $how += " Fell back to RandomNumberGenerator because the bash script did not yield a 64-hex token. The guide's generator is a Bash script and is specified for WSL, not native PowerShell."
        }
        $script:Token = $tokenLine
        $env:OPENCLAW_GATEWAY_TOKEN = $tokenLine
        @{ Ok = ($tokenLine.Length -eq 64); Detail = "length=$($tokenLine.Length). $how" }
    }

    Invoke-Step "openclaw onboard --non-interactive" {
        $ran = Invoke-Tool "openclaw" @(
            "onboard", "--non-interactive", "--accept-risk",
            "--mode", "local", "--flow", "manual", "--auth-choice", "skip",
            "--gateway-auth", "token", "--gateway-token-ref-env", "OPENCLAW_GATEWAY_TOKEN",
            "--gateway-bind", "loopback", "--gateway-port", "18789",
            "--no-install-daemon", "--skip-channels", "--skip-skills", "--skip-search", "--skip-ui", "--json"
        ) 300
        $ok = ($ran.Exit -eq 0) -and ($ran.Text -match '"ok"\s*:\s*true')
        @{ Ok = $ok; Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "openclaw security audit (before baseline)" {
        $ran = Invoke-Tool "openclaw" @("security", "audit") 180
        @{ Ok = ($ran.Exit -eq 0); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    $safe = Join-Path $Root "templates\openclaw\openclaw.safe-baseline.json5"
    $cfg = Join-Path $env:USERPROFILE ".openclaw\openclaw.json"
    if (Test-Path $cfg) { Copy-Item $cfg "$cfg.bak" -Force }

    Invoke-Step "openclaw config patch --dry-run (safe baseline)" {
        $ran = Invoke-Tool "openclaw" @("config", "patch", "--file", $safe, "--dry-run") 180
        @{ Ok = ($ran.Exit -eq 0); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "openclaw config patch (safe baseline)" {
        $ran = Invoke-Tool "openclaw" @("config", "patch", "--file", $safe) 180
        @{ Ok = ($ran.Exit -eq 0); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "openclaw config validate" {
        $ran = Invoke-Tool "openclaw" @("config", "validate") 120
        $bad = $ran.Text -match "Unrecognized key|Invalid option"
        @{ Ok = ($ran.Exit -eq 0 -and -not $bad); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "chmod 700/600 (bash-only in the guide)" {
        $dir = Join-Path $env:USERPROFILE ".openclaw"
        $exists = (Test-Path $dir) -and (Test-Path (Join-Path $dir "openclaw.json")) -and (Test-Path (Join-Path $dir ".env"))
        @{ Status = "SKIP"; Detail = "Guide sections 5.2 and 6.2 use chmod 700/600 in bash. Native NTFS modes are not specified. Files exist=$exists. The guide sends Windows readers to WSL 2 for these steps." }
    }

    Invoke-Step "openclaw health" {
        Update-SessionPath
        $node = Get-Command node.exe -ErrorAction SilentlyContinue
        $entry = Get-OpenClawEntry
        if ($node -and $entry) {
            $launch = @{ File = $node.Source; Args = @($entry, "gateway", "run"); ArgumentString = $null }
        } else {
            $launch = Resolve-Launch "openclaw" @("gateway", "run")
        }
        $gwOut = Join-Path $LogDir "gateway.out"
        $gwErr = Join-Path $LogDir "gateway.err"
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $launch.File
        $psi.WorkingDirectory = $Root
        if ($launch.ArgumentString) {
            # /d /c <shim> gateway run 1>log 2>log  (path has no spaces on the runner)
            $psi.Arguments = $launch.ArgumentString + " 1>`"$gwOut`" 2>`"$gwErr`""
            $psi.RedirectStandardOutput = $false
            $psi.RedirectStandardError = $false
        } else {
            $psi.Arguments = ($launch.Args -join " ")
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
        }
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $script:GatewayProc = New-Object System.Diagnostics.Process
        $script:GatewayProc.StartInfo = $psi
        [void]$script:GatewayProc.Start()
        if ($psi.RedirectStandardOutput) {
            $script:GatewayProc.BeginOutputReadLine()
            $script:GatewayProc.BeginErrorReadLine()
        }
        $healthy = $false
        $last = ""
        for ($i = 0; $i -lt 40; $i++) {
            $ran = Invoke-Tool "openclaw" @("health") 25
            $last = $ran.Text
            if ($ran.Exit -eq 0) { $healthy = $true; break }
            if ($script:GatewayProc.HasExited) { break }
            Start-Sleep -Seconds 3
        }
        $logTail = ""
        if (Test-Path $gwOut) { $logTail += (Get-Content $gwOut -Raw -ErrorAction SilentlyContinue) }
        if (Test-Path $gwErr) { $logTail += (Get-Content $gwErr -Raw -ErrorAction SilentlyContinue) }
        if ($logTail.Length -gt 800) { $logTail = $logTail.Substring($logTail.Length - 800) }
        if ($healthy) { @{ Ok = $true; Detail = $last } }
        else { @{ Ok = $false; Detail = "not healthy. $last $logTail" } }
    }

    Invoke-Step "openclaw gateway status" {
        $ran = Invoke-Tool "openclaw" @("gateway", "status") 90
        $ok = ($ran.Exit -eq 0) -and ($ran.Text -match "18789")
        @{ Ok = $ok; Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "openclaw status" {
        $ran = Invoke-Tool "openclaw" @("status") 90
        @{ Ok = ($ran.Exit -eq 0); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "openclaw models status (expect missing auth)" {
        $ran = Invoke-Tool "openclaw" @("models", "status") 90
        $ok = ($ran.Exit -ne 124 -and $ran.Exit -ne 127) -and ($ran.Text -match "(?i)auth" -or $ran.Exit -eq 0)
        @{ Ok = [bool]$ok; Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "openclaw security audit (after baseline)" {
        $ran = Invoke-Tool "openclaw" @("security", "audit") 180
        $critical = $ran.Text -match "(?i)[1-9][0-9]* critical"
        @{ Ok = ($ran.Exit -eq 0 -and -not $critical); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "openclaw security audit --deep" {
        $ran = Invoke-Tool "openclaw" @("security", "audit", "--deep") 180
        $documented = $ran.Text -match "(?i)probe_failed|missing scope: operator.read"
        $ok = ($ran.Exit -eq 0) -or $documented
        @{ Ok = [bool]$ok; Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "openclaw skills list (4 workspace skills)" {
        $dest = Join-Path $env:USERPROFILE ".openclaw\workspace\skills"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item (Join-Path $Root "templates\openclaw\workspace-skills\*") $dest -Recurse -Force
        $ran = Invoke-Tool "openclaw" @("skills", "list") 90
        $missing = @()
        foreach ($skill in @("research-brief", "daily-digest", "weekly-review", "inbox-triage")) {
            if ($ran.Text -notmatch [regex]::Escape($skill)) { $missing += $skill }
        }
        @{ Ok = ($ran.Exit -eq 0 -and $missing.Count -eq 0); Detail = "exit $($ran.Exit) missing=$($missing -join ','). $($ran.Text)" }
    }

    Invoke-Step "openclaw automations list" {
        $ran = Invoke-Tool "openclaw" @("automations", "list") 90
        $ok = ($ran.Exit -eq 0) -and ($ran.Text -match "(?i)4h|heartbeat")
        @{ Ok = [bool]$ok; Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "openclaw gateway usage-cost --days 7" {
        $ran = Invoke-Tool "openclaw" @("gateway", "usage-cost", "--days", "7") 90
        @{ Ok = ($ran.Exit -eq 0); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "stop gateway before doctor" {
        Stop-GatewayProcess
        Start-Sleep -Seconds 3
        @{ Ok = $true; Detail = "stopped the background gateway process before doctor" }
    }

    Invoke-Step "openclaw doctor (gateway stopped)" {
        $ran = Invoke-Tool "openclaw" @("doctor") 180
        $busy = $ran.Text -match "state database is busy"
        $launchError = $ran.Text -match "not recognized|not a valid Win32"
        $looksLikeDoctor = $ran.Text -match "Gateway|skill|memory|Doctor|OpenClaw"
        $ok = (-not $busy) -and (-not $launchError) -and ($ran.Exit -ne 124) -and $looksLikeDoctor
        @{ Ok = [bool]$ok; Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "openclaw backup create" {
        $ran = Invoke-Tool "openclaw" @("backup", "create") 180
        @{ Ok = ($ran.Exit -eq 0); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "hook tests via Git Bash (25 cases)" {
        $bash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
        if (-not (Test-Path $bash)) {
            return @{ Status = "SKIP"; Detail = "Git Bash is not installed. Native PowerShell cannot run templates/claude-code/hooks/test-hooks.sh. The guide says to use WSL 2 for these Bash hooks, and WSL is not available on this runner." }
        }
        $jqDir = Join-Path $LogDir "bin"
        $jqUnix = (& $bash --noprofile --norc -lc "cygpath -u '$jqDir'").Trim()
        $hookBody = "export PATH='$jqUnix':" + '$PATH' + "`nbash templates/claude-code/hooks/test-hooks.sh`n"
        $ran = Invoke-GitBashFile $hookBody 120
        $ok = ($ran.Exit -eq 0) -and ($ran.Text -match "25 cases, 0 failed")
        @{ Ok = [bool]$ok; Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "validate-templates.sh via Git Bash" {
        $bash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
        if (-not (Test-Path $bash)) {
            return @{ Status = "SKIP"; Detail = "Git Bash is not installed, so validate-templates.sh was not run. It is a Bash script; the guide specifies WSL 2 on Windows." }
        }
        $jqDir = Join-Path $LogDir "bin"
        $jqUnix = (& $bash --noprofile --norc -lc "cygpath -u '$jqDir'").Trim()
        $py = Get-Command python -ErrorAction SilentlyContinue
        $env:PYTHONUTF8 = "1"
        $env:PYTHONIOENCODING = "utf-8"
        $pipNote = "python not on PATH"
        if ($py) {
            $pip = Invoke-Captured -File $py.Source -TimeoutSec 180 -ArgumentList @("-m", "pip", "install", "--user", "jsonschema", "pyyaml")
            $pipNote = "pip exit $($pip.Exit)"
        }
        $validator = Join-Path $LogDir "run-validate.sh"
        $validatorBody = @"
#!/bin/sh
if ! command -v python3 >/dev/null 2>&1 && command -v python >/dev/null 2>&1; then
  mkdir -p "`$HOME/bin-ci"
  printf '%s\n' '#!/bin/sh' 'exec python "`$@"' > "`$HOME/bin-ci/python3"
  chmod +x "`$HOME/bin-ci/python3"
  export PATH="`$HOME/bin-ci:`$PATH"
fi
export PATH='$jqUnix':"`$PATH"
bash templates/scripts/validate-templates.sh
"@
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($validator, (($validatorBody -replace "`r`n", "`n") + "`n"), $utf8)
        $validatorUnix = (& $bash --noprofile --norc -lc "cygpath -u '$validator'").Trim()
        $ran = Invoke-Captured -File $bash -TimeoutSec 300 -ArgumentList @("--noprofile", "--norc", $validatorUnix)
        @{ Ok = ($ran.Exit -eq 0); Detail = "$pipNote. validator exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "skill-audit.sh via Git Bash" {
        $bash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
        if (-not (Test-Path $bash)) {
            return @{ Status = "SKIP"; Detail = "Git Bash missing; skill-audit.sh is Bash." }
        }
        $ran = Invoke-GitBashFile "bash templates/scripts/skill-audit.sh templates/openclaw/workspace-skills && bash templates/scripts/skill-audit.sh templates/claude-code/skills" 60
        @{ Ok = ($ran.Exit -eq 0); Detail = "exit $($ran.Exit). $($ran.Text)" }
    }

    Invoke-Step "apply balanced preset + claude doctor" {
        $bash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
        $proj = Join-Path $env:USERPROFILE "code\my-app"
        New-Item -ItemType Directory -Force -Path $proj | Out-Null
        if (-not (Test-Path $bash)) {
            return @{ Status = "SKIP"; Detail = "apply-claude-preset.sh is Bash. Git Bash is missing and WSL is not available." }
        }
        $ran = Invoke-GitBashFile "mkdir -p `"`$HOME/code/my-app`" && bash templates/scripts/apply-claude-preset.sh balanced `"`$HOME/code/my-app`" && cp templates/claude-code/claude-md/CLAUDE.webapp.md `"`$HOME/code/my-app/CLAUDE.md`"" 60
        if ($ran.Exit -ne 0) { return @{ Ok = $false; Detail = $ran.Text } }
        $doc = Invoke-Tool "claude" @("doctor") 180 $proj
        $bad = $doc.Text -match "Invalid settings"
        @{ Ok = ($doc.Exit -eq 0 -and -not $bad); Detail = "apply: $($ran.Text) doctor exit $($doc.Exit). $($doc.Text)" }
    }
} finally {
    Stop-GatewayProcess
    Write-Summary
    if ($script:Fail -gt 0) { exit $script:Fail }
}

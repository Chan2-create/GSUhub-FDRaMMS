<#
.SYNOPSIS
    Runs GSUhub locally: the Supabase stack, the Firebase Auth emulator,
    the demo accounts, and the web app.

.DESCRIPTION
    The whole system on one machine (docs/local_setup.md):

    1. The local Supabase stack (database, photos, live updates, the token
       exchange), in Docker. Reused if it is already running. The first
       time, the token exchange's local secrets are written and the stack
       restarted so it reads them.
    2. The Firebase Auth emulator, in its own window, on Java 21. Reused if
       it is already running. The demo sign-in accounts are added each
       time it starts (it keeps nothing).
    3. The app in debug mode, which signs in with the emulator and reads
       the local stack, with the stack's anon key passed in.

    Stop the app with q in this window. Stop the emulator with Ctrl+C in
    its window. Or run this script with -Stop, which also stops the stack.

    Run it through run_local.cmd, which bypasses the PowerShell execution
    policy for this script only.

.EXAMPLE
    .\tool\run_local.cmd
    Starts everything and opens the app in Edge.

.EXAMPLE
    .\tool\run_local.cmd -Server
    Serves the app at http://localhost:5556 instead, for any browser.
    The faculty and staff app is at http://localhost:5556/#/staff/login.

.EXAMPLE
    .\tool\run_local.cmd -Reseed
    Loads the demo data again (npx supabase db reset), from scratch.

.EXAMPLE
    .\tool\run_local.cmd -Stop
    Stops the app, the emulator and the Supabase stack.
#>
[CmdletBinding()]
param(
    # Serve the app on a fixed port instead of opening a browser for it.
    [switch]$Server,

    # The port -Server uses.
    [int]$Port = 5556,

    # The browser the app opens in without -Server.
    [ValidateSet('edge', 'chrome')]
    [string]$Device = 'edge',

    # Load the demo data again: every table is emptied and refilled.
    [switch]$Reseed,

    # Stop the app, the emulator and the Supabase stack, then exit.
    [switch]$Stop
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = Split-Path -Parent $PSScriptRoot

# The Auth emulator and the ports its suite opens for itself (UI 4000,
# hub 4400, logging 4500, UI websocket 9150).
$emulatorPorts = 9099, 4000, 4400, 4500, 9150

# What the local stack leaves out on an 8 GB machine (docs/local_setup.md).
$skip = 'studio,imgproxy,vector,logflare,supavisor,mailpit'

# Processes this script may stop to free a port. Anything else holding one
# is reported and left alone.
$ownProcesses = 'java', 'node', 'dart', 'dartvm', 'dartaotruntime'

function Write-Step([string]$message) {
    Write-Host ''
    Write-Host "==> $message" -ForegroundColor Cyan
}

function Stop-WithError([string]$message) {
    Write-Host ''
    Write-Host $message -ForegroundColor Red
    exit 1
}

# The major version a JDK declares in its release file; 0 if unreadable.
function Get-JdkMajor([string]$jdk) {
    $release = Join-Path $jdk 'release'
    if (-not (Test-Path -LiteralPath $release)) { return 0 }
    $match = Select-String -LiteralPath $release -Pattern '^JAVA_VERSION="(\d+)' |
        Select-Object -First 1
    if ($null -eq $match) { return 0 }
    return [int]$match.Matches[0].Groups[1].Value
}

# JAVA_HOME if it is already 21+, otherwise the newest installed JDK that is.
function Find-Jdk21 {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += $env:JAVA_HOME }
    foreach ($vendor in 'Eclipse Adoptium', 'Java', 'Microsoft', 'Zulu', 'Amazon Corretto') {
        $dir = Join-Path $env:ProgramFiles $vendor
        if (Test-Path -LiteralPath $dir) {
            $candidates += Get-ChildItem -LiteralPath $dir -Directory |
                Sort-Object Name -Descending |
                ForEach-Object { $_.FullName }
        }
    }
    foreach ($jdk in $candidates) {
        $java = Join-Path $jdk 'bin\java.exe'
        if ((Get-JdkMajor $jdk) -ge 21 -and (Test-Path -LiteralPath $java)) {
            return $jdk.TrimEnd('\')
        }
    }
    return $null
}

# Who is listening on any of the given ports.
function Get-PortOwners([int[]]$ports) {
    $connections = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $ports -contains $_.LocalPort })
    $owners = foreach ($connection in $connections) {
        $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
        $name = '?'
        if ($process) { $name = $process.ProcessName }
        [pscustomobject]@{
            Port = [int]$connection.LocalPort
            Name = $name
            Id   = [int]$connection.OwningProcess
        }
    }
    $owners | Sort-Object Port, Id -Unique
}

# The window a previous run opened for the emulator, if it is still open.
function Close-EmulatorWindow {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like '*GSUhub Auth emulator*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# Stops the GSUhub processes on the given ports. False if something else
# holds one of them.
function Stop-PortOwners([int[]]$ports) {
    $owners = @(Get-PortOwners $ports)
    if ($owners.Count -eq 0) { return $true }
    $clear = $true
    foreach ($id in ($owners | Select-Object -ExpandProperty Id -Unique)) {
        $held = @($owners | Where-Object { $_.Id -eq $id })
        $name = $held[0].Name
        $portList = ($held | Select-Object -ExpandProperty Port) -join ', '
        if ($ownProcesses -contains $name) {
            Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped $name (process $id) on port $portList"
        } else {
            Write-Host "Left $name (process $id) on port $portList alone - it is not part of GSUhub." -ForegroundColor Yellow
            $clear = $false
        }
    }
    Start-Sleep -Seconds 2
    return $clear
}

function Test-Http([string]$url) {
    try {
        $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2
        return $true
    } catch {
        return $false
    }
}

# The local stack's settings (API_URL, ANON_KEY, ...), or $null when it is
# not running.
function Get-StackStatus {
    $lines = & npx supabase status -o env 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $status = @{}
    foreach ($line in $lines) {
        if ($line -match '^([A-Z_]+)="?(.*?)"?$') { $status[$Matches[1]] = $Matches[2] }
    }
    if (-not $status.ContainsKey('ANON_KEY')) { return $null }
    return $status
}

$opener = $null
Push-Location -LiteralPath $root
try {
    if ($Stop) {
        Write-Step 'Stopping the app and the Auth emulator'
        $null = Stop-PortOwners ($emulatorPorts + $Port)
        Close-EmulatorWindow
        Write-Step 'Stopping the Supabase stack'
        & npx supabase stop
        return
    }

    foreach ($tool in 'flutter', 'dart', 'firebase', 'npx', 'docker') {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Stop-WithError "'$tool' was not found. See docs/local_setup.md for the prerequisites."
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'lib\firebase_options.dart'))) {
        Stop-WithError 'lib/firebase_options.dart is missing. Generate it with flutterfire configure (see README.md).'
    }
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Stop-WithError 'Docker is not running. Open Docker Desktop, wait for "Engine running", and run this again.'
    }

    # --- 1. The Supabase stack ---

    $status = Get-StackStatus
    if ($status) {
        Write-Step 'The Supabase stack is already running - reusing it'
    } else {
        Write-Step 'Starting the Supabase stack (the first start downloads its images and takes a while)'
        & npx supabase start -x $skip
        if ($LASTEXITCODE -ne 0) { Stop-WithError 'The Supabase stack did not start - see the output above.' }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'supabase\functions\.env'))) {
        Write-Step "Writing the token exchange's local secrets, then restarting the stack so it reads them"
        & node tool/supabase_function_env.mjs
        if ($LASTEXITCODE -ne 0) { Stop-WithError 'Writing the local secrets failed - see the output above.' }
        & npx supabase stop
        & npx supabase start -x $skip
        if ($LASTEXITCODE -ne 0) { Stop-WithError 'The Supabase stack did not restart - see the output above.' }
    }
    if ($Reseed) {
        Write-Step 'Loading the demo data again (npx supabase db reset)'
        & npx supabase db reset
        if ($LASTEXITCODE -ne 0) { Stop-WithError 'Loading the demo data failed - see the output above.' }
    }
    $status = Get-StackStatus
    if (-not $status) { Stop-WithError 'Could not read the Supabase stack''s anon key from npx supabase status.' }

    # --- 2. The Auth emulator and the demo accounts ---

    if (Test-Http 'http://127.0.0.1:9099/') {
        Write-Step 'The Auth emulator is already running - reusing it'
    } else {
        $busy = @(Get-PortOwners $emulatorPorts)
        if ($busy.Count -gt 0) {
            Write-Host 'The emulator ports are taken, probably by a run that did not shut down cleanly:' -ForegroundColor Yellow
            $busy | Format-Table Port, Name, Id -AutoSize | Out-Host
            if (-not (Stop-PortOwners $emulatorPorts)) {
                Stop-WithError 'A program that is not part of GSUhub holds one of the ports. Close it and run this again.'
            }
        }
        Close-EmulatorWindow

        $jdk = Find-Jdk21
        if (-not $jdk) {
            Stop-WithError 'Java 21 or newer was not found; the Auth emulator needs it. Install Temurin 21 from https://adoptium.net.'
        }
        # This window only - the machine-wide JAVA_HOME stays as it is for Gradle.
        $env:JAVA_HOME = $jdk
        $env:Path = "$jdk\bin;$env:Path"

        Write-Step "Starting the Auth emulator on Java $(Get-JdkMajor $jdk), in a new window"
        $command = "`$Host.UI.RawUI.WindowTitle = 'GSUhub Auth emulator - Ctrl+C to stop'; firebase emulators:start --only auth"
        Start-Process -FilePath 'powershell.exe' -WorkingDirectory $root `
            -ArgumentList "-NoExit -ExecutionPolicy Bypass -Command `"$command`""

        Write-Host 'Waiting for it to come up...'
        $deadline = (Get-Date).AddMinutes(2)
        while (-not (Test-Http 'http://127.0.0.1:9099/')) {
            if ((Get-Date) -gt $deadline) {
                Stop-WithError "The Auth emulator did not start within 2 minutes. The 'GSUhub Auth emulator' window shows why."
            }
            Start-Sleep -Seconds 2
        }
        Write-Host 'Auth emulator ready.' -ForegroundColor Green
    }

    Write-Step 'Adding the demo sign-in accounts to the Auth emulator'
    & dart run tool/seed.dart auth
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'Adding the sign-in accounts failed - see the output above.' }

    # --- 3. The app ---

    Write-Step 'Starting the app'
    Write-Host 'Administrator:   admin@dorsu.edu.ph / password123'
    Write-Host 'Faculty/Staff:   faculty@dorsu.edu.ph / password123'
    Write-Host 'Maintenance:     personnel@dorsu.edu.ph / password123'
    Write-Host 'Keys in this window: r = hot reload, R = hot restart, q = quit'
    $anon = "--dart-define=SUPABASE_ANON_KEY=$($status['ANON_KEY'])"
    if ($Server) {
        $null = Stop-PortOwners @($Port)
        $url = "http://localhost:$Port"
        Write-Host "The console opens at $url once it has compiled; the mobile apps are at $url/#/staff/login."
        $opener = Start-Job -ArgumentList $url -ScriptBlock {
            param($url)
            $ProgressPreference = 'SilentlyContinue'
            for ($i = 0; $i -lt 300; $i++) {
                try {
                    $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
                    Start-Process $url
                    return
                } catch {
                    Start-Sleep -Seconds 2
                }
            }
        }
        & flutter run -d web-server --web-port $Port $anon
    } else {
        & flutter run -d $Device $anon
    }

    Write-Host ''
    Write-Host 'The app has stopped. The Auth emulator is still running in its own window'
    Write-Host 'and the Supabase stack in Docker; .\tool\run_local.cmd -Stop stops both.'
} finally {
    if ($opener) { Remove-Job $opener -Force }
    Pop-Location
}

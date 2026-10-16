<#
.SYNOPSIS
  Builds the GSUhub Android release APK against LIVE Firebase, signed with
  the release key.

.DESCRIPTION
  Steps: [flutter clean] -> flutter pub get -> flutter build apk --release
  (one APK per CPU type by default) -> release check (no emulator
  references) -> prints each APK's path, size and signing certificate.

  Needs SUPABASE_URL and SUPABASE_ANON_KEY in the environment: the hosted
  Supabase project the app reads its data from.

  Needs android\key.properties and the keystore it names (see
  docs\manual_deploy.md, "Release signing"). Refuses to build without
  them: a debug-signed install cannot later be updated by a release one.

.PARAMETER Universal
  Build one APK that runs on every phone, instead of one per CPU type.
  Bigger, but there is only one file to share.

.PARAMETER Clean
  Run flutter clean first.

.EXAMPLE
  .\scripts\build_apk.ps1
  .\scripts\build_apk.ps1 -Universal
#>
[CmdletBinding()]
param(
  [switch]$Universal,
  [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$outputDir = Join-Path $root 'build\app\outputs\flutter-apk'

function Stop-Build([string]$message) {
  Write-Host "`nSTOPPED: $message" -ForegroundColor Red
  exit 1
}

# Runs a native command and stops on a non-zero exit code. Native tools
# write progress to stderr, which must not count as a failure by itself.
function Invoke-Step([string]$name, [scriptblock]$command) {
  Write-Host "`n==> $name" -ForegroundColor Cyan
  $ErrorActionPreference = 'Continue'
  $global:LASTEXITCODE = 0
  & $command
  if ($LASTEXITCODE -ne 0) { Stop-Build "$name failed (exit code $LASTEXITCODE)." }
}

foreach ($required in 'lib\firebase_options.dart', 'android\app\google-services.json') {
  if (-not (Test-Path (Join-Path $root $required))) {
    Stop-Build "$required is missing. It is gitignored; see docs\firebase_setup.md."
  }
}

# The database (Objective 1): the hosted Supabase project's URL and anon
# key, read from the environment so neither is committed. Never the
# service-role key; the app refuses to start with it.
foreach ($name in 'SUPABASE_URL', 'SUPABASE_ANON_KEY') {
  if (-not [Environment]::GetEnvironmentVariable($name)) {
    Stop-Build "$name is not set. Set it in this window first: `$env:$name = '...' (see docs\manual_deploy.md)."
  }
}

$keyProperties = Join-Path $root 'android\key.properties'
if (-not (Test-Path $keyProperties)) {
  Stop-Build ('android\key.properties is missing, so the APK would be signed with the debug key. ' +
    'Create the release keystore first: docs\manual_deploy.md, "Release signing".')
}
$storeLine = Select-String -Path $keyProperties -Pattern '^\s*storeFile\s*=\s*(.+?)\s*$' | Select-Object -First 1
if (-not $storeLine) { Stop-Build 'android\key.properties has no storeFile line.' }
$storeFile = $storeLine.Matches[0].Groups[1].Value
if (-not [System.IO.Path]::IsPathRooted($storeFile)) { $storeFile = Join-Path $root "android\app\$storeFile" }
if (-not (Test-Path $storeFile)) { Stop-Build "The keystore named in android\key.properties does not exist: $storeFile" }

$version = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$commit = (git rev-parse --short HEAD) 2>$null
Write-Host "Building GSUhub $version ($commit) for LIVE Firebase" -ForegroundColor Yellow

$started = Get-Date
if ($Clean) { Invoke-Step 'flutter clean' { flutter clean } }
Invoke-Step 'flutter pub get' { flutter pub get }
# A release build uses live Firebase; IS_PRODUCTION makes that explicit.
if ($Universal) {
  Invoke-Step 'flutter build apk --release' {
    flutter build apk --release --dart-define=IS_PRODUCTION=true "--dart-define=SUPABASE_URL=$env:SUPABASE_URL" "--dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY"
  }
} else {
  Invoke-Step 'flutter build apk --release --split-per-abi' {
    flutter build apk --release --split-per-abi --dart-define=IS_PRODUCTION=true "--dart-define=SUPABASE_URL=$env:SUPABASE_URL" "--dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY"
  }
}

$apks = Get-ChildItem $outputDir -Filter '*-release.apk' |
  Where-Object { $_.LastWriteTime -ge $started } |
  Sort-Object Name
if (-not $apks) { Stop-Build "No release APK was written to $outputDir." }

Invoke-Step 'release check' {
  & (Join-Path $PSScriptRoot 'check_release_output.ps1') -Apk ($apks | ForEach-Object { $_.FullName })
}

# The signing certificate, to confirm it is the release key and for the
# SHA-1 the Firebase Console asks for.
$buildTools = Get-ChildItem (Join-Path $env:ANDROID_HOME 'build-tools') -Directory -ErrorAction SilentlyContinue |
  Sort-Object { [version]($_.Name -replace '[^\d.].*$', '') } -Descending | Select-Object -First 1
$apksigner = if ($buildTools) { Join-Path $buildTools.FullName 'apksigner.bat' }
if ($apksigner -and (Test-Path $apksigner)) {
  Write-Host "`n==> signing certificate" -ForegroundColor Cyan
  $ErrorActionPreference = 'Continue'
  & $apksigner verify --print-certs $apks[0].FullName 2>&1 |
    Select-String -Pattern 'certificate DN|SHA-1|SHA-256' | ForEach-Object { "  $($_.Line.Trim())" }
  $ErrorActionPreference = 'Stop'
}

Write-Host "`nBuilt GSUhub $version ($commit):" -ForegroundColor Green
foreach ($apk in $apks) {
  '  {0,-34} {1,6:N1} MB   {2}' -f $apk.Name, ($apk.Length / 1MB), $apk.FullName
}
if ($Universal) {
  Write-Host "`nShare app-release.apk - it installs on any Android 8.0+ phone."
} else {
  Write-Host "`nShare app-arm64-v8a-release.apk - it fits almost every phone from the last several years."
  Write-Host 'For an older 32-bit phone, use app-armeabi-v7a-release.apk; if unsure, build again with -Universal.'
}
Write-Host 'Install or update over USB:  adb install -r <apk>'

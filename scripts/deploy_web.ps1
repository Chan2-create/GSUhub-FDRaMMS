<#
.SYNOPSIS
  Builds the GSUhub admin web console against LIVE Firebase and deploys it
  to Vercel.

.DESCRIPTION
  Vercel's build image has no Flutter, and lib\firebase_options.dart is
  gitignored, so the site is built here and the finished build\web folder
  is uploaded as-is.

  Steps: [flutter clean] -> flutter pub get -> flutter build web --release
  -> copy deploy\vercel.json in -> release check (no emulator references)
  -> vercel deploy. Stops at the first step that fails.

  Needs SUPABASE_URL and SUPABASE_ANON_KEY in the environment: the hosted
  Supabase project the console reads its data from.

  The first deploy asks Vercel's link questions (see docs\manual_deploy.md).
  The link is then kept in .vercel\ at the repo root (gitignored) and
  copied into build\web before each deploy, so a rebuild or flutter clean
  does not lose it.

.PARAMETER Clean
  Run flutter clean first.

.PARAMETER Preview
  Deploy a preview URL instead of production (gsuhub-dorsu.vercel.app).

.PARAMETER SkipDeploy
  Build and check only; upload nothing.

.EXAMPLE
  .\scripts\deploy_web.ps1
  .\scripts\deploy_web.ps1 -Clean
  .\scripts\deploy_web.ps1 -SkipDeploy
#>
[CmdletBinding()]
param(
  [switch]$Clean,
  [switch]$Preview,
  [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$web = Join-Path $root 'build\web'

function Stop-Deploy([string]$message) {
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
  if ($LASTEXITCODE -ne 0) { Stop-Deploy "$name failed (exit code $LASTEXITCODE)." }
}

if (-not (Test-Path (Join-Path $root 'lib\firebase_options.dart'))) {
  Stop-Deploy 'lib\firebase_options.dart is missing. It is gitignored; see docs\firebase_setup.md.'
}

# The database (Objective 1): the hosted Supabase project's URL and anon
# key, read from the environment so neither is committed. Never the
# service-role key; the app refuses to start with it.
foreach ($name in 'SUPABASE_URL', 'SUPABASE_ANON_KEY') {
  if (-not [Environment]::GetEnvironmentVariable($name)) {
    Stop-Deploy "$name is not set. Set it in this window first: `$env:$name = '...' (see docs\manual_deploy.md)."
  }
}
if (-not $SkipDeploy) {
  if (-not (Get-Command vercel -ErrorAction SilentlyContinue)) {
    Stop-Deploy 'The Vercel CLI is not installed. Run: npm install --global vercel@latest'
  }
  $ErrorActionPreference = 'Continue'
  vercel whoami 2>&1 | Out-Null
  $signedIn = $LASTEXITCODE -eq 0
  $ErrorActionPreference = 'Stop'
  if (-not $signedIn) { Stop-Deploy 'Not signed in to Vercel. Run: vercel login' }
}

$commit = (git rev-parse --short HEAD) 2>$null
$branch = (git rev-parse --abbrev-ref HEAD) 2>$null
Write-Host "Building $branch @ $commit for LIVE Firebase" -ForegroundColor Yellow

if ($Clean) { Invoke-Step 'flutter clean' { flutter clean } }
Invoke-Step 'flutter pub get' { flutter pub get }
# A release build uses live Firebase; IS_PRODUCTION makes that explicit.
Invoke-Step 'flutter build web --release' {
  flutter build web --release --dart-define=IS_PRODUCTION=true "--dart-define=SUPABASE_URL=$env:SUPABASE_URL" "--dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY"
}

Write-Host "`n==> copy deploy\vercel.json into build\web" -ForegroundColor Cyan
Copy-Item (Join-Path $root 'deploy\vercel.json') (Join-Path $web 'vercel.json') -Force

Invoke-Step 'release check' {
  & (Join-Path $PSScriptRoot 'check_release_output.ps1') -WebDir $web
}

if ($SkipDeploy) {
  Write-Host "`nBuilt and checked: $web (not deployed, -SkipDeploy)." -ForegroundColor Green
  exit 0
}

# Keep the Vercel link across rebuilds: repo-root .vercel\ <-> build\web\.vercel\.
$savedLink = Join-Path $root '.vercel\project.json'
$buildLink = Join-Path $web '.vercel\project.json'
if (Test-Path $savedLink) {
  New-Item -ItemType Directory -Force (Split-Path $buildLink) | Out-Null
  Copy-Item $savedLink $buildLink -Force
}

if ($Preview) {
  Invoke-Step 'vercel deploy (preview)' { vercel deploy $web }
} else {
  Invoke-Step 'vercel deploy --prod' { vercel deploy $web --prod }
}

if (-not (Test-Path $savedLink) -and (Test-Path $buildLink)) {
  New-Item -ItemType Directory -Force (Split-Path $savedLink) | Out-Null
  Copy-Item $buildLink $savedLink -Force
  Write-Host 'Saved the Vercel project link to .vercel\ for next time.' -ForegroundColor Green
}

Write-Host "`nDeployed $branch @ $commit." -ForegroundColor Green

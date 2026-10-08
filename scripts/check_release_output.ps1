<#
.SYNOPSIS
  Fails if a release build still points at the Firebase emulators.

.DESCRIPTION
  Checks a built web folder (-WebDir) or Android APKs (-Apk) for:
    - 127.0.0.1 or 10.0.2.2 anywhere;
    - an emulator port in host:port form (:8080 Firestore, :9099 Auth,
      :9199 Storage);
  and confirms the live project id from lib/firebase_options.dart was
  compiled in. Then, by build type:

  Web: "localhost" anywhere, except one line in the firebase_auth_web
  package that compares the page's own hostname to it. A build that
  connects to the emulators calls them with ("localhost", 9099) and
  similar, and fails here.

  APK: it reads lib/<abi>/libapp.so, where the app's Dart code is. The
  compiled code keeps one shared copy of each string, and Flutter's own
  code already holds a "localhost", so that word proves nothing there.
  Instead it fails on the emulator calls themselves (useAuthEmulator,
  useFirestoreEmulator, useStorageEmulator), which are compiled in only
  when the app uses them, and on 10.0.2.2, which they bring with them.
  Firebase's Android SDKs carry emulator support of their own; that is
  not evidence the app uses the emulator, so they are not searched.

  Bare numbers such as 8080 are not searched for: they turn up inside
  unrelated larger numbers and CanvasKit's symbol files.

  Both rules were checked against a build forced onto the emulator
  (--dart-define=USE_EMULATOR=true), which each fails.

.EXAMPLE
  .\scripts\check_release_output.ps1 -WebDir build\web
  .\scripts\check_release_output.ps1 -Apk build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
#>
[CmdletBinding()]
param(
  [string]$WebDir,
  [string[]]$Apk
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# The one "localhost" the release web build is allowed to contain:
# firebase_auth_web's `window.location.hostname == "localhost"` check.
$allowedLocalhost = 'location\.hostname,"localhost"'
$forbidden = @(
  @{ Name = 'loopback address 127.0.0.1'; Pattern = '127\.0\.0\.1' },
  @{ Name = 'Android emulator host 10.0.2.2'; Pattern = '10\.0\.2\.2' },
  @{ Name = 'emulator port (:8080, :9099, :9199)'; Pattern = ':(8080|9099|9199)(?!\d)' }
)
# Only in an APK: the FlutterFire calls that point the app at the emulators.
$forbiddenInApk = @(
  @{ Name = 'emulator connection (useAuthEmulator)'; Pattern = 'useAuthEmulator' },
  @{ Name = 'emulator connection (useFirestoreEmulator)'; Pattern = 'useFirestoreEmulator' },
  @{ Name = 'emulator connection (useStorageEmulator)'; Pattern = 'useStorageEmulator' }
)

function Get-LiveProjectId {
  $options = Join-Path $root 'lib\firebase_options.dart'
  if (-not (Test-Path $options)) {
    throw "lib\firebase_options.dart is missing. It is gitignored; see docs\firebase_setup.md."
  }
  $match = [regex]::Match((Get-Content $options -Raw), "projectId:\s*'([^']+)'")
  if (-not $match.Success) { throw 'No projectId found in lib\firebase_options.dart.' }
  return $match.Groups[1].Value
}

# Text in a file, one byte per character, so binary files can be searched
# for ASCII strings without decoding errors.
function Read-Latin1([byte[]]$bytes) {
  return [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
}

function Find-Problems([string]$label, [string]$text, [switch]$Apk) {
  $problems = @()
  $rules = if ($Apk) { $forbidden + $forbiddenInApk } else { $forbidden }
  foreach ($rule in $rules) {
    foreach ($m in [regex]::Matches($text, $rule.Pattern)) {
      $start = [Math]::Max(0, $m.Index - 40)
      $context = $text.Substring($start, [Math]::Min(100, $text.Length - $start)) -replace '[^\x20-\x7E]', '.'
      $problems += "  ${label}: $($rule.Name)`n      ...$context..."
    }
  }
  if ($Apk) { return , $problems }
  foreach ($m in [regex]::Matches($text, 'localhost')) {
    $start = [Math]::Max(0, $m.Index - 30)
    $window = $text.Substring($start, [Math]::Min(60, $text.Length - $start))
    if ($window -match $allowedLocalhost) { continue }
    $context = $window -replace '[^\x20-\x7E]', '.'
    $problems += "  ${label}: localhost`n      ...$context..."
  }
  return , $problems
}

if (-not $WebDir -and -not $Apk) { throw 'Give -WebDir or -Apk.' }

$projectId = Get-LiveProjectId
$problems = @()
$foundProjectId = $false

if ($WebDir) {
  $dir = Resolve-Path $WebDir
  Get-ChildItem $dir -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.vercel\\' } | ForEach-Object {
    $text = Read-Latin1 ([System.IO.File]::ReadAllBytes($_.FullName))
    $relative = $_.FullName.Substring($dir.Path.Length + 1)
    $problems += Find-Problems $relative $text
    if ($text.Contains($projectId)) { $foundProjectId = $true }
  }
}

if ($Apk) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  foreach ($path in $Apk) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $path))
    try {
      $libs = $zip.Entries | Where-Object { $_.FullName -match '^lib/[^/]+/libapp\.so$' }
      if (-not $libs) { throw "$path contains no libapp.so - is it a Flutter release APK?" }
      foreach ($entry in $libs) {
        $stream = $entry.Open()
        try {
          $buffer = New-Object System.IO.MemoryStream
          $stream.CopyTo($buffer)
          $text = Read-Latin1 $buffer.ToArray()
        } finally { $stream.Dispose() }
        $label = "$(Split-Path $path -Leaf)!$($entry.FullName)"
        $problems += Find-Problems $label $text -Apk
        if ($text.Contains($projectId)) { $foundProjectId = $true }
      }
    } finally { $zip.Dispose() }
  }
}

if (-not $foundProjectId) {
  $problems += "  live project id '$projectId' not found in the build - it may not use lib\firebase_options.dart"
}

if ($problems.Count -gt 0) {
  Write-Host 'RELEASE CHECK FAILED - this build may point at the emulators:' -ForegroundColor Red
  $problems | ForEach-Object { Write-Host $_ -ForegroundColor Red }
  exit 1
}

Write-Host "Release check passed: no emulator references; live project '$projectId'." -ForegroundColor Green
exit 0

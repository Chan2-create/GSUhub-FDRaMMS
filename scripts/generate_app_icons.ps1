<#
.SYNOPSIS
  Draws GSUhub's app icons from the logo: the Android launcher icon
  (adaptive for Android 8 and later, classic for older phones) and the
  web console's install icons.

.DESCRIPTION
  The icon is the logo's gear mark on white. The wordmark beside it would
  be unreadable at launcher size, and Android prints "GSUhub" under the
  icon anyway. The mark is found in the logo as its first run of drawn
  columns, left to right.

  Run it from the repository root whenever the logo changes, then rebuild
  the APK and redeploy the web console. A larger logo file gives sharper
  icons: the gear in assets\images\gsuhub_logo.png is only about 140 px
  wide, so the largest icons are drawn up from it.

.PARAMETER Logo
  The logo to draw from. Defaults to the one the app shows.

.EXAMPLE
  .\scripts\generate_app_icons.ps1

.EXAMPLE
  .\scripts\generate_app_icons.ps1 -Logo C:\Users\chris\Downloads\gsuhub_logo_1024.png
#>
param(
  [string]$Logo = 'assets\images\gsuhub_logo.png'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($Logo)) { $Logo = Join-Path $root $Logo }
if (-not (Test-Path $Logo)) { throw "The logo was not found: $Logo" }

# --- where the gear mark is ------------------------------------------------

$source = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Logo).Path)
$w = $source.Width
$h = $source.Height
$whole = New-Object System.Drawing.Rectangle 0, 0, $w, $h
$data = $source.LockBits($whole, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
  [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$bytes = New-Object byte[] ($stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
$source.UnlockBits($data)

# Drawn: visible and not near-white. Pixels are stored B, G, R, A.
$drawn = New-Object 'bool[,]' $w, $h
$columnDrawn = New-Object bool[] $w
for ($y = 0; $y -lt $h; $y++) {
  $row = $y * $stride
  for ($x = 0; $x -lt $w; $x++) {
    $i = $row + 4 * $x
    if ($bytes[$i + 3] -gt 40 -and -not ($bytes[$i + 2] -gt 235 -and $bytes[$i + 1] -gt 235 -and $bytes[$i] -gt 235)) {
      $drawn[$x, $y] = $true
      $columnDrawn[$x] = $true
    }
  }
}

$x0 = -1
$x1 = -1
for ($x = 0; $x -lt $w; $x++) {
  if ($columnDrawn[$x]) {
    if ($x0 -lt 0) { $x0 = $x }
    $x1 = $x
  } elseif ($x0 -ge 0) {
    break
  }
}
if ($x0 -lt 0) { throw "Nothing is drawn in $Logo." }

$y0 = $h
$y1 = -1
for ($y = 0; $y -lt $h; $y++) {
  for ($x = $x0; $x -le $x1; $x++) {
    if ($drawn[$x, $y]) {
      if ($y -lt $y0) { $y0 = $y }
      if ($y -gt $y1) { $y1 = $y }
      break
    }
  }
}

# A few transparent pixels around it, so its edges are not cut when drawn.
$pad = 3
$left = [Math]::Max(0, $x0 - $pad)
$top = [Math]::Max(0, $y0 - $pad)
$right = [Math]::Min($w - 1, $x1 + $pad)
$bottom = [Math]::Min($h - 1, $y1 + $pad)
$mark = New-Object System.Drawing.RectangleF $left, $top, ($right - $left + 1), ($bottom - $top + 1)
Write-Host ("Gear mark: {0} x {1} px at ({2}, {3}) in {4}" -f ($x1 - $x0 + 1), ($y1 - $y0 + 1), $x0, $y0, (Split-Path -Leaf $Logo))

# --- drawing an icon -------------------------------------------------------

# Size: the icon's side in pixels. Share: the mark's longer side, as a share
# of the icon. Fill: 'none' (transparent), 'full' (white to the edges) or
# 'tile' (a white tile with rounded corners, a sixteenth in from each edge,
# as classic launcher icons are drawn).
function Save-Icon {
  param([int]$Size, [double]$Share, [string]$Fill, [string]$Out)

  $bmp = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    if ($Fill -eq 'full') {
      $g.Clear([System.Drawing.Color]::White)
    } elseif ($Fill -eq 'tile') {
      $inset = $Size / 16.0
      $side = $Size - 2 * $inset
      $d = 2 * ($side * 0.2)
      $path = New-Object System.Drawing.Drawing2D.GraphicsPath
      $path.AddArc($inset, $inset, $d, $d, 180, 90)
      $path.AddArc($inset + $side - $d, $inset, $d, $d, 270, 90)
      $path.AddArc($inset + $side - $d, $inset + $side - $d, $d, $d, 0, 90)
      $path.AddArc($inset, $inset + $side - $d, $d, $d, 90, 90)
      $path.CloseFigure()
      $g.FillPath([System.Drawing.Brushes]::White, $path)
      $path.Dispose()
    }

    $scale = ($Size * $Share) / [Math]::Max($mark.Width, $mark.Height)
    $dw = $mark.Width * $scale
    $dh = $mark.Height * $scale
    $dx = ($Size - $dw) / 2
    $dy = ($Size - $dh) / 2
    $corners = [System.Drawing.PointF[]]@(
      (New-Object System.Drawing.PointF $dx, $dy),
      (New-Object System.Drawing.PointF ($dx + $dw), $dy),
      (New-Object System.Drawing.PointF $dx, ($dy + $dh))
    )
    $attributes = New-Object System.Drawing.Imaging.ImageAttributes
    $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
    $g.DrawImage($source, $corners, $mark, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
    $attributes.Dispose()
  } finally {
    $g.Dispose()
  }

  $folder = Split-Path -Parent $Out
  if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Force $folder | Out-Null }
  $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host ("  {0,4} px  {1}" -f $Size, $Out.Substring($root.Length + 1))
}

function Save-Text([string]$Out, [string]$Text) {
  $folder = Split-Path -Parent $Out
  if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Force $folder | Out-Null }
  [System.IO.File]::WriteAllText($Out, $Text, (New-Object System.Text.UTF8Encoding $false))
  Write-Host ("          {0}" -f $Out.Substring($root.Length + 1))
}

# --- Android ----------------------------------------------------------------

$res = Join-Path $root 'android\app\src\main\res'

# Android 8 and later: the mark on its own layer over a white one, which
# the phone masks to its own shape (circle, squircle, rounded square).
# The layer is 108 dp; the phone shows the middle 72 dp and only the middle
# 66 dp is sure to show, so the round gear is drawn about 50 dp across, the
# size launcher logos usually are.
Write-Host "`nAndroid 8 and later (adaptive icon)"
$layer = [ordered]@{ mdpi = 108; hdpi = 162; xhdpi = 216; xxhdpi = 324; xxxhdpi = 432 }
foreach ($density in $layer.Keys) {
  Save-Icon -Size $layer[$density] -Share 0.46 -Fill 'none' -Out (Join-Path $res "mipmap-$density\ic_launcher_foreground.png")
}
Save-Text (Join-Path $res 'mipmap-anydpi-v26\ic_launcher.xml') (@(
  '<?xml version="1.0" encoding="utf-8"?>',
  '<!-- Drawn by scripts/generate_app_icons.ps1 from the GSUhub logo. -->',
  '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">',
  '    <background android:drawable="@color/ic_launcher_background" />',
  '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />',
  '</adaptive-icon>',
  '') -join "`r`n")
Save-Text (Join-Path $res 'values\ic_launcher_background.xml') (@(
  '<?xml version="1.0" encoding="utf-8"?>',
  '<!-- The adaptive icon''s back layer: white, behind the gear mark. -->',
  '<resources>',
  '    <color name="ic_launcher_background">#FFFFFF</color>',
  '</resources>',
  '') -join "`r`n")

# Older phones show the picture as it is: the mark on a white tile.
Write-Host "`nAndroid 7 and earlier (classic icon)"
$classic = [ordered]@{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }
foreach ($density in $classic.Keys) {
  Save-Icon -Size $classic[$density] -Share 0.6 -Fill 'tile' -Out (Join-Path $res "mipmap-$density\ic_launcher.png")
}

# --- web console ------------------------------------------------------------

# Used when the console is installed or added to a home screen. The tab
# icon, web\favicon.png, is the gear mark already and is left alone.
Write-Host "`nWeb console"
$web = Join-Path $root 'web\icons'
Save-Icon -Size 192 -Share 0.6 -Fill 'tile' -Out (Join-Path $web 'Icon-192.png')
Save-Icon -Size 512 -Share 0.6 -Fill 'tile' -Out (Join-Path $web 'Icon-512.png')
# Maskable: the browser crops to its own shape; the middle 80 % is safe.
Save-Icon -Size 192 -Share 0.56 -Fill 'full' -Out (Join-Path $web 'Icon-maskable-192.png')
Save-Icon -Size 512 -Share 0.56 -Fill 'full' -Out (Join-Path $web 'Icon-maskable-512.png')
# iPhone and iPad round the corners themselves, and fill transparency black.
Save-Icon -Size 180 -Share 0.62 -Fill 'full' -Out (Join-Path $web 'apple-touch-icon.png')

$source.Dispose()
Write-Host "`nDone. Rebuild the APK, and redeploy the web console, to see them."

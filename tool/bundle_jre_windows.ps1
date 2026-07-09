# Copy monorepo vendor JRE 21 next to a Windows runner (Debug/Release).
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File tool/bundle_jre_windows.ps1
#   powershell -ExecutionPolicy Bypass -File tool/bundle_jre_windows.ps1 -Target apps/yomu_desktop/build/windows/x64/runner/Release

param(
  [string]$Target = "apps/yomu_desktop/build/windows/x64/runner/Release"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$jreSrc = Join-Path $root "packages\yomu_suwayomi\vendor\jre21"
$destRoot = if ([System.IO.Path]::IsPathRooted($Target)) { $Target } else { Join-Path $root $Target }
$jreDst = Join-Path $destRoot "jre"

if (-not (Test-Path (Join-Path $jreSrc "bin\java.exe"))) {
  throw "Vendor JRE missing: $jreSrc\bin\java.exe"
}

Write-Host "Copying JRE 21 -> $jreDst"
if (Test-Path $jreDst) { Remove-Item -Recurse -Force $jreDst }
New-Item -ItemType Directory -Path $jreDst | Out-Null
Copy-Item -Path (Join-Path $jreSrc "*") -Destination $jreDst -Recurse -Force

$ver = & (Join-Path $jreDst "bin\java.exe") -version 2>&1 | Out-String
Write-Host $ver
if ($ver -notmatch 'version "2[1-9]') {
  throw "Bundled java is not 21+"
}
Write-Host "OK: packaged JRE ready at $jreDst"

# Fetch pinned Temurin JRE 21 (Windows x64), verify SHA-256, extract to vendor/jre21.
# Usage (repo root):
#   powershell -ExecutionPolicy Bypass -File tool/fetch_jre21_windows.ps1
#   powershell -ExecutionPolicy Bypass -File tool/fetch_jre21_windows.ps1 -UpdateManifestHash

param(
  [switch]$UpdateManifestHash
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $root "packages\yomu_suwayomi\vendor\jre_manifest.json"
$vendorDir = Join-Path $root "packages\yomu_suwayomi\vendor"
$destJre = Join-Path $vendorDir "jre21"
$cacheDir = Join-Path $vendorDir ".jre_cache"

if (-not (Test-Path $manifestPath)) { throw "Missing $manifestPath" }
$man = Get-Content $manifestPath -Raw | ConvertFrom-Json
$j = $man.jre
$url = [string]$j.downloadUrl
$expected = ([string]$j.sha256).ToLowerInvariant()
$ver = [string]$j.version

Write-Host "Pinned JRE: $ver"
Write-Host "URL: $url"
Write-Host "License: $($j.license) ($($j.licenseUrl))"

New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
$zipName = "OpenJDK21U-jre_x64_windows_hotspot.zip"
$zipPath = Join-Path $cacheDir $zipName

if (-not (Test-Path $zipPath)) {
  Write-Host "Downloading..."
  Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
}

$hash = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLowerInvariant()
Write-Host "SHA-256: $hash"

if ($UpdateManifestHash -or $expected -eq 'placeholder_fill_on_fetch' -or $expected -eq '') {
  $raw = Get-Content $manifestPath -Raw
  $raw = $raw -replace '"sha256"\s*:\s*"[^"]*"', ('"sha256": "' + $hash + '"')
  Set-Content -Path $manifestPath -Value $raw -NoNewline
  Write-Host "Updated manifest hash."
  $expected = $hash
}

if ($hash -ne $expected) {
  throw "SHA-256 mismatch. expected=$expected actual=$hash"
}

$extractTmp = Join-Path $cacheDir "extract_$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $extractTmp | Out-Null
try {
  Expand-Archive -Path $zipPath -DestinationPath $extractTmp -Force
  # Zip usually has one top-level folder
  $inner = Get-ChildItem $extractTmp -Directory | Select-Object -First 1
  if (-not $inner) { throw "No directory in JRE zip" }
  $javaProbe = Join-Path $inner.FullName "bin\java.exe"
  if (-not (Test-Path $javaProbe)) { throw "bin/java.exe missing in extract" }

  if (Test-Path $destJre) { Remove-Item -Recurse -Force $destJre }
  Move-Item -Path $inner.FullName -Destination $destJre

  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $verOut = & (Join-Path $destJre "bin\java.exe") -version 2>&1 | ForEach-Object { "$_" }
  } finally { $ErrorActionPreference = $prev }
  $verText = $verOut -join "`n"
  Write-Host $verText
  if ($verText -notmatch 'version "2[1-9]') { throw "Extracted JRE is not 21+" }
  Write-Host "OK: $destJre"
} finally {
  if (Test-Path $extractTmp) { Remove-Item -Recurse -Force $extractTmp }
}

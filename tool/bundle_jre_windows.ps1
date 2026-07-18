# Create an explicit offline Windows bundle for development or release staging.
# JRE/JAR/source inputs must already be prepared by fetch_jre21_windows.ps1.

param(
  [string]$Target = 'apps/yomu_desktop/build/windows/x64/runner/Release',
  [string]$SourceArchivePath = ''
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$vendor = Join-Path $root 'packages\yomu_suwayomi\vendor'
$manifestPath = Join-Path $vendor 'engine_manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$targetRoot = if ([System.IO.Path]::IsPathRooted($Target)) {
  [System.IO.Path]::GetFullPath($Target)
} else {
  [System.IO.Path]::GetFullPath((Join-Path $root $Target))
}
if ([System.IO.Path]::GetPathRoot($targetRoot) -eq $targetRoot) {
  throw "Refusing to use a filesystem root as bundle target: $targetRoot"
}
New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null

$jreSource = Join-Path $vendor ([string]$manifest.jre.localVendorPath)
$jarSource = Join-Path $vendor ([string]$manifest.suwayomi.jarFile)
$noticesSource = Join-Path $root ([string]$manifest.noticesFile)
$pwaSource = Join-Path $root 'apps\yomu_mobile_pwa'
$sourceArchive = if ($SourceArchivePath) {
  [System.IO.Path]::GetFullPath($SourceArchivePath)
} else {
  Join-Path $vendor ".jre_cache\$($manifest.jre.source.archiveFile)"
}

foreach ($required in @(
  (Join-Path $jreSource ([string]$manifest.jre.executable)),
  $jarSource,
  $manifestPath,
  $noticesSource,
  (Join-Path $pwaSource 'index.html'),
  $sourceArchive
)) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "Offline bundle prerequisite missing: $required"
  }
}

$jreDestination = Join-Path $targetRoot 'jre'
$engineDestination = Join-Path $targetRoot 'engine'
$licensesDestination = Join-Path $targetRoot 'licenses'
$pwaDestination = Join-Path $targetRoot 'pwa'

foreach ($destination in @(
  $jreDestination,
  $engineDestination,
  $licensesDestination,
  $pwaDestination
)) {
  $full = [System.IO.Path]::GetFullPath($destination)
  if (-not $full.StartsWith($targetRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Computed bundle destination escaped target root: $full"
  }
  if (Test-Path -LiteralPath $full) {
    Remove-Item -LiteralPath $full -Recurse -Force
  }
  New-Item -ItemType Directory -Path $full | Out-Null
}

Copy-Item -Path (Join-Path $jreSource '*') -Destination $jreDestination -Recurse -Force
Copy-Item -LiteralPath $manifestPath -Destination $engineDestination
Copy-Item -LiteralPath $jarSource -Destination $engineDestination
Copy-Item -LiteralPath $noticesSource -Destination $licensesDestination
Copy-Item -Path (Join-Path $pwaSource '*') -Destination $pwaDestination -Recurse -Force

& (Join-Path $root 'tool\verify_engine_bundle.ps1') `
  -BundleRoot $targetRoot `
  -SourceArchivePath $sourceArchive
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "PASS: offline engine bundle ready at $targetRoot"

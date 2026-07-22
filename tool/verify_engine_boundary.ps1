$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Get-DartFiles([string[]]$relativeRoots) {
  $files = @()
  foreach ($relativeRoot in $relativeRoots) {
    $path = Join-Path $root $relativeRoot
    if (Test-Path -LiteralPath $path) {
      $files += Get-ChildItem -LiteralPath $path -Recurse -File -Filter '*.dart'
    }
  }
  return @($files)
}

function Assert-NoMatch(
  [System.IO.FileInfo[]]$files,
  [string]$pattern,
  [string]$message
) {
  foreach ($file in $files) {
    $matches = Select-String -LiteralPath $file.FullName -Pattern $pattern
    if ($matches) {
      $first = $matches | Select-Object -First 1
      $relative = [IO.Path]::GetRelativePath($root, $file.FullName)
      throw "$message ($relative`:$($first.LineNumber))"
    }
  }
}

$desktopFiles = Get-DartFiles @('apps/yomu_desktop/lib')
$screenFiles = Get-DartFiles @('apps/yomu_desktop/lib/screens')
$coreFiles = Get-DartFiles @('packages/yomu_core/lib')
$localServerFiles = Get-DartFiles @('packages/yomu_local_server')
$aiFiles = Get-DartFiles @('packages/yomu_ai')

# Desktop vendor implementation is restricted to the composition root.
$compositionRoot = [IO.Path]::GetFullPath(
  (Join-Path $root 'apps/yomu_desktop/lib/shell/home_shell.dart'))
$desktopBoundaryFiles = @(
  $desktopFiles | Where-Object { $_.FullName -ne $compositionRoot }
)
$vendorBoundaryFiles = @($desktopBoundaryFiles + $coreFiles)
$productBoundaryFiles = @($desktopFiles + $coreFiles)
foreach ($file in $desktopFiles) {
  $importsVendor = Select-String -LiteralPath $file.FullName `
    -Pattern "package:yomu_suwayomi/"
  if ($importsVendor -and $file.FullName -ne $compositionRoot) {
    $relative = [IO.Path]::GetRelativePath($root, $file.FullName)
    throw "Direct yomu_suwayomi import outside composition root: $relative"
  }
}

Assert-NoMatch @($localServerFiles + $aiFiles) `
  'package:yomu_suwayomi/|\byomu_suwayomi\b' `
  'yomu_local_server/yomu_ai must not depend on yomu_suwayomi'

$vendorDtos = @(
  'ExtensionStoreInfo', 'ExtensionInfo', 'SourceInfo', 'MangaSummary',
  'SourceMangaFetchType', 'SourceMangaPage', 'MangaDetails', 'ChapterInfo',
  'DownloadQueueItem', 'DownloadStatusInfo', 'ChapterPages', 'SuwayomiApi',
  'SuwayomiClient', 'SuwayomiStatus', 'SuwayomiProcessState') -join '|'
Assert-NoMatch $vendorBoundaryFiles "\b($vendorDtos)\b" `
  'Vendor DTO/client/process state leaked into desktop UI or Yomu Core'
Assert-NoMatch $productBoundaryFiles '\babsoluteUrl\b' `
  'absoluteUrl leaked into desktop UI or Yomu Core'
Assert-NoMatch $productBoundaryFiles '(127\.0\.0\.1|localhost):14567|https?://[^\s''"]*:14567' `
  'Internal engine URL leaked into desktop UI or Yomu Core'
Assert-NoMatch $desktopFiles '\bImage\.network\s*\(' `
  'Desktop screen bypasses opaque EngineMediaGateway references'
Assert-NoMatch $productBoundaryFiles `
  '[''"](Started|Stopped|Queued|Downloading|Finished|Error)[''"]' `
  'Upstream download state string leaked into desktop UI or Yomu Core'

# Product copy may name Suwayomi only on a screen backed by generic diagnostics.
foreach ($file in $screenFiles) {
  $brand = Select-String -LiteralPath $file.FullName -Pattern '\bSuwayomi\b'
  if (-not $brand) { continue }
  $genericDiagnostics = Select-String -LiteralPath $file.FullName `
    -Pattern '\bEngineDiagnosticsSnapshot\b'
  if (-not $genericDiagnostics) {
    $relative = [IO.Path]::GetRelativePath($root, $file.FullName)
    throw "Suwayomi product copy outside generic Diagnostics UI: $relative"
  }
}

Write-Host 'ENGINE BOUNDARY GUARD PASSED'

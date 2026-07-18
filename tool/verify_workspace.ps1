# Yomu workspace verification (Windows PowerShell)
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File tool/verify_workspace.ps1
param(
  [switch]$VerifyOfflineEngineBundle
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$flutterBin = if (Test-Path 'C:\src\flutter\bin\flutter.bat') {
  'C:\src\flutter\bin'
} else {
  ''
}
if ($flutterBin) {
  $env:Path = "$flutterBin;" + $env:Path
}

Write-Host '== dart pub get (workspace) =='
dart pub get

Write-Host '== flutter analyze (repo root) =='
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '== package tests =='
Push-Location packages/yomu_core
dart test
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Pop-Location

Push-Location packages/yomu_suwayomi
dart test
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Pop-Location

Push-Location packages/yomu_local_server
dart test
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Pop-Location

Push-Location packages/yomu_ai
dart test
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Pop-Location

Push-Location packages/yomu_storage
dart test
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Pop-Location

Write-Host '== PWA preload + reader race logic =='
node apps/yomu_mobile_pwa/test_preload_logic.mjs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
node apps/yomu_mobile_pwa/test_reader_races.mjs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '== desktop tests =='
Push-Location apps/yomu_desktop
flutter test
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Pop-Location

Write-Host '== flutter build windows --debug =='
Push-Location apps/yomu_desktop
flutter build windows --debug
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Pop-Location

if ($VerifyOfflineEngineBundle) {
  Write-Host '== offline engine bundle + corresponding source =='
  $engineManifest = Get-Content `
    'packages/yomu_suwayomi/vendor/engine_manifest.json' -Raw | ConvertFrom-Json
  $sourceArchive = Join-Path $root `
    "packages/yomu_suwayomi/vendor/.jre_cache/$($engineManifest.jre.source.archiveFile)"
  & (Join-Path $root 'tool/verify_engine_bundle.ps1') `
    -BundleRoot (Join-Path $root 'apps/yomu_desktop/build/windows/x64/runner/Debug') `
    -SourceArchivePath $sourceArchive
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host '== ALL CHECKS PASSED =='
exit 0

# Yomu workspace verification (Windows PowerShell)
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File tool/verify_workspace.ps1
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

Write-Host '== ALL CHECKS PASSED =='
exit 0

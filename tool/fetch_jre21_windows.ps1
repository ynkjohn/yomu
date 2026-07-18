# Prepare the exact offline engine inputs pinned by engine_manifest.json.
# The legacy filename is preserved for existing developer documentation.
# No hash or version is ever updated by this script.

param(
  [switch]$UpdateManifestHash
)

$ErrorActionPreference = 'Stop'
if ($UpdateManifestHash) {
  throw 'Manifest hash updates require a separately approved version change.'
}

$root = Split-Path -Parent $PSScriptRoot
$vendorDir = Join-Path $root 'packages\yomu_suwayomi\vendor'
$manifestPath = Join-Path $vendorDir 'engine_manifest.json'
$cacheDir = Join-Path $vendorDir '.jre_cache'
$destJre = Join-Path $vendorDir 'jre21'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "Missing unified engine manifest: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([int]$manifest.schemaVersion -ne 1) {
  throw "Unsupported engine manifest schema: $($manifest.schemaVersion)"
}
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

function Get-Sha256Hex([string]$Path) {
  $stream = [System.IO.File]::OpenRead($Path)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hex = [System.BitConverter]::ToString($sha.ComputeHash($stream))
    return $hex.Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
    $stream.Dispose()
  }
}

function Get-VerifiedArtifact(
  [string]$Url,
  [string]$FileName,
  [string]$ExpectedSha256,
  [string]$Label
) {
  if ($ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "$Label manifest SHA-256 is malformed: $ExpectedSha256"
  }
  $path = Join-Path $cacheDir $FileName
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    Write-Host "Downloading $Label..."
    $partial = "$path.partial"
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    try {
      Invoke-WebRequest -Uri $Url -OutFile $partial -UseBasicParsing
      Move-Item -LiteralPath $partial -Destination $path
    } finally {
      if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    }
  }

  $actual = Get-Sha256Hex $path
  if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
    throw "$Label SHA-256 mismatch. expected=$ExpectedSha256 actual=$actual path=$path"
  }
  Write-Host "Verified ${Label}: $actual"
  return $path
}

$jreArchive = Get-VerifiedArtifact `
  ([string]$manifest.jre.downloadUrl) `
  ([string]$manifest.jre.archiveFile) `
  ([string]$manifest.jre.sha256) `
  'Temurin JRE'

$sourceArchive = Get-VerifiedArtifact `
  ([string]$manifest.jre.source.downloadUrl) `
  ([string]$manifest.jre.source.archiveFile) `
  ([string]$manifest.jre.source.sha256) `
  'Temurin corresponding source'

$buildSourceArchive = Get-VerifiedArtifact `
  ([string]$manifest.jre.source.build.downloadUrl) `
  ([string]$manifest.jre.source.build.archiveFile) `
  ([string]$manifest.jre.source.build.sha256) `
  'Temurin build source'

$provenanceFile = Get-VerifiedArtifact `
  ([string]$manifest.jre.source.provenance.downloadUrl) `
  ([string]$manifest.jre.source.provenance.metadataFile) `
  ([string]$manifest.jre.source.provenance.sha256) `
  'Temurin build provenance'

$jarCache = Get-VerifiedArtifact `
  ([string]$manifest.suwayomi.downloadUrl) `
  ([string]$manifest.suwayomi.jarFile) `
  ([string]$manifest.suwayomi.sha256) `
  'Suwayomi JAR'

$suwayomiSourceArchive = Get-VerifiedArtifact `
  ([string]$manifest.suwayomi.sourceArchiveUrl) `
  ([string]$manifest.suwayomi.sourceArchiveFile) `
  ([string]$manifest.suwayomi.sourceSha256) `
  'Suwayomi source'

$sourceEntries = @(& tar -tzf $sourceArchive)
if ($LASTEXITCODE -ne 0) {
  throw "Unable to inspect corresponding-source archive: $sourceArchive"
}
foreach ($required in @($manifest.jre.source.requiredEntries)) {
  if ($sourceEntries -notcontains [string]$required) {
    throw "Corresponding-source build material missing: $required"
  }
}

$buildSourceEntries = @(& tar -tzf $buildSourceArchive)
if ($LASTEXITCODE -ne 0) {
  throw "Unable to inspect Temurin build source: $buildSourceArchive"
}
foreach ($required in @($manifest.jre.source.build.requiredEntries)) {
  if ($buildSourceEntries -notcontains [string]$required) {
    throw "Temurin build material missing: $required"
  }
}

$provenance = Get-Content -LiteralPath $provenanceFile -Raw | ConvertFrom-Json
if ([string]$provenance.sha256 -ne [string]$manifest.jre.sha256) {
  throw 'Temurin provenance does not identify the pinned JRE hash.'
}
if ([string]$provenance.scmRef -ne [string]$manifest.jre.source.scmRef) {
  throw 'Temurin provenance SCM ref does not match the manifest.'
}
if ([string]$provenance.openjdk_source -notmatch [regex]::Escape([string]$manifest.jre.source.openJdkSourceCommit)) {
  throw 'Temurin provenance OpenJDK commit does not match the manifest.'
}
if ([string]$provenance.buildRef -notmatch [regex]::Escape([string]$manifest.jre.source.build.commit)) {
  throw 'Temurin provenance build commit does not match the manifest.'
}
foreach ($requiredArg in @('--create-jre-image', '--use-jep319-certs', '--tag jdk-21.0.11+10_adopt')) {
  if ([string]$provenance.makejdk_any_platform_args -notmatch [regex]::Escape($requiredArg)) {
    throw "Temurin provenance is missing build argument: $requiredArg"
  }
}

$suwayomiSourceEntries = @(& tar -tzf $suwayomiSourceArchive)
if ($LASTEXITCODE -ne 0) {
  throw "Unable to inspect Suwayomi source: $suwayomiSourceArchive"
}
foreach ($required in @($manifest.suwayomi.sourceRequiredEntries)) {
  if ($suwayomiSourceEntries -notcontains [string]$required) {
    throw "Suwayomi source material missing: $required"
  }
}

$extractRoot = Join-Path $cacheDir "extract_$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $extractRoot | Out-Null
try {
  Expand-Archive -LiteralPath $jreArchive -DestinationPath $extractRoot -Force
  $inner = Get-ChildItem -LiteralPath $extractRoot -Directory | Select-Object -First 1
  if (-not $inner) { throw 'No top-level directory found in the JRE archive.' }

  $javaProbe = Join-Path $inner.FullName ([string]$manifest.jre.executable)
  if (-not (Test-Path -LiteralPath $javaProbe -PathType Leaf)) {
    throw "Packaged Java missing after extraction: $javaProbe"
  }
  foreach ($relative in @($manifest.jre.requiredNoticePaths)) {
    $notice = Join-Path $inner.FullName ([string]$relative)
    if (-not (Test-Path -LiteralPath $notice -PathType Leaf)) {
      throw "Required JRE notice missing after extraction: $relative"
    }
  }

  if (Test-Path -LiteralPath $destJre) {
    Remove-Item -LiteralPath $destJre -Recurse -Force
  }
  Move-Item -LiteralPath $inner.FullName -Destination $destJre
} finally {
  if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
  }
}

$jarDestination = Join-Path $vendorDir ([string]$manifest.suwayomi.jarFile)
$jarTemp = "$jarDestination.partial"
if (Test-Path -LiteralPath $jarTemp) { Remove-Item -LiteralPath $jarTemp -Force }
try {
  Copy-Item -LiteralPath $jarCache -Destination $jarTemp
  $copiedHash = Get-Sha256Hex $jarTemp
  if ($copiedHash -ne ([string]$manifest.suwayomi.sha256).ToLowerInvariant()) {
    throw "Copied Suwayomi JAR failed integrity verification: $copiedHash"
  }
  if (Test-Path -LiteralPath $jarDestination) {
    Remove-Item -LiteralPath $jarDestination -Force
  }
  Move-Item -LiteralPath $jarTemp -Destination $jarDestination
} finally {
  if (Test-Path -LiteralPath $jarTemp) { Remove-Item -LiteralPath $jarTemp -Force }
}

$javaExe = Join-Path $destJre ([string]$manifest.jre.executable)
$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  $versionText = (& $javaExe -version 2>&1 | ForEach-Object { "$_" }) -join "`n"
  $javaExit = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previous
}
if ($javaExit -ne 0 -or $versionText -notmatch 'Temurin-21\.0\.11\+10') {
  throw "Extracted Java is not the pinned Temurin 21.0.11+10:`n$versionText"
}

Write-Host $versionText
Write-Host "PASS: offline engine inputs are ready under $vendorDir"
Write-Host 'Release-source set retained outside the installer:'
Write-Host "  $sourceArchive"
Write-Host "  $buildSourceArchive"
Write-Host "  $provenanceFile"
Write-Host "  $suwayomiSourceArchive"

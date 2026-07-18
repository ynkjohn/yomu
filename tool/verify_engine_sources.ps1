param(
  [Parameter(Mandatory = $true)]
  [string]$ManifestPath,

  [Parameter(Mandatory = $true)]
  [string]$PrimarySourceArchivePath
)

$ErrorActionPreference = 'Stop'

function Resolve-ExistingFile([string]$Path, [string]$Label) {
  $full = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
    throw "$Label missing: $full"
  }
  return $full
}

function Assert-SafeRelativePath([string]$Relative, [string]$Label) {
  if ([string]::IsNullOrWhiteSpace($Relative) -or
      [System.IO.Path]::IsPathRooted($Relative)) {
    throw "$Label must be a non-empty relative path: $Relative"
  }
  $segments = @($Relative -split '[\\/]' | Where-Object { $_ -ne '' })
  if ($segments.Count -eq 0 -or
      @($segments | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
    throw "$Label escapes its declared artifact root: $Relative"
  }
}

function Assert-LeafFileName([string]$Name, [string]$Label) {
  Assert-SafeRelativePath $Name $Label
  if ([System.IO.Path]::GetFileName($Name) -ne $Name -or
      $Name.Contains('/') -or $Name.Contains('\')) {
    throw "$Label must be a leaf file name: $Name"
  }
}

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

function Assert-Sha256([string]$Path, [string]$Expected, [string]$Label) {
  if ($Expected -notmatch '^[0-9a-fA-F]{64}$') {
    throw "$Label manifest SHA-256 is malformed: $Expected"
  }
  $actual = Get-Sha256Hex $Path
  if ($actual -ne $Expected.ToLowerInvariant()) {
    throw "$Label SHA-256 mismatch. expected=$Expected actual=$actual"
  }
}

function Read-TarEntry([string]$Archive, [string]$Entry, [string]$Label) {
  Assert-SafeRelativePath $Entry $Label
  $text = (& tar -xOzf $Archive $Entry 2>&1) -join "`n"
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to read $Label from archive: $Entry"
  }
  return $text
}

function Resolve-SourceAsset(
  [string]$Directory,
  [string]$FileName,
  [string]$Label
) {
  Assert-LeafFileName $FileName $Label
  return Resolve-ExistingFile (Join-Path $Directory $FileName) $Label
}

$manifestFile = Resolve-ExistingFile $ManifestPath 'Engine manifest'
$manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
if ([int]$manifest.schemaVersion -ne 1) {
  throw "Unsupported engine manifest schema: $($manifest.schemaVersion)"
}

$primarySource = Resolve-ExistingFile `
  $PrimarySourceArchivePath `
  'JRE corresponding source'
$sourceDirectory = Split-Path -Parent $primarySource
$source = $manifest.jre.source
Assert-LeafFileName ([string]$source.archiveFile) `
  'JRE corresponding-source asset'
if ([System.IO.Path]::GetFileName($primarySource) -ne [string]$source.archiveFile) {
  throw "Corresponding-source filename mismatch. expected=$($source.archiveFile) actual=$([System.IO.Path]::GetFileName($primarySource))"
}
if ([string]$source.distributionPolicy -ne
    'GPL-2.0-section-3a-same-download-location') {
  throw "Unexpected corresponding-source policy: $($source.distributionPolicy)"
}
Assert-Sha256 $primarySource ([string]$source.sha256) `
  'JRE corresponding source'

$entries = @(& tar -tzf $primarySource)
if ($LASTEXITCODE -ne 0) {
  throw "Unable to inspect corresponding-source archive: $primarySource"
}
foreach ($required in @($source.requiredEntries)) {
  Assert-SafeRelativePath ([string]$required) 'Corresponding-source entry'
  if ($entries -notcontains [string]$required) {
    throw "Corresponding-source build material missing: $required"
  }
}
$sourceLicenseEntry = @(
  $source.requiredEntries | Where-Object { $_ -like '*/LICENSE' }
)[0]
$sourceAdditionalEntry = @(
  $source.requiredEntries |
    Where-Object { $_ -like '*/ADDITIONAL_LICENSE_INFO' }
)[0]
$sourceLicense = Read-TarEntry $primarySource `
  ([string]$sourceLicenseEntry) `
  'OpenJDK source GPLv2 license'
if ($sourceLicense -notmatch 'Version 2, June 1991') {
  throw 'OpenJDK source archive does not contain the expected GPLv2 license.'
}
$sourceAdditional = Read-TarEntry $primarySource `
  ([string]$sourceAdditionalEntry) `
  'OpenJDK source Classpath Exception notice'
if ($sourceAdditional -notmatch 'GNU Classpath Exception') {
  throw 'OpenJDK source archive does not contain the Classpath Exception notice.'
}

$buildSource = $source.build
$buildSourcePath = Resolve-SourceAsset `
  $sourceDirectory `
  ([string]$buildSource.archiveFile) `
  'Temurin build source'
Assert-Sha256 $buildSourcePath ([string]$buildSource.sha256) `
  'Temurin build source'
$buildEntries = @(& tar -tzf $buildSourcePath)
if ($LASTEXITCODE -ne 0) {
  throw "Unable to inspect Temurin build source: $buildSourcePath"
}
foreach ($required in @($buildSource.requiredEntries)) {
  Assert-SafeRelativePath ([string]$required) 'Temurin build-source entry'
  if ($buildEntries -notcontains [string]$required) {
    throw "Temurin build material missing: $required"
  }
}
$buildLicenseEntry = @(
  $buildSource.requiredEntries | Where-Object { $_ -like '*/LICENSE' }
)[0]
$buildNoticeEntry = @(
  $buildSource.requiredEntries | Where-Object { $_ -like '*/NOTICE' }
)[0]
$buildLicense = Read-TarEntry $buildSourcePath `
  ([string]$buildLicenseEntry) `
  'Temurin build-source license'
if ($buildLicense -notmatch 'Apache License' -or
    $buildLicense -notmatch 'Version 2\.0') {
  throw 'Temurin build-source archive does not contain the expected Apache-2.0 license.'
}
$buildNotice = Read-TarEntry $buildSourcePath `
  ([string]$buildNoticeEntry) `
  'Temurin build-source NOTICE'
if ($buildNotice -notmatch 'IBM Corporation 2017') {
  throw 'Temurin build-source archive does not contain its expected NOTICE.'
}

$provenancePath = Resolve-SourceAsset `
  $sourceDirectory `
  ([string]$source.provenance.metadataFile) `
  'Temurin build provenance'
Assert-Sha256 $provenancePath ([string]$source.provenance.sha256) `
  'Temurin build provenance'
$provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
if ([string]$provenance.sha256 -ne [string]$manifest.jre.sha256) {
  throw 'Temurin provenance does not identify the pinned JRE binary.'
}
if ([string]$provenance.scmRef -ne [string]$source.scmRef) {
  throw 'Temurin provenance SCM ref does not match the manifest.'
}
if ([string]$provenance.openjdk_source -notmatch
    [regex]::Escape([string]$source.openJdkSourceCommit)) {
  throw 'Temurin provenance OpenJDK commit does not match the manifest.'
}
if ([string]$provenance.buildRef -notmatch
    [regex]::Escape([string]$buildSource.commit)) {
  throw 'Temurin provenance build commit does not match the manifest.'
}
$provenanceVersion = [string]$provenance.version.version
if (-not $provenanceVersion.StartsWith(
  [string]$manifest.jre.version,
  [System.StringComparison]::Ordinal
)) {
  throw 'Temurin provenance version does not match the manifest.'
}
foreach ($requiredArg in @(
  '--create-jre-image',
  '--use-jep319-certs',
  '--tag jdk-21.0.11+10_adopt'
)) {
  if ([string]$provenance.makejdk_any_platform_args -notmatch
      [regex]::Escape($requiredArg)) {
    throw "Temurin provenance is missing build argument: $requiredArg"
  }
}

$suwayomiSourcePath = Resolve-SourceAsset `
  $sourceDirectory `
  ([string]$manifest.suwayomi.sourceArchiveFile) `
  'Suwayomi source'
Assert-Sha256 $suwayomiSourcePath `
  ([string]$manifest.suwayomi.sourceSha256) `
  'Suwayomi source'
$suwayomiEntries = @(& tar -tzf $suwayomiSourcePath)
if ($LASTEXITCODE -ne 0) {
  throw "Unable to inspect Suwayomi source: $suwayomiSourcePath"
}
foreach ($required in @($manifest.suwayomi.sourceRequiredEntries)) {
  Assert-SafeRelativePath ([string]$required) 'Suwayomi source entry'
  if ($suwayomiEntries -notcontains [string]$required) {
    throw "Suwayomi source material missing: $required"
  }
}
$suwayomiLicenseEntry = [string]$manifest.suwayomi.sourceRequiredEntries[0]
$suwayomiLicense = Read-TarEntry $suwayomiSourcePath `
  $suwayomiLicenseEntry `
  'Suwayomi source license'
if ($suwayomiLicense -notmatch 'Mozilla Public License Version 2\.0') {
  throw 'Suwayomi source archive does not expose the expected MPL-2.0 license.'
}

Write-Host 'PASS: complete corresponding-source set is verified.'
Write-Host "OpenJDK source: $($source.archiveFile)"
Write-Host "Temurin build source: $($buildSource.archiveFile)"
Write-Host "Temurin provenance: $($source.provenance.metadataFile)"
Write-Host "Suwayomi source: $($manifest.suwayomi.sourceArchiveFile)"

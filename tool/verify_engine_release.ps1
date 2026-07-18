param(
  [Parameter(Mandatory = $true)]
  [string]$ReleaseDirectory,

  [Parameter(Mandatory = $true)]
  [string]$BinaryArtifactPath
)

$ErrorActionPreference = 'Stop'

function Get-Sha256HexFromStream([System.IO.Stream]$Stream) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hex = [System.BitConverter]::ToString($sha.ComputeHash($Stream))
    return $hex.Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-Sha256HexFromFile([string]$Path) {
  $stream = [System.IO.File]::OpenRead($Path)
  try {
    return Get-Sha256HexFromStream $stream
  } finally {
    $stream.Dispose()
  }
}

function Read-ZipEntryText(
  [System.IO.Compression.ZipArchiveEntry]$Entry,
  [string]$Label
) {
  $stream = $Entry.Open()
  $reader = New-Object System.IO.StreamReader($stream)
  try {
    return $reader.ReadToEnd()
  } finally {
    $reader.Dispose()
    $stream.Dispose()
  }
}

function Assert-SafeZipEntry([string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Contains('\')) {
    throw "Unsafe release archive entry: $Name"
  }
  $segments = @($Name -split '/' | Where-Object { $_ -ne '' })
  if ($segments.Count -eq 0 -or
      @($segments | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0 -or
      [System.IO.Path]::IsPathRooted($Name)) {
    throw "Unsafe release archive entry: $Name"
  }
}

$release = [System.IO.Path]::GetFullPath($ReleaseDirectory).TrimEnd(
  [char[]]@('\', '/')
)
if (-not (Test-Path -LiteralPath $release -PathType Container)) {
  throw "Release directory missing: $release"
}

$binary = [System.IO.Path]::GetFullPath($BinaryArtifactPath)
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
  throw "Binary release artifact missing: $binary"
}
$binaryDirectory = [System.IO.Path]::GetFullPath(
  [System.IO.Path]::GetDirectoryName($binary)
).TrimEnd([char[]]@('\', '/'))
if (-not [string]::Equals(
  $binaryDirectory,
  $release,
  [System.StringComparison]::OrdinalIgnoreCase
)) {
  throw 'Binary artifact must be directly inside the release directory.'
}
if ((Get-Item -LiteralPath $binary).Length -le 0) {
  throw "Binary release artifact is empty: $binary"
}
if ([System.IO.Path]::GetExtension($binary) -ne '.zip') {
  throw 'Unsupported release artifact. R2 verifies portable ZIP bundles only; an installer requires its own content-aware gate.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$repoRoot = Split-Path -Parent $PSScriptRoot
$canonicalManifestPath = [System.IO.Path]::GetFullPath(
  (Join-Path `
    $repoRoot `
    'packages\yomu_suwayomi\vendor\engine_manifest.json')
)
if (-not (Test-Path -LiteralPath $canonicalManifestPath -PathType Leaf)) {
  throw "Canonical engine manifest missing: $canonicalManifestPath"
}
$canonicalManifestHash = Get-Sha256HexFromFile $canonicalManifestPath
$canonicalJreRoot = [System.IO.Path]::GetFullPath(
  (Join-Path $repoRoot 'packages\yomu_suwayomi\vendor\jre21')
).TrimEnd([char[]]@('\', '/'))
if (-not (Test-Path -LiteralPath $canonicalJreRoot -PathType Container)) {
  throw "Canonical packaged JRE missing: $canonicalJreRoot"
}
$canonicalNoticesPath = [System.IO.Path]::GetFullPath(
  (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md')
)
$canonicalPwaPath = [System.IO.Path]::GetFullPath(
  (Join-Path $repoRoot 'apps\yomu_mobile_pwa\index.html')
)
foreach ($requiredCanonical in @($canonicalNoticesPath, $canonicalPwaPath)) {
  if (-not (Test-Path -LiteralPath $requiredCanonical -PathType Leaf)) {
    throw "Canonical release input missing: $requiredCanonical"
  }
}
$archive = [System.IO.Compression.ZipFile]::OpenRead($binary)
try {
  $entries = @{}
  foreach ($entry in $archive.Entries) {
    Assert-SafeZipEntry $entry.FullName
    if ($entry.FullName.EndsWith('/')) { continue }
    if ($entries.ContainsKey($entry.FullName)) {
      throw "Duplicate release archive entry: $($entry.FullName)"
    }
    $entries[$entry.FullName] = $entry
  }

  $manifestMatches = @(
    $entries.Keys | Where-Object {
      $_ -eq 'engine/engine_manifest.json' -or
      $_ -like '*/engine/engine_manifest.json'
    }
  )
  if ($manifestMatches.Count -ne 1) {
    throw "Release archive must contain exactly one engine manifest; found $($manifestMatches.Count)."
  }
  $manifestEntryName = [string]$manifestMatches[0]
  $suffix = 'engine/engine_manifest.json'
  $prefix = $manifestEntryName.Substring(
    0,
    $manifestEntryName.Length - $suffix.Length
  )

  $manifestStream = $entries[$manifestEntryName].Open()
  try {
    $embeddedManifestHash = Get-Sha256HexFromStream $manifestStream
  } finally {
    $manifestStream.Dispose()
  }
  if ($embeddedManifestHash -ne $canonicalManifestHash) {
    throw 'Release archive engine manifest differs from the repository-pinned manifest.'
  }

  function Require-Entry([string]$Relative, [string]$Label) {
    if ($Relative.Contains('\') -or $Relative.StartsWith('/') -or
        $Relative -match '(^|/)\.\.(/|$)') {
      throw "$Label has an unsafe relative path: $Relative"
    }
    $name = $prefix + $Relative
    if (-not $entries.ContainsKey($name)) {
      throw "$Label missing from release archive: $name"
    }
    return $entries[$name]
  }

  function Assert-EntryMatchesFile(
    [string]$Relative,
    [string]$CanonicalPath,
    [string]$Label
  ) {
    $entry = Require-Entry $Relative $Label
    $canonicalFile = Get-Item -LiteralPath $CanonicalPath
    if ($entry.Length -ne $canonicalFile.Length) {
      throw "$Label length differs from the canonical release input: $Relative"
    }
    $entryStream = $entry.Open()
    try {
      $entryHash = Get-Sha256HexFromStream $entryStream
    } finally {
      $entryStream.Dispose()
    }
    $canonicalHash = Get-Sha256HexFromFile $canonicalFile.FullName
    if ($entryHash -ne $canonicalHash) {
      throw "$Label differs from the canonical release input: $Relative"
    }
    return $entry
  }

  $manifestText = Read-ZipEntryText `
    $entries[$manifestEntryName] `
    'Engine manifest'
  $manifest = $manifestText | ConvertFrom-Json
  if ([int]$manifest.schemaVersion -ne 1) {
    throw "Unsupported engine manifest schema: $($manifest.schemaVersion)"
  }

  $desktopEntry = Require-Entry `
    'yomu_desktop.exe' `
    'Yomu desktop executable'
  if ($desktopEntry.Length -le 0) {
    throw 'Yomu desktop executable is empty inside the release archive.'
  }
  $jarEntry = Require-Entry `
    ("engine/" + [string]$manifest.suwayomi.jarFile) `
    'Suwayomi JAR'
  $jarStream = $jarEntry.Open()
  try {
    $jarHash = Get-Sha256HexFromStream $jarStream
  } finally {
    $jarStream.Dispose()
  }
  if ($jarHash -ne ([string]$manifest.suwayomi.sha256).ToLowerInvariant()) {
    throw "Suwayomi JAR SHA-256 mismatch inside release archive. expected=$($manifest.suwayomi.sha256) actual=$jarHash"
  }

  $canonicalJreFiles = @(
    Get-ChildItem -LiteralPath $canonicalJreRoot -Recurse -File
  )
  $archiveJreEntries = @(
    $entries.Keys | Where-Object { $_.StartsWith(
      $prefix + 'jre/',
      [System.StringComparison]::OrdinalIgnoreCase
    ) }
  )
  if ($archiveJreEntries.Count -ne $canonicalJreFiles.Count) {
    throw "Release archive JRE file count differs from the canonical JRE. expected=$($canonicalJreFiles.Count) actual=$($archiveJreEntries.Count)"
  }
  $canonicalJrePrefix = $canonicalJreRoot +
    [System.IO.Path]::DirectorySeparatorChar
  foreach ($file in $canonicalJreFiles) {
    if (-not $file.FullName.StartsWith(
      $canonicalJrePrefix,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
      throw "Canonical JRE file escaped its root: $($file.FullName)"
    }
    $relative = $file.FullName.Substring($canonicalJrePrefix.Length).
      Replace('\', '/')
    Assert-EntryMatchesFile `
      ("jre/" + $relative) `
      $file.FullName `
      'Packaged JRE file' | Out-Null
  }

  $releaseEntry = Require-Entry 'jre/release' 'JRE release metadata'
  $releaseText = Read-ZipEntryText $releaseEntry 'JRE release metadata'
  foreach ($requiredText in @(
    'IMPLEMENTOR="Eclipse Adoptium"',
    'IMPLEMENTOR_VERSION="Temurin-21.0.11+10"',
    'JAVA_RUNTIME_VERSION="21.0.11+10-LTS"',
    'SOURCE=".:git:254494ad7d75"',
    'BUILD_SOURCE="git:a612825ee82a20ac872d60958c349854c1f29a8e"',
    'IMAGE_TYPE="JRE"'
  )) {
    if ($releaseText -notmatch [regex]::Escape($requiredText)) {
      throw "JRE release metadata missing required text: $requiredText"
    }
  }
  foreach ($relative in @($manifest.jre.requiredNoticePaths)) {
    Require-Entry ("jre/" + [string]$relative).Replace('\', '/') `
      "JRE notice $relative" | Out-Null
  }
  $jreLicense = Read-ZipEntryText `
    (Require-Entry 'jre/legal/java.base/LICENSE' 'JRE GPLv2 license') `
    'JRE GPLv2 license'
  if ($jreLicense -notmatch 'Version 2, June 1991') {
    throw 'Release archive lacks the expected JRE GPLv2 license.'
  }
  $jreAdditional = Read-ZipEntryText `
    (Require-Entry `
      'jre/legal/java.base/ADDITIONAL_LICENSE_INFO' `
      'JRE Classpath Exception notice') `
    'JRE Classpath Exception notice'
  if ($jreAdditional -notmatch 'GNU Classpath Exception') {
    throw 'Release archive lacks the JRE Classpath Exception notice.'
  }
  $jreNotice = Read-ZipEntryText `
    (Require-Entry 'jre/NOTICE' 'JRE NOTICE') `
    'JRE NOTICE'
  if ($jreNotice -notmatch 'Notices for Eclipse Temurin') {
    throw 'Release archive lacks the expected JRE NOTICE.'
  }

  $noticesEntry = Assert-EntryMatchesFile `
    ("licenses/" + [string]$manifest.noticesFile) `
    $canonicalNoticesPath `
    'Third-party notices'
  $notices = Read-ZipEntryText $noticesEntry 'Third-party notices'
  Assert-EntryMatchesFile `
    'pwa/index.html' `
    $canonicalPwaPath `
    'Bundled PWA' | Out-Null
  foreach ($requiredText in @(
    'Suwayomi-Server v2.3.2238',
    'Eclipse Temurin 21.0.11+10',
    'GPLv2',
    'Classpath Exception',
    'MPL-2.0',
    'OpenJDK21U-jdk-sources_21.0.11_10.tar.gz',
    'temurin-build-a612825ee82a20ac872d60958c349854c1f29a8e.tar.gz',
    'OpenJDK21U-jre_x64_windows_hotspot_21.0.11_10.zip.json',
    'Suwayomi-Server-a1770cb0553e37c1f660a88c23afd7badde11328.tar.gz'
  )) {
    if ($notices -notmatch [regex]::Escape($requiredText)) {
      throw "Third-party notices missing required text: $requiredText"
    }
  }

  $requiredSourceAssets = @(
    [string]$manifest.jre.source.archiveFile,
    [string]$manifest.jre.source.build.archiveFile,
    [string]$manifest.jre.source.provenance.metadataFile,
    [string]$manifest.suwayomi.sourceArchiveFile
  )
  foreach ($fileName in $requiredSourceAssets) {
    if ([string]::IsNullOrWhiteSpace($fileName) -or
        [System.IO.Path]::IsPathRooted($fileName) -or
        [System.IO.Path]::GetFileName($fileName) -ne $fileName -or
        $fileName.Contains('/') -or $fileName.Contains('\')) {
      throw "Release source asset must be a leaf file name: $fileName"
    }
    $path = Join-Path $release $fileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Release source asset missing beside binary archive: $fileName"
    }
  }

  & (Join-Path $PSScriptRoot 'verify_engine_sources.ps1') `
    -ManifestPath $canonicalManifestPath `
    -PrimarySourceArchivePath `
      (Join-Path $release ([string]$manifest.jre.source.archiveFile))
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  $archive.Dispose()
}

Write-Host 'PASS: release ZIP contains the verified engine and complete source set is beside it.'
Write-Host "Release directory: $release"
Write-Host "Binary archive: $([System.IO.Path]::GetFileName($binary))"

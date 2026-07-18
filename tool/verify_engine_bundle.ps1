param(
  [Parameter(Mandatory = $true)]
  [string]$BundleRoot,

  [Parameter(Mandatory = $true)]
  [string]$SourceArchivePath
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

function Resolve-WithinRoot(
  [string]$Root,
  [string]$Relative,
  [string]$Label
) {
  Assert-SafeRelativePath $Relative $Label
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
  $full = [System.IO.Path]::GetFullPath((Join-Path $rootFull $Relative))
  $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
  if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Label escaped its declared artifact root: $full"
  }
  return Resolve-ExistingFile $full $Label
}

function Assert-FileContains([string]$Path, [string]$Expected, [string]$Label) {
  $text = Get-Content -LiteralPath $Path -Raw
  if ($text -notmatch [regex]::Escape($Expected)) {
    throw "$Label is missing required text: $Expected"
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

$bundle = [System.IO.Path]::GetFullPath($BundleRoot)
if (-not (Test-Path -LiteralPath $bundle -PathType Container)) {
  throw "Bundle root missing: $bundle"
}

$manifestPath = Resolve-ExistingFile `
  (Join-Path $bundle 'engine\engine_manifest.json') `
  'Engine manifest'
$canonicalManifestPath = Resolve-ExistingFile `
  (Join-Path `
    (Split-Path -Parent $PSScriptRoot) `
    'packages\yomu_suwayomi\vendor\engine_manifest.json') `
  'Canonical engine manifest'
if ((Get-Sha256Hex $manifestPath) -ne
    (Get-Sha256Hex $canonicalManifestPath)) {
  throw 'Bundled engine manifest differs from the repository-pinned manifest.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

if ([int]$manifest.schemaVersion -ne 1) {
  throw "Unsupported engine manifest schema: $($manifest.schemaVersion)"
}

$jarPath = Resolve-WithinRoot `
  (Join-Path $bundle 'engine') `
  ([string]$manifest.suwayomi.jarFile) `
  'Suwayomi JAR'
Assert-Sha256 $jarPath ([string]$manifest.suwayomi.sha256) 'Suwayomi JAR'

if ([string]$manifest.suwayomi.license -ne 'MPL-2.0') {
  throw "Unexpected Suwayomi license: $($manifest.suwayomi.license)"
}
if ([string]$manifest.suwayomi.sourceUrl -notmatch '^https://') {
  throw 'Suwayomi source URL must be an HTTPS version-pinned location.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$jar = [System.IO.Compression.ZipFile]::OpenRead($jarPath)
try {
  $jarEntries = @($jar.Entries | ForEach-Object { $_.FullName })
  foreach ($required in @('LICENSE', 'NOTICE')) {
    if ($jarEntries -notcontains $required) {
      throw "Suwayomi JAR notice entry missing: $required"
    }
  }
} finally {
  $jar.Dispose()
}

$jreRoot = Join-Path $bundle 'jre'
$javaPath = Resolve-WithinRoot `
  $jreRoot `
  ([string]$manifest.jre.executable) `
  'Packaged Java'
foreach ($relative in @($manifest.jre.requiredNoticePaths)) {
  Resolve-WithinRoot $jreRoot ([string]$relative) "JRE notice $relative" |
    Out-Null
}
Assert-FileContains (Join-Path $jreRoot 'legal\java.base\LICENSE') `
  'Version 2, June 1991' 'JRE GPLv2 license'
Assert-FileContains (Join-Path $jreRoot 'legal\java.base\ADDITIONAL_LICENSE_INFO') `
  'GNU Classpath Exception' 'JRE Classpath Exception notice'
Assert-FileContains (Join-Path $jreRoot ([string]$manifest.jre.noticeFile)) `
  'Notices for Eclipse Temurin' 'JRE NOTICE'

$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  $javaVersion = (& $javaPath -version 2>&1 | ForEach-Object { "$_" }) -join "`n"
  $javaExit = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previous
}
if ($javaExit -ne 0 -or $javaVersion -notmatch 'Temurin-21\.0\.11\+10') {
  throw "Packaged Java is not the pinned Temurin 21.0.11+10:`n$javaVersion"
}

$noticesPath = Resolve-WithinRoot `
  (Join-Path $bundle 'licenses') `
  ([string]$manifest.noticesFile) `
  'Third-party notices'
$notices = Get-Content -LiteralPath $noticesPath -Raw
Resolve-WithinRoot (Join-Path $bundle 'pwa') 'index.html' 'Bundled PWA' |
  Out-Null
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

& (Join-Path $PSScriptRoot 'verify_engine_sources.ps1') `
  -ManifestPath $manifestPath `
  -PrimarySourceArchivePath $SourceArchivePath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'PASS: engine bundle and complete release-source set are verified.'
Write-Host "Bundle: $bundle"
Write-Host "JAR: $($manifest.suwayomi.version) SHA-256 verified"
Write-Host "JRE: $($manifest.jre.version) notices and executable verified"

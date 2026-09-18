[CmdletBinding()]
param([string]$CacheRoot = (Join-Path $PSScriptRoot "..\.cache\cef-windows-build"), [switch]$Force)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$version = "152.0.6+g708dc14+chromium-152.0.7977.83"
$archiveName = "cef_binary_" + $version + "_windows64_minimal.tar.bz2"
$archiveUrl = "https://cef-builds.spotifycdn.com/" + $archiveName
$expectedSha256 = "DB3E0751979C3CB3068F732ED4F0EF12ADE69D183D98CEEE120AD08C8D00F74C"
$expectedSha1 = "E5E3020627F4528BD43E22F4C4970000B0458E99"

function Assert-Within([string]$Child, [string]$Parent, [string]$Name) {
  $prefix = $Parent.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  if (-not $Child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "$Name must be inside $Parent." }
}
function Remove-CacheTree([string]$Path, [string]$Cache) {
  Assert-Within $Path $Cache "Cache removal target"
  Remove-Item -Recurse -Force -LiteralPath $Path -ErrorAction SilentlyContinue
}
function Test-SdkRoot([string]$Path) {
  foreach ($relative in @("CMakeLists.txt", "include\cef_app.h", "Release\bootstrap.exe", "Resources\locales")) {
    if (-not (Test-Path -LiteralPath (Join-Path $Path $relative))) { return $false }
  }
  return $true
}
function Assert-ArchiveHash([string]$Archive) {
  $actualSha256 = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash
  $actualSha1 = (Get-FileHash -LiteralPath $Archive -Algorithm SHA1).Hash
  if ($actualSha256 -ne $expectedSha256 -or $actualSha1 -ne $expectedSha1) {
    throw "CEF checksum verification failed: SHA256=$actualSha256 SHA1=$actualSha1"
  }
  return $actualSha256
}

$cache = [IO.Path]::GetFullPath($CacheRoot)
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$sdkName = [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetFileNameWithoutExtension($archiveName))
$sdkRoot = Join-Path $cache $sdkName
$archive = Join-Path $cache $archiveName
$proofPath = Join-Path $sdkRoot ".kelpie-cef-proof.json"
Assert-Within $sdkRoot $cache "CEF root"
Assert-Within $archive $cache "CEF archive"

if ($Force -or -not (Test-Path -LiteralPath $archive)) {
  Invoke-WebRequest -Uri $archiveUrl -OutFile "$archive.part" -UseBasicParsing
  Move-Item -Force -LiteralPath "$archive.part" -Destination $archive
}
$archiveHash = Assert-ArchiveHash $archive

if (-not $Force -and (Test-SdkRoot $sdkRoot) -and (Test-Path -LiteralPath $proofPath)) {
  $proof = Get-Content -LiteralPath $proofPath -Raw | ConvertFrom-Json
  $bootstrapHash = (Get-FileHash -LiteralPath (Join-Path $sdkRoot "Release\bootstrap.exe") -Algorithm SHA256).Hash
  if ($proof.archiveSha256 -ne $archiveHash -or $proof.bootstrapSha256 -ne $bootstrapHash) {
    throw "Cached CEF SDK proof does not match its verified archive or bootstrap."
  }
  Write-Output "CEF_ROOT=$sdkRoot"
  exit 0
}

$extract = Join-Path $cache ("extract-" + $PID)
Remove-CacheTree $extract $cache
New-Item -ItemType Directory -Path $extract | Out-Null
try {
  & tar.exe -xjf $archive -C $extract
  if ($LASTEXITCODE -ne 0) { throw "Unable to extract pinned CEF archive." }
  $extractedRoot = Join-Path $extract $sdkName
  if (-not (Test-SdkRoot $extractedRoot)) { throw "Pinned CEF archive has an invalid layout." }
  $bootstrapHash = (Get-FileHash -LiteralPath (Join-Path $extractedRoot "Release\bootstrap.exe") -Algorithm SHA256).Hash
  [pscustomobject]@{ archiveSha256 = $archiveHash; bootstrapSha256 = $bootstrapHash } |
    ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $extractedRoot ".kelpie-cef-proof.json") -NoNewline -Encoding ascii
  Remove-CacheTree $sdkRoot $cache
  Move-Item -LiteralPath $extractedRoot -Destination $sdkRoot
} finally {
  Remove-CacheTree $extract $cache
}
Write-Output "CEF_ROOT=$sdkRoot"
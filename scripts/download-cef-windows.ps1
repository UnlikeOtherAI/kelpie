[CmdletBinding()]
param([string]$CacheRoot = (Join-Path $PSScriptRoot "..\.cache\cef-windows-build"), [switch]$Force)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$version = "152.0.6+g708dc14+chromium-152.0.7977.83"
$archiveName = "cef_binary_" + $version + "_windows64_minimal.tar.bz2"
$archiveUrl = "https://cef-builds.spotifycdn.com/" + $archiveName
$expectedSha256 = "DB3E0751979C3CB3068F732ED4F0EF12ADE69D183D98CEEE120AD08C8D00F74C"
$expectedSha1 = "E5E3020627F4528BD43E22F4C4970000B0458E99"
function Test-SdkRoot([string]$Path) {
  foreach ($relative in @("CMakeLists.txt", "include\cef_app.h", "Release\bootstrap.exe", "Resources\locales")) {
    if (-not (Test-Path -LiteralPath (Join-Path $Path $relative))) { return $false }
  }
  return $true
}
$cache = [IO.Path]::GetFullPath($CacheRoot)
$sdkName = [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetFileNameWithoutExtension($archiveName))
$sdkRoot = Join-Path $cache $sdkName
if (-not $Force -and (Test-SdkRoot $sdkRoot)) { Write-Output "CEF_ROOT=$sdkRoot"; exit 0 }
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$archive = Join-Path $cache $archiveName
if ($Force -or -not (Test-Path -LiteralPath $archive)) {
  Invoke-WebRequest -Uri $archiveUrl -OutFile "$archive.part" -UseBasicParsing
  Move-Item -Force -LiteralPath "$archive.part" -Destination $archive
}
$actualSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
$actualSha1 = (Get-FileHash -LiteralPath $archive -Algorithm SHA1).Hash
if ($actualSha256 -ne $expectedSha256 -or $actualSha1 -ne $expectedSha1) {
  Remove-Item -Force -LiteralPath $archive
  throw "CEF checksum verification failed: SHA256=$actualSha256 SHA1=$actualSha1"
}
$extract = Join-Path $cache "extract-$PID"
Remove-Item -Recurse -Force -LiteralPath $extract -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $extract | Out-Null
try {
  & tar.exe -xjf $archive -C $extract
  if ($LASTEXITCODE -ne 0) { throw "Unable to extract pinned CEF archive." }
  $extractedRoot = Join-Path $extract $sdkName
  if (-not (Test-SdkRoot $extractedRoot)) { throw "Pinned CEF archive has an invalid layout." }
  Remove-Item -Recurse -Force -LiteralPath $sdkRoot -ErrorAction SilentlyContinue
  Move-Item -LiteralPath $extractedRoot -Destination $sdkRoot
} finally {
  Remove-Item -Recurse -Force -LiteralPath $extract -ErrorAction SilentlyContinue
}
Write-Output "CEF_ROOT=$sdkRoot"
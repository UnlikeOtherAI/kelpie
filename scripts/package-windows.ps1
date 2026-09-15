[CmdletBinding()]
param(
  [string]$BuildDir = (Join-Path $PSScriptRoot "..\.cache\windows-release3"),
  [string]$CefRoot = (Join-Path $PSScriptRoot "..\.cache\cef-windows-build\cef_binary_152.0.6+g708dc14+chromium-152.0.7977.83_windows64_minimal"),
  [string]$OutputDir = (Join-Path $PSScriptRoot "..\dist\release\windows"),
  [string]$Version = "0.1.1"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$cefVersion = "152.0.6+g708dc14+chromium-152.0.7977.83"
function Require-File([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file is missing: $Path" }
}
function Require-Directory([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Required directory is missing: $Path" }
}
function Get-DumpbinPath {
  $existing = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
  if ($existing) { return $existing.Source }
  $vswhere = Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path -LiteralPath $vswhere)) { throw "dumpbin.exe and VS2022 Build Tools are unavailable." }
  $installation = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
  $toolRoot = Join-Path $installation "VC\Tools\MSVC"
  $tool = Get-ChildItem -LiteralPath $toolRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
  if (-not $tool) { throw "No MSVC toolset was found." }
  $dumpbin = Join-Path $tool.FullName "bin\Hostx64\x64\dumpbin.exe"
  Require-File $dumpbin
  return $dumpbin
}
function Assert-Within([string]$Child, [string]$Parent, [string]$Name) {
  $separator = [IO.Path]::DirectorySeparatorChar
  $parentPrefix = $Parent.TrimEnd('\','/') + $separator
  if (-not $Child.StartsWith($parentPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$Name must be inside $Parent."
  }
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$build = [IO.Path]::GetFullPath($BuildDir)
$cef = [IO.Path]::GetFullPath($CefRoot)
$output = [IO.Path]::GetFullPath($OutputDir)
Assert-Within $output $repoRoot "OutputDir"
$stage = Join-Path $output "stage"
Assert-Within $stage $output "Stage directory"

$dll = Join-Path $build "kelpie.dll"
$bootstrap = Join-Path $build "kelpie.exe"
$sourceBootstrap = Join-Path $cef "Release\bootstrap.exe"
Require-File $dll
Require-File $bootstrap
Require-File $sourceBootstrap
Require-Directory (Join-Path $build "locales")
Require-File (Join-Path $repoRoot "LICENSE")
$dumpbin = Get-DumpbinPath

$dllVersion = (Get-Item -LiteralPath $dll).VersionInfo.FileVersion
if ($dllVersion -ne $Version) { throw "kelpie.dll FileVersion '$dllVersion' does not equal '$Version'." }
$bootstrapVersion = (Get-Item -LiteralPath $bootstrap).VersionInfo.FileVersion
if ($bootstrapVersion -ne $cefVersion) { throw "kelpie.exe must retain CEF bootstrap version '$cefVersion'; got '$bootstrapVersion'." }
$sourceBootstrapHash = (Get-FileHash -LiteralPath $sourceBootstrap -Algorithm SHA256).Hash
if ((Get-FileHash -LiteralPath $bootstrap -Algorithm SHA256).Hash -ne $sourceBootstrapHash) {
  throw "Packaged kelpie.exe does not match the verified CEF bootstrap."
}
if (-not ((& $dumpbin /headers $dll | Out-String) -match "machine \(x64\)")) { throw "kelpie.dll is not x64." }
if (-not ((& $dumpbin /exports $dll | Out-String) -match "\bRunWinMain\b")) { throw "kelpie.dll does not export RunWinMain." }

$runtimeFiles = @(
  "chrome_elf.dll", "d3dcompiler_47.dll", "dxcompiler.dll", "dxil.dll",
  "libcef.dll", "libEGL.dll", "libGLESv2.dll", "v8_context_snapshot.bin",
  "vk_swiftshader.dll", "vk_swiftshader_icd.json", "vulkan-1.dll"
)
$resourceFiles = @("chrome_100_percent.pak", "chrome_200_percent.pak", "icudtl.dat", "resources.pak")
foreach ($file in $runtimeFiles + $resourceFiles) { Require-File (Join-Path $build $file) }

Remove-Item -Recurse -Force -LiteralPath $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
  Copy-Item -LiteralPath $bootstrap, $dll -Destination $stage
  Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE") -Destination (Join-Path $stage "LICENSE.txt")
  foreach ($file in $runtimeFiles + $resourceFiles) { Copy-Item -LiteralPath (Join-Path $build $file) -Destination $stage }
  Copy-Item -LiteralPath (Join-Path $build "locales") -Destination (Join-Path $stage "locales") -Recurse
  $cefLicense = Join-Path $cef "LICENSE.txt"
  if (Test-Path -LiteralPath $cefLicense) { Copy-Item -LiteralPath $cefLicense -Destination (Join-Path $stage "CEF-LICENSE.txt") }

  if (Get-ChildItem -LiteralPath $stage -Recurse -Include "*.lib", "*.pdb" -File) { throw "Package contains development files." }
  $asset = Join-Path $output ("kelpie-windows-x64-" + $Version + ".zip")
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  Remove-Item -Force -LiteralPath $asset -ErrorAction SilentlyContinue
  Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $asset -CompressionLevel Optimal
  $assetHash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant()
  Set-Content -LiteralPath ($asset + ".sha256") -NoNewline -Encoding ascii -Value ($assetHash + "  " + [IO.Path]::GetFileName($asset))
  @(
    "asset_sha256=$assetHash",
    "kelpie_dll_version=$dllVersion",
    "kelpie_dll_sha256=$((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant())",
    "bootstrap=verified original CEF bootstrap",
    "bootstrap_version=$bootstrapVersion",
    "bootstrap_sha256=$($sourceBootstrapHash.ToLowerInvariant())"
  ) | Set-Content -LiteralPath ($asset + ".provenance.txt") -Encoding ascii
} finally {
  Remove-Item -Recurse -Force -LiteralPath $stage -ErrorAction SilentlyContinue
}
Write-Output "PACKAGE=$asset"
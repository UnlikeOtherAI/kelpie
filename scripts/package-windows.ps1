[CmdletBinding()]
param(
  [string]$BuildDir = (Join-Path $PSScriptRoot "..\.cache\windows-release3"),
  [string]$CefRoot = (Join-Path $PSScriptRoot "..\.cache\cef-windows-build\cef_binary_152.0.6+g708dc14+chromium-152.0.7977.83_windows64_minimal"),
  [string]$OutputDir = (Join-Path $PSScriptRoot "..\dist\release\windows"),
  [string]$Version,
  [string]$DumpbinPath
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
  if (-not [string]::IsNullOrWhiteSpace($DumpbinPath)) {
    Require-File ([IO.Path]::GetFullPath($DumpbinPath))
    return [IO.Path]::GetFullPath($DumpbinPath)
  }
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
function Copy-KelpieBranding([string]$SourceDll, [string]$DestinationExe) {
  if (-not ("KelpieResourceStamp" -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class KelpieResourceStamp {
  const int DataFile = 2, Version = 16, GroupIcon = 14, Icon = 3, Lang = 1033;
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr LoadLibraryEx(string p, IntPtr h, int f);
  [DllImport("kernel32", SetLastError=true)] static extern bool FreeLibrary(IntPtr h);
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr FindResource(IntPtr h, IntPtr n, IntPtr t);
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr LoadResource(IntPtr h, IntPtr r);
  [DllImport("kernel32", SetLastError=true)] static extern uint SizeofResource(IntPtr h, IntPtr r);
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr LockResource(IntPtr d);
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr BeginUpdateResource(string p, bool deleteExisting);
  [DllImport("kernel32", SetLastError=true)] static extern bool UpdateResource(IntPtr h, IntPtr t, IntPtr n, ushort l, byte[] d, uint s);
  [DllImport("kernel32", SetLastError=true)] static extern bool EndUpdateResource(IntPtr h, bool discard);
  static byte[] Read(IntPtr module, int type, int name) {
    IntPtr resource = FindResource(module, (IntPtr)name, (IntPtr)type);
    if (resource == IntPtr.Zero) throw new InvalidOperationException("Missing source resource " + type + "/" + name);
    uint size = SizeofResource(module, resource); byte[] bytes = new byte[size];
    Marshal.Copy(LockResource(LoadResource(module, resource)), bytes, 0, (int)size); return bytes;
  }
  static void Put(IntPtr update, int type, int name, byte[] value) {
    if (!UpdateResource(update, (IntPtr)type, (IntPtr)name, Lang, value, (uint)value.Length))
      throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  }
  public static void Copy(string source, string destination) {
    IntPtr module = LoadLibraryEx(source, IntPtr.Zero, DataFile);
    if (module == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    IntPtr update = IntPtr.Zero;
    try {
      byte[] version = Read(module, Version, 1), group = Read(module, GroupIcon, 101);
      update = BeginUpdateResource(destination, false);
      if (update == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      Put(update, Version, 1, version); Put(update, GroupIcon, 101, group);
      int count = BitConverter.ToUInt16(group, 4);
      for (int i = 0; i < count; i++) { int id = BitConverter.ToUInt16(group, 6 + i * 14 + 12); Put(update, Icon, id, Read(module, Icon, id)); }
      if (!EndUpdateResource(update, false)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      update = IntPtr.Zero;
    } finally { if (update != IntPtr.Zero) EndUpdateResource(update, true); FreeLibrary(module); }
  }
}
'@
  }
  [KelpieResourceStamp]::Copy($SourceDll, $DestinationExe)
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
Require-File (Join-Path $cef "LICENSE.txt")
$dumpbin = Get-DumpbinPath

$dllVersion = (Get-Item -LiteralPath $dll).VersionInfo.FileVersion
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $dllVersion }
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
  $originalBootstrapHash = (Get-FileHash -LiteralPath (Join-Path $stage "kelpie.exe") -Algorithm SHA256).Hash
  Copy-KelpieBranding $dll (Join-Path $stage "kelpie.exe")
  $customBootstrap = Join-Path $stage "kelpie.exe"
  if ((Get-Item -LiteralPath $customBootstrap).VersionInfo.FileVersion -ne $Version) {
    throw "Stamped package bootstrap does not have FileVersion $Version."
  }
  $customBootstrapHash = (Get-FileHash -LiteralPath $customBootstrap -Algorithm SHA256).Hash
  if ($customBootstrapHash -eq $originalBootstrapHash) { throw "Package bootstrap branding did not change the verified copy." }
  Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE") -Destination (Join-Path $stage "LICENSE.txt")
  foreach ($file in $runtimeFiles + $resourceFiles) { Copy-Item -LiteralPath (Join-Path $build $file) -Destination $stage }
  Copy-Item -LiteralPath (Join-Path $build "locales") -Destination (Join-Path $stage "locales") -Recurse
  Copy-Item -LiteralPath (Join-Path $cef "LICENSE.txt") -Destination (Join-Path $stage "CEF-LICENSE.txt")

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
    "bootstrap_original=verified CEF bootstrap",
    "bootstrap_original_version=$bootstrapVersion",
    "bootstrap_original_sha256=$($sourceBootstrapHash.ToLowerInvariant())",
    "bootstrap_custom_version=$Version",
    "bootstrap_custom_sha256=$($customBootstrapHash.ToLowerInvariant())"
  ) | Set-Content -LiteralPath ($asset + ".provenance.txt") -Encoding ascii
} finally {
  Remove-Item -Recurse -Force -LiteralPath $stage -ErrorAction SilentlyContinue
}
Write-Output "PACKAGE=$asset"

[CmdletBinding()]
param(
  [string]$CefRoot,
  [string]$SourceRoot = (Join-Path $PSScriptRoot ".."),
  [string]$CppHttplibRoot,
  [string]$NlohmannJsonRoot,
  [string]$WrapperBuildDir = (Join-Path $PSScriptRoot "..\.cache\cef-windows-build\wrapper"),
  [string]$BuildDir = (Join-Path $PSScriptRoot "..\.cache\windows-release3"),
  [switch]$SkipTests
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Initialize-VsEnvironment {
  $vswhere = Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path -LiteralPath $vswhere)) { throw "VS2022 Build Tools (vswhere) is required." }
  $installation = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
  if ([string]::IsNullOrWhiteSpace($installation)) { throw "VS2022 x64 C++ tools are required." }
  $devCmd = Join-Path $installation "Common7\Tools\VsDevCmd.bat"
  if (-not (Test-Path -LiteralPath $devCmd)) { throw "VsDevCmd.bat is missing." }
  $environment = & cmd.exe /d /s /c ('call "{0}" -arch=x64 -host_arch=x64 >nul && set' -f $devCmd)
  foreach ($line in $environment) {
    if ($line -match "^([^=]+)=(.*)$") { Set-Item -Path ("Env:" + $matches[1]) -Value $matches[2] }
  }
}
function Require-Path([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "Required path is missing: $Path" }
}
function Write-Stage([string]$Message) { Write-Host "==> $Message" }
function Invoke-Checked([string]$Description, [scriptblock]$Command) {
  Write-Stage $Description
  & $Command
  if ($LASTEXITCODE -ne 0) { throw "$Description failed with exit code $LASTEXITCODE." }
}

$repoRoot = [IO.Path]::GetFullPath($SourceRoot)
Require-Path (Join-Path $repoRoot "apps\windows\CMakeLists.txt")
if ([string]::IsNullOrWhiteSpace($CefRoot)) {
  Write-Stage "CEF SDK"
  $line = & (Join-Path $PSScriptRoot "download-cef-windows.ps1")
  if ($line -notmatch "^CEF_ROOT=(.+)$") { throw "CEF downloader did not return CEF_ROOT." }
  $CefRoot = $matches[1]
}
$cef = [IO.Path]::GetFullPath($CefRoot)
$wrapperBuild = [IO.Path]::GetFullPath($WrapperBuildDir)
$build = [IO.Path]::GetFullPath($BuildDir)
foreach ($relative in @("CMakeLists.txt", "include\cef_app.h", "Release\bootstrap.exe")) {
  Require-Path (Join-Path $cef $relative)
}

Write-Stage "Visual Studio environment"
Initialize-VsEnvironment
foreach ($tool in @("cmake.exe", "ninja.exe", "cl.exe", "dumpbin.exe", "ctest.exe")) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Missing build tool: $tool" }
}
Invoke-Checked "CEF wrapper configure" { cmake -S $cef -B $wrapperBuild -G Ninja -DCMAKE_BUILD_TYPE=Release -DUSE_SANDBOX=ON -DCEF_RUNTIME_LIBRARY_FLAG=/MT }
if (-not (Select-String -LiteralPath (Join-Path $wrapperBuild "CMakeCache.txt") -Pattern "^USE_SANDBOX:BOOL=ON$" -Quiet)) {
  throw "CEF wrapper cache does not enable USE_SANDBOX=ON."
}
if (-not (Select-String -LiteralPath (Join-Path $wrapperBuild "CMakeCache.txt") -Pattern "^CEF_RUNTIME_LIBRARY_FLAG:STRING=/MT$" -Quiet)) {
  throw "CEF wrapper cache does not use the static /MT runtime."
}
Invoke-Checked "CEF wrapper build" { cmake --build $wrapperBuild --target libcef_dll_wrapper --config Release }
$wrapper = Join-Path $wrapperBuild "libcef_dll_wrapper\libcef_dll_wrapper.lib"
Require-Path $wrapper

$kelpieConfigure = @(
  "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_TESTING=ON", "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded",
  ("-DCEF_ROOT=" + $cef), ("-DCEF_WRAPPER=" + $wrapper)
)
if (-not [string]::IsNullOrWhiteSpace($CppHttplibRoot)) {
  $httplib = [IO.Path]::GetFullPath($CppHttplibRoot)
  Require-Path (Join-Path $httplib "CMakeLists.txt")
  $kelpieConfigure += "-DFETCHCONTENT_SOURCE_DIR_CPP_HTTPLIB=$httplib"
}
if (-not [string]::IsNullOrWhiteSpace($NlohmannJsonRoot)) {
  $nlohmann = [IO.Path]::GetFullPath($NlohmannJsonRoot)
  Require-Path (Join-Path $nlohmann "CMakeLists.txt")
  $kelpieConfigure += "-DFETCHCONTENT_SOURCE_DIR_NLOHMANN_JSON=$nlohmann"
}
Invoke-Checked "Kelpie configure" { cmake -S (Join-Path $repoRoot "apps\windows") -B $build -G Ninja @kelpieConfigure }
Invoke-Checked "Kelpie build" { cmake --build $build --config Release }
foreach ($relative in @("kelpie.dll", "kelpie.exe", "locales")) { Require-Path (Join-Path $build $relative) }
if (-not ((& dumpbin.exe /exports (Join-Path $build "kelpie.dll") | Out-String) -match "\bRunWinMain\b")) {
  throw "kelpie.dll must export RunWinMain."
}
# A test with no TIMEOUT of its own otherwise inherits CTest's 1500 s default,
# so one that hangs holds the job for 25 minutes before anything names it.
if (-not $SkipTests) { Invoke-Checked "Windows CTest" { ctest.exe --test-dir $build -C Release --output-on-failure --timeout 120 } }
Write-Output "BUILD_DIR=$build"

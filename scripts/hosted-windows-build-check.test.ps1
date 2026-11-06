$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hosted-windows-build-check.ps1')
$cache = @'
CEF_ROOT:PATH=C:/cef
CMAKE_BUILD_TYPE:STRING=Release
KELPIE_LOCAL_LLM:BOOL=ON
CMAKE_MSVC_RUNTIME_LIBRARY:STRING=MultiThreaded$<$<CONFIG:Debug>:Debug>
'@
$wrapper = @'
USE_SANDBOX:BOOL=ON
CEF_RUNTIME_LIBRARY_FLAG:STRING=/MT
'@
$ninja = @'
build CMakeFiles\kelpie.dir\src\sample.cpp.obj: CXX_COMPILER__kelpie_unscanned_Release sample.cpp
  DEFINES = -DCEF_USE_BOOTSTRAP=1 -DHAS_CEF=1
  FLAGS = /DWIN32 /O2 -MT /utf-8
build another: phony
'@
function Assert-Code([string]$Actual,[string]$Expected) { if ($Actual -cne $Expected) { throw "expected $Expected got $Actual" } }
Assert-Code (Test-HostedWindowsBuild $cache $wrapper $ninja) 'OK'
Assert-Code (Test-HostedWindowsBuild ($cache.Replace('MultiThreaded$<$<CONFIG:Debug>:Debug>','MultiThreaded')) $wrapper $ninja) 'OK'
Assert-Code (Test-HostedWindowsBuild ($cache.Replace('Release','Debug')) $wrapper $ninja) 'HOSTED_BUILD_NOT_RELEASE'
Assert-Code (Test-HostedWindowsBuild ($cache.Replace('MultiThreaded$<$<CONFIG:Debug>:Debug>','MultiThreadedDLL')) $wrapper $ninja) 'HOSTED_RUNTIME_CACHE_MISMATCH'
Assert-Code (Test-HostedWindowsBuild ($cache.Replace('CONFIG:Debug','CONFIG:Release')) $wrapper $ninja) 'HOSTED_RUNTIME_CACHE_MISMATCH'
Assert-Code (Test-HostedWindowsBuild $cache $wrapper ($ninja.Replace('-MT','/MD'))) 'HOSTED_RUNTIME_FLAGS_MISMATCH'
Assert-Code (Test-HostedWindowsBuild $cache $wrapper ($ninja.Replace('-MT','/MTd'))) 'HOSTED_RUNTIME_FLAGS_MISMATCH'
$second = $ninja.Replace('sample.cpp.obj','second.cpp.obj').Replace('sample.cpp','second.cpp').Replace('-MT','/MD')
Assert-Code (Test-HostedWindowsBuild $cache $wrapper ($ninja + "`n" + $second)) 'HOSTED_RUNTIME_FLAGS_MISMATCH'
Assert-Code (Test-HostedWindowsBuild $cache ($wrapper.Replace('USE_SANDBOX:BOOL=ON','USE_SANDBOX:BOOL=OFF')) $ninja) 'HOSTED_CEF_SANDBOX_MISMATCH'
Assert-Code (Test-HostedWindowsBuild ($cache.Replace('CEF_ROOT:PATH=C:/cef','CEF_ROOT:PATH=')) $wrapper $ninja) 'HOSTED_CEF_ROOT_MISSING'
Assert-Code (Test-HostedWindowsBuild $cache $wrapper ($ninja.Replace('-DHAS_CEF=1',''))) 'HOSTED_CEF_DEFINITIONS_MISSING'
$savedTemp = $env:RUNNER_TEMP
$savedSha = $env:GITHUB_SHA
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('kelpie-preflight-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $scratch | Out-Null
try {
  $env:RUNNER_TEMP = $scratch
  $env:GITHUB_SHA = '0000000000000000000000000000000000000000'
  $failed = $false
  try { & (Join-Path $PSScriptRoot 'run-hosted-windows-g08.ps1') } catch { $failed = $true }
  if (-not $failed) { throw 'source mismatch was accepted' }
  $saved = Get-Content (Join-Path $scratch 'kelpie-hosted-g08-preflight/preflight.json') -Raw | ConvertFrom-Json
  Assert-Code $saved.status 'failed'
  Assert-Code $saved.code 'HOSTED_SOURCE_MISMATCH'
  if (Test-Path (Join-Path $scratch 'kelpie-hosted-g08-evidence')) { throw 'child evidence directory was precreated' }
} finally {
  $env:RUNNER_TEMP = $savedTemp
  $env:GITHUB_SHA = $savedSha
}
Write-Output 'Hosted build preflight tests passed'

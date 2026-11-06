$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$preflightDir = Join-Path $env:RUNNER_TEMP "kelpie-hosted-g08-preflight"
if (-not (Test-Path -LiteralPath $preflightDir)) { New-Item -ItemType Directory $preflightDir | Out-Null }
$preflightFile = Join-Path $preflightDir "preflight.json"
$preflight = [ordered]@{stage="preflight";status="started";code=$null;sourceMatched=$false;runtime=$null;buildType=$null;targetRuntime="unverified"}
function Save-Preflight { [IO.File]::WriteAllText($preflightFile,($preflight | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false)) }
Save-Preflight
try {
. (Join-Path $PSScriptRoot "hosted-windows-build-check.ps1")
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$build = Join-Path $repo ".cache\windows-release3"
$private = Join-Path $env:RUNNER_TEMP "kelpie-hosted-g08-private"
$evidence = Join-Path $env:RUNNER_TEMP "kelpie-hosted-g08-evidence"
$manifestFile = Join-Path $env:RUNNER_TEMP "kelpie-hosted-g08-manifest.json"
foreach ($path in @($private,$evidence,$manifestFile)) {
  if (Test-Path -LiteralPath $path) { throw "HOSTED_OUTPUT_EXISTS" }
}
$source = (& git -C $repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $source -ne $env:GITHUB_SHA) { throw "HOSTED_SOURCE_MISMATCH" }
$preflight.sourceMatched = $true
$exe = Join-Path $build "kelpie.exe"
$dll = Join-Path $build "kelpie.dll"
$ffmpeg = $env:FFMPEG
$ffprobe = $env:FFPROBE
if ([string]::IsNullOrWhiteSpace($ffmpeg) -or [string]::IsNullOrWhiteSpace($ffprobe) -or -not (Test-Path -LiteralPath $ffmpeg) -or -not (Test-Path -LiteralPath $ffprobe)) { throw "HOSTED_MEDIA_MISSING" }
$cache = Get-Content (Join-Path $build "CMakeCache.txt") -Raw
$wrapperCache = Get-Content (Join-Path $repo ".cache\cef-windows-build\wrapper\CMakeCache.txt") -Raw
$ninja = Get-Content (Join-Path $build "build.ninja") -Raw
$runtime = Get-HostedCacheValue $cache 'CMAKE_MSVC_RUNTIME_LIBRARY'
$preflight.runtime = if ($runtime -ceq 'MultiThreaded') { 'MultiThreaded' } elseif ($runtime -ceq 'MultiThreaded$<$<CONFIG:Debug>:Debug>') { 'MultiThreaded-Release-expression' } else { 'other' }
$preflight.buildType = if ((Get-HostedCacheValue $cache 'CMAKE_BUILD_TYPE') -ceq 'Release') { 'Release' } else { 'other' }
$buildCheck = Test-HostedWindowsBuild $cache $wrapperCache $ninja
if ($buildCheck -ne 'OK') { throw $buildCheck }
$witnessRequested = $env:KELPIE_TEST_G08_WITNESS -eq '1'
$witnessCache = Get-HostedCacheValue $cache 'KELPIE_TEST_G08_ROI_WITNESS'
if (($witnessRequested -and $witnessCache -cne 'ON') -or (-not $witnessRequested -and $witnessCache -cne 'OFF')) {
  throw 'HOSTED_WITNESS_BUILD_MISMATCH'
}
$preflight.targetRuntime = 'all-kelpie-objects-MT'
$files = @(Get-ChildItem $build -File | Where-Object { ($_.Extension -in @('.dll','.pak','.bin','.dat') -and $_.Name -ne 'kelpie.dll') -or $_.Name -eq 'vk_swiftshader_icd.json' }) +
  @(Get-ChildItem (Join-Path $build "locales") -Recurse -File)
$assets = @($files | Sort-Object FullName | ForEach-Object {
  [ordered]@{path=$_.FullName.Substring($build.Length+1).Replace('\','/');size=$_.Length;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$manifest = [ordered]@{
  source=$source;exeSha256=(Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant()
  dllSha256=(Get-FileHash $dll -Algorithm SHA256).Hash.ToLowerInvariant()
  ffmpegSha256=(Get-FileHash $ffmpeg -Algorithm SHA256).Hash.ToLowerInvariant()
  ffprobeSha256=(Get-FileHash $ffprobe -Algorithm SHA256).Hash.ToLowerInvariant()
  mediaArchiveSha256="fec81ae03971d9dd4be3ebe02e263bd2ec1d789483f931bdba5f5715e65da2e9"
  configuration=@{cef="ON";sandbox="ON";runtime="MultiThreaded /MT";localLlm="ON";roiWitness=$witnessRequested}
  assets=$assets;scope="hosted-public-export-only";wgc="not-run"
}
[IO.File]::WriteAllText($manifestFile,($manifest | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
$preflight.stage = 'ready'; $preflight.status = 'passed'; Save-Preflight
} catch {
  $known = @('HOSTED_OUTPUT_EXISTS','HOSTED_SOURCE_MISMATCH','HOSTED_MEDIA_MISSING','HOSTED_CEF_ROOT_MISSING',
    'HOSTED_BUILD_NOT_RELEASE','HOSTED_LLM_DISABLED','HOSTED_RUNTIME_CACHE_MISMATCH','HOSTED_CEF_SANDBOX_MISMATCH',
    'HOSTED_TARGET_OBJECTS_MISSING','HOSTED_CEF_DEFINITIONS_MISSING','HOSTED_RUNTIME_FLAGS_MISMATCH','HOSTED_WITNESS_BUILD_MISMATCH')
  $preflight.status = 'failed'
  $preflight.code = if ($known -contains $_.Exception.Message) { $_.Exception.Message } else { 'HOSTED_PREFLIGHT_IO_FAILURE' }
  Save-Preflight
  throw $preflight.code
}
$env:FFMPEG = $ffmpeg
$env:FFPROBE = $ffprobe
$env:KELPIE_HOSTED_PUBLIC_G08 = "1"
$runner = Join-Path $repo "tests\windows\run-direct-viewport-diagnostic.mjs"
& node $runner $exe $private $evidence $manifestFile 1> (Join-Path $env:RUNNER_TEMP "kelpie-hosted-g08.out") 2> (Join-Path $env:RUNNER_TEMP "kelpie-hosted-g08.err")
$captureExit = $LASTEXITCODE
if (-not (Test-Path -LiteralPath $evidence)) { New-Item -ItemType Directory $evidence | Out-Null }
Copy-Item -LiteralPath $manifestFile -Destination (Join-Path $evidence "manifest.json")
$reportPath = Join-Path $evidence "diagnostic.json"
$report = if (Test-Path -LiteralPath $reportPath) { Get-Content $reportPath -Raw | ConvertFrom-Json } else { $null }
$spawnPath = Join-Path $evidence "hosted-spawn.json"
$spawn = if (Test-Path -LiteralPath $spawnPath) { Get-Content $spawnPath -Raw | ConvertFrom-Json } else { $null }
$ownedPid = if ($spawn) { $spawn.pid } else { $null }
$present = if ($ownedPid) { [bool](Get-Process -Id $ownedPid -ErrorAction SilentlyContinue) } else { $null }
$listener = [bool](Get-NetTCPConnection -LocalPort 28420 -State Listen -ErrorAction SilentlyContinue)
$cleanup = [ordered]@{spawnPid=$ownedPid;pidPresent=$present;listenerPresent=$listener;captureExit=$captureExit;scope="absence-check-only"}
[IO.File]::WriteAllText((Join-Path $evidence "hosted-cleanup.json"),($cleanup | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
if ($captureExit -ne 0) { throw "HOSTED_PUBLIC_CAPTURE_FAILED" }
if (-not $report) { throw "HOSTED_REPORT_MISSING" }
if ($report.cleanup -ne "public-close-exited" -or -not $report.readinessAbsent -or -not $report.casePassed) { throw "HOSTED_CLEANUP_UNCONFIRMED" }
if (-not $ownedPid -or $report.identity.pid -ne $ownedPid -or $present) { throw "HOSTED_PROCESS_STILL_PRESENT" }
if ($listener) { throw "HOSTED_LISTENER_STILL_PRESENT" }
$inputFile = Join-Path $evidence "hosted\oracle-input.json"
$oracleFile = Join-Path $evidence "hosted\oracle-output.json"
& node (Join-Path $repo "tests\capture\g08-verify-single.mjs") $inputFile $oracleFile 1> (Join-Path $env:RUNNER_TEMP "kelpie-hosted-oracle.out") 2> (Join-Path $env:RUNNER_TEMP "kelpie-hosted-oracle.err")
if ($LASTEXITCODE -ne 0) { throw "HOSTED_G08_ORACLE_FAILED_OR_INSUFFICIENT" }
Write-Output "HOSTED_PUBLIC_G08_PASS"

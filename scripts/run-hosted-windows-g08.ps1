$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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
$exe = Join-Path $build "kelpie.exe"
$dll = Join-Path $build "kelpie.dll"
$ffmpeg = $env:FFMPEG
$ffprobe = $env:FFPROBE
if (-not (Test-Path -LiteralPath $ffmpeg) -or -not (Test-Path -LiteralPath $ffprobe)) { throw "HOSTED_MEDIA_MISSING" }
$cache = Get-Content (Join-Path $build "CMakeCache.txt") -Raw
if ($cache -notmatch '(?m)^KELPIE_LOCAL_LLM:BOOL=ON\r?$') { throw "HOSTED_LLM_DISABLED" }
if ($cache -notmatch '(?m)^CEF_ROOT:PATH=.+\r?$' -or $cache -notmatch '(?m)^CMAKE_MSVC_RUNTIME_LIBRARY:(STRING|UNINITIALIZED)=MultiThreaded\r?$') { throw "HOSTED_CEF_CONFIGURATION_MISMATCH" }
$wrapperCache = Get-Content (Join-Path $repo ".cache\cef-windows-build\wrapper\CMakeCache.txt") -Raw
if ($wrapperCache -notmatch '(?m)^USE_SANDBOX:BOOL=ON\r?$' -or $wrapperCache -notmatch '(?m)^CEF_RUNTIME_LIBRARY_FLAG:STRING=/MT\r?$') { throw "HOSTED_CEF_SANDBOX_MISMATCH" }
$ninja = Get-Content (Join-Path $build "build.ninja") -Raw
if (-not $ninja.Contains("HAS_CEF=1") -or -not $ninja.Contains("CEF_USE_BOOTSTRAP=1")) { throw "HOSTED_CEF_DEFINITIONS_MISSING" }
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
  configuration=@{cef="ON";sandbox="ON";runtime="MultiThreaded /MT";localLlm="ON"}
  assets=$assets;scope="hosted-public-export-only";wgc="not-run"
}
[IO.File]::WriteAllText($manifestFile,($manifest | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
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

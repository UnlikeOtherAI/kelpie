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
$ffmpeg = (Get-Command ffmpeg.exe -ErrorAction Stop).Source
$ffprobe = (Get-Command ffprobe.exe -ErrorAction Stop).Source
$cache = Get-Content (Join-Path $build "CMakeCache.txt") -Raw
if ($cache -notmatch '(?m)^KELPIE_LOCAL_LLM:BOOL=ON\r?$') { throw "HOSTED_LLM_DISABLED" }
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
if ($captureExit -ne 0) { throw "HOSTED_PUBLIC_CAPTURE_FAILED" }
$report = Get-Content (Join-Path $evidence "diagnostic.json") -Raw | ConvertFrom-Json
if ($report.cleanup -ne "public-close-exited" -or -not $report.readinessAbsent -or -not $report.casePassed) { throw "HOSTED_CLEANUP_UNCONFIRMED" }
if (Get-Process -Id $report.identity.pid -ErrorAction SilentlyContinue) { throw "HOSTED_PROCESS_STILL_PRESENT" }
if (Get-NetTCPConnection -LocalPort 28420 -State Listen -ErrorAction SilentlyContinue) { throw "HOSTED_LISTENER_STILL_PRESENT" }
$inputFile = Join-Path $evidence "hosted\oracle-input.json"
$oracleFile = Join-Path $evidence "hosted\oracle-output.json"
& node (Join-Path $repo "tests\capture\g08-verify-single.mjs") $inputFile $oracleFile 1> (Join-Path $env:RUNNER_TEMP "kelpie-hosted-oracle.out") 2> (Join-Path $env:RUNNER_TEMP "kelpie-hosted-oracle.err")
if ($LASTEXITCODE -ne 0) { throw "HOSTED_G08_ORACLE_FAILED_OR_INSUFFICIENT" }
Write-Output "HOSTED_PUBLIC_G08_PASS"

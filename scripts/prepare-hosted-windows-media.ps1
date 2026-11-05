$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Immutable release asset and digest from GyanD/codexffmpeg release 9.0.1.
$url = "https://github.com/GyanD/codexffmpeg/releases/download/9.0.1/ffmpeg-9.0.1-essentials_build.zip"
$expected = "fec81ae03971d9dd4be3ebe02e263bd2ec1d789483f931bdba5f5715e65da2e9"
$root = Join-Path $env:RUNNER_TEMP "kelpie-hosted-media"
if (Test-Path -LiteralPath $root) { throw "HOSTED_MEDIA_OUTPUT_EXISTS" }
New-Item -ItemType Directory $root | Out-Null
$archive = Join-Path $root "ffmpeg.zip"
Invoke-WebRequest -Uri $url -OutFile $archive -TimeoutSec 180
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw "HOSTED_MEDIA_HASH_MISMATCH" }
Expand-Archive -LiteralPath $archive -DestinationPath $root
$bin = Join-Path $root "ffmpeg-9.0.1-essentials_build\bin"
$ffmpeg = Join-Path $bin "ffmpeg.exe"
$ffprobe = Join-Path $bin "ffprobe.exe"
if (-not (Test-Path -LiteralPath $ffmpeg) -or -not (Test-Path -LiteralPath $ffprobe)) { throw "HOSTED_MEDIA_MISSING" }
"FFMPEG=$ffmpeg" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
"FFPROBE=$ffprobe" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append

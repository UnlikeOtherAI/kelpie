[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SignedPackage,
  [string]$ArtifactRoot,
  [switch]$Worker,
  [string]$RequestPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$SignedPackage = (Resolve-Path -LiteralPath $SignedPackage).Path
if (-not $ArtifactRoot) { $ArtifactRoot = Join-Path $PSScriptRoot '../../.cache/update-install-verification' }
if ($Worker) {
  # Replace transport only in this test process. All package validation, process
  # handoff, directory replacement and restart use the shipping helper unchanged.
  function Invoke-WebRequest {
    param($Uri, $OutFile, $TimeoutSec, [switch]$UseBasicParsing)
    Copy-Item -LiteralPath $SignedPackage -Destination $OutFile
  }
  function Get-FileHash {
    throw 'The application updater must work when Get-FileHash is unavailable.'
  }
  & (Join-Path $PSScriptRoot '../../apps/updates/install-windows.ps1') -RequestPath $RequestPath
  exit $LASTEXITCODE
}

function Wait-Until([scriptblock]$Condition, [string]$Description) {
  $deadline = [DateTime]::UtcNow.AddSeconds(120)
  do {
    if (& $Condition) { return }
    Start-Sleep -Milliseconds 200
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "Timed out: $Description"
}
function Read-Record([string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
  }
  return $null
}
function Close-Browser([string]$Readiness) {
  $record = Read-Record $Readiness
  if (-not $record) { return }
  $null = Invoke-RestMethod -Uri "http://127.0.0.1:$($record.port)/v1/close-browser" -Method Post `
    -Headers @{Authorization = "Bearer $($record.token)"} -ContentType 'application/json' -Body '{}'
}

$root = Join-Path ([IO.Path]::GetFullPath($ArtifactRoot)) ([guid]::NewGuid().ToString('N'))
$installation = Join-Path $root ('Kelpie-' + [char]0x6D4B)
$operation = Join-Path $root 'operation'
$profile = Join-Path $installation 'verification-profile'
$readiness = Join-Path $profile 'readiness.json'
New-Item -ItemType Directory -Path $installation, $operation, $profile -Force | Out-Null
Expand-Archive -LiteralPath $SignedPackage -DestinationPath $installation
Set-Content -LiteralPath (Join-Path $installation 'old-install-marker') -Value 'previous directory'
Set-Content -LiteralPath (Join-Path $profile 'profile-marker') -Value 'preserve browsing data'
$longProfileFile = Join-Path $profile ('profile-long-path-' + ('x' * 180) + '.txt')
[IO.File]::WriteAllText(('\\?\' + $longProfileFile), 'preserve long paths')
$version = (Get-Item -LiteralPath (Join-Path $installation 'kelpie.dll')).VersionInfo.ProductVersion
$arguments = '--profile-dir "' + $profile + '" --readiness-file "' + $readiness + '" --url https://example.com --port 18498'
$parent = $null
$workerProcess = $null
try {
  $parent = Start-Process -FilePath (Join-Path $installation 'kelpie.exe') -ArgumentList $arguments -PassThru -WindowStyle Hidden
  Wait-Until {
    if ($parent.HasExited) { throw "The isolated browser exited with code $($parent.ExitCode). Close any other standalone instance first." }
    return (Read-Record $readiness) -ne $null
  } 'isolated signed browser readiness'
  $request = Join-Path $operation 'request.json'
  $metadata = @{
    url = "https://github.com/UnlikeOtherAI/kelpie/releases/download/verification/kelpie-windows-x64-$version.zip"
    sha256 = (Get-FileHash -LiteralPath $SignedPackage -Algorithm SHA256).Hash.ToLowerInvariant()
    version = $version; parent = $parent.Id; installDirectory = $installation
    profileDirectory = $profile; arguments = $arguments
  }
  $workerArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $PSCommandPath +
    '" -Worker -SignedPackage "' + $SignedPackage + '" -RequestPath "' + $request + '"'
  $statusPath = Join-Path $operation 'status'
  $powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
  $expectedHash = $metadata.sha256
  $metadata.sha256 = '0' * 64
  [IO.File]::WriteAllText($request, ($metadata | ConvertTo-Json))
  $workerProcess = Start-Process -FilePath $powershell -ArgumentList $workerArgs -PassThru -WindowStyle Hidden
  Wait-Until { $workerProcess.HasExited } 'checksum rejection'
  if ($workerProcess.ExitCode -ne 1 -or $parent.HasExited -or
      (Get-Content -LiteralPath (Join-Path $operation 'error') -Raw) -ne 'The downloaded package checksum does not match GitHub.') {
    throw 'A checksum mismatch did not keep the existing installation running.'
  }

  $metadata.sha256 = $expectedHash
  [IO.File]::WriteAllText($request, ($metadata | ConvertTo-Json))
  Remove-Item -LiteralPath $statusPath
  $workerProcess = Start-Process -FilePath $powershell -ArgumentList $workerArgs -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $operation 'worker-output.log') -RedirectStandardError (Join-Path $operation 'worker-error.log')
  Wait-Until {
    if (Test-Path -LiteralPath $statusPath) {
      $state = Get-Content -LiteralPath $statusPath -Raw
      if ($state -eq 'error') { throw (Get-Content -LiteralPath (Join-Path $operation 'error') -Raw) }
      return $state -eq 'ready'
    }
    return $false
  } 'verified package ready before parent exit'
  if ($parent.HasExited) { throw 'The parent exited before package validation finished.' }
  Close-Browser $readiness
  Wait-Until {
    if (Test-Path -LiteralPath $statusPath) {
      $state = Get-Content -LiteralPath $statusPath -Raw
      if ($state -eq 'error') { throw (Get-Content -LiteralPath (Join-Path $operation 'error') -Raw) }
      return $state -eq 'installed'
    }
    return $false
  } 'automatic replacement and restart'
  if (Test-Path -LiteralPath (Join-Path $installation 'old-install-marker')) { throw 'The installation was not replaced.' }
  if (-not (Test-Path -LiteralPath (Join-Path $profile 'profile-marker'))) { throw 'The browser profile was lost.' }
  if ([IO.File]::ReadAllText(('\\?\' + $longProfileFile)) -ne 'preserve long paths') { throw 'A long profile filename was lost.' }
  if (@(Get-ChildItem -LiteralPath $root -Directory -Filter ((Split-Path -Leaf $installation) + '.previous-*')).Count -ne 1) {
    throw 'No recovery copy retained.'
  }
  Wait-Until { (Read-Record $readiness) -ne $null } 'restarted browser readiness'
  Write-Output "PASS: verified signed package, waited for parent exit, replaced installation, retained profile and backup, restarted browser. Transport was local to this test. Evidence: $root"
} finally {
  # A failing helper may have just relaunched the retained installation. Let it
  # finish before looking up the new readiness capability for normal cleanup.
  if ($workerProcess) { $null = $workerProcess.WaitForExit(5000) }
  Close-Browser $readiness
}

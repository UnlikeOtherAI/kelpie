[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$InputPackage,
  [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSha256,
  [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$SourceCommit,
  [Parameter(Mandatory)][ValidatePattern('^[0-9]+(\.[0-9]+)+
  [Parameter(Mandatory)][string]$SigningScript
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$inputZip = (Resolve-Path -LiteralPath $InputPackage).Path
$signer = (Resolve-Path -LiteralPath $SigningScript).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if ([IO.Path]::GetExtension($inputZip) -ne '.zip') { throw 'InputPackage must be a ZIP archive.' }
if ((Get-FileHash -LiteralPath $inputZip -Algorithm SHA256).Hash -ne $ExpectedSha256) {
  throw 'The unsigned package hash does not match ExpectedSha256.'
}
if (Test-Path -LiteralPath $output) { throw 'OutputDirectory must be new; existing evidence is preserved.' }
New-Item -ItemType Directory -Path $output | Out-Null
$stage = Join-Path $output 'stage'
$unsigned = Join-Path $output 'unsigned'
$signed = Join-Path $output 'signed'
New-Item -ItemType Directory -Path $stage, $unsigned, $signed | Out-Null
Expand-Archive -LiteralPath $inputZip -DestinationPath $stage

# CEF checks the primary certificate thumbprint, not just the publisher name.
$publisher = 'CN=UnlikeOtherAI s.r.o., O=UnlikeOtherAI s.r.o., L=Mnichovice, S=Central Bohemia, C=CZ'
$thumbprint = $null
$records = @()
foreach ($name in @('kelpie.exe', 'chrome_elf.dll', 'kelpie.dll')) {
  $stagedFile = Join-Path $stage $name
  if (-not (Test-Path -LiteralPath $stagedFile -PathType Leaf)) { throw "Missing package file: $name" }
  $originalFile = Join-Path $unsigned $name
  $signedFile = Join-Path $signed $name
  Copy-Item -LiteralPath $stagedFile -Destination $originalFile
  $inputHash = (Get-FileHash -LiteralPath $originalFile -Algorithm SHA256).Hash
  & $signer -InputPath $originalFile -OutputPath $signedFile -ExpectedSha256 $inputHash -SourceCommit $SourceCommit
  if (-not (Test-Path -LiteralPath $signedFile -PathType Leaf)) { throw "Signer did not produce $name." }
  $signature = Get-AuthenticodeSignature -LiteralPath $signedFile
  if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) {
    throw "The signature or timestamp for $name is invalid."
  }
  $ekuExtension = $signature.SignerCertificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' }
  if (-not $ekuExtension -or $ExpectedSignerEku -notin @($ekuExtension.EnhancedKeyUsages | ForEach-Object Value)) {
    throw "The signing profile EKU for $name is invalid."
  }
  if ($signature.SignerCertificate.Subject -ne $publisher) { throw "Unexpected publisher for $name." }
  if ($null -eq $thumbprint) { $thumbprint = $signature.SignerCertificate.Thumbprint }
  if ($signature.SignerCertificate.Thumbprint -ne $thumbprint) {
    throw 'CEF requires the launcher, chrome_elf.dll and client DLL to use the same certificate.'
  }
  Copy-Item -LiteralPath $signedFile -Destination $stagedFile
  $records += [pscustomobject]@{
    Name = $name
    InputSha256 = $inputHash.ToLowerInvariant()
    OutputSha256 = (Get-FileHash -LiteralPath $signedFile -Algorithm SHA256).Hash.ToLowerInvariant()
    Publisher = $signature.SignerCertificate.Subject
    Thumbprint = $thumbprint
    Timestamp = $signature.TimeStamperCertificate.Subject
  }
}

$asset = Join-Path $output ([IO.Path]::GetFileName($inputZip))
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $asset -CompressionLevel Optimal
$assetHash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($asset + '.sha256') -NoNewline -Encoding ascii -Value ($assetHash + '  ' + [IO.Path]::GetFileName($asset))
[pscustomobject]@{
  SourceCommit = $SourceCommit
  SignerProfileEku = $ExpectedSignerEku
  InputPackageSha256 = $ExpectedSha256.ToLowerInvariant()
  AssetSha256 = $assetHash
  Size = (Get-Item -LiteralPath $asset).Length
  Signatures = $records
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ($asset + '.provenance.json') -Encoding utf8
Write-Output "SIGNED_PACKAGE=$asset"
)][string]$ExpectedSignerEku,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [Parameter(Mandatory)][string]$SigningScript
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$inputZip = (Resolve-Path -LiteralPath $InputPackage).Path
$signer = (Resolve-Path -LiteralPath $SigningScript).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if ([IO.Path]::GetExtension($inputZip) -ne '.zip') { throw 'InputPackage must be a ZIP archive.' }
if ((Get-FileHash -LiteralPath $inputZip -Algorithm SHA256).Hash -ne $ExpectedSha256) {
  throw 'The unsigned package hash does not match ExpectedSha256.'
}
if (Test-Path -LiteralPath $output) { throw 'OutputDirectory must be new; existing evidence is preserved.' }
New-Item -ItemType Directory -Path $output | Out-Null
$stage = Join-Path $output 'stage'
$unsigned = Join-Path $output 'unsigned'
$signed = Join-Path $output 'signed'
New-Item -ItemType Directory -Path $stage, $unsigned, $signed | Out-Null
Expand-Archive -LiteralPath $inputZip -DestinationPath $stage

# CEF checks the primary certificate thumbprint, not just the publisher name.
$publisher = 'CN=UnlikeOtherAI s.r.o., O=UnlikeOtherAI s.r.o., L=Mnichovice, S=Central Bohemia, C=CZ'
$thumbprint = $null
$records = @()
foreach ($name in @('kelpie.exe', 'chrome_elf.dll', 'kelpie.dll')) {
  $stagedFile = Join-Path $stage $name
  if (-not (Test-Path -LiteralPath $stagedFile -PathType Leaf)) { throw "Missing package file: $name" }
  $originalFile = Join-Path $unsigned $name
  $signedFile = Join-Path $signed $name
  Copy-Item -LiteralPath $stagedFile -Destination $originalFile
  $inputHash = (Get-FileHash -LiteralPath $originalFile -Algorithm SHA256).Hash
  & $signer -InputPath $originalFile -OutputPath $signedFile -ExpectedSha256 $inputHash -SourceCommit $SourceCommit
  if (-not (Test-Path -LiteralPath $signedFile -PathType Leaf)) { throw "Signer did not produce $name." }
  $signature = Get-AuthenticodeSignature -LiteralPath $signedFile
  if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) {
    throw "The signature or timestamp for $name is invalid."
  }
  if ($signature.SignerCertificate.Subject -ne $publisher) { throw "Unexpected publisher for $name." }
  if ($null -eq $thumbprint) { $thumbprint = $signature.SignerCertificate.Thumbprint }
  if ($signature.SignerCertificate.Thumbprint -ne $thumbprint) {
    throw 'CEF requires the launcher, chrome_elf.dll and client DLL to use the same certificate.'
  }
  Copy-Item -LiteralPath $signedFile -Destination $stagedFile
  $records += [pscustomobject]@{
    Name = $name
    InputSha256 = $inputHash.ToLowerInvariant()
    OutputSha256 = (Get-FileHash -LiteralPath $signedFile -Algorithm SHA256).Hash.ToLowerInvariant()
    Publisher = $signature.SignerCertificate.Subject
    Thumbprint = $thumbprint
    Timestamp = $signature.TimeStamperCertificate.Subject
  }
}

$asset = Join-Path $output ([IO.Path]::GetFileName($inputZip))
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $asset -CompressionLevel Optimal
$assetHash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($asset + '.sha256') -NoNewline -Encoding ascii -Value ($assetHash + '  ' + [IO.Path]::GetFileName($asset))
[pscustomobject]@{
  SourceCommit = $SourceCommit
  InputPackageSha256 = $ExpectedSha256.ToLowerInvariant()
  AssetSha256 = $assetHash
  Size = (Get-Item -LiteralPath $asset).Length
  Signatures = $records
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ($asset + '.provenance.json') -Encoding utf8
Write-Output "SIGNED_PACKAGE=$asset"

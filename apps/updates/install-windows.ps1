[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$RequestPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# This helper is copied outside the installation before launch. It stages and
# verifies everything before asking Kelpie to quit, and preserves the old tree.
$operation = Split-Path -Parent ([IO.Path]::GetFullPath($RequestPath))
$statusPath = Join-Path $operation 'status'
$closed = $false
$moved = $false
$installed = $false
$backup = $null
$request = $null
function Set-Status([string]$Value) { [IO.File]::WriteAllText($statusPath, $Value) }
function Extended-Path([string]$Path) {
    if ($Path.StartsWith('\\?\')) { return $Path }
    if ($Path.StartsWith('\\')) { return '\\?\UNC\' + $Path.Substring(2) }
    return '\\?\' + $Path
}
function Assert-PlainDirectory([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The installation must be a regular directory.'
    }
}
function Start-Kelpie([string]$Directory) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $Directory 'kelpie.exe'
    $start.Arguments = $request.arguments
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    if (-not $process) { throw 'Kelpie could not restart.' }
    return $process
}

try {
    $request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
    if ($request.url -cnotmatch '^https://github\.com/UnlikeOtherAI/kelpie/releases/download/[^\s\\?#%]+\.zip$' -or
        $request.url.Contains('..') -or $request.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $request.version -notmatch '^\d{1,6}\.\d{1,6}\.\d{1,6}$') { throw 'Invalid update metadata.' }
    $destination = [IO.Path]::GetFullPath($request.installDirectory).TrimEnd('\')
    $profile = [IO.Path]::GetFullPath($request.profileDirectory).TrimEnd('\')
    if ([string]::Equals($profile, $destination, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'This installation mixes its browser profile and application files. The updater cannot safely separate them.'
    }
    Assert-PlainDirectory $destination
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'kelpie.dll'))) { throw 'No complete Kelpie installation found.' }
    $parent = Get-Process -Id $request.parent
    if (-not [string]::Equals($parent.Path, (Join-Path $destination 'kelpie.exe'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The updater parent does not match the installation.'
    }
    # A sibling staging tree makes the final directory moves stay on one volume.
    $staged = Join-Path (Split-Path -Parent $destination) ('.kelpie-update-' + [guid]::NewGuid().ToString('N'))
    $backup = $destination + '.previous-' + [guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $staged | Out-Null
    $archive = Join-Path $operation 'package.zip'
    Set-Status 'downloading'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $request.url -OutFile $archive -TimeoutSec 300
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $request.sha256) {
        throw 'The downloaded package checksum does not match GitHub.'
    }
    if (Test-Path -LiteralPath (Join-Path $operation 'cancel')) { throw 'Update cancelled.' }
    Set-Status 'verifying'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $expanded = [long]0
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('/', '\')
            $resolved = [IO.Path]::GetFullPath((Join-Path $staged $name))
            if ($name.Contains(':') -or -not $resolved.StartsWith($staged + '\', [StringComparison]::OrdinalIgnoreCase) -or
                (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Unsafe archive entry.' }
            $expanded += $entry.Length
            if ($expanded -gt 8GB) { throw 'The update archive is too large.' }
        }
    } finally { $zip.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $staged)
    $publisher = 'CN=UnlikeOtherAI s.r.o., O=UnlikeOtherAI s.r.o., L=Mnichovice, S=Central Bohemia, C=CZ'
    $thumbprint = $null
    foreach ($name in @('kelpie.exe', 'kelpie.dll', 'chrome_elf.dll')) {
        $file = Join-Path $staged $name
        $signature = Get-AuthenticodeSignature -LiteralPath $file
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -cne $publisher -or
            -not $signature.TimeStamperCertificate) { throw "The signature on $name is not a trusted Kelpie release." }
        if ($thumbprint -and $signature.SignerCertificate.Thumbprint -ne $thumbprint) { throw 'CEF signing identities do not match.' }
        $thumbprint = $signature.SignerCertificate.Thumbprint
    }
    foreach ($name in @('libcef.dll', 'resources.pak', 'icudtl.dat', 'locales', 'install-update.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $staged $name))) { throw "Missing package file: $name" }
    }
    if ((Get-Item -LiteralPath (Join-Path $staged 'kelpie.dll')).VersionInfo.ProductVersion -ne $request.version) {
        throw 'The package version does not match the offered update.'
    }
    if (Test-Path -LiteralPath (Join-Path $operation 'cancel')) { throw 'Update cancelled.' }
    Set-Status 'ready'
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    while (-not $parent.WaitForExit(200)) {
        if ((Test-Path -LiteralPath (Join-Path $operation 'cancel')) -or [DateTime]::UtcNow -gt $deadline) {
            throw 'Kelpie did not finish closing. The update was not installed.'
        }
    }
    $closed = $true
    # CEF children can outlive the browser parent while flushing their caches.
    # The profile must have no writers before copying it or moving its app tree.
    while (@(Get-Process -Name kelpie -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and [string]::Equals($_.Path, (Join-Path $destination 'kelpie.exe'), [StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0) {
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Another Kelpie process is still using this installation.' }
        Start-Sleep -Milliseconds 200
    }
    if ($profile.StartsWith($destination + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $relative = $profile.Substring($destination.Length + 1)
        $stagedProfile = Join-Path $staged $relative
        if (Test-Path -LiteralPath $stagedProfile) { throw 'The package conflicts with the browser profile directory.' }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stagedProfile) | Out-Null
        # Windows PowerShell otherwise fails when staging makes a profile path
        # exceed MAX_PATH, even though Chromium can read and write that profile.
        Copy-Item -LiteralPath (Extended-Path $profile) -Destination (Extended-Path $stagedProfile) -Recurse
    }
    Assert-PlainDirectory $destination
    Move-Item -LiteralPath $destination -Destination $backup
    $moved = $true
    Move-Item -LiteralPath $staged -Destination $destination
    $installed = $true
    $restarted = Start-Kelpie $destination
    if ($restarted.WaitForExit(5000)) { throw 'The updated Kelpie exited during startup.' }
    Set-Status 'installed'
    # Keep the previous installation for recovery; never delete user files.
} catch {
    $message = $_.Exception.Message
    if ($moved) {
        try {
            if ($installed) {
                Move-Item -LiteralPath $destination -Destination ($destination + '.failed-' + [guid]::NewGuid().ToString('N'))
            }
            Move-Item -LiteralPath $backup -Destination $destination
        } catch { $message += ' Automatic recovery failed: ' + $_.Exception.Message }
    }
    [IO.File]::WriteAllText((Join-Path $operation 'error'), $message)
    Set-Status 'error'
    if ($closed) {
        try { $null = Start-Kelpie $destination } catch { $message += ' Kelpie could not restart.' }
        if ([Environment]::UserInteractive) {
            Add-Type -AssemblyName System.Windows.Forms
            [Windows.Forms.MessageBox]::Show($message, 'Kelpie could not update') | Out-Null
        }
    }
    exit 1
}

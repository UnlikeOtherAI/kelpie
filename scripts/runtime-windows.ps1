function Get-CefRuntimeFiles {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$BuildDir)
  $root = [IO.Path]::GetFullPath($BuildDir)
  $manifest = Join-Path $root 'cef-runtime-files.txt'
  if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "Missing CEF runtime manifest: $manifest; configure and build with the selected CEF SDK."
  }
  $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $files = @(Get-Content -LiteralPath $manifest | Where-Object { $_ -ne '' })
  foreach ($name in $files) {
    if ($name -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]*$' -or -not $names.Add($name)) {
      throw "Invalid or duplicate CEF runtime name: $name"
    }
    if ([IO.Path]::GetExtension($name) -in '.lib', '.pdb', '.exe') {
      throw "Unexpected development file or executable in CEF runtime manifest: $name"
    }
    $pathType = if ($name -eq 'locales') { 'Container' } else { 'Leaf' }
    if (-not (Test-Path -LiteralPath (Join-Path $root $name) -PathType $pathType)) {
      throw "Missing staged CEF runtime file: $name"
    }
  }
  foreach ($required in @('libcef.dll', 'chrome_elf.dll', 'locales')) {
    if (-not $names.Contains($required)) { throw "CEF runtime manifest omits required component: $required" }
  }
  return $files
}

function Copy-CefRuntimeFiles {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$BuildDir, [Parameter(Mandatory)][string]$Destination)
  # Validate the complete source before creating or changing output files.
  $files = @(Get-CefRuntimeFiles -BuildDir $BuildDir)
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  foreach ($name in $files) {
    Copy-Item -LiteralPath (Join-Path $BuildDir $name) -Destination $Destination -Recurse
  }
  Copy-Item -LiteralPath (Join-Path $BuildDir 'cef-runtime-files.txt') -Destination $Destination
}

function Get-HostedCacheValue([string]$Text,[string]$Name) {
  $pattern = '(?m)^' + [Regex]::Escape($Name) + ':[^=\r\n]+=(.*)\r?$'
  $matches = [Regex]::Matches($Text,$pattern)
  if ($matches.Count -ne 1) { return $null }
  return $matches[0].Groups[1].Value.TrimEnd("`r")
}

function Test-HostedWindowsBuild([string]$Cache,[string]$WrapperCache,[string]$Ninja) {
  $cefRoot = Get-HostedCacheValue $Cache 'CEF_ROOT'
  if ([string]::IsNullOrWhiteSpace($cefRoot)) { return 'HOSTED_CEF_ROOT_MISSING' }
  if ((Get-HostedCacheValue $Cache 'CMAKE_BUILD_TYPE') -cne 'Release') { return 'HOSTED_BUILD_NOT_RELEASE' }
  if ((Get-HostedCacheValue $Cache 'KELPIE_LOCAL_LLM') -cne 'ON') { return 'HOSTED_LLM_DISABLED' }
  $runtime = Get-HostedCacheValue $Cache 'CMAKE_MSVC_RUNTIME_LIBRARY'
  if ($runtime -cne 'MultiThreaded' -and $runtime -cne 'MultiThreaded$<$<CONFIG:Debug>:Debug>') { return 'HOSTED_RUNTIME_CACHE_MISMATCH' }
  if ((Get-HostedCacheValue $WrapperCache 'USE_SANDBOX') -cne 'ON' -or (Get-HostedCacheValue $WrapperCache 'CEF_RUNTIME_LIBRARY_FLAG') -cne '/MT') { return 'HOSTED_CEF_SANDBOX_MISMATCH' }
  $objects = [Regex]::Matches($Ninja,'(?m)^build CMakeFiles[\\/]kelpie\.dir[\\/][^\r\n]+\.obj:[^\r\n]*\r?\n(?:(?!build )[^\r\n]*\r?\n)*')
  if ($objects.Count -eq 0) { return 'HOSTED_TARGET_OBJECTS_MISSING' }
  foreach ($object in $objects) {
    $block = $object.Value
    if ($block -notmatch '(?<!\S)[/-]DHAS_CEF=1(?!\S)' -or $block -notmatch '(?<!\S)[/-]DCEF_USE_BOOTSTRAP=1(?!\S)') { return 'HOSTED_CEF_DEFINITIONS_MISSING' }
    $flagMatch = [Regex]::Match($block,'(?m)^\s*FLAGS = ([^\r\n]*)')
    if (-not $flagMatch.Success) { return 'HOSTED_RUNTIME_FLAGS_MISMATCH' }
    $flags = $flagMatch.Groups[1].Value
    if ($flags -notmatch '(?<!\S)[/-]MT(?!\S)' -or $flags -match '(?<!\S)[/-](MDd?|MTd)(?!\S)') { return 'HOSTED_RUNTIME_FLAGS_MISMATCH' }
  }
  return 'OK'
}

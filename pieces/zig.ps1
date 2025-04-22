. $PSScriptRoot/../utils/fileUtils.ps1

# Script level variables for caching
$script:cachedZigVersion ??= $null
$script:lastBuildZigZonTimestamp ??= $null

function flare_zig {
  # Check if zig command is available
  if ($null -eq (Get-Command zig -ErrorAction SilentlyContinue)) {
    return ""
  }

  $buildZigPath = FindFileInParentDirectories -fileName "build.zig"
  $buildZigZonPath = FindFileInParentDirectories -fileName "build.zig.zon"
  
  # Check if we need to invalidate the cache due to build.zig.zon changes only
  if ($null -ne $buildZigZonPath) {
    $currentTimestamp = (Get-Item $buildZigZonPath).LastWriteTime
    if ($script:lastBuildZigZonTimestamp -ne $currentTimestamp) {
      $script:cachedZigVersion = $null
      $script:lastBuildZigZonTimestamp = $currentTimestamp
    }
  }

  if ($null -ne $buildZigPath) {
    # Use cached version if available
    if ($null -eq $script:cachedZigVersion) {
      $script:cachedZigVersion = zig version
    }
    return " $script:cachedZigVersion"
  }
  else {
    # Reset cache when not in a Zig project
    $script:cachedZigVersion = $null
    $script:lastBuildZigZonTimestamp = $null
    return ""
  }
}
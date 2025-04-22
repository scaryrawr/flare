. $PSScriptRoot/../utils/fileUtils.ps1

# Script level variables for caching
$script:cachedZigVersion ??= $null
$script:lastBuildZigZonTimestamp ??= $null
$script:lastBuildZigTimestamp ??= $null
$script:lastZigProjectPath ??= $null

function flare_zig {
  # Check if zig command is available
  if ($null -eq (Get-Command zig -ErrorAction SilentlyContinue)) {
    return ""
  }

  $buildZigPath = FindFileInParentDirectories -fileName "build.zig"
  $buildZigZonPath = FindFileInParentDirectories -fileName "build.zig.zon"
  
  # Get the current project directory based on build.zig location
  $currentProjectPath = if ($null -ne $buildZigPath) { Split-Path -Parent $buildZigPath } else { $null }
  
  # Check if we've changed projects or if build files have changed
  $shouldInvalidateCache = $false
  
  # Invalidate cache when switching between projects
  if ($script:lastZigProjectPath -ne $currentProjectPath) {
    $shouldInvalidateCache = $true
    $script:lastZigProjectPath = $currentProjectPath
  }
  
  # Check build.zig.zon changes
  if ($null -ne $buildZigZonPath) {
    $currentTimestamp = (Get-Item $buildZigZonPath).LastWriteTime
    if ($script:lastBuildZigZonTimestamp -ne $currentTimestamp) {
      $shouldInvalidateCache = $true
      $script:lastBuildZigZonTimestamp = $currentTimestamp
    }
  }
  
  # Check build.zig changes
  if ($null -ne $buildZigPath) {
    $currentTimestamp = (Get-Item $buildZigPath).LastWriteTime
    if ($script:lastBuildZigTimestamp -ne $currentTimestamp) {
      $shouldInvalidateCache = $true
      $script:lastBuildZigTimestamp = $currentTimestamp
    }
  }
  
  # Invalidate cache if needed
  if ($shouldInvalidateCache) {
    $script:cachedZigVersion = $null
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
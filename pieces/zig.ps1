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
  
  # Invalidate cache when switching between projects
  if ($script:lastZigProjectPath -ne $currentProjectPath) {
    $script:cachedZigVersion = $null
    $script:lastZigProjectPath = $currentProjectPath
  }
  
  # Check build.zig.zon changes and invalidate cache if needed
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
. $PSScriptRoot/../utils/fileUtils.ps1

# Script level variables for caching
$script:cachedZigVersion ??= $null
$script:lastBuildZigTimestamp ??= $null
$script:lastBuildZigZonTimestamp ??= $null
$script:zigWorkspaceRootPath ??= $null

# Helper function to check if this is a potential Zig workspace/multi-module project
function Test-IsZigWorkspace {
  param (
    [string]$BuildZigPath
  )
    
  try {
    # Check if build.zig.zon exists alongside build.zig
    $buildZigZonPath = Join-Path (Split-Path -Parent $BuildZigPath) "build.zig.zon"
    return (Test-Path $buildZigZonPath -PathType Leaf)
  }
  catch {
    return $false
  }
}

function flare_zig {
  # Check if zig command is available
  if ($null -eq (Get-Command zig -ErrorAction SilentlyContinue)) {
    return ""
  }

  $buildZigPath = FindFileInParentDirectories -fileName "build.zig"
  $buildZigZonPath = FindFileInParentDirectories -fileName "build.zig.zon"
  
  # Check if we need to invalidate the cache due to build.zig or build.zig.zon changes
  $needsCacheInvalidation = $false
  
  if ($null -ne $buildZigPath) {
    $currentTimestamp = (Get-Item $buildZigPath).LastWriteTime
    if ($script:lastBuildZigTimestamp -ne $currentTimestamp) {
      $needsCacheInvalidation = $true
      $script:lastBuildZigTimestamp = $currentTimestamp
    }
  }
  
  if ($null -ne $buildZigZonPath) {
    $currentTimestamp = (Get-Item $buildZigZonPath).LastWriteTime
    if ($script:lastBuildZigZonTimestamp -ne $currentTimestamp) {
      $needsCacheInvalidation = $true
      $script:lastBuildZigZonTimestamp = $currentTimestamp
    }
  }
  
  if ($needsCacheInvalidation) {
    $script:cachedZigVersion = $null
  }

  if ($null -ne $buildZigPath) {
    # Check if we need to determine or update the workspace root
    if ($null -eq $script:zigWorkspaceRootPath -or -not (Test-Path $script:zigWorkspaceRootPath)) {
      # Check if this is a workspace root based on build.zig.zon presence
      if (Test-IsZigWorkspace -BuildZigPath $buildZigPath) {
        $script:zigWorkspaceRootPath = (Split-Path -Parent $buildZigPath)
      }
      else {
        # Check if we're in a subdirectory of a workspace
        $dir = (Split-Path -Parent $buildZigPath)
        while ($dir) {
          $potentialBuildZig = Join-Path $dir "build.zig"
          if (Test-Path $potentialBuildZig -PathType Leaf) {
            if (Test-IsZigWorkspace -BuildZigPath $potentialBuildZig) {
              $script:zigWorkspaceRootPath = $dir
              break
            }
          }
          $dir = Split-Path -Parent $dir
          if ($null -eq $dir -or $dir -eq "") { break }
        }
      }
    }
    
    # Use cached version if available
    if ($null -eq $script:cachedZigVersion) {
      $script:cachedZigVersion = zig version
    }
    return " $script:cachedZigVersion"
  }
  else {
    # Check if we're still within the previously identified workspace
    if ($null -ne $script:zigWorkspaceRootPath -and (Test-Path $script:zigWorkspaceRootPath)) {
      $currentPath = (Get-Location).Path
      # If we're still within the workspace, don't invalidate the cache
      if ($currentPath.StartsWith($script:zigWorkspaceRootPath)) {
        if ($null -ne $script:cachedZigVersion) {
          return " $script:cachedZigVersion"
        }
      }
    }
    
    # Reset cache when not in a Zig project and not in a known workspace
    $script:cachedZigVersion = $null
    $script:lastBuildZigTimestamp = $null
    $script:lastBuildZigZonTimestamp = $null
    $script:zigWorkspaceRootPath = $null
    return ""
  }
}
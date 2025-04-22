. $PSScriptRoot/../utils/fileUtils.ps1

# Script level variables for caching
$script:cachedNodeVersion ??= $null
$script:lastNvmrcTimestamp ??= $null
$script:workspaceRootPath ??= $null

# Helper function to check if a package.json contains workspace definitions
function Test-IsWorkspace {
  param (
    [string]$PackageJsonPath
  )
    
  try {
    $packageJson = Get-Content -Path $PackageJsonPath -Raw | ConvertFrom-Json
    # Check for workspace definitions in various formats
    return ($null -ne $packageJson.workspaces) -or 
    ($null -ne $packageJson.workspace) -or
    ($packageJson.private -eq $true -and $null -ne $packageJson.workspaces)
  }
  catch {
    return $false
  }
}

function flare_node {
  $packageJsonPath = FindFileInParentDirectories -fileName "package.json"
  $nvmrcPath = FindFileInParentDirectories -fileName ".nvmrc"

  # Check if we need to invalidate the cache due to .nvmrc changes
  if ($null -ne $nvmrcPath) {
    $currentTimestamp = (Get-Item $nvmrcPath).LastWriteTime
    if ($script:lastNvmrcTimestamp -ne $currentTimestamp) {
      $script:cachedNodeVersion = $null
      $script:lastNvmrcTimestamp = $currentTimestamp
    }
  }

  if ($null -ne $packageJsonPath) {
    # Check if we need to determine or update the workspace root
    if ($null -eq $script:workspaceRootPath -or -not (Test-Path $script:workspaceRootPath)) {
      # Check if this is a workspace root
      if (Test-IsWorkspace -PackageJsonPath $packageJsonPath) {
        $script:workspaceRootPath = (Split-Path -Parent $packageJsonPath)
      }
      else {
        # Check if we're in a subdirectory of a workspace
        $dir = (Split-Path -Parent $packageJsonPath)
        while ($dir) {
          $potentialRoot = Join-Path $dir "package.json"
          if (Test-Path $potentialRoot -PathType Leaf) {
            if (Test-IsWorkspace -PackageJsonPath $potentialRoot) {
              $script:workspaceRootPath = $dir
              break
            }
          }
          $dir = Split-Path -Parent $dir
          if ($null -eq $dir -or $dir -eq "") { break }
        }
      }
    }
    
    # Use cached version if available
    if ($null -eq $script:cachedNodeVersion) {
      $script:cachedNodeVersion = node -v
    }
    return "󰎙 $script:cachedNodeVersion"
  }
  else {
    # Check if we're still within the previously identified workspace
    if ($null -ne $script:workspaceRootPath -and (Test-Path $script:workspaceRootPath)) {
      $currentPath = (Get-Location).Path
      # If we're still within the workspace, don't invalidate the cache
      if ($currentPath.StartsWith($script:workspaceRootPath)) {
        if ($null -ne $script:cachedNodeVersion) {
          return "󰎙 $script:cachedNodeVersion"
        }
      }
    }
    
    # Reset cache when not in a node project and not in a known workspace
    $script:cachedNodeVersion = $null
    $script:lastNvmrcTimestamp = $null
    $script:workspaceRootPath = $null
    return ""
  }
}
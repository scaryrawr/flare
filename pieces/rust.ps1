. $PSScriptRoot/../utils/fileUtils.ps1

# Script level variables for caching
$script:cachedRustVersion ??= $null
$script:lastToolchainTimestamp ??= $null
$script:rustWorkspaceRootPath ??= $null

# Helper function to check if a Cargo.toml contains workspace definitions
function Test-IsRustWorkspace {
  param (
    [string]$CargoTomlPath
  )
    
  try {
    $content = Get-Content -Path $CargoTomlPath -Raw
    # Check for [workspace] section in Cargo.toml
    return $content -match '\[\s*workspace\s*\]'
  }
  catch {
    return $false
  }
}

function flare_rust {
  $cargoTomlPath = FindFileInParentDirectories -fileName "Cargo.toml"
  $toolchainPath = FindFileInParentDirectories -fileName "rust-toolchain.toml"
  
  # Check if we need to invalidate the cache due to rust-toolchain.toml changes
  if ($null -ne $toolchainPath) {
    $currentTimestamp = (Get-Item $toolchainPath).LastWriteTime
    if ($script:lastToolchainTimestamp -ne $currentTimestamp) {
      $script:cachedRustVersion = $null
      $script:lastToolchainTimestamp = $currentTimestamp
    }
  }

  if ($null -ne $cargoTomlPath) {
    # Check if we need to determine or update the workspace root
    if ($null -eq $script:rustWorkspaceRootPath -or -not (Test-Path $script:rustWorkspaceRootPath)) {
      # Check if this is a workspace root
      if (Test-IsRustWorkspace -CargoTomlPath $cargoTomlPath) {
        $script:rustWorkspaceRootPath = (Split-Path -Parent $cargoTomlPath)
      }
      else {
        # Check if we're in a subdirectory of a workspace
        $dir = (Split-Path -Parent $cargoTomlPath)
        while ($dir) {
          $potentialRoot = Join-Path $dir "Cargo.toml"
          if (Test-Path $potentialRoot -PathType Leaf) {
            if (Test-IsRustWorkspace -CargoTomlPath $potentialRoot) {
              $script:rustWorkspaceRootPath = $dir
              break
            }
          }
          $dir = Split-Path -Parent $dir
          if ($null -eq $dir -or $dir -eq "") { break }
        }
      }
    }
    
    # Use cached version if available
    if ($null -eq $script:cachedRustVersion) {
      $script:cachedRustVersion = rustc --version | Select-String -Pattern "(\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    }
    return "󱘗 $script:cachedRustVersion"
  }
  else {
    # Check if we're still within the previously identified workspace
    if ($null -ne $script:rustWorkspaceRootPath -and (Test-Path $script:rustWorkspaceRootPath)) {
      $currentPath = (Get-Location).Path
      # If we're still within the workspace, don't invalidate the cache
      if ($currentPath.StartsWith($script:rustWorkspaceRootPath)) {
        if ($null -ne $script:cachedRustVersion) {
          return "󱘗 $script:cachedRustVersion"
        }
      }
    }
    
    # Reset cache when not in a Rust project and not in a known workspace
    $script:cachedRustVersion = $null
    $script:lastToolchainTimestamp = $null
    $script:rustWorkspaceRootPath = $null
    return ""
  }
}

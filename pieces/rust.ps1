. $PSScriptRoot/../utils/fileUtils.ps1

# Script level variables for caching
$script:cachedRustVersion ??= $null
$script:lastToolchainTimestamp ??= $null
$script:rustWorkspaceRootPath ??= $null

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
    # Use cached version if available
    if ($null -eq $script:cachedRustVersion) {
      # Check if the rustc command is available
      if (Get-Command rustc -ErrorAction SilentlyContinue) {
        $script:cachedRustVersion = rustc --version | Select-String -Pattern "(\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
      }
      else {
        $script:cachedRustVersion = ""
      }
    }

    $script:rustWorkspaceRootPath = Split-Path -Path $cargoTomlPath -Parent
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

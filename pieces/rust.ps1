. $PSScriptRoot/../utils/fileUtils.ps1

# Cache for rust version
$script:lastCargoPath = ""
$script:lastRustVersion = ""

function flare_rust {
  $cargoTomlPath = FindFileInParentDirectories -fileName "Cargo.toml"
  $cwd = (Get-Location).Path

  if ($null -ne $cargoTomlPath) {
    # Check if we're in the same project
    if ($cargoTomlPath -eq $script:lastCargoPath -and $script:lastRustVersion -ne "") {
      return "󱘗 $script:lastRustVersion"
    }
    
    # Cache miss, get the version
    $rustVersion = rustc --version | Select-String -Pattern "(\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    $script:lastCargoPath = $cargoTomlPath
    $script:lastRustVersion = $rustVersion
    return "󱘗 $rustVersion"
  }
  else {
    # Reset cache when not in a Rust project
    $script:lastCargoPath = ""
    $script:lastRustVersion = ""
    return ""
  }
}

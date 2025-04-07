. $PSScriptRoot/../utils/fileUtils.ps1

function Get-RustVersion {
  $cargoTomlPath = FindFileInParentDirectories -fileName "Cargo.toml"

  if ($null -ne $cargoTomlPath) {
    $rustVersion = rustc --version | Select-String -Pattern "(\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    return "󱘗 $rustVersion"
  }
  else {
    return ""
  }
}

Get-RustVersion
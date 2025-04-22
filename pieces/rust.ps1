. $PSScriptRoot/../utils/fileUtils.ps1

function flare_rust {
  $cargoTomlPath = FindFileInParentDirectories -fileName "Cargo.toml"

  if ($null -ne $cargoTomlPath) {
    $rustVersion = rustc --version | Select-String -Pattern "(\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    return "󱘗 $rustVersion"
  }
  else {
    return ""
  }
}

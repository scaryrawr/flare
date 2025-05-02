. $PSScriptRoot/../utils/fileUtils.ps1

function flare_rust {
  $cargoTomlPath = FindFileInParentDirectories -fileName 'Cargo.toml'
  $toolchainPath = FindFileInParentDirectories -fileName 'rust-toolchain.toml'

  if ($cargoTomlPath -or $toolchainPath) {
    # Check if the rustc command is available
    if (Get-Command rustc -ErrorAction SilentlyContinue) {
      return rustc --version | Select-String -Pattern '(\d+\.\d+\.\d+)' | ForEach-Object { $_.Matches.Groups[1].Value }
    }
  }

  return ''
}

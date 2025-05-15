. $PSScriptRoot/../utils/fileUtils.ps1

function flare_bun {
  $bunlockPath = FindFileInParentDirectories -fileName 'bun.lockb'
  $bunfigPath = FindFileInParentDirectories -fileName 'bunfig.toml'

  if ($bunlockPath -or $bunfigPath) {
    if (Get-Command bun -ErrorAction SilentlyContinue) {
      return bun --version
    }
  }

  return ''
}

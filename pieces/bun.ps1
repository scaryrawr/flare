. $PSScriptRoot/../utils/fileUtils.ps1

<#
.SYNOPSIS
Shows the Bun version for a detected Bun project.
.OUTPUTS
System.String
#>
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

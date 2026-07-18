. $PSScriptRoot/../utils/fileUtils.ps1

<#
.SYNOPSIS
Shows the Zig version for a detected Zig project.
.OUTPUTS
System.String
#>
function flare_zig {
  $buildZigPath = FindFileInParentDirectories -fileName 'build.zig'
  $buildZigZonPath = FindFileInParentDirectories -fileName 'build.zig.zon'

  if ($buildZigPath -or $buildZigZonPath) {
    if (Get-Command zig -ErrorAction SilentlyContinue) {
      zig version
    }
  }

  return ''
}

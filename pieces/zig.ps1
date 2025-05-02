. $PSScriptRoot/../utils/fileUtils.ps1

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

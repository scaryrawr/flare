. $PSScriptRoot/../utils/fileUtils.ps1

function flare_zig {
  $buildZigPath = FindFileInParentDirectories -fileName "build.zig"
  $cwd = (Get-Location).Path

  if ($null -ne $buildZigPath) {
    $zigVersion = zig version
    return " $zigVersion"
  }
  else {
    return ""
  }
}
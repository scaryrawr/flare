. $PSScriptRoot/../utils/fileUtils.ps1

function Get-ZigVersion {
  $buildZigPath = FindFileInParentDirectories -fileName "build.zig"

  if ($null -ne $buildZigPath) {
    $zigVersion = zig version
    return " $zigVersion"
  }
  else {
    return ""
  }
}

Get-ZigVersion
. $PSScriptRoot/../utils/fileUtils.ps1

function flare_zig {
  $buildZigPath = FindFileInParentDirectories -fileName "build.zig"

  if ($null -ne $buildZigPath) {
    # Cache miss, get the version
    $zigVersion = zig version
    return " $zigVersion"
  }
  else {
    return ""
  }
}
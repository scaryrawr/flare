. $PSScriptRoot/../utils/fileUtils.ps1

# Cache for zig version
$script:lastBuildZigPath = ""
$script:lastZigVersion = ""

function flare_zig {
  $buildZigPath = FindFileInParentDirectories -fileName "build.zig"
  $cwd = (Get-Location).Path

  if ($null -ne $buildZigPath) {
    # Check if we're in the same project
    if ($buildZigPath -eq $script:lastBuildZigPath -and $script:lastZigVersion -ne "") {
      return " $script:lastZigVersion"
    }
    
    # Cache miss, get the version
    $zigVersion = zig version
    $script:lastBuildZigPath = $buildZigPath
    $script:lastZigVersion = $zigVersion
    return " $zigVersion"
  }
  else {
    # Reset cache when not in a Zig project
    $script:lastBuildZigPath = ""
    $script:lastZigVersion = ""
    return ""
  }
}
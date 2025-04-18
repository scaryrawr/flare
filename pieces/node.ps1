. $PSScriptRoot/../utils/fileUtils.ps1

function flare_node {
  $packageJsonPath = FindFileInParentDirectories -fileName "package.json"

  if ($null -ne $packageJsonPath) {
    $nodeVersion = node -v
    return "󰎙 $nodeVersion"
  }
  else {
    return ""
  }
}
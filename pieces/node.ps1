. $PSScriptRoot/../utils/fileUtils.ps1

function flare_node {
  $packageJsonPath = FindFileInParentDirectories -fileName "package.json"

  if ($null -ne $packageJsonPath) {
    # Check if we're in the same project
    if ($packageJsonPath -eq $script:lastNodePath -and $script:lastNodeVersion -ne "") {
      return "󰎙 $script:lastNodeVersion"
    }
    
    $nodeVersion = node -v
    return "󰎙 $nodeVersion"
  }
  else {
    return ""
  }
}
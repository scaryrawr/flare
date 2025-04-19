. $PSScriptRoot/../utils/fileUtils.ps1

# Cache for node version
$script:lastNodePath = ""
$script:lastNodeVersion = ""

function flare_node {
  $packageJsonPath = FindFileInParentDirectories -fileName "package.json"

  if ($null -ne $packageJsonPath) {
    # Check if we're in the same project
    if ($packageJsonPath -eq $script:lastNodePath -and $script:lastNodeVersion -ne "") {
      return "󰎙 $script:lastNodeVersion"
    }
    
    # Cache miss, get the version
    $nodeVersion = node -v
    $script:lastNodePath = $packageJsonPath
    $script:lastNodeVersion = $nodeVersion
    return "󰎙 $nodeVersion"
  }
  else {
    # Reset cache when not in a Node project
    $script:lastNodePath = ""
    $script:lastNodeVersion = ""
    return ""
  }
}
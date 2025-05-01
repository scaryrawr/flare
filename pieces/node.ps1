. $PSScriptRoot/../utils/fileUtils.ps1

function flare_node {
  $packageJsonPath = FindFileInParentDirectories -fileName 'package.json'

  if ($packageJsonPath) {
    # Check if the node command is available
    if (Get-Command node -ErrorAction SilentlyContinue) {
      return node -v
    }
  }

  return ''
}

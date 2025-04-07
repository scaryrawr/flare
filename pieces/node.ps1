. $PSScriptRoot/../utils/fileUtils.ps1

function Get-NodeVersion {
  $packageJsonPath = FindFileInParentDirectories -fileName "package.json"

  if ($null -ne $packageJsonPath) {
    $nodeVersion = node -v
    return "󰎙 $nodeVersion"
  }
  else {
    return ""
  }
}

Get-NodeVersion
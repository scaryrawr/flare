. $PSScriptRoot/../utils/fileUtils.ps1

function flare_go {
  $goModPath = FindFileInParentDirectories -fileName 'go.mod'
  $mainGoPath = FindFileInParentDirectories -fileName 'main.go'

  if ($goModPath -or $mainGoPath) {
    if (Get-Command go -ErrorAction SilentlyContinue) {
      return go version | Select-String -Pattern 'go(\d+\.\d+(?:\.\d+)?)' | ForEach-Object { $_.Matches.Groups[1].Value }
    }
  }

  return ''
}

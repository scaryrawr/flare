function FindFileInParentDirectories {
  param (
    [string]$fileName
  )

  try {
    $currentDir = Get-Location
    $dir = $currentDir

    while ($null -ne $dir) {
      $filePath = Join-Path -Path $dir -ChildPath $fileName
      if (Test-Path $filePath) {
        return $filePath
      }
      # Move up to the parent directory
      $dir = Split-Path -Path $dir -Parent
    }
  } catch {
    return $null
  }

  return $null
}
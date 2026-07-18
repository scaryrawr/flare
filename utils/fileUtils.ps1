$global:flare_findFileInParentDirectories ??= {
  param (
    [string]$FileName,
    [string]$StartDirectory = $null
  )

  try {
    $dir = if ($StartDirectory) {
      $StartDirectory
    }
    else {
      Get-Location
    }

    while ($null -ne $dir) {
      $filePath = Join-Path -Path $dir -ChildPath $FileName
      if (Test-Path $filePath) {
        return $filePath
      }
      # Move up to the parent directory
      $dir = Split-Path -Path $dir -Parent
    }
  }
  catch {
    return $null
  }

  return $null
}

<#
.SYNOPSIS
Finds the nearest named file in the current or an ancestor directory.
.PARAMETER FileName
The file or directory name to locate.
.PARAMETER StartDirectory
The directory where the upward search begins. Defaults to the current location.
.OUTPUTS
System.String
#>
function FindFileInParentDirectories {
  param (
    [string]$FileName,
    [string]$StartDirectory = $null
  )

  return & $global:flare_findFileInParentDirectories -FileName $FileName -StartDirectory $StartDirectory
}
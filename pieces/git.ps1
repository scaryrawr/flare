. $PSScriptRoot/../utils/fileUtils.ps1

# Cache variables
$global:flare_gitStatusCache = $null
$global:flare_gitRepoCachePath = $null
$global:flare_gitLastModified = $null

function Get-GitStatus {  
  # Find git directory using FindFileInParentDirectories (faster than git command)
  $gitDir = FindFileInParentDirectories ".git"
  if (-not $gitDir) { return "" }

  # Set gitDir to the parent directory (the actual git repo root)
  $gitDir = Split-Path -Parent $gitDir
  
  # Check if we need to invalidate the cache
  $currentTime = (Get-Item $gitDir -Force).LastWriteTime
  
  if (($global:flare_gitRepoCachePath -ne $gitDir) -or 
      ($global:flare_gitLastModified -eq $null) -or 
      ($currentTime -gt $global:flare_gitLastModified)) {
    $global:flare_gitStatusCache = $null
  }
  
  # Return cached result if valid
  if ($global:flare_gitStatusCache -ne $null) {
    return $global:flare_gitStatusCache
  }
  
  # Update cache path and modification time
  $global:flare_gitRepoCachePath = $gitDir
  $global:flare_gitLastModified = $currentTime
  
  # Get fresh git status
  $status = git --no-optional-locks status -sb --porcelain 2> $null
  if ($status) {
    $added = 0
    $modified = 0
    $deleted = 0
    $renamed = 0
    $copied = 0
    $unmerged = 0
    $untracked = 0
    $ahead = 0;
    $behind = 0;

    $status -split "`n" | ForEach-Object {
      if ($_ -match "^\s*([AMDRCU?]+)\s+(.*)") {
        # $file = $Matches[2]
        $status = $Matches[1]
        switch ($status) {
          "A" { $added += 1 }
          "M" { $modified += 1 }
          "D" { $deleted += 1 }
          "R" { $renamed += 1 }
          "C" { $copied += 1 }
          "U" { $unmerged += 1 }
          "??" { $untracked += 1 }
        }
      }
      elseif ($_ -match "(ahead|behind) (\d+)") {
        $status = $Matches[1]
        $count = $Matches[2]
        switch ($status) {
          "ahead" { $ahead += $count }
          "behind" { $behind += $count }
        }
      }
    }

    $global:flare_gitStatusCache = ""
    function Add-Status($icon, $count) {
      if ($count -eq 0) { return }
      if ($global:flare_gitStatusCache) { $global:flare_gitStatusCache += " " }
      $global:flare_gitStatusCache += "$icon $count"
    }

    Add-Status "" $ahead
    Add-Status "" $behind
    Add-Status "" $added
    Add-Status "" $modified
    Add-Status "󰆴" $deleted
    Add-Status "󰑕" $renamed
    Add-Status "" $copied
    Add-Status "" $unmerged
    Add-Status "" $untracked

    return $global:flare_gitStatusCache
  }

  return ""
}

function flare_git {
  # Find git directory using FindFileInParentDirectories (faster than git command)
  $gitDir = FindFileInParentDirectories ".git"
  if (-not $gitDir) { return "" }

  $branch = git --no-optional-locks rev-parse --abbrev-ref HEAD 2> $null
  if ($branch) {
    $flare_gitIcon ??= ''
    return "$flare_gitIcon $branch $(Get-GitStatus)"
  }
  else {
    return ""
  }
}

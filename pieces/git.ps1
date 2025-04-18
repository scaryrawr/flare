. $PSScriptRoot/../utils/fileUtils.ps1

function Get-GitStatus {  
  # Find git directory using FindFileInParentDirectories (faster than git command)
  $gitDir = FindFileInParentDirectories ".git"
  if (-not $gitDir) { return "" }

  $repoRoot = Split-Path -Parent $gitDir
  
  # Get the most recent timestamp between repo root and .git directory
  $repoModified = (Get-Item $repoRoot -Force).LastWriteTime
  $gitDirModified = (Get-Item $gitDir -Force).LastWriteTime
  
  # Check files that change during push, pull, checkout operations
  $remoteRefsDir = Join-Path -Path $gitDir -ChildPath "refs/remotes"
  
  # Check for any changes in remote refs (updated during push)
  $remoteRefsModified = $null
  if (Test-Path $remoteRefsDir) {
    $latestRemoteRef = Get-ChildItem -Path $remoteRefsDir -Recurse -File | 
                     Sort-Object LastWriteTime -Descending | 
                     Select-Object -First 1 -ExpandProperty LastWriteTime
    if ($latestRemoteRef) {
      $remoteRefsModified = $latestRemoteRef
    }
  }
  
  # Use the most recent timestamp of all checked files
  $lastModified = $repoModified
  if ($gitDirModified -gt $lastModified) { $lastModified = $gitDirModified }
  if ($remoteRefsModified -and $remoteRefsModified -gt $lastModified) { $lastModified = $remoteRefsModified }
  
  $script:cacheLastModified ??= $null
  $script:repoCachePath ??= $null
  $script:statusCache ??= $null
  if (($script:repoCachePath -ne $repoRoot) -or 
      ($script:cacheLastModified -eq $null) -or 
      ($lastModified -gt $script:cacheLastModified)) {
    $script:statusCache = $null
  }
  
  # Return cached result if valid
  if ($script:statusCache -ne $null) {
    return $script:statusCache
  }
  
  # Update cache path and modification time
  $script:repoCachePath = $repoRoot
  $script:cacheLastModified = $lastModified
  
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

    $script:statusCache = ""
    function Add-Status($icon, $count) {
      if ($count -eq 0) { return }
      if ($script:statusCache) { $script:statusCache += " " }
      $script:statusCache += "$icon$count"
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

    return $script:statusCache
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
    $gitStatus = Get-GitStatus
    if ($gitStatus) {
      return "$flare_gitIcon $branch $gitStatus"
    } else {
      return "$flare_gitIcon $branch"
    }
  }
  else {
    return ""
  }
}

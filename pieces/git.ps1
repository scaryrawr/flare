. $PSScriptRoot/../utils/fileUtils.ps1

function Get-GitStatusRaw {
  $status = git --no-optional-locks status -sb --porcelain 2> $null
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

  $script:statusBuilder = ""
  function Add-Status($icon, $count) {
    if ($count -eq 0) { return }
    if ($script:statusBuilder) { $script:statusBuilder += " " }
    $script:statusBuilder += "$icon$count"
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

  return $script:statusBuilder
}

function Get-GitStatus {
  # Find git directory using FindFileInParentDirectories (faster than git command)
  $gitDir = FindFileInParentDirectories ".git"
  if (-not $gitDir) { return "" }

  $repoRoot = Split-Path -Parent $gitDir

  # Initialize cache variables if they don't exist
  $script:statusCache ??= $null
  $script:repoCachePath ??= $null
  $script:cacheSignature ??= $null
  
  # Get current repository signature based on key files that change during git operations
  $currentSignature = Get-RepoSignature -GitDir $gitDir -RepoRoot $repoRoot
  
  # Check if we need to invalidate the cache
  $cacheInvalid = $false
  
  # Invalidate cache if:
  # 1. Different repository
  # 2. No cached signature
  # 3. Signature has changed
  if (($script:repoCachePath -ne $repoRoot) -or 
    ($null -eq $script:cacheSignature) -or 
    ($currentSignature -ne $script:cacheSignature)) {
    $cacheInvalid = $true
  }
  
  # Return cached result if valid
  if (-not $cacheInvalid -and ($null -ne $script:statusCache)) {
    return $script:statusCache
  }
  
  # Update cache information
  $script:repoCachePath = $repoRoot
  $script:cacheSignature = $currentSignature
  
  # Get fresh git status
  $script:statusCache = Get-GitStatusRaw
  return $script:statusCache
}

# Helper function to generate a signature for the repository state
function Get-RepoSignature {
  param (
    [string]$GitDir,
    [string]$RepoRoot
  )
  
  $signature = ""
  
  # Check critical git files that change during operations
  $indexFile = Join-Path -Path $GitDir -ChildPath "index"
  $headFile = Join-Path -Path $GitDir -ChildPath "HEAD"
  
  # Add index file timestamp if it exists
  if (Test-Path $indexFile) {
    $indexModified = (Get-Item $indexFile -Force).LastWriteTime.Ticks
    $signature += "idx:$indexModified;"
  }
  
  # Add HEAD file timestamp if it exists
  if (Test-Path $headFile) {
    $headModified = (Get-Item $headFile -Force).LastWriteTime.Ticks
    $signature += "head:$headModified;"
  }
  
  # Check refs directories for branch and remote changes
  $refsHeads = Join-Path -Path $GitDir -ChildPath "refs/heads"
  $refsRemotes = Join-Path -Path $GitDir -ChildPath "refs/remotes"
  
  # Add latest ref modification time from local branches
  if (Test-Path $refsHeads) {
    $latestHeadRef = Get-ChildItem -Path $refsHeads -Recurse -File -ErrorAction SilentlyContinue | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1 -ExpandProperty LastWriteTime -ErrorAction SilentlyContinue
    if ($latestHeadRef) {
      $signature += "localref:$($latestHeadRef.Ticks);"
    }
  }
  
  # Add latest ref modification time from remote branches
  if (Test-Path $refsRemotes) {
    $latestRemoteRef = Get-ChildItem -Path $refsRemotes -Recurse -File -ErrorAction SilentlyContinue | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1 -ExpandProperty LastWriteTime -ErrorAction SilentlyContinue
    if ($latestRemoteRef) {
      $signature += "remoteref:$($latestRemoteRef.Ticks);"
    }
  }
  
  # Add working directory timestamp (to catch unstaged changes)
  $workingDirTimestamp = (Get-ChildItem -Path $RepoRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "$GitDir*" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty LastWriteTime -ErrorAction SilentlyContinue)
  
  if ($workingDirTimestamp) {
    $signature += "work:$($workingDirTimestamp.Ticks);"
  }
  
  # Fall back to checking if the git directory itself changed if signature is empty
  if (-not $signature) {
    $gitDirModified = (Get-Item $GitDir -Force).LastWriteTime.Ticks
    $signature = "gitdir:$gitDirModified"
  }
  
  return $signature
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
    }
    else {
      return "$flare_gitIcon $branch"
    }
  }
  else {
    return ""
  }
}

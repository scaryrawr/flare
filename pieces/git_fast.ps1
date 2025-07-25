. $PSScriptRoot/../utils/fileUtils.ps1

# Global cache for git repo info to avoid repeated filesystem calls
$global:flare_git_cache = @{}

function Get-GitRepoInfo {
  param([string]$Path = (Get-Location))
  
  # Use cache key based on current directory
  $cacheKey = $Path
  $cached = $global:flare_git_cache[$cacheKey]
  
  # Cache hit - return cached result
  if ($cached -and $cached.Timestamp -gt (Get-Date).AddSeconds(-2)) {
    return $cached
  }
  
  # Find .git (file or directory)
  $gitPath = FindFileInParentDirectories '.git' $Path
  if (-not $gitPath) {
    $result = @{ RepoPath = $null; GitDir = $null; Timestamp = Get-Date }
    $global:flare_git_cache[$cacheKey] = $result
    return $result
  }
  
  $repoPath = Split-Path -Parent $gitPath
  $gitDir = $gitPath
  
  # Handle worktrees/submodules where .git is a file
  if (Test-Path $gitPath -PathType Leaf) {
    try {
      $gitFileContent = Get-Content -Path $gitPath -Raw -ErrorAction Stop
      if ($gitFileContent -match 'gitdir:\s*(.+)') {
        $gitDir = $Matches[1].Trim()
        # Make relative paths absolute
        if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
          $gitDir = Join-Path $repoPath $gitDir
        }
      }
    }
    catch {
      $result = @{ RepoPath = $null; GitDir = $null; Timestamp = Get-Date }
      $global:flare_git_cache[$cacheKey] = $result
      return $result
    }
  }
  
  $result = @{ 
    RepoPath = $repoPath
    GitDir = $gitDir
    Timestamp = Get-Date
  }
  $global:flare_git_cache[$cacheKey] = $result
  return $result
}

function Get-TagForCommit {
  param([string]$GitDir, [string]$CommitHash)
  
  try {
    # Check packed-refs first (most common)
    $packedRefs = Join-Path $GitDir 'packed-refs'
    if (Test-Path $packedRefs -PathType Leaf) {
      $packedContent = [System.IO.File]::ReadAllText($packedRefs)
      foreach ($line in $packedContent -split "`n") {
        if ($line.StartsWith($CommitHash) -and $line.Contains('refs/tags/')) {
          if ($line -match 'refs/tags/(.+)$') {
            return $Matches[1]
          }
        }
      }
    }
    
    # Check individual tag refs
    $tagsDir = Join-Path $GitDir 'refs/tags'
    if (Test-Path $tagsDir -PathType Container) {
      $tagFiles = Get-ChildItem $tagsDir -File -ErrorAction SilentlyContinue
      foreach ($tagFile in $tagFiles) {
        try {
          $tagContent = [System.IO.File]::ReadAllText($tagFile.FullName).Trim()
          if ($tagContent -eq $CommitHash) {
            return $tagFile.Name
          }
        }
        catch { continue }
      }
    }
  }
  catch { }
  
  return $null
}

function Get-GitOperationStatus {
  param([string]$GitDir)
  
  $operation = $null
  $step = $null
  $totalSteps = $null
  
  # Check rebase-merge (interactive rebase)
  $rebaseMerge = Join-Path $GitDir 'rebase-merge'
  if (Test-Path $rebaseMerge -PathType Container) {
    try {
      $stepFile = Join-Path $rebaseMerge 'msgnum'
      $totalFile = Join-Path $rebaseMerge 'end'
      if ((Test-Path $stepFile -PathType Leaf) -and (Test-Path $totalFile -PathType Leaf)) {
        $step = [System.IO.File]::ReadAllText($stepFile).Trim()
        $totalSteps = [System.IO.File]::ReadAllText($totalFile).Trim()
      }
      
      $interactive = Join-Path $rebaseMerge 'interactive'
      if (Test-Path $interactive -PathType Leaf) {
        $operation = 'rebase-i'
      } else {
        $operation = 'rebase-m'
      }
    }
    catch {
      $operation = 'rebase'
    }
  }
  # Check rebase-apply (am/rebase)
  elseif (Test-Path (Join-Path $GitDir 'rebase-apply') -PathType Container) {
    $rebaseApply = Join-Path $GitDir 'rebase-apply'
    try {
      $nextFile = Join-Path $rebaseApply 'next'
      $lastFile = Join-Path $rebaseApply 'last'
      if ((Test-Path $nextFile -PathType Leaf) -and (Test-Path $lastFile -PathType Leaf)) {
        $step = [System.IO.File]::ReadAllText($nextFile).Trim()
        $totalSteps = [System.IO.File]::ReadAllText($lastFile).Trim()
      }
      
      if (Test-Path (Join-Path $rebaseApply 'rebasing') -PathType Leaf) {
        $operation = 'rebase'
      } elseif (Test-Path (Join-Path $rebaseApply 'applying') -PathType Leaf) {
        $operation = 'am'
      } else {
        $operation = 'am/rebase'
      }
    }
    catch {
      $operation = 'rebase'
    }
  }
  # Check other operations
  elseif (Test-Path (Join-Path $GitDir 'MERGE_HEAD') -PathType Leaf) {
    $operation = 'merge'
  }
  elseif (Test-Path (Join-Path $GitDir 'CHERRY_PICK_HEAD') -PathType Leaf) {
    $operation = 'cherry-pick'
  }
  elseif (Test-Path (Join-Path $GitDir 'REVERT_HEAD') -PathType Leaf) {
    $operation = 'revert'
  }
  elseif (Test-Path (Join-Path $GitDir 'BISECT_LOG') -PathType Leaf) {
    $operation = 'bisect'
  }
  
  return @{
    Operation = $operation
    Step = $step
    TotalSteps = $totalSteps
  }
}

function Get-StashCount {
  param([string]$GitDir)
  
  try {
    $stashRef = Join-Path $GitDir 'refs/stash'
    if (Test-Path $stashRef -PathType Leaf) {
      return 1  # Basic detection - has stashes
    }
    
    # Check logs/refs/stash for more accurate count
    $stashLog = Join-Path $GitDir 'logs/refs/stash'
    if (Test-Path $stashLog -PathType Leaf) {
      $lines = [System.IO.File]::ReadAllLines($stashLog)
      return $lines.Length
    }
  }
  catch { }
  
  return 0
}

function flare_git_fast {
  # Get cached repository info
  $repoInfo = Get-GitRepoInfo
  
  if (-not $repoInfo.RepoPath) { 
    return '' 
  }

  $gitDir = $repoInfo.GitDir
  $headFile = Join-Path $gitDir 'HEAD'

  # Fast file existence and content check
  if (-not (Test-Path $headFile -PathType Leaf)) {
    return ''
  }

  try {
    # Read HEAD file efficiently
    $headContent = [System.IO.File]::ReadAllText($headFile).Trim()
    
    $location = ''
    
    # Branch reference (most common case)
    if ($headContent.StartsWith('ref: refs/heads/')) {
      $location = $headContent.Substring(16)
    }
    # Handle detached HEAD with commit hash
    elseif ($headContent -match '^[0-9a-f]{40}$|^[0-9a-f]{7,40}$') {
      # Try to find a tag pointing to this commit
      $tag = Get-TagForCommit $gitDir $headContent
      if ($tag) {
        $location = "#$tag"
      } else {
        # Use short hash for detached HEAD
        $location = "@" + $headContent.Substring(0, 7)
      }
    }
    
    if (-not $location) {
      return ''
    }
    
    # Get operation status
    $opStatus = Get-GitOperationStatus $gitDir
    
    # Build output
    $output = $location
    
    # Add operation info
    if ($opStatus.Operation) {
      $output += " $($opStatus.Operation)"
      if ($opStatus.Step -and $opStatus.TotalSteps) {
        $output += " $($opStatus.Step)/$($opStatus.TotalSteps)"
      }
    }
    
    # Add stash indicator
    $stashCount = Get-StashCount $gitDir
    if ($stashCount -gt 0) {
      $output += " *$stashCount"
    }
    
    return $output
  }
  catch {
    return ''
  }
}

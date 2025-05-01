. $PSScriptRoot/../utils/fileUtils.ps1
. $PSScriptRoot/git.ps1

function flare_git_fast {
  # Get repository path
  $repoPath = Get-GitRepoPath
  
  # Not in a git repo
  if (-not $repoPath) { 
    return '' 
  }

  # Fast branch detection by directly reading the git HEAD file
  $gitDir = Join-Path $repoPath '.git'
  $headFile = Join-Path $gitDir 'HEAD'

  if (Test-Path $headFile) {
    $headContent = Get-Content -Path $headFile -Raw
    
    # Check if we have a direct reference to a branch
    if ($headContent -match 'ref: refs/heads/(.+)$') {
      return $Matches[1]
    }
    # If in a special state (detached HEAD, rebase, merge, etc.)
    elseif ($headContent -match '^([0-9a-f]+)') {
      # Check for rebase/merge/cherry-pick in progress
      if (Test-Path (Join-Path $gitDir 'rebase-merge')) {
        return 'REBASE'
      }
      elseif (Test-Path (Join-Path $gitDir 'rebase-apply')) {
        return 'REBASE'
      }
      elseif (Test-Path (Join-Path $gitDir 'MERGE_HEAD')) {
        return 'MERGE'
      }
      elseif (Test-Path (Join-Path $gitDir 'CHERRY_PICK_HEAD')) {
        return 'CHERRY'
      }
      # Detached HEAD state - use abbreviated commit hash
      return 'DETACHED@' + $headContent.Substring(0, 7)
    }
  }

  return ''
}

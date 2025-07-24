. $PSScriptRoot/../utils/fileUtils.ps1

# Function to detect git operations (rebase, merge, etc.) and their steps
# based on https://github.com/IlanCosman/tide/blob/main/functions/_tide_item_git.fish
function Get-GitOperation {
  param(
    [Parameter(Mandatory = $true)]
    [string]$GitDir
  )
  
  $operation = $null
  $step = $null
  $total = $null

  # Check for rebase-merge (interactive or merge rebase)
  if (Test-Path "$GitDir/rebase-merge") {
    if ((Test-Path "$GitDir/rebase-merge/msgnum") -and (Test-Path "$GitDir/rebase-merge/end")) {
      $step = Get-Content "$GitDir/rebase-merge/msgnum" -Raw
      $total = Get-Content "$GitDir/rebase-merge/end" -Raw
      # Trim any whitespace/newlines
      $step = $step.Trim()
      $total = $total.Trim()
    }
    
    if (Test-Path "$GitDir/rebase-merge/interactive") {
      $operation = "rebase-i"
    }
    else {
      $operation = "rebase-m"
    }
  } 
  # Check for rebase-apply (standard rebase/am)
  elseif (Test-Path "$GitDir/rebase-apply") {
    if ((Test-Path "$GitDir/rebase-apply/next") -and (Test-Path "$GitDir/rebase-apply/last")) {
      $step = Get-Content "$GitDir/rebase-apply/next" -Raw
      $total = Get-Content "$GitDir/rebase-apply/last" -Raw
      # Trim any whitespace/newlines
      $step = $step.Trim()
      $total = $total.Trim()
    }
    
    if (Test-Path "$GitDir/rebase-apply/rebasing") {
      $operation = "rebase"
    }
    elseif (Test-Path "$GitDir/rebase-apply/applying") {
      $operation = "am"
    }
    else {
      $operation = "am/rebase"
    }
  } 
  # Check for merge
  elseif (Test-Path "$GitDir/MERGE_HEAD") {
    $operation = "merge"
  } 
  # Check for cherry-pick
  elseif (Test-Path "$GitDir/CHERRY_PICK_HEAD") {
    $operation = "cherry-pick"
  } 
  # Check for revert
  elseif (Test-Path "$GitDir/REVERT_HEAD") {
    $operation = "revert"
  } 
  # Check for bisect
  elseif (Test-Path "$GitDir/BISECT_LOG") {
    $operation = "bisect"
  }
  
  return @{ 
    Operation = $operation
    Step      = $step
    Total     = $total
  }
}

# Updates the cached git status when files change in the repository
function Update-GitStatus {
  param(
    [Parameter(Mandatory = $false)]
    [string]$GitRepoPath
  )

  # If we're not in a git repo, return empty
  if (-not $GitRepoPath) {
    return @{ Branch = $null; Status = $null; Operation = $null }
  }
  
  # Get fresh git status
  return Get-GitBranchAndStatus -GitRepoPath $GitRepoPath
}

function Format-GitStatus {
  param(
    [Parameter(Mandatory = $false)]
    [string[]]$StatusOutput,
    
    [Parameter(Mandatory = $false)]
    [string]$GitDir
  )
    
  if (-not $StatusOutput) {
    $StatusOutput = git --no-optional-locks status --porcelain 2> $null
  }

  $added = 0
  $modified = 0
  $deleted = 0
  $renamed = 0
  $copied = 0
  $unmerged = 0
  $untracked = 0
  $ahead = 0
  $behind = 0
  $stash = 0
  
  # Parse git status output for file changes
  $StatusOutput | ForEach-Object {
    if ($_ -match '^\s*(.{2})\s+(.*)') {
      $status = $Matches[1]
      
      # Handle unmerged files (conflicts) - match UU pattern like fish version
      if ($status -match '^UU') {
        $unmerged += 1
      }
      # Handle other standard statuses
      else {
        $stagingChar = $status[0]
        $workingChar = $status[1]
        
        # Count staging area changes (first character)
        if ($stagingChar -match '[ADMR]') {
          $added += 1
        }
        
        # Count working directory changes (second character)  
        if ($workingChar -match '[ADMR]') {
          $modified += 1
        }
        
        # Count untracked files
        if ($status -match '^\?\?') {
          $untracked += 1
        }
      }
    }
  }

  # Get stash count
  if ($GitDir) {
    $stashOutput = git stash list 2>$null
    if ($stashOutput) {
      $stash = ($stashOutput | Measure-Object).Count
    }
  }

  # Get behind/ahead counts using git rev-list like the fish version
  $revListOutput = git rev-list --count --left-right '@{upstream}...HEAD' 2>$null
  if ($revListOutput -and $revListOutput -match '(\d+)\s+(\d+)') {
    $behind = [int]$Matches[1]
    $ahead = [int]$Matches[2]
  }
 
  $script:statusBuilder = ''
  function Add-Status($icon, $count) {
    if ($count -eq 0) { return }
    if ($script:statusBuilder) { $script:statusBuilder += ' ' }
    $script:statusBuilder += "$icon$count"
  }

  Add-Status '⇣' $behind
  Add-Status '⇡' $ahead  
  Add-Status '*' $stash
  Add-Status '~' $unmerged
  Add-Status '+' $added
  Add-Status '!' $modified
  Add-Status '?' $untracked

  return $script:statusBuilder
}

# Optimized function to get both branch and status in one call
function Get-GitBranchAndStatus {
  param(
    [Parameter(Mandatory = $false)]
    [string]$GitRepoPath
  )

  # Find git directory - if GitRepoPath is provided, append .git, otherwise find it
  if ($GitRepoPath) {
    $gitDir = Join-Path -Path $GitRepoPath -ChildPath '.git'
  } else {
    $gitDir = FindFileInParentDirectories '.git'
  }

  # Not in a git repository
  if (-not $gitDir -or -not (Test-Path $gitDir)) {
    return @{ Branch = $null; Status = $null; Operation = $null }
  }

  # Check if git command is available
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    return @{ Branch = $null; Status = $null; Operation = $null }
  }

  # Get git operation information
  $gitOp = Get-GitOperation -GitDir $gitDir
  
  # Try to get branch name directly from git files (no git command needed)
  $branch = $null
  
  # Check if we're on a branch or in a detached HEAD state
  $headFile = Join-Path -Path $gitDir -ChildPath 'HEAD'
  if (Test-Path $headFile) {
    $headContent = Get-Content -Path $headFile -Raw
    
    # Check if we have a direct reference to a branch
    if ($headContent -match 'ref: refs/heads/(.+)$') {
      $branch = $Matches[1]
    }
    # If not a symbolic ref (detached HEAD), check for tags
    else {
      $commitHash = $headContent.Trim()
      
      # Try to find a tag pointing to this commit
      $tag = git describe --tags --exact-match $commitHash 2>$null
      if ($tag) {
        $branch = "#$tag" # Tag format like in tide
      }
      else {
        # Fallback to short hash
        $shortHash = $commitHash.Substring(0, 7)
        $branch = "@$shortHash" # Detached format like in tide
      }
    }
  }

  # If we couldn't determine branch from HEAD file, fallback to git command
  if (-not $branch) {
    # Get branch name using git branch --show-current (like fish version)
    $branch = git branch --show-current 2>$null
    if (-not $branch) {
      # Fallback for detached HEAD - try tags first
      $tag = git tag --points-at HEAD 2>$null | Select-Object -First 1
      if ($tag) {
        $branch = "#$tag"
      }
      else {
        # Get short hash for detached HEAD
        $shortHash = git rev-parse --short HEAD 2>$null
        if ($shortHash) {
          $branch = "@$shortHash"
        }
      }
    }
  }
    
  # Get status information using --porcelain (not -sb) like fish version
  $output = git --no-optional-locks status --porcelain 2> $null
  $status = Format-GitStatus -StatusOutput $output -GitDir $gitDir
  
  return @{ 
    Branch    = $branch
    Status    = $status
    Operation = $gitOp.Operation
    Step      = $gitOp.Step
    Total     = $gitOp.Total
  }
}

function Get-GitRepoPath {
  # Find git directory using FindFileInParentDirectories (faster than git command)
  $gitDir = FindFileInParentDirectories '.git'
  if (-not $gitDir) { 
    return $null
  }
  
  return Split-Path -Parent $gitDir
}

function Format-GitOutput {
  param(
    [Parameter(Mandatory = $false)]
    [string]$Branch,
    
    [Parameter(Mandatory = $false)]
    [string]$Status,
    
    [Parameter(Mandatory = $false)]
    [string]$Operation,
    
    [Parameter(Mandatory = $false)]
    [string]$Step,
    
    [Parameter(Mandatory = $false)]
    [string]$Total
  )
  
  if (-not $Branch) {
    return ''
  }
  
  # Build the output string
  $output = $Branch
  
  # Add operation information if available
  if ($Operation) {
    $output += " $Operation"
    
    # Add step/total if available
    if ($Step -and $Total) {
      $output += " $Step/$Total"
    }
  }
  
  # Add status information if available
  if ($Status) {
    $output += " $Status"
  }
  
  return $output
}

function flare_git {
  # Get repository path
  $repoPath = Get-GitRepoPath
  
  # Not in a git repo
  if (-not $repoPath) { 
    return '' 
  }

  # Get git info including branch, status and operation
  $gitInfo = Get-GitBranchAndStatus -GitRepoPath $repoPath
  
  return Format-GitOutput -Branch $gitInfo.Branch -Status $gitInfo.Status -Operation $gitInfo.Operation -Step $gitInfo.Step -Total $gitInfo.Total
}
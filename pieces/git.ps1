. $PSScriptRoot/../utils/fileUtils.ps1

# Function to detect git operations (rebase, merge, etc.) and their steps
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
    if (Test-Path "$GitDir/rebase-merge/msgnum" -and Test-Path "$GitDir/rebase-merge/end") {
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
    if (Test-Path "$GitDir/rebase-apply/next" -and Test-Path "$GitDir/rebase-apply/last") {
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
    $StatusOutput = git --no-optional-locks status -sb --porcelain 2> $null
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
  
  # Parse git status output
  $StatusOutput | ForEach-Object {
    if ($_ -match '^\s*([AMDRCU?]{1,2})\s+(.*)') {
      # $file = $Matches[2]
      $status = $Matches[1]
      
      # Handle unmerged files (conflicts) with priority
      if ($status -match 'U' -or $status -match 'U{2,}|A{2,}|D{2,}') {
        $unmerged += 1
      }
      # Handle other standard statuses
      else {
        switch -Regex ($status) {
          '^A' { $added += 1 }
          '^M' { $modified += 1 }
          '^.M' { $modified += 1 }
          '^D' { $deleted += 1 }
          '^.D' { $deleted += 1 }
          '^R' { $renamed += 1 }
          '^C' { $copied += 1 }
          '^\?\?' { $untracked += 1 }
        }
      }
    }
    elseif ($_ -match 'ahead (\d+)') {
      $ahead = [int]$Matches[1]
    }
    elseif ($_ -match 'behind (\d+)') {
      $behind = [int]$Matches[1]
    }
  }

  # Count stashes if we have a git directory
  if ($GitDir) {
    $stashOutput = git stash list 2>$null
    if ($stashOutput) {
      $stash = ($stashOutput | Measure-Object).Count
    }
  }
 
  $script:statusBuilder = ''
  function Add-Status($icon, $count) {
    if ($count -eq 0) { return }
    if ($script:statusBuilder) { $script:statusBuilder += ' ' }
    $script:statusBuilder += "$icon$count"
  }

  Add-Status '' $ahead
  Add-Status '' $behind
  Add-Status '' $added
  Add-Status '' $modified
  Add-Status '󰆴' $deleted
  Add-Status '󰑕' $renamed
  Add-Status '' $copied
  Add-Status '' $unmerged
  Add-Status '' $untracked
  Add-Status '*' $stash

  return $script:statusBuilder
}

# Optimized function to get both branch and status in one call
function Get-GitBranchAndStatus {
  param(
    [Parameter(Mandatory = $false)]
    [string]$GitRepoPath
  )

  # Find git directory using FindFileInParentDirectories (faster than git command)
  $gitDir = $GitRepoPath ?? $(FindFileInParentDirectories '.git')

  # Not in a git repository
  if (-not $gitDir) {
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
    # Cache is invalid, get fresh data (one git call instead of two)
    $output = git --no-optional-locks status -sb --porcelain 2> $null
      
    # Extract branch name from the first line
    # Format is usually "## branch...origin/branch [ahead/behind]"
    $branch = if ($output -and $output -is [array]) {
      if ($output[0] -match '## (.+?)(?:\.\.\.|$)') {
        $Matches[1]
      }
      else { $null }
    }
    elseif ($output -and $output -is [string] -and $output -match '## (.+?)(?:\.\.\.|$)') {
      $Matches[1]
    }
    else {
      # Fallback if status -sb doesn't work for some reason
      git --no-optional-locks rev-parse --abbrev-ref HEAD 2> $null
    }
    
    # Process status information
    $status = Format-GitStatus -StatusOutput $output -GitDir $gitDir
  }
  else {
    # If we got the branch without git command, we still need status info
    $output = git --no-optional-locks status -sb --porcelain 2> $null
    $status = Format-GitStatus -StatusOutput $output -GitDir $gitDir
  }
  
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

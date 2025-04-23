. $PSScriptRoot/../utils/fileUtils.ps1

# Script level variables to track git state
$script:gitFileWatcher ??= $null
$global:flare_currentGitDir ??= $null
$global:flare_cachedGitInfo ??= @{ Branch = $null; Status = $null }

$global:flare_gitStatusFunc ??= {
  param(
    [Parameter(Mandatory = $false)]
    [string]$GitRepoPath
  )
  
  # If we're not in a git repo, clear the cache
  if (-not $GitRepoPath) {
    $global:flare_cachedGitInfo = @{ Branch = $null; Status = $null }
    return
  }
  
  # Get fresh git status
  return Get-GitBranchAndStatus -GitRepoPath $GitRepoPath
}

# Updates the cached git status when files change in the repository
function Update-GitStatus {
  param(
    [Parameter(Mandatory = $false)]
    [string]$GitRepoPath
  )

  return & $global:flare_gitStatusFunc -GitRepoPath $GitRepoPath
}

function Format-GitStatus {
  param(
    [Parameter(Mandatory = $false)]
    [string[]]$StatusOutput
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
  
  $StatusOutput | ForEach-Object {
    if ($_ -match "^\s*([AMDRCU?]+)\s+(.*)") {
      # $file = $Matches[2]
      $status = $Matches[1]
      
      # Handle unmerged files (conflicts) with priority
      if ($status -match "U" -or $status -match "U{2,}|A{2,}|D{2,}") {
        $unmerged += 1
      }
      # Handle other standard statuses
      else {
        switch ($status) {
          "A" { $added += 1 }
          "M" { $modified += 1 }
          "D" { $deleted += 1 }
          "R" { $renamed += 1 }
          "C" { $copied += 1 }
          "??" { $untracked += 1 }
        }
      }
    }
    elseif ($_ -match "(ahead|behind) (\d+)") {
      $status = $Matches[1]
      $count = $Matches[2]
      switch ($status) {
        "ahead" { $ahead += [int]$count }
        "behind" { $behind += [int]$count }
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

# Optimized function to get both branch and status in one call
function Get-GitBranchAndStatus {
  param(
    [Parameter(Mandatory = $false)]
    [string]$GitRepoPath
  )

  # Check if git command is available
  if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    return @{ Branch = $null; Status = $null }
  }

  # Find git directory using FindFileInParentDirectories (faster than git command)
  $gitDir = $GitRepoPath ?? $(FindFileInParentDirectories ".git")

  # Not in a git repository
  if (-not $gitDir) {
    return @{ Branch = $null; Status = $null }
  }

  # Try to get branch name directly from git files (no git command needed)
  $branch = $null
  
  # Check if we're on a branch or in a detached HEAD state
  $headFile = Join-Path -Path $gitDir -ChildPath "HEAD"
  if (Test-Path $headFile) {
    $headContent = Get-Content -Path $headFile -Raw
    
    # Check if we have a direct reference to a branch
    if ($headContent -match "ref: refs/heads/(.+)$") {
      $branch = $Matches[1]
    }
    # If not a symbolic ref (detached HEAD), use abbreviated commit hash
    elseif ($headContent -match "^([0-9a-f]+)") {
      $commitHash = $Matches[1].Substring(0, 7)  # Use first 7 chars
      $branch = "detached@$commitHash"
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
    
    # Process status information using existing Format-GitStatus logic
    $status = Format-GitStatus -StatusOutput $output
  }
  else {
    # If we got the branch without git command, we still need status info
    $output = git --no-optional-locks status -sb --porcelain 2> $null
    $status = Format-GitStatus -StatusOutput $output
  }
    
  # Process status information using existing Format-GitStatus logic
  $status = Format-GitStatus -StatusOutput $output
  
  return @{ 
    Branch = $branch
    Status = $status
  }
}

function flare_init_git {
  $gitDir = FindFileInParentDirectories ".git"
  if (-not $gitDir) {
    return
  }
  
  # Get the parent directory of .git which is the actual repo directory
  $repoDir = Split-Path -Parent $gitDir
  $global:flare_currentGitDir = $repoDir
  
  # Configure the FileSystemWatcher
  try {
    # Reuse existing watcher if possible
    if ($script:gitFileWatcher) {
      # Just update the path of the existing watcher
      $script:gitFileWatcher.EnableRaisingEvents = $false
      $script:gitFileWatcher.Path = $repoDir
      $script:gitFileWatcher.EnableRaisingEvents = $true
    }
    else {
      # Create new watcher only if one doesn't exist
      $script:gitFileWatcher = New-Object System.IO.FileSystemWatcher
      $script:gitFileWatcher.Path = $repoDir
      $script:gitFileWatcher.IncludeSubdirectories = $true
      
      # Watch for any changes that might affect git status
      $script:gitFileWatcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor 
      [System.IO.NotifyFilters]::DirectoryName -bor
      [System.IO.NotifyFilters]::LastWrite -bor
      [System.IO.NotifyFilters]::CreationTime
      
      # Register for change events
      $writeHandler = {
        $path = $event.SourceEventArgs.FullPath
        $gitDir = & $global:flare_findFileInParentDirectories -FileName ".git" -StartDirectory $path
        $global:flare_cachedGitInfo = & $global:flare_gitStatusFunc -GitRepoPath $gitDir
      }
      
      # Register events - changes to files and directories will trigger the same handler
      $null = Register-ObjectEvent -InputObject $script:gitFileWatcher -EventName Created -Action $writeHandler
      $null = Register-ObjectEvent -InputObject $script:gitFileWatcher -EventName Changed -Action $writeHandler
      $null = Register-ObjectEvent -InputObject $script:gitFileWatcher -EventName Deleted -Action $writeHandler
      $null = Register-ObjectEvent -InputObject $script:gitFileWatcher -EventName Renamed -Action $writeHandler
      
      # Enable the watcher
      $script:gitFileWatcher.EnableRaisingEvents = $true
    }
  }
  catch {
    Write-Error "Failed to initialize git FileSystemWatcher: $_"
    $script:gitFileWatcher = $null
  }
}

function flare_cleanup_git {
  # Clean up the FileSystemWatcher and its event handlers
  if ($script:gitFileWatcher) {
    $script:gitFileWatcher.EnableRaisingEvents = $false
    $script:gitFileWatcher.Dispose()
    $script:gitFileWatcher = $null
    
    # Clean up any registered events
    Get-EventSubscriber | Where-Object { 
      $_.SourceObject -is [System.IO.FileSystemWatcher] -and 
      $_.SourceObject.Path -eq $global:flare_currentGitDir 
    } | Unregister-Event
  }
  
  $global:flare_currentGitDir = $null
  $global:flare_cachedGitInfo = @{ Branch = $null; Status = $null }
}

function Get-GitRepoPath {
  # Find git directory using FindFileInParentDirectories (faster than git command)
  $gitDir = FindFileInParentDirectories ".git"
  if (-not $gitDir) { 
    return $null
  }
  
  return Split-Path -Parent $gitDir
}

function Update-GitWatcher {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath
  )
  
  # Check if we need to initialize or update the watcher
  if (-not $script:gitFileWatcher) {
    # Initialize the watcher if it doesn't exist
    $global:flare_currentGitDir = $RepoPath
    flare_init_git
  }
  # Only update if we've changed directories
  elseif ($global:flare_currentGitDir -ne $RepoPath) {
    $global:flare_currentGitDir = $RepoPath
    flare_init_git  # This will reuse the existing watcher
  }
}

function Format-GitOutput {
  param(
    [Parameter(Mandatory = $false)]
    [string]$Branch,
    
    [Parameter(Mandatory = $false)]
    [string]$Status
  )
  
  $global:flare_gitIcon ??= ''
  
  if (-not $Branch) {
    return ""
  }
  
  if ($Status) {
    return "$global:flare_gitIcon $Branch $Status"
  }
  else {
    return "$global:flare_gitIcon $Branch"
  }
}

function Test-GitStatusUpdateNeeded {
  param(
    [Parameter(Mandatory = $true)]
    [string]$GitRepoPath
  )
  
  return ($GitRepoPath -ne $global:flare_currentGitDir) -or ((-not $global:flare_cachedGitInfo.Branch) -and (-not $global:flare_cachedGitInfo.Status))
}

function flare_git {
  # Get repository path
  $repoPath = Get-GitRepoPath
  
  # Not in a git repo, clean up if needed
  if (-not $repoPath) { 
    if ($script:gitFileWatcher) {
      flare_cleanup_git
    }
    return "" 
  }
  
  # Check if we should force an update of the git status
  if (Test-GitStatusUpdateNeeded $repoPath) {
    $global:flare_cachedGitInfo = Update-GitStatus -GitRepoPath $repoPath
  }

  # Update or initialize git watcher
  Update-GitWatcher -RepoPath $repoPath
    
  # Use cached data if available, otherwise get fresh data
  if ($global:flare_cachedGitInfo.Branch) {
    return Format-GitOutput -Branch $global:flare_cachedGitInfo.Branch -Status $global:flare_cachedGitInfo.Status
  }
  else {
    # Fallback to direct calculation if cache not available
    $gitInfo = Get-GitBranchAndStatus -GitRepoPath $repoPath
    return Format-GitOutput -Branch $gitInfo.Branch -Status $gitInfo.Status
  }
}

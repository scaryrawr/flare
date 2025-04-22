. $PSScriptRoot/../utils/fileUtils.ps1

# Script level variables to track git state
$script:gitFileWatcher ??= $null
$script:currentGitDir ??= $null
$script:cachedGitInfo ??= @{ Branch = $null; Status = $null }
$script:lastGitCheck ??= 0
$script:gitEventThrottleSeconds ??= 1 # Throttle time between git status updates to prevent excessive operations

# Updates the cached git status when files change in the repository
function Update-GitStatus {
  param(
    [Parameter(Mandatory = $false)]
    [string]$GitRepoPath
  )
  
  # If we're not in a git repo, clear the cache
  if (-not $GitRepoPath) {
    $script:cachedGitInfo = @{ Branch = $null; Status = $null }
    return
  }
  
  # Get fresh git status
  $gitInfo = Get-GitBranchAndStatus
  $script:cachedGitInfo = $gitInfo
  $script:lastGitCheck = [int](Get-Date -UFormat '%s')
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
  # Check if git command is available
  if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    return @{ Branch = $null; Status = $null }
  }

  # Find git directory using FindFileInParentDirectories (faster than git command)
  $gitDir = FindFileInParentDirectories ".git"

  # Not in a git repository
  if (-not $gitDir) {
    return @{ Branch = $null; Status = $null }
  }

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
  $script:currentGitDir = $repoDir
  
  # Configure the FileSystemWatcher
  try {
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
      # Throttle updates to prevent excessive git operations
      $currentTime = [int](Get-Date -UFormat '%s')
      if (($currentTime - $script:lastGitCheck) -ge $script:gitEventThrottleSeconds) {
        Update-GitStatus -GitRepoPath $script:currentGitDir
      }
    }
    
    # Register events - changes to files and directories will trigger the same handler
    $null = Register-ObjectEvent -InputObject $script:gitFileWatcher -EventName Created -Action $writeHandler
    $null = Register-ObjectEvent -InputObject $script:gitFileWatcher -EventName Changed -Action $writeHandler
    $null = Register-ObjectEvent -InputObject $script:gitFileWatcher -EventName Deleted -Action $writeHandler
    $null = Register-ObjectEvent -InputObject $script:gitFileWatcher -EventName Renamed -Action $writeHandler
    
    # Enable the watcher
    $script:gitFileWatcher.EnableRaisingEvents = $true
    
    # Initialize cached git status
    Update-GitStatus -GitRepoPath $repoDir
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
      $_.SourceObject.Path -eq $script:currentGitDir 
    } | Unregister-Event
  }
  
  $script:currentGitDir = $null
  $script:cachedGitInfo = @{ Branch = $null; Status = $null }
}

function flare_git {
  # Find git directory using FindFileInParentDirectories (faster than git command)
  $gitDir = FindFileInParentDirectories ".git"
  if (-not $gitDir) { 
    # Not in a git repo, clean up if needed
    if ($script:gitFileWatcher) {
      flare_cleanup_git
    }
    return "" 
  }
  
  $repoDir = Split-Path -Parent $gitDir
  $global:flare_gitIcon ??= ''
  
  # Check if we need to create or update the watcher
  if (-not $script:gitFileWatcher -or $script:currentGitDir -ne $repoDir) {
    # Clean up existing watcher if we're in a different repo
    if ($script:gitFileWatcher) {
      flare_cleanup_git
    }
    
    # Create new watcher for current repo
    $script:currentGitDir = $repoDir
    flare_init_git
  }
  
  # Check if we should force an update of the git status
  $currentTime = [int](Get-Date -UFormat '%s')
  if (($currentTime - $script:lastGitCheck) -ge $script:gitEventThrottleSeconds) {
    Update-GitStatus -GitRepoPath $repoDir
  }
    
  # Use cached data
  if ($script:cachedGitInfo.Branch) {
    if ($script:cachedGitInfo.Status) {
      return "$global:flare_gitIcon $($script:cachedGitInfo.Branch) $($script:cachedGitInfo.Status)"
    }
    else {
      return "$global:flare_gitIcon $($script:cachedGitInfo.Branch)"
    }
  }
  else {
    # Fallback to direct calculation if cache not available
    $gitInfo = Get-GitBranchAndStatus
    
    if ($gitInfo.Branch) {
      if ($gitInfo.Status) {
        return "$global:flare_gitIcon $($gitInfo.Branch) $($gitInfo.Status)"
      }
      else {
        return "$global:flare_gitIcon $($gitInfo.Branch)"
      }
    }
    else {
      return ""
    }
  }
}

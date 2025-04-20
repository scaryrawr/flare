. $PSScriptRoot/../utils/fileUtils.ps1

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

function flare_git {
  # Find git directory using FindFileInParentDirectories (faster than git command)
  $gitDir = FindFileInParentDirectories ".git"
  if (-not $gitDir) { return "" }
    
  $global:flare_gitIcon ??= ''
    
  # Get branch and status from cache
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

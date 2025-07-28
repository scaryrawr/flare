. $PSScriptRoot/../utils/fileUtils.ps1

function flare_git {
    # Check if git command is available
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return ''
    }

    # Check if we're in a git repository
    $gitDir = git rev-parse --git-dir 2>$null
    if (-not $gitDir -or $LASTEXITCODE -ne 0) {
        return ''
    }
    
    # Get location (branch/tag/commit) - use individual commands for reliability
    $location = $null
    
    # Try to get current branch name
    $branch = git symbolic-ref --short HEAD 2>$null
    if ($branch -and $LASTEXITCODE -eq 0) {
        $location = $branch
    }
    else {
        # Try to get tag pointing to HEAD
        $tag = git describe --exact-match --tags HEAD 2>$null | Select-Object -First 1
        if ($tag -and $LASTEXITCODE -eq 0) {
            $location = "#$tag"
        }
        else {
            # Get short commit hash for detached HEAD
            $shortHash = git rev-parse --short HEAD 2>$null
            if ($shortHash -and $LASTEXITCODE -eq 0) {
                $location = "@$shortHash"
            }
        }
    }
    
    # If no location found, return empty
    if (-not $location) {
        return ''
    }

    # Check for operations (rebase, merge, etc.)
    $operation = $null
    $step = $null
    $totalSteps = $null
    
    if (Test-Path "$gitDir/rebase-merge") {
        if ((Test-Path "$gitDir/rebase-merge/msgnum") -and (Test-Path "$gitDir/rebase-merge/end")) {
            $step = (Get-Content "$gitDir/rebase-merge/msgnum" -Raw -ErrorAction SilentlyContinue).Trim()
            $totalSteps = (Get-Content "$gitDir/rebase-merge/end" -Raw -ErrorAction SilentlyContinue).Trim()
        }
        if (Test-Path "$gitDir/rebase-merge/interactive") {
            $operation = 'rebase-i'
        }
        else {
            $operation = 'rebase-m'
        }
    }
    elseif (Test-Path "$gitDir/rebase-apply") {
        if ((Test-Path "$gitDir/rebase-apply/next") -and (Test-Path "$gitDir/rebase-apply/last")) {
            $step = (Get-Content "$gitDir/rebase-apply/next" -Raw -ErrorAction SilentlyContinue).Trim()
            $totalSteps = (Get-Content "$gitDir/rebase-apply/last" -Raw -ErrorAction SilentlyContinue).Trim()
        }
        if (Test-Path "$gitDir/rebase-apply/rebasing") {
            $operation = 'rebase'
        }
        elseif (Test-Path "$gitDir/rebase-apply/applying") {
            $operation = 'am'
        }
        else {
            $operation = 'am/rebase'
        }
    }
    elseif (Test-Path "$gitDir/MERGE_HEAD") {
        $operation = 'merge'
    }
    elseif (Test-Path "$gitDir/CHERRY_PICK_HEAD") {
        $operation = 'cherry-pick'
    }
    elseif (Test-Path "$gitDir/REVERT_HEAD") {
        $operation = 'revert'
    }
    elseif (Test-Path "$gitDir/BISECT_LOG") {
        $operation = 'bisect'
    }

    # Get git status and counts - use individual commands for reliability
    $stat = git --no-optional-locks status --porcelain 2>$null
    
    # Count stashes
    $stashList = git stash list 2>$null
    $stash = if ($stashList) { ($stashList | Measure-Object).Count } else { 0 }
    
    # Count conflicted files (UU status)
    $conflicted = if ($stat) { ($stat | Where-Object { $_ -match '^UU' } | Measure-Object).Count } else { 0 }
    
    # Count staged files (first character is A, D, M, R)
    $staged = if ($stat) { ($stat | Where-Object { $_ -match '^[ADMR]' } | Measure-Object).Count } else { 0 }
    
    # Count dirty files (second character is A, D, M, R)
    $dirty = if ($stat) { ($stat | Where-Object { $_ -match '^.[ADMR]' } | Measure-Object).Count } else { 0 }
    
    # Count untracked files
    $untracked = if ($stat) { ($stat | Where-Object { $_ -match '^\?\?' } | Measure-Object).Count } else { 0 }
    
    # Get behind/ahead counts - use proper PowerShell escaping
    $behind = 0
    $ahead = 0
    try {
        $revListOutput = git rev-list --count --left-right '@{upstream}...HEAD' 2>$null
        if ($revListOutput -and $LASTEXITCODE -eq 0 -and $revListOutput -match '(\d+)\s+(\d+)') {
            $behind = [int]$Matches[1]
            $ahead = [int]$Matches[2]
        }
    }
    catch {
        # Silently handle upstream tracking issues
    }

    # Build output string
    $output = $location
    
    # Add operation info
    if ($operation) {
        $output += " $operation"
        if ($step -and $totalSteps) {
            $output += " $step/$totalSteps"
        }
    }
    
    # Add status indicators (matching tide order: behind, ahead, stash, conflicted, staged, dirty, untracked)
    $statusParts = @()
    if ($behind -gt 0) { $statusParts += "⇣$behind" }
    if ($ahead -gt 0) { $statusParts += "⇡$ahead" }
    if ($stash -gt 0) { $statusParts += "*$stash" }
    if ($conflicted -gt 0) { $statusParts += "~$conflicted" }
    if ($staged -gt 0) { $statusParts += "+$staged" }
    if ($dirty -gt 0) { $statusParts += "!$dirty" }
    if ($untracked -gt 0) { $statusParts += "?$untracked" }
    
    if ($statusParts.Count -gt 0) {
        $output += ' ' + ($statusParts -join ' ')
    }
    
    return $output
}
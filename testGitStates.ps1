#!/usr/bin/env pwsh

# Test script for git piece functionality
# Tests all various git states and operations to ensure the git piece works correctly
# 
# Test coverage includes:
# - Basic states: no repo, empty repo, clean repo, branches, tags, detached HEAD
# - File status: untracked, staged, modified, stash
# - Operations: merge, rebase (interactive and standard), cherry-pick
# - Upstream tracking: ahead, behind, diverged branches
# - Complex combinations: multiple status types, remote scenarios

param(
    [switch]$Verbose
)

# Source the git piece directly
. "$PSScriptRoot/pieces/git.ps1"

# Function to log test results
function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Expected,
        [string]$Actual,
        [bool]$Success
    )
    
    if ($Success) {
        Write-Host "✅ $TestName" -ForegroundColor Green
    } else {
        Write-Host "❌ $TestName" -ForegroundColor Red
        Write-Host "   Expected: '$Expected'" -ForegroundColor Yellow
        Write-Host "   Actual:   '$Actual'" -ForegroundColor Yellow
    }
    
    # Always show what the git piece outputs
    Write-Host "   Git piece output: '$Actual'" -ForegroundColor Cyan
}

# Function to test git piece output
function Test-GitPiece {
    param(
        [string]$TestName,
        [string]$ExpectedPattern,
        [bool]$ShouldContain = $true
    )
    
    $output = flare_git
    
    if ($ShouldContain) {
        $success = $output -match $ExpectedPattern
    } else {
        $success = $output -notmatch $ExpectedPattern
    }
    
    Write-TestResult -TestName $TestName -Expected $ExpectedPattern -Actual $output -Success $success
    return $success
}

# Function to reset git state
function Reset-GitState {
    git reset --hard HEAD 2>$null | Out-Null
    git clean -fd 2>$null | Out-Null
    git checkout main 2>$null | Out-Null
    git branch -D feature-branch 2>$null | Out-Null
    git tag -d v1.0.0 2>$null | Out-Null
    git stash clear 2>$null | Out-Null
}

# Create a temporary directory for testing
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "flare-git-test-$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
Push-Location $TempDir

Write-Host "🧪 Testing Git Piece Functionality" -ForegroundColor Magenta
Write-Host "Test directory: $TempDir" -ForegroundColor Gray

$allTestsPassed = $true

try {
    # Test 1: Not in a git repository
    Write-Host "`n📁 Testing: Not in git repository" -ForegroundColor Blue
    $result = Test-GitPiece -TestName "No git repo" -ExpectedPattern "^$" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Initialize git repository
    git init --initial-branch=main | Out-Null
    git config user.name "Test User" | Out-Null
    git config user.email "test@example.com" | Out-Null

    # Test 2: Empty repository (no commits)
    Write-Host "`n📁 Testing: Empty repository" -ForegroundColor Blue
    $result = Test-GitPiece -TestName "Empty repo" -ExpectedPattern "main" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Create initial commit
    "Initial commit" | Out-File -FilePath "README.md" -Encoding UTF8
    git add README.md | Out-Null
    git commit -m "Initial commit" | Out-Null

    # Test 3: Clean repository
    Write-Host "`n📁 Testing: Clean repository" -ForegroundColor Blue
    $result = Test-GitPiece -TestName "Clean repo" -ExpectedPattern "^main$" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Test 4: Untracked files
    Write-Host "`n📁 Testing: Untracked files" -ForegroundColor Blue
    "Untracked content" | Out-File -FilePath "untracked.txt" -Encoding UTF8
    $result = Test-GitPiece -TestName "Untracked files" -ExpectedPattern "\?1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    Remove-Item "untracked.txt" -Force

    # Test 5: Staged files
    Write-Host "`n📁 Testing: Staged files" -ForegroundColor Blue
    "Staged content" | Out-File -FilePath "staged.txt" -Encoding UTF8
    git add staged.txt | Out-Null
    $result = Test-GitPiece -TestName "Staged files" -ExpectedPattern "\+1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    git reset --hard HEAD | Out-Null  # Reset everything
    git clean -fd | Out-Null  # Remove untracked files

    # Test 6: Modified files  
    Write-Host "`n📁 Testing: Modified files" -ForegroundColor Blue
    "Modified content" | Out-File -FilePath "README.md" -Encoding UTF8 -Append
    $result = Test-GitPiece -TestName "Modified files" -ExpectedPattern "main.*!1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    git checkout -- README.md | Out-Null

    # Test 7: Stash
    Write-Host "`n📁 Testing: Stash" -ForegroundColor Blue
    "Stash content" | Out-File -FilePath "stash.txt" -Encoding UTF8
    git add stash.txt | Out-Null
    git stash | Out-Null
    $result = Test-GitPiece -TestName "Stash" -ExpectedPattern "\*1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    git stash clear | Out-Null

    # Test 8: Branch creation
    Write-Host "`n📁 Testing: Branch creation" -ForegroundColor Blue
    git checkout -b feature-branch | Out-Null
    $result = Test-GitPiece -TestName "Feature branch" -ExpectedPattern "feature-branch" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    git checkout main | Out-Null

    # Test 9: Detached HEAD
    Write-Host "`n📁 Testing: Detached HEAD" -ForegroundColor Blue
    $commitHash = git log --format="%H" -1
    git checkout $commitHash 2>$null | Out-Null
    $result = Test-GitPiece -TestName "Detached HEAD" -ExpectedPattern "@" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    git checkout main | Out-Null

    # Test 10: Tag checkout
    Write-Host "`n📁 Testing: Tag checkout" -ForegroundColor Blue
    git tag v1.0.0 | Out-Null
    git checkout v1.0.0 2>$null | Out-Null
    $result = Test-GitPiece -TestName "Tag checkout" -ExpectedPattern "#v1\.0\.0" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    git checkout main | Out-Null

    # Test 11: Merge operation with conflict  
    Write-Host "`n📁 Testing: Merge operation" -ForegroundColor Blue
    git checkout feature-branch | Out-Null
    # Modify the same file differently to create conflict
    "Feature line" | Out-File -FilePath "README.md" -Encoding UTF8 -Append
    git add README.md | Out-Null
    git commit -m "Feature change to README" | Out-Null
    
    git checkout main | Out-Null  
    "Main line" | Out-File -FilePath "README.md" -Encoding UTF8 -Append
    git add README.md | Out-Null
    git commit -m "Main change to README" | Out-Null
    
    # Start merge (will conflict on README.md)
    git merge feature-branch --no-edit 2>$null | Out-Null
    $result = Test-GitPiece -TestName "Merge operation" -ExpectedPattern "merge" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    
    # Test 12: Unmerged files during merge
    Write-Host "`n📁 Testing: Unmerged files" -ForegroundColor Blue
    $result = Test-GitPiece -TestName "Unmerged files" -ExpectedPattern "~1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    
    # Abort merge to clean up
    git merge --abort | Out-Null

    # Test 13: Ahead commits (with upstream)
    Write-Host "`n📁 Testing: Ahead commits" -ForegroundColor Blue
    git checkout -b upstream-test | Out-Null
    "Upstream content" | Out-File -FilePath "upstream.txt" -Encoding UTF8
    git add upstream.txt | Out-Null
    git commit -m "Upstream commit" | Out-Null
    
    # Create a "remote" branch to track
    git checkout main | Out-Null
    git branch upstream-main upstream-test | Out-Null
    git checkout upstream-test | Out-Null
    git branch --set-upstream-to=upstream-main | Out-Null
    
    # Make commits ahead of upstream
    "Ahead content 1" | Out-File -FilePath "ahead1.txt" -Encoding UTF8
    git add ahead1.txt | Out-Null
    git commit -m "Ahead commit 1" | Out-Null
    
    $result = Test-GitPiece -TestName "Ahead commits" -ExpectedPattern "⇡1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Test 14: Behind commits
    Write-Host "`n📁 Testing: Behind commits" -ForegroundColor Blue
    git checkout upstream-main | Out-Null
    "Behind content" | Out-File -FilePath "behind.txt" -Encoding UTF8
    git add behind.txt | Out-Null
    git commit -m "Behind commit" | Out-Null
    
    git checkout upstream-test | Out-Null
    $result = Test-GitPiece -TestName "Behind commits" -ExpectedPattern "⇣1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Test 15: Both ahead and behind (diverged)
    Write-Host "`n📁 Testing: Both ahead and behind" -ForegroundColor Blue
    "Ahead content 2" | Out-File -FilePath "ahead2.txt" -Encoding UTF8
    git add ahead2.txt | Out-Null
    git commit -m "Ahead commit 2" | Out-Null
    
    $result = Test-GitPiece -TestName "Both ahead and behind" -ExpectedPattern "⇣1.*⇡2" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Clean up upstream test
    git checkout main | Out-Null
    git branch -D upstream-test upstream-main 2>$null | Out-Null

    # Test 16: Rebase conflict
    Write-Host "`n📁 Testing: Rebase conflict" -ForegroundColor Blue
    git checkout feature-branch | Out-Null
    git reset --hard HEAD~1 | Out-Null  # Reset to before merge conflict setup
    
    # Create rebase conflict scenario on the same file
    "Feature change to README" | Out-File -FilePath "README.md" -Encoding UTF8 -Append
    git add README.md | Out-Null
    git commit -m "Feature commit for rebase" | Out-Null
    
    git checkout main | Out-Null
    "Main change to README" | Out-File -FilePath "README.md" -Encoding UTF8 -Append
    git add README.md | Out-Null
    git commit -m "Main commit for rebase" | Out-Null
    
    git checkout feature-branch | Out-Null
    # Start rebase (will conflict on README.md)
    git rebase main 2>$null | Out-Null
    $result = Test-GitPiece -TestName "Rebase operation" -ExpectedPattern "rebase" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Test 17: Unmerged files during rebase
    Write-Host "`n📁 Testing: Rebase unmerged files" -ForegroundColor Blue
    $result = Test-GitPiece -TestName "Rebase unmerged files" -ExpectedPattern "~1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    
    # Clean up rebase
    git rebase --abort 2>$null | Out-Null
    git checkout main | Out-Null

    # Test 18: Complex diverged state with remote
    Write-Host "`n📁 Testing: Complex diverged state" -ForegroundColor Blue
    
    # Create a bare remote repo
    $remoteDir = Join-Path ([System.IO.Path]::GetTempPath()) "flare-git-remote-$(Get-Random)"
    git init --bare $remoteDir | Out-Null
    git remote add origin $remoteDir | Out-Null
    git push -u origin main 2>$null | Out-Null
    
    # Create local commits (ahead)
    "Local commit 1" | Out-File -FilePath "local1.txt" -Encoding UTF8
    git add local1.txt | Out-Null
    git commit -m "Local commit 1" | Out-Null
    
    "Local commit 2" | Out-File -FilePath "local2.txt" -Encoding UTF8
    git add local2.txt | Out-Null
    git commit -m "Local commit 2" | Out-Null
    
    # Simulate remote commits by creating them in a temp clone
    $cloneDir = Join-Path ([System.IO.Path]::GetTempPath()) "flare-git-clone-$(Get-Random)"
    git clone $remoteDir $cloneDir 2>$null | Out-Null
    Push-Location $cloneDir
    git config user.name "Remote User" | Out-Null
    git config user.email "remote@example.com" | Out-Null
    
    "Remote commit 1" | Out-File -FilePath "remote1.txt" -Encoding UTF8
    git add remote1.txt | Out-Null
    git commit -m "Remote commit 1" | Out-Null
    
    "Remote commit 2" | Out-File -FilePath "remote2.txt" -Encoding UTF8
    git add remote2.txt | Out-Null
    git commit -m "Remote commit 2" | Out-Null
    
    "Remote commit 3" | Out-File -FilePath "remote3.txt" -Encoding UTF8
    git add remote3.txt | Out-Null
    git commit -m "Remote commit 3" | Out-Null
    
    git push origin main 2>$null | Out-Null
    Pop-Location
    
    # Fetch remote changes to create diverged state
    git fetch origin 2>$null | Out-Null
    
    # Should be 2 ahead, 3 behind
    $result = Test-GitPiece -TestName "Complex diverged state" -ExpectedPattern "⇣3.*⇡2" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    
    # Clean up remote test
    Remove-Item -Path $remoteDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $cloneDir -Recurse -Force -ErrorAction SilentlyContinue
    git remote remove origin 2>$null | Out-Null

    # Test 19: Complex status combination
    Write-Host "`n📁 Testing: Complex status combination" -ForegroundColor Blue
    
    # Create stash
    "Stash content" | Out-File -FilePath "stash-file.txt" -Encoding UTF8
    git add stash-file.txt | Out-Null
    git stash | Out-Null
    
    # Create staged files
    "Staged content 1" | Out-File -FilePath "staged1.txt" -Encoding UTF8
    "Staged content 2" | Out-File -FilePath "staged2.txt" -Encoding UTF8
    git add staged1.txt staged2.txt | Out-Null
    
    # Create dirty files
    "Modified content" | Out-File -FilePath "README.md" -Encoding UTF8 -Append
    "Modified content" | Out-File -FilePath "local1.txt" -Encoding UTF8 -Append
    
    # Create untracked files
    "Untracked 1" | Out-File -FilePath "untracked1.txt" -Encoding UTF8
    "Untracked 2" | Out-File -FilePath "untracked2.txt" -Encoding UTF8
    "Untracked 3" | Out-File -FilePath "untracked3.txt" -Encoding UTF8
    
    # Should show stash, staged, dirty, and untracked
    $result = Test-GitPiece -TestName "Complex status combination" -ExpectedPattern "\*1.*\+2.*!2.*\?3" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    
    # Clean up
    git reset --hard HEAD | Out-Null
    git clean -fd | Out-Null
    git stash clear | Out-Null

    # Test 20: Cherry-pick operation
    Write-Host "`n📁 Testing: Cherry-pick operation" -ForegroundColor Blue
    
    # Create a commit on feature branch to cherry-pick
    git checkout feature-branch | Out-Null
    "Cherry pick content" | Out-File -FilePath "cherry.txt" -Encoding UTF8
    git add cherry.txt | Out-Null
    git commit -m "Commit to cherry-pick" | Out-Null
    $cherryCommit = git rev-parse HEAD
    
    git checkout main | Out-Null
    
    # Start cherry-pick that will conflict
    "Conflicting content" | Out-File -FilePath "cherry.txt" -Encoding UTF8
    git add cherry.txt | Out-Null
    git commit -m "Conflicting commit" | Out-Null
    
    # This should create a conflict
    git cherry-pick $cherryCommit 2>$null | Out-Null
    
    $result = Test-GitPiece -TestName "Cherry-pick operation" -ExpectedPattern "cherry-pick" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    
    # Clean up cherry-pick
    git cherry-pick --abort 2>$null | Out-Null

    # Test 21: Interactive rebase detection
    Write-Host "`n📁 Testing: Interactive rebase detection" -ForegroundColor Blue
    
    # Create some commits for interactive rebase
    "Commit 1 content" | Out-File -FilePath "commit1.txt" -Encoding UTF8
    git add commit1.txt | Out-Null
    git commit -m "Commit 1 for rebase" | Out-Null
    
    "Commit 2 content" | Out-File -FilePath "commit2.txt" -Encoding UTF8
    git add commit2.txt | Out-Null
    git commit -m "Commit 2 for rebase" | Out-Null
    
    # Create conflicting commit on main
    git checkout main | Out-Null
    "Conflicting main content" | Out-File -FilePath "commit1.txt" -Encoding UTF8
    git add commit1.txt | Out-Null
    git commit -m "Conflicting main commit" | Out-Null
    
    git checkout feature-branch | Out-Null
    
    # Start interactive rebase (will conflict)
    $env:GIT_SEQUENCE_EDITOR = "true"  # Auto-accept the todo list
    git rebase -i main 2>$null | Out-Null
    $env:GIT_SEQUENCE_EDITOR = $null
    
    $result = Test-GitPiece -TestName "Interactive rebase" -ExpectedPattern "rebase-i.*1/2" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    
    # Clean up rebase
    git rebase --abort 2>$null | Out-Null
    git checkout main | Out-Null

    # Test 22: Multiple unmerged files
    Write-Host "`n📁 Testing: Multiple unmerged files" -ForegroundColor Blue
    
    # Create multiple conflicting files
    git checkout feature-branch | Out-Null
    "Feature content 1" | Out-File -FilePath "conflict1.txt" -Encoding UTF8
    "Feature content 2" | Out-File -FilePath "conflict2.txt" -Encoding UTF8
    "Feature content 3" | Out-File -FilePath "conflict3.txt" -Encoding UTF8
    git add conflict1.txt conflict2.txt conflict3.txt | Out-Null
    git commit -m "Feature conflicts" | Out-Null
    
    git checkout main | Out-Null
    "Main content 1" | Out-File -FilePath "conflict1.txt" -Encoding UTF8
    "Main content 2" | Out-File -FilePath "conflict2.txt" -Encoding UTF8
    "Main content 3" | Out-File -FilePath "conflict3.txt" -Encoding UTF8
    git add conflict1.txt conflict2.txt conflict3.txt | Out-Null
    git commit -m "Main conflicts" | Out-Null
    
    # Start merge (will have multiple conflicts)
    git merge feature-branch --no-edit 2>$null | Out-Null
    
    $result = Test-GitPiece -TestName "Multiple unmerged files" -ExpectedPattern "merge.*~[1-9]" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result
    
    # Clean up merge
    git merge --abort | Out-Null

    # Summary
    Write-Host "`n📊 Test Summary" -ForegroundColor Magenta
    if ($allTestsPassed) {
        Write-Host "✅ All git piece tests passed!" -ForegroundColor Green
        $exitCode = 0
    } else {
        Write-Host "❌ Some git piece tests failed!" -ForegroundColor Red
        $exitCode = 1
    }

} finally {
    # Clean up
    Pop-Location
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "`n🧹 Cleaned up test directory" -ForegroundColor Gray
}

exit $exitCode
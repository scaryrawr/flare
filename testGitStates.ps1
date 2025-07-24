#!/usr/bin/env pwsh

# Test script for git piece functionality
# Tests all various git states and operations to ensure the git piece works correctly

param(
    [switch]$Verbose
)

# Import the flare module
$ModulePath = Join-Path $PSScriptRoot "flare.psm1"
Import-Module $ModulePath -Force

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
    
    if ($Verbose) {
        Write-Host "   Output: '$Actual'" -ForegroundColor Cyan
    }
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
    git init | Out-Null
    git config user.name "Test User" | Out-Null
    git config user.email "test@example.com" | Out-Null

    # Test 2: Empty repository (no commits)
    Write-Host "`n📁 Testing: Empty repository" -ForegroundColor Blue
    $result = Test-GitPiece -TestName "Empty repo" -ExpectedPattern "main|master" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Create initial commit
    "Initial commit" | Out-File -FilePath "README.md" -Encoding UTF8
    git add README.md | Out-Null
    git commit -m "Initial commit" | Out-Null

    # Test 3: Clean repository
    Write-Host "`n📁 Testing: Clean repository" -ForegroundColor Blue
    $result = Test-GitPiece -TestName "Clean repo" -ExpectedPattern "main|master" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Test 4: Untracked files
    Write-Host "`n📁 Testing: Untracked files" -ForegroundColor Blue
    "Untracked content" | Out-File -FilePath "untracked.txt" -Encoding UTF8
    $result = Test-GitPiece -TestName "Untracked files" -ExpectedPattern "\?1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Test 5: Staged files
    Write-Host "`n📁 Testing: Staged files" -ForegroundColor Blue
    git add untracked.txt | Out-Null
    $result = Test-GitPiece -TestName "Staged files" -ExpectedPattern "\+1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Commit the staged file
    git commit -m "Add untracked file" | Out-Null

    # Test 6: Modified files
    Write-Host "`n📁 Testing: Modified files" -ForegroundColor Blue
    "Modified content" | Out-File -FilePath "README.md" -Encoding UTF8 -Append
    $result = Test-GitPiece -TestName "Modified files" -ExpectedPattern "!1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Test 7: Mixed states (staged + modified + untracked)
    Write-Host "`n📁 Testing: Mixed states" -ForegroundColor Blue
    git add README.md | Out-Null  # Stage the modified file
    "Another untracked" | Out-File -FilePath "another.txt" -Encoding UTF8
    "More modifications" | Out-File -FilePath "README.md" -Encoding UTF8 -Append
    $result = Test-GitPiece -TestName "Mixed states" -ExpectedPattern "\+1.*!1.*\?1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Clean up for next tests
    git add . | Out-Null
    git commit -m "Mixed changes" | Out-Null

    # Test 8: Create and test stash
    Write-Host "`n📁 Testing: Stash" -ForegroundColor Blue
    "Stash content" | Out-File -FilePath "stash.txt" -Encoding UTF8
    git add stash.txt | Out-Null
    git stash | Out-Null
    $result = Test-GitPiece -TestName "Stash" -ExpectedPattern "\*1" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Test 9: Create branch and test branch switching
    Write-Host "`n📁 Testing: Branch creation" -ForegroundColor Blue
    git checkout -b feature-branch | Out-Null
    $result = Test-GitPiece -TestName "Feature branch" -ExpectedPattern "feature-branch" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Test 10: Ahead commits
    Write-Host "`n📁 Testing: Ahead commits" -ForegroundColor Blue
    "Feature content" | Out-File -FilePath "feature.txt" -Encoding UTF8
    git add feature.txt | Out-Null
    git commit -m "Add feature" | Out-Null
    # Note: ahead/behind only shows when there's an upstream, so this test may not show ahead status
    $result = Test-GitPiece -TestName "Ahead commits" -ExpectedPattern "feature-branch" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Test 11: Merge conflict setup
    Write-Host "`n📁 Testing: Merge conflict" -ForegroundColor Blue
    git checkout main | Out-Null
    "Main branch content" | Out-File -FilePath "conflict.txt" -Encoding UTF8
    git add conflict.txt | Out-Null
    git commit -m "Add conflict file on main" | Out-Null
    
    git checkout feature-branch | Out-Null
    "Feature branch content" | Out-File -FilePath "conflict.txt" -Encoding UTF8
    git add conflict.txt | Out-Null
    git commit -m "Add conflict file on feature" | Out-Null
    
    git checkout main | Out-Null
    # Attempt merge (this should create a conflict)
    git merge feature-branch --no-edit 2>$null | Out-Null
    $result = Test-GitPiece -TestName "Merge operation" -ExpectedPattern "merge" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Test 12: Unmerged files (conflict state)
    Write-Host "`n📁 Testing: Unmerged files" -ForegroundColor Blue
    $result = Test-GitPiece -TestName "Unmerged files" -ExpectedPattern "~" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Resolve conflict
    git merge --abort | Out-Null

    # Test 13: Cherry-pick operation
    Write-Host "`n📁 Testing: Cherry-pick operation" -ForegroundColor Blue
    $featureCommit = git log --oneline feature-branch -1 --format="%H"
    git cherry-pick $featureCommit --no-commit 2>$null | Out-Null
    $result = Test-GitPiece -TestName "Cherry-pick operation" -ExpectedPattern "cherry-pick" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Reset cherry-pick
    git cherry-pick --abort 2>$null | Out-Null

    # Test 14: Detached HEAD state
    Write-Host "`n📁 Testing: Detached HEAD" -ForegroundColor Blue
    $commitHash = git log --format="%H" -1
    git checkout $commitHash | Out-Null
    $result = Test-GitPiece -TestName "Detached HEAD" -ExpectedPattern "@" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Return to main branch
    git checkout main | Out-Null

    # Test 15: Create and test tag
    Write-Host "`n📁 Testing: Tag on HEAD" -ForegroundColor Blue
    git tag v1.0.0 | Out-Null
    git checkout v1.0.0 | Out-Null
    $result = Test-GitPiece -TestName "Tag checkout" -ExpectedPattern "#v1\.0\.0" -ShouldContain $true
    $allTestsPassed = $allTestsPassed -and $result

    # Return to main branch
    git checkout main | Out-Null

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
#!/usr/bin/env pwsh

# Test script for git piece functionality
# Tests all various git states and operations to ensure the git piece works correctly

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
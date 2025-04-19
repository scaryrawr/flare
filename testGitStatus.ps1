# Test script to compare Get-GitStatusRaw and Get-GitStatus
# This performs various git operations and ensures both functions return consistent results

# Import the module
Import-Module -Name $PSScriptRoot/flare.psm1 -Force

# Get the absolute path to the test directory
# Use /tmp on macOS or $env:TEMP on Windows
$tempDir = if ($IsMacOS -or $IsLinux) { "/tmp" } else { $env:TEMP }
$testRootDir = Join-Path $tempDir "flare_git_test_$(Get-Random)"
$repoDir = Join-Path $testRootDir "test_repo"
$remoteDir = Join-Path $testRootDir "remote.git"

# Function to run tests and compare results
function Test-GitStatus {
  param(
    [string]$Action
  )

  Write-Host "Testing after action: $Action" -ForegroundColor Cyan
    
  # Temporarily change directory
  Push-Location $repoDir
    
  try {
    # Get results from both functions
    $rawStatus = Get-GitStatusRaw
    $cachedStatus = Get-GitStatus
        
    # Compare results
    if ($rawStatus -ne $cachedStatus) {
      Write-Host "ERROR: Status mismatch after '$Action'" -ForegroundColor Red
      Write-Host "Raw status   : '$rawStatus'" -ForegroundColor Yellow
      Write-Host "Cached status: '$cachedStatus'" -ForegroundColor Yellow
      throw "Test failed: Status mismatch after '$Action'"
    }
    else {
      Write-Host "✅ Status match: '$rawStatus'" -ForegroundColor Green
    }
  }
  catch {
    Write-Error "Test failed during '$Action': $_"
    throw
  }
  finally {
    # Restore original directory
    Pop-Location
  }
}

try {
  # Create test directories
  Write-Host "Creating test directories..." -ForegroundColor Blue
  New-Item -ItemType Directory -Path $repoDir -Force | Out-Null
  New-Item -ItemType Directory -Path $remoteDir -Force | Out-Null

  # Initialize bare remote repository
  Write-Host "Setting up remote repository..." -ForegroundColor Blue
  Push-Location $remoteDir
  git init --bare
  Pop-Location

  # Initialize local repository
  Write-Host "Setting up local repository..." -ForegroundColor Blue
  Push-Location $repoDir
  git init
  git config user.name "Test User"
  git config user.email "test@example.com"
    
  # Add remote
  git remote add origin $remoteDir
  Pop-Location

  # TEST: Initial status (empty repo)
  Test-GitStatus -Action "Initial repo creation"

  # TEST: Add a file
  Write-Host "Adding a file..." -ForegroundColor Blue
  Set-Content -Path "$repoDir/test.txt" -Value "Initial content"
  Test-GitStatus -Action "File created but not staged"

  # TEST: Stage the file
  Write-Host "Staging file..." -ForegroundColor Blue
  Push-Location $repoDir
  git add test.txt
  Pop-Location
  Test-GitStatus -Action "File staged"

  # TEST: Commit the file
  Write-Host "Committing file..." -ForegroundColor Blue
  Push-Location $repoDir
  git commit -m "Initial commit"
  Pop-Location
  Test-GitStatus -Action "After commit"

  # TEST: First push (ahead)
  Write-Host "Pushing commits..." -ForegroundColor Blue
  Push-Location $repoDir
  # Get the current branch name (could be main or master depending on git version)
  $currentBranch = git rev-parse --abbrev-ref HEAD
  git push -u origin $currentBranch
  Pop-Location
  Test-GitStatus -Action "After first push"

  # TEST: Modify file
  Write-Host "Modifying file..." -ForegroundColor Blue
  Set-Content -Path "$repoDir/test.txt" -Value "Modified content"
  Test-GitStatus -Action "File modified but not staged"

  # TEST: Stage modified file
  Write-Host "Staging modified file..." -ForegroundColor Blue
  Push-Location $repoDir
  git add test.txt
  Pop-Location
  Test-GitStatus -Action "Modified file staged"

  # TEST: Add new file (to test untracked files)
  Write-Host "Creating untracked file..." -ForegroundColor Blue
  Set-Content -Path "$repoDir/untracked.txt" -Value "Untracked content"
  Test-GitStatus -Action "With untracked file"

  # TEST: Commit only the modified file
  Write-Host "Committing modified file..." -ForegroundColor Blue
  Push-Location $repoDir
  git commit -m "Update test.txt"
  Pop-Location
  Test-GitStatus -Action "After partial commit"

  # TEST: Create a second commit for the untracked file
  Write-Host "Staging and committing previously untracked file..." -ForegroundColor Blue
  Push-Location $repoDir
  git add untracked.txt
  git commit -m "Add untracked.txt"
  Pop-Location
  Test-GitStatus -Action "After second commit"

  # TEST: Push multiple commits
  Write-Host "Pushing multiple commits..." -ForegroundColor Blue
  Push-Location $repoDir
  git push
  Pop-Location
  Test-GitStatus -Action "After pushing multiple commits"

  # TEST: Create divergent history (for behind state)
  Write-Host "Creating divergent history..." -ForegroundColor Blue
    
  # Create a commit directly on the remote to simulate someone else's push
  $tempCloneDir = Join-Path $testRootDir "temp_clone"
  New-Item -ItemType Directory -Path $tempCloneDir -Force | Out-Null
    
  Push-Location $tempCloneDir
  git clone $remoteDir .
  git config user.name "Other User"
  git config user.email "other@example.com"
  Set-Content -Path "remote_change.txt" -Value "Change from remote"
  git add remote_change.txt
  git commit -m "Remote change"
  git push
  Pop-Location
    
  # TEST: Check status before pulling (should be behind)
  Test-GitStatus -Action "With remote ahead (before pull)"

  # TEST: Pull the changes
  Write-Host "Pulling changes..." -ForegroundColor Blue
  Push-Location $repoDir
  git pull
  Pop-Location
  Test-GitStatus -Action "After pull"

  # TEST: Create a merge conflict
  Write-Host "Creating merge conflict..." -ForegroundColor Blue
    
  # Create conflicting changes in both repositories
  Set-Content -Path "$repoDir/conflict.txt" -Value "Local content"
  Push-Location $repoDir
  git add conflict.txt
  git commit -m "Local change for conflict"
  Pop-Location

  # Make conflicting change in temp clone
  Push-Location $tempCloneDir
  Set-Content -Path "conflict.txt" -Value "Remote content"
  git add conflict.txt
  git commit -m "Remote change for conflict"
  git push
  Pop-Location

  # Try to push from local which should fail
  Push-Location $repoDir
  git push 2>&1 | Out-Null
  Test-GitStatus -Action "With push rejected"
    
  # Pull which will create a merge conflict
  git pull 2>&1 | Out-Null
  Pop-Location
  Test-GitStatus -Action "With merge conflict"

  # TEST: Resolve the conflict
  Write-Host "Resolving merge conflict..." -ForegroundColor Blue
  Set-Content -Path "$repoDir/conflict.txt" -Value "Resolved content"
  Push-Location $repoDir
  git add conflict.txt
  git commit -m "Resolve conflict"
  Pop-Location
  Test-GitStatus -Action "After conflict resolution"

  # TEST: Rename a file
  Write-Host "Renaming a file..." -ForegroundColor Blue
  Push-Location $repoDir
  git mv test.txt renamed.txt
  Pop-Location
  Test-GitStatus -Action "After file rename"

  # TEST: Delete a file
  Write-Host "Deleting a file..." -ForegroundColor Blue
  Push-Location $repoDir
  git rm untracked.txt
  Pop-Location
  Test-GitStatus -Action "After file deletion"

  # TEST: Final commit and push
  Write-Host "Final commit and push..." -ForegroundColor Blue
  Push-Location $repoDir
  git commit -m "Rename and delete files"
  git push
  Pop-Location
  Test-GitStatus -Action "After final push"

  Write-Host "All tests passed successfully!" -ForegroundColor Green
}
catch {
  Write-Error "Test failure: $_"
}
finally {
  # Clean up test directories
  if (Test-Path $testRootDir) {
    Write-Host "Cleaning up test directories..." -ForegroundColor Blue
    Remove-Item -Path $testRootDir -Recurse -Force
  }
}

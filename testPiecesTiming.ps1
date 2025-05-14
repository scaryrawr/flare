# Measure the execution time of individual prompt pieces in a controlled test environment

# Allow command-line parameter to override number of iterations
param(
    [int]$Iterations = 100
)

# Set up a temporary test environment
function New-TestEnvironment {
    Write-Host 'Creating temporary test environment...' -ForegroundColor Cyan
    
    # Create a temporary directory
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "flare_test_$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    # Initialize git repo in temp directory
    Push-Location $tempDir
    git init --quiet
    git config --local user.name 'Flare Test'
    git config --local user.email 'test@example.com'
    
    # Create initial commit to have a valid git repo
    '# Flare Test Repo' | Out-File -FilePath 'README.md' -Encoding utf8
    git add README.md
    git commit -m 'Initial commit' --quiet
    
    # Create package.json for node.ps1 piece
    @'
{
  "name": "flare-test",
  "version": "1.0.0",
  "description": "Test file to trigger node.ps1 piece",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "author": "",
  "license": "MIT"
}
'@ | Out-File -FilePath 'package.json' -Encoding utf8

    # Create go.mod for go.ps1 piece
    @'
module flare-test

go 1.22
'@ | Out-File -FilePath 'go.mod' -Encoding utf8
    
    # Create Cargo.toml for rust.ps1 piece
    @'
[package]
name = "flare-test"
version = "0.1.0"
edition = "2021"
description = "Test file to trigger rust.ps1 piece"
license = "MIT"

[dependencies]
'@ | Out-File -FilePath 'Cargo.toml' -Encoding utf8
    
    # Create build.zig for zig.ps1 piece
    @'
const std = @import("std");

// Simple build.zig file to trigger the zig.ps1 piece
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "flare-test", 
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);
}
'@ | Out-File -FilePath 'build.zig' -Encoding utf8
    
    # Add files to git to ensure git status shows something
    git add package.json Cargo.toml build.zig
    git commit -m 'Add project files' --quiet
    
    # Make a change to trigger git status
    '# Modified' | Add-Content -Path 'README.md' -Encoding utf8
    
    Pop-Location
    
    Write-Host "✅ Temporary test environment created at $tempDir" -ForegroundColor Green
    return $tempDir
}

# Clean up the test environment
function Remove-TestEnvironment {
    param(
        [string]$TempDir
    )
    
    Write-Host 'Cleaning up temporary test environment...' -ForegroundColor Cyan
    
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        if ($?) {
            Write-Host '✅ Temporary test environment removed' -ForegroundColor Green
        }
    }
}

# Import the module to access all pieces
try {
    Import-Module "$PSScriptRoot/flare.psm1" -Force -ErrorAction Stop
    Write-Host '✅ Flare module loaded successfully' -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to load the Flare module: $_" -ForegroundColor Red
    exit 1
}

Write-Host 'Testing individual pieces performance in controlled environment...'
Write-Host "Running $Iterations iterations per piece..."
Write-Host ''

# Create temporary test environment
$originalLocation = Get-Location
$tempTestDir = New-TestEnvironment

# Call debugPieceTiming.ps1 with our test environment
Write-Host 'Calling debugPieceTiming.ps1 in test environment...' -ForegroundColor Cyan
$anyFailures = $false
try {
    # Run the debug script
    & "$PSScriptRoot/debugPieceTiming.ps1" -Iterations $Iterations -WorkingDirectory $tempTestDir -NoRestore
    # PowerShell's $LASTEXITCODE will contain the exit code from the script
    if ($LASTEXITCODE -ne 0) {
        $anyFailures = $true
    }
}
catch {
    Write-Host "❌ Error running debugPieceTiming.ps1: $_" -ForegroundColor Red
    $anyFailures = $true
}

# Return to original location and clean up
Set-Location $originalLocation
Remove-TestEnvironment -TempDir $tempTestDir

# Provide final summary and exit with appropriate code
Write-Host ''
if ($anyFailures) {
    Write-Host '❌ TEST FAILED: One or more pieces or the full prompt failed to load or execute correctly' -ForegroundColor Red
    exit 1
}
else {
    Write-Host '✅ TEST PASSED: All pieces and the full prompt loaded and executed successfully' -ForegroundColor Green
    exit 0
}

# Return to original location and clean up
Set-Location $originalLocation
Remove-TestEnvironment -TempDir $tempTestDir

# Provide final summary and exit with appropriate code
Write-Host ''
if ($anyFailures) {
    Write-Host '❌ TEST FAILED: One or more pieces or the full prompt failed to load or execute correctly' -ForegroundColor Red
    exit 1
}
else {
    Write-Host '✅ TEST PASSED: All pieces and the full prompt loaded and executed successfully' -ForegroundColor Green
    exit 0
}

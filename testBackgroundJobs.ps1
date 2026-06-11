#!/usr/bin/env pwsh

# Validate that the idle redraw handler only processes terminal background jobs.
# Treating queued jobs as completed can block keyboard input when Wait-Job runs.

$module = Import-Module "$PSScriptRoot/flare.psm1" -Force -PassThru -ErrorAction Stop

$testCases = @(
    @{ State = 'Completed'; Expected = $true },
    @{ State = 'Failed'; Expected = $true },
    @{ State = 'Stopped'; Expected = $true },
    @{ State = 'NotStarted'; Expected = $false },
    @{ State = 'Running'; Expected = $false },
    @{ State = 'Blocked'; Expected = $false },
    @{ State = 'Suspended'; Expected = $false },
    @{ State = 'Disconnected'; Expected = $false },
    @{ State = 'Suspending'; Expected = $false },
    @{ State = 'Stopping'; Expected = $false },
    @{ State = 'AtBreakpoint'; Expected = $false }
)

$allTestsPassed = $true

foreach ($testCase in $testCases) {
    $actual = & $module {
        param($state)

        $jobState = [System.Management.Automation.JobState]::$state
        Test-FlareBackgroundJobTerminalState ([pscustomobject]@{ State = $jobState })
    } $testCase.State

    if ($actual -eq $testCase.Expected) {
        Write-Host "PASS Background job state '$($testCase.State)' classified correctly"
    }
    else {
        Write-Host "FAIL Background job state '$($testCase.State)' expected '$($testCase.Expected)' but got '$actual'" -ForegroundColor Red
        $allTestsPassed = $false
    }
}

$originalLocation = Get-Location
$originalLeftPieces = @($global:flare_leftPieces)
$originalRightPieces = @($global:flare_rightPieces)
$originalPath = $env:PATH
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "flare-git-cache-test-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    Push-Location $tempDir
    git init --quiet
    git config user.name 'Flare Test'
    git config user.email 'test@example.com'
    git checkout -b main 2>$null | Out-Null
    'Initial commit' | Out-File -FilePath 'README.md' -Encoding utf8
    git add README.md
    git commit -m 'Initial commit' --quiet

    $env:PATH = ''

    & $module {
        $global:flare_leftPieces = @('git')
        $global:flare_rightPieces = @()
        $global:flare_resultCache.Clear()
        $global:flare_lastRenderCache.Clear()
        $global:flare_fastRefreshTimestamps.Clear()
    }

    $cleanGitStatus = & $module {
        Update-MainThreadPieces
        $global:flare_resultCache['git']
    }

    'Untracked content' | Out-File -FilePath 'untracked.txt' -Encoding utf8

    $untrackedGitStatus = & $module {
        Update-MainThreadPieces
        $global:flare_resultCache['git']
    }

    if ($cleanGitStatus -match '\?1') {
        Write-Host "FAIL Clean git prompt unexpectedly reported untracked files: '$cleanGitStatus'" -ForegroundColor Red
        $allTestsPassed = $false
    }
    elseif ($untrackedGitStatus -match '\?1') {
        Write-Host 'PASS Git prompt cache refreshes untracked files immediately'
    }
    else {
        Write-Host "FAIL Git prompt cache did not report untracked files. Actual: '$untrackedGitStatus'" -ForegroundColor Red
        $allTestsPassed = $false
    }
}
finally {
    Set-Location $originalLocation
    $env:PATH = $originalPath
    $global:flare_leftPieces = $originalLeftPieces
    $global:flare_rightPieces = $originalRightPieces
    $global:flare_resultCache.Clear()
    $global:flare_lastRenderCache.Clear()
    $global:flare_fastRefreshTimestamps.Clear()
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $allTestsPassed) {
    exit 1
}

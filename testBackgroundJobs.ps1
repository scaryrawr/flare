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

    $untrackedRefreshTiming = [System.Diagnostics.Stopwatch]::StartNew()
    $untrackedGitStatus = & $module {
        Update-MainThreadPieces
        $global:flare_resultCache['git']
    }
    $untrackedRefreshTiming.Stop()

    if ($cleanGitStatus -match '\?1') {
        Write-Host "FAIL Clean git prompt unexpectedly reported untracked files: '$cleanGitStatus'" -ForegroundColor Red
        $allTestsPassed = $false
    }
    elseif ($untrackedGitStatus -match '\?') {
        Write-Host "FAIL Git fast prompt synchronously scanned untracked files: '$untrackedGitStatus'" -ForegroundColor Red
        $allTestsPassed = $false
    }
    elseif ($untrackedRefreshTiming.Elapsed.TotalMilliseconds -gt 250) {
        Write-Host "FAIL Git fast prompt took $([math]::Round($untrackedRefreshTiming.Elapsed.TotalMilliseconds, 2)) ms after adding untracked files" -ForegroundColor Red
        $allTestsPassed = $false
    }
    else {
        Write-Host 'PASS Git fast prompt avoids synchronous untracked scans'
    }

    $preservedGitStatus = & $module {
        $global:flare_resultCache['git'] = 'main ?1'
        Update-MainThreadPieces
        $global:flare_resultCache['git']
    }

    if ($preservedGitStatus -eq 'main ?1') {
        Write-Host 'PASS Git fast prompt preserves completed background status'
    }
    else {
        Write-Host "FAIL Git fast prompt dropped cached background status. Actual: '$preservedGitStatus'" -ForegroundColor Red
        $allTestsPassed = $false
    }

    $appliedStatusFromLastPromptDirectory = & $module {
        param($promptDirectory, $eventDirectory)

        $global:flare_resultCache.Clear()
        $global:flare_lastRenderCache.Clear()
        $global:flare_fastRefreshTimestamps.Clear()
        $global:flare_backgroundJobs = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        $global:flare_resultCache['git'] = 'main'
        $global:flare_lastDirectory = [pscustomobject]@{ Path = $promptDirectory }

        $timestamp = Get-Date
        $global:flare_resultCache["_package_$timestamp"] = @{
            Timestamp        = $timestamp
            WorkingDirectory = $promptDirectory
            Results          = @{ git = 'main ?1' }
        }

        $job = Start-ThreadJob -ScriptBlock { }
        Wait-Job -Job $job | Out-Null
        $job | Add-Member -NotePropertyName Timestamp -NotePropertyValue $timestamp
        $job | Add-Member -NotePropertyName WorkingDirectory -NotePropertyValue $promptDirectory
        $global:flare_backgroundJobs.Add($job)

        Push-Location $eventDirectory
        try {
            Invoke-FlareBackgroundJobUpdates
        }
        finally {
            Pop-Location
        }

        $global:flare_resultCache['git']
    } $tempDir ([System.IO.Path]::GetTempPath())

    if ($appliedStatusFromLastPromptDirectory -eq 'main ?1') {
        Write-Host 'PASS Background git status applies for the last prompt directory'
    }
    else {
        Write-Host "FAIL Background git status used the event location instead of the prompt directory. Actual: '$appliedStatusFromLastPromptDirectory'" -ForegroundColor Red
        $allTestsPassed = $false
    }
}
finally {
    Pop-Location -ErrorAction SilentlyContinue
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

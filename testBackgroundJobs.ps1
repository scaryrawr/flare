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

if (-not $allTestsPassed) {
    exit 1
}

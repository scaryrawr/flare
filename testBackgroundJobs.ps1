#!/usr/bin/env pwsh

if ($env:FLARE_BACKGROUND_TEST_CHILD -ne '1') {
    $previousChildMarker = $env:FLARE_BACKGROUND_TEST_CHILD
    $env:FLARE_BACKGROUND_TEST_CHILD = '1'
    try {
        & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File $PSCommandPath
        $childExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $previousChildMarker) {
            Remove-Item Env:FLARE_BACKGROUND_TEST_CHILD -ErrorAction SilentlyContinue
        }
        else {
            $env:FLARE_BACKGROUND_TEST_CHILD = $previousChildMarker
        }
    }

    if ($childExitCode -ne 0) {
        exit $childExitCode
    }
    return
}

$module = Import-Module "$PSScriptRoot/flare.psm1" -Force -PassThru -ErrorAction Stop
$allTestsPassed = $true

function Test-FlareCondition {
    param(
        [bool]$Condition,
        [string]$SuccessMessage,
        [string]$FailureMessage
    )

    if ($Condition) {
        Write-Host "PASS $SuccessMessage"
    }
    else {
        Write-Host "FAIL $FailureMessage" -ForegroundColor Red
        $script:allTestsPassed = $false
    }
}

function Receive-FlareResultsUntil {
    param(
        [System.Management.Automation.PSModuleInfo]$Module,
        [long]$RequestId,
        [int]$TimeoutMilliseconds = 5000
    )

    $received = @()
    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    do {
        Start-Sleep -Milliseconds 25
        $received += @(& $Module { Receive-FlareRefreshResult })
    } until (
        ($received | Where-Object RequestId -eq $RequestId) -or
        (Get-Date) -gt $deadline
    )

    return $received
}

$originalLeftPieces = @($global:flare_leftPieces)
$originalRightPieces = @($global:flare_rightPieces)
$originalPath = $env:PATH
$originalLocation = Get-Location
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "flare-refresh-worker-test-$(Get-Random)"
$workerRoot = Join-Path $tempRoot 'worker'
$firstDirectory = Join-Path $tempRoot 'first'
$secondDirectory = Join-Path $tempRoot 'second'

try {
    New-Item -ItemType Directory -Path (Join-Path $workerRoot 'utils'), (Join-Path $workerRoot 'pieces'), $firstDirectory, $secondDirectory -Force | Out-Null
    Copy-Item "$PSScriptRoot/utils/invokeUtils.ps1" (Join-Path $workerRoot 'utils/invokeUtils.ps1')

    @'
function flare_slow {
    $value = [System.IO.File]::ReadAllText((Join-Path $PWD 'value.txt')).Trim()
    [System.IO.File]::WriteAllText((Join-Path $PWD 'started.txt'), $value)
    $delay = [int][System.IO.File]::ReadAllText((Join-Path $PWD 'delay.txt')).Trim()
    if ($delay -gt 0) {
        Start-Sleep -Milliseconds $delay
    }
    return $value
}
'@ | Set-Content -Path (Join-Path $workerRoot 'pieces/slow.ps1') -Encoding utf8

    'first' | Set-Content -Path (Join-Path $firstDirectory 'value.txt') -Encoding utf8
    '400' | Set-Content -Path (Join-Path $firstDirectory 'delay.txt') -Encoding utf8
    'second' | Set-Content -Path (Join-Path $secondDirectory 'value.txt') -Encoding utf8
    '0' | Set-Content -Path (Join-Path $secondDirectory 'delay.txt') -Encoding utf8

    $enterBinding = Get-PSReadLineKeyHandler -Chord Enter
    Test-FlareCondition `
        -Condition ($enterBinding.Function -ne 'Clear prompt and rewrite input on Enter') `
        -SuccessMessage 'Legacy Flare Enter handler is not active' `
        -FailureMessage 'Legacy Flare Enter handler remained active'

    & $module {
        $script:flare_refreshResults = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $script:flare_latestRefreshRequestId = 50
        $script:flare_refreshResults.Enqueue([pscustomobject]@{
                RequestId        = 50
                WorkingDirectory = $PWD.Path
                Pieces           = @('live')
                Results          = @{ live = 'updated' }
                Succeeded        = $true
                Error            = $null
            })
    }
    $null = New-Event -SourceIdentifier PowerShell.OnIdle
    $idleDeadline = (Get-Date).AddSeconds(3)
    while ($global:flare_resultCache['live'] -ne 'updated' -and (Get-Date) -lt $idleDeadline) {
        Start-Sleep -Milliseconds 25
    }
    $idleEventErrors = & $module { @($script:flare_idleEventJob.Error).Count }
    Test-FlareCondition `
        -Condition ($global:flare_resultCache['live'] -eq 'updated' -and $idleEventErrors -eq 0) `
        -SuccessMessage 'Idle event applies completed refresh results through the module callback' `
        -FailureMessage "Idle event left '$($global:flare_resultCache['live'])' with $idleEventErrors errors"
    Get-Event | Remove-Event -ErrorAction SilentlyContinue
    $global:flare_resultCache.Remove('live')

    # Drive result application directly so OnIdle cannot race these assertions.
    & $module {
        if ($script:flare_idleSubscriptionId) {
            Unregister-Event -SubscriptionId $script:flare_idleSubscriptionId -ErrorAction SilentlyContinue
            $script:flare_idleSubscriptionId = $null
        }
        if ($script:flare_idleEventJob) {
            Remove-Job -Job $script:flare_idleEventJob -Force -ErrorAction SilentlyContinue
            $script:flare_idleEventJob = $null
        }
    }

    $firstRequestId = & $module {
        param($root, $directory)
        Send-FlareRefreshRequest -WorkingDirectory $directory -Pieces @('slow') -ModuleRoot $root
    } $workerRoot $firstDirectory

    $workerIdentity = & $module {
        [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($script:flare_refreshWorker.PowerShell)
    }

    $startDeadline = (Get-Date).AddSeconds(2)
    while (-not (Test-Path (Join-Path $firstDirectory 'started.txt')) -and (Get-Date) -lt $startDeadline) {
        Start-Sleep -Milliseconds 20
    }

    Test-FlareCondition `
        -Condition (Test-Path (Join-Path $firstDirectory 'started.txt')) `
        -SuccessMessage 'Durable worker started the first refresh' `
        -FailureMessage 'Durable worker did not start the first refresh'

    'latest' | Set-Content -Path (Join-Path $firstDirectory 'value.txt') -Encoding utf8
    $submissionTiming = [System.Diagnostics.Stopwatch]::StartNew()
    $discardedRequestId = & $module {
        param($root, $directory)
        Send-FlareRefreshRequest -WorkingDirectory $directory -Pieces @('slow') -ModuleRoot $root
    } $workerRoot $firstDirectory
    $latestRequestId = & $module {
        param($root, $directory)
        Send-FlareRefreshRequest -WorkingDirectory $directory -Pieces @('slow') -ModuleRoot $root
    } $workerRoot $firstDirectory
    $submissionTiming.Stop()

    $workerIdentityAfterRequests = & $module {
        [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($script:flare_refreshWorker.PowerShell)
    }
    $coalescedResults = @(Receive-FlareResultsUntil -Module $module -RequestId $latestRequestId)
    $coalescedIds = @($coalescedResults | ForEach-Object RequestId)

    Test-FlareCondition `
        -Condition ($submissionTiming.Elapsed.TotalMilliseconds -lt 250) `
        -SuccessMessage 'New refresh requests remain non-blocking while slow work is active' `
        -FailureMessage "Submitting refresh requests took $([math]::Round($submissionTiming.Elapsed.TotalMilliseconds, 2)) ms"
    Test-FlareCondition `
        -Condition ($workerIdentity -eq $workerIdentityAfterRequests) `
        -SuccessMessage 'Refresh requests reuse one durable worker' `
        -FailureMessage 'Refresh requests replaced the worker unexpectedly'
    Test-FlareCondition `
        -Condition (($firstRequestId -in $coalescedIds) -and ($latestRequestId -in $coalescedIds) -and ($discardedRequestId -notin $coalescedIds)) `
        -SuccessMessage 'Busy worker retains only the newest pending refresh' `
        -FailureMessage "Expected request IDs $firstRequestId and $latestRequestId but received $($coalescedIds -join ', ')"

    $failedRequestId = & $module {
        param($root, $directory)
        Send-FlareRefreshRequest -WorkingDirectory $directory -Pieces @('slow') -ModuleRoot $root
    } $workerRoot (Join-Path $tempRoot 'missing')
    $failedResults = @(Receive-FlareResultsUntil -Module $module -RequestId $failedRequestId)
    $failedResult = $failedResults | Where-Object RequestId -eq $failedRequestId | Select-Object -Last 1

    $recoveryRequestId = & $module {
        param($root, $directory)
        Send-FlareRefreshRequest -WorkingDirectory $directory -Pieces @('slow') -ModuleRoot $root
    } $workerRoot $secondDirectory
    $recoveryResults = @(Receive-FlareResultsUntil -Module $module -RequestId $recoveryRequestId)
    $recoveryResult = $recoveryResults | Where-Object RequestId -eq $recoveryRequestId | Select-Object -Last 1
    $workerIdentityAfterFailure = & $module {
        [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($script:flare_refreshWorker.PowerShell)
    }

    Test-FlareCondition `
        -Condition ($failedResult -and -not $failedResult.Succeeded -and $failedResult.Error) `
        -SuccessMessage 'Refresh failures return explicit error results' `
        -FailureMessage 'Refresh failure did not return an error result'
    Test-FlareCondition `
        -Condition ($recoveryResult.Succeeded -and $recoveryResult.Results['slow'] -eq 'second' -and $workerIdentityAfterFailure -eq $workerIdentity) `
        -SuccessMessage 'Worker continues after a failed refresh' `
        -FailureMessage 'Worker did not recover after a failed refresh'

    & $module {
        Stop-FlareRefreshWorker
        $global:flare_resultCache.Clear()
        $script:flare_refreshResults = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $script:flare_latestRefreshRequestId = 100
    }

    $staleChanged = & $module {
        $script:flare_refreshResults.Enqueue([pscustomobject]@{
                RequestId        = 99
                WorkingDirectory = $PWD.Path
                Pieces           = @('sample')
                Results          = @{ sample = 'stale' }
                Succeeded        = $true
                Error            = $null
            })
        Update-FlareBackgroundResults -DisableRedraw
    }

    $wrongDirectoryChanged = & $module {
        param($directory)
        $script:flare_refreshResults.Enqueue([pscustomobject]@{
                RequestId        = 100
                WorkingDirectory = $directory
                Pieces           = @('sample')
                Results          = @{ sample = 'wrong directory' }
                Succeeded        = $true
                Error            = $null
            })
        Update-FlareBackgroundResults -DisableRedraw
    } $secondDirectory

    Test-FlareCondition `
        -Condition (-not $staleChanged -and -not $wrongDirectoryChanged -and -not $global:flare_resultCache.ContainsKey('sample')) `
        -SuccessMessage 'Obsolete and wrong-directory results are rejected' `
        -FailureMessage 'An obsolete or wrong-directory result changed the cache'

    $acceptedChanged = & $module {
        $script:flare_refreshResults.Enqueue([pscustomobject]@{
                RequestId        = 100
                WorkingDirectory = $PWD.Path
                Pieces           = @('sample')
                Results          = @{ sample = 'accepted' }
                Succeeded        = $true
                Error            = $null
            })
        Update-FlareBackgroundResults -DisableRedraw
    }
    $unchangedResult = & $module {
        $script:flare_refreshResults.Enqueue([pscustomobject]@{
                RequestId        = 100
                WorkingDirectory = $PWD.Path
                Pieces           = @('sample')
                Results          = @{ sample = 'accepted' }
                Succeeded        = $true
                Error            = $null
            })
        Update-FlareBackgroundResults -DisableRedraw
    }
    $removedResult = & $module {
        $script:flare_refreshResults.Enqueue([pscustomobject]@{
                RequestId        = 100
                WorkingDirectory = $PWD.Path
                Pieces           = @('sample')
                Results          = @{ sample = '' }
                Succeeded        = $true
                Error            = $null
            })
        Update-FlareBackgroundResults -DisableRedraw
    }

    Test-FlareCondition `
        -Condition ($acceptedChanged -and -not $unchangedResult -and $removedResult -and -not $global:flare_resultCache.ContainsKey('sample')) `
        -SuccessMessage 'Accepted results redraw only on visible changes and remove empty pieces' `
        -FailureMessage 'Accepted result change detection or empty-piece removal was incorrect'

    $gitDirectory = Join-Path $tempRoot 'git'
    New-Item -ItemType Directory -Path $gitDirectory -Force | Out-Null
    Push-Location $gitDirectory
    git init --quiet
    git config user.name 'Flare Test'
    git config user.email 'test@example.com'
    git checkout -b main 2>$null | Out-Null
    'Initial commit' | Set-Content -Path 'README.md' -Encoding utf8
    git add README.md
    git commit -m 'Initial commit' --quiet

    $env:PATH = ''
    & $module {
        $global:flare_leftPieces = @('git')
        $global:flare_rightPieces = @()
        $global:flare_resultCache.Clear()
    }

    $cleanGitStatus = & $module {
        Update-MainThreadPieces
        $global:flare_resultCache['git']
    }
    'Untracked content' | Set-Content -Path 'untracked.txt' -Encoding utf8
    $untrackedRefreshTiming = [System.Diagnostics.Stopwatch]::StartNew()
    $untrackedGitStatus = & $module {
        Update-MainThreadPieces
        $global:flare_resultCache['git']
    }
    $untrackedRefreshTiming.Stop()

    Test-FlareCondition `
        -Condition ($cleanGitStatus -eq 'main' -and $untrackedGitStatus -eq 'main' -and $untrackedRefreshTiming.Elapsed.TotalMilliseconds -lt 250) `
        -SuccessMessage 'Git fast prompt avoids synchronous untracked scans' `
        -FailureMessage "Git fast prompt returned '$untrackedGitStatus' in $([math]::Round($untrackedRefreshTiming.Elapsed.TotalMilliseconds, 2)) ms"

    $preservedGitStatus = & $module {
        $global:flare_resultCache['git'] = 'main ?1'
        Update-MainThreadPieces
        $global:flare_resultCache['git']
    }
    Test-FlareCondition `
        -Condition ($preservedGitStatus -eq 'main ?1') `
        -SuccessMessage 'Git fast prompt preserves compatible completed status' `
        -FailureMessage "Git fast prompt dropped compatible cached status: '$preservedGitStatus'"

    Pop-Location
    $env:PATH = $originalPath

    '5000' | Set-Content -Path (Join-Path $firstDirectory 'delay.txt') -Encoding utf8
    Remove-Item (Join-Path $firstDirectory 'started.txt') -ErrorAction SilentlyContinue
    $null = & $module {
        param($root, $directory)
        Send-FlareRefreshRequest -WorkingDirectory $directory -Pieces @('slow') -ModuleRoot $root
    } $workerRoot $firstDirectory
    $stopStartDeadline = (Get-Date).AddSeconds(2)
    while (-not (Test-Path (Join-Path $firstDirectory 'started.txt')) -and (Get-Date) -lt $stopStartDeadline) {
        Start-Sleep -Milliseconds 20
    }

    $removeTiming = [System.Diagnostics.Stopwatch]::StartNew()
    Remove-Module flare -Force
    $removeTiming.Stop()

    Test-FlareCondition `
        -Condition ($removeTiming.Elapsed.TotalMilliseconds -lt 500) `
        -SuccessMessage 'Module removal does not wait for active slow work' `
        -FailureMessage "Module removal took $([math]::Round($removeTiming.Elapsed.TotalMilliseconds, 2)) ms"

    $module = Import-Module "$PSScriptRoot/flare.psm1" -Force -PassThru -ErrorAction Stop
    $cleanupDeadline = (Get-Date).AddSeconds(3)
    do {
        Start-Sleep -Milliseconds 25
        $stoppingWorkerCount = & $module {
            Remove-FlareStoppedRefreshWorkers
            $global:flare_stoppingWorkers.Count
        }
    } until ($stoppingWorkerCount -eq 0 -or (Get-Date) -gt $cleanupDeadline)
    Test-FlareCondition `
        -Condition ($stoppingWorkerCount -eq 0) `
        -SuccessMessage 'Asynchronously stopped workers are eventually disposed' `
        -FailureMessage "$stoppingWorkerCount stopped workers remained undisposed"

    $firstSubscriptionId = & $module { $script:flare_idleSubscriptionId }
    $firstExitSubscriptionId = & $module { $script:flare_exitSubscriptionId }
    $firstSubscriberCount = @(Get-EventSubscriber | Where-Object SubscriptionId -eq $firstSubscriptionId).Count
    $firstExitSubscriberCount = @(Get-EventSubscriber | Where-Object SubscriptionId -eq $firstExitSubscriptionId).Count
    $module = Import-Module "$PSScriptRoot/flare.psm1" -Force -PassThru -ErrorAction Stop
    $secondSubscriptionId = & $module { $script:flare_idleSubscriptionId }
    $secondExitSubscriptionId = & $module { $script:flare_exitSubscriptionId }
    $oldSubscriberCountAfterReload = @(Get-EventSubscriber | Where-Object SubscriptionId -eq $firstSubscriptionId).Count
    $oldExitSubscriberCountAfterReload = @(Get-EventSubscriber | Where-Object SubscriptionId -eq $firstExitSubscriptionId).Count
    $secondSubscriberCount = @(Get-EventSubscriber | Where-Object SubscriptionId -eq $secondSubscriptionId).Count
    $secondExitSubscriberCount = @(Get-EventSubscriber | Where-Object SubscriptionId -eq $secondExitSubscriptionId).Count

    Test-FlareCondition `
        -Condition (
            $firstSubscriberCount -eq 1 -and
            $firstExitSubscriberCount -eq 1 -and
            $oldSubscriberCountAfterReload -eq 0 -and
            $oldExitSubscriberCountAfterReload -eq 0 -and
            $secondSubscriberCount -eq 1 -and
            $secondExitSubscriberCount -eq 1
        ) `
        -SuccessMessage 'Module reload replaces its idle and exit subscriptions' `
        -FailureMessage "Module reload left idle=$oldSubscriberCountAfterReload/$secondSubscriberCount and exit=$oldExitSubscriberCountAfterReload/$secondExitSubscriberCount subscriptions"

    Set-PSReadLineKeyHandler -Key Enter -BriefDescription 'Flare test custom Enter' -ScriptBlock {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
    $module = Import-Module "$PSScriptRoot/flare.psm1" -Force -PassThru -ErrorAction Stop
    $customEnterBinding = Get-PSReadLineKeyHandler -Chord Enter
    Test-FlareCondition `
        -Condition ($customEnterBinding.Function -eq 'Flare test custom Enter') `
        -SuccessMessage 'Module import preserves user-defined Enter bindings' `
        -FailureMessage "Module import replaced custom Enter binding with '$($customEnterBinding.Function)'"

    $exitProbePath = Join-Path $tempRoot 'exitProbe.ps1'
    @"
Import-Module '$($module.Path.Replace("'", "''"))' -Force -ErrorAction Stop
`$probeModule = Get-Module flare
`$null = Prompt
`$deadline = (Get-Date).AddSeconds(10)
do {
    Start-Sleep -Milliseconds 25
    `$resultCount = & `$probeModule { `$script:flare_refreshResults.Count }
} until (`$resultCount -gt 0 -or (Get-Date) -gt `$deadline)
exit
"@ | Set-Content -Path $exitProbePath -Encoding utf8

    $processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processStartInfo.FileName = (Get-Process -Id $PID).Path
    $processStartInfo.UseShellExecute = $false
    $processStartInfo.ArgumentList.Add('-NoLogo')
    $processStartInfo.ArgumentList.Add('-NoProfile')
    $processStartInfo.ArgumentList.Add('-File')
    $processStartInfo.ArgumentList.Add($exitProbePath)
    $exitProcess = [System.Diagnostics.Process]::Start($processStartInfo)
    $exitCompleted = $exitProcess.WaitForExit(15000)
    if (-not $exitCompleted) {
        Stop-Process -Id $exitProcess.Id -ErrorAction SilentlyContinue
    }

    Test-FlareCondition `
        -Condition ($exitCompleted -and $exitProcess.ExitCode -eq 0) `
        -SuccessMessage 'Shell exit stops an idle durable worker' `
        -FailureMessage 'Shell process did not exit within 15 seconds'
}
finally {
    Set-Location $originalLocation -ErrorAction SilentlyContinue
    $env:PATH = $originalPath
    $global:flare_leftPieces = $originalLeftPieces
    $global:flare_rightPieces = $originalRightPieces
    $global:flare_resultCache.Clear()
    if ($module) {
        & $module { Stop-FlareRefreshWorker }
    }
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $allTestsPassed) {
    exit 1
}

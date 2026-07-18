if (-not $global:flare_stoppingWorkers) {
    $global:flare_stoppingWorkers = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
}

<#
.SYNOPSIS
Disposes refresh workers whose asynchronous stop has completed.
.DESCRIPTION
Retains workers that are still stopping so module removal never waits for slow
piece evaluation to end.
.OUTPUTS
None
#>
function Remove-FlareStoppedRefreshWorkers {
    $workersToCheck = $global:flare_stoppingWorkers.Count
    for ($i = 0; $i -lt $workersToCheck; $i++) {
        $stoppingWorker = $null
        if (-not $global:flare_stoppingWorkers.TryDequeue([ref]$stoppingWorker)) {
            continue
        }

        if (-not $stoppingWorker.Completion.IsCompleted) {
            $global:flare_stoppingWorkers.Enqueue($stoppingWorker)
            continue
        }

        try {
            if ($stoppingWorker.CompletionKind -eq 'Stop') {
                $stoppingWorker.PowerShell.EndStop($stoppingWorker.Completion)
            }
            else {
                $null = $stoppingWorker.PowerShell.EndInvoke($stoppingWorker.Completion)
            }
        }
        catch {
            Write-Debug "Flare stopped worker cleanup failed: $($_.Exception.Message)"
        }
        finally {
            $stoppingWorker.PowerShell.Dispose()
            $stoppingWorker.Requests.Dispose()
        }
    }
}

<#
.SYNOPSIS
Starts Flare's durable background refresh worker.
.DESCRIPTION
Creates one in-process PowerShell pipeline with a bounded request queue and a
shared result queue. An already-running worker is reused.
.PARAMETER ModuleRoot
The Flare module root containing the pieces and utility scripts.
.OUTPUTS
None
#>
function Start-FlareRefreshWorker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleRoot
    )

    Remove-FlareStoppedRefreshWorkers

    if ($script:flare_refreshWorker -and -not $script:flare_refreshWorker.AsyncResult.IsCompleted) {
        return
    }

    if ($script:flare_refreshWorker) {
        Stop-FlareRefreshWorker
    }

    if (-not $script:flare_refreshResults) {
        $script:flare_refreshResults = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    }

    $requests = [System.Collections.Concurrent.BlockingCollection[object]]::new(1)
    $powerShell = [System.Management.Automation.PowerShell]::Create()
    $workerScript = {
        param($RequestQueue, $ResultQueue, $Root)

        . (Join-Path $Root 'utils/invokeUtils.ps1')
        $piecesPath = Join-Path $Root 'pieces'
        foreach ($pieceFile in Get-ChildItem $piecesPath -Filter '*.ps1' -File) {
            . $pieceFile.FullName
        }

        foreach ($request in $RequestQueue.GetConsumingEnumerable()) {
            try {
                Set-Location -LiteralPath $request.WorkingDirectory -ErrorAction Stop

                $results = @{}
                foreach ($piece in $request.Pieces) {
                    $results[$piece] = Invoke-FlarePiece -PieceName $piece -PiecesPath $piecesPath
                }

                $ResultQueue.Enqueue([pscustomobject]@{
                        RequestId        = $request.RequestId
                        WorkingDirectory = $request.WorkingDirectory
                        Pieces           = $request.Pieces
                        Results          = $results
                        Succeeded        = $true
                        Error            = $null
                    })
            }
            catch {
                $ResultQueue.Enqueue([pscustomobject]@{
                        RequestId        = $request.RequestId
                        WorkingDirectory = $request.WorkingDirectory
                        Pieces           = $request.Pieces
                        Results          = @{}
                        Succeeded        = $false
                        Error            = $_.Exception.Message
                    })
            }
        }
    }

    $null = $powerShell.AddScript($workerScript.ToString()).
        AddArgument($requests).
        AddArgument($script:flare_refreshResults).
        AddArgument($ModuleRoot)

    $script:flare_refreshWorker = [pscustomobject]@{
        PowerShell  = $powerShell
        Requests    = $requests
        AsyncResult = $powerShell.BeginInvoke()
        ModuleRoot  = $ModuleRoot
    }
}

<#
.SYNOPSIS
Queues the newest slow-piece refresh request.
.DESCRIPTION
Starts the worker if needed, discards any pending request, and enqueues the
latest working-directory snapshot without interrupting active work.
.PARAMETER WorkingDirectory
The directory in which the worker evaluates the pieces.
.PARAMETER Pieces
Names of the slow pieces to evaluate.
.PARAMETER ModuleRoot
The Flare module root used to initialize the worker.
.OUTPUTS
System.Int64
#>
function Send-FlareRefreshRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string[]]$Pieces,

        [Parameter(Mandatory = $true)]
        [string]$ModuleRoot
    )

    Start-FlareRefreshWorker -ModuleRoot $ModuleRoot

    $script:flare_nextRefreshRequestId += 1
    $request = [pscustomobject]@{
        RequestId        = $script:flare_nextRefreshRequestId
        WorkingDirectory = $WorkingDirectory
        Pieces           = @($Pieces)
    }

    $discardedRequest = $null
    while ($script:flare_refreshWorker.Requests.TryTake([ref]$discardedRequest)) {
        $discardedRequest = $null
    }

    $script:flare_refreshWorker.Requests.Add($request)
    return $request.RequestId
}

<#
.SYNOPSIS
Drains completed refresh results from the worker.
.OUTPUTS
System.Management.Automation.PSCustomObject
#>
function Receive-FlareRefreshResult {
    if (-not $script:flare_refreshResults) {
        return
    }

    $result = $null
    while ($script:flare_refreshResults.TryDequeue([ref]$result)) {
        $result
        $result = $null
    }
}

<#
.SYNOPSIS
Requests asynchronous shutdown of Flare's background refresh worker.
.DESCRIPTION
Completes the request queue and begins stopping active work without waiting.
Finished workers are disposed the next time worker state is initialized.
.OUTPUTS
None
#>
function Stop-FlareRefreshWorker {
    if (-not $script:flare_refreshWorker) {
        return
    }

    $worker = $script:flare_refreshWorker
    $script:flare_refreshWorker = $null
    $disposeWorker = $false

    try {
        if (-not $worker.Requests.IsAddingCompleted) {
            $worker.Requests.CompleteAdding()
        }

        if (-not $worker.AsyncResult.IsCompleted) {
            try {
                $stopResult = $worker.PowerShell.BeginStop($null, $null)
                $global:flare_stoppingWorkers.Enqueue([pscustomobject]@{
                        PowerShell     = $worker.PowerShell
                        Requests       = $worker.Requests
                        Completion     = $stopResult
                        CompletionKind = 'Stop'
                    })
            }
            catch {
                $global:flare_stoppingWorkers.Enqueue([pscustomobject]@{
                        PowerShell     = $worker.PowerShell
                        Requests       = $worker.Requests
                        Completion     = $worker.AsyncResult
                        CompletionKind = 'Invoke'
                    })
                Write-Debug "Flare refresh worker stop request failed: $($_.Exception.Message)"
            }
        }
        else {
            $disposeWorker = $true
            $null = $worker.PowerShell.EndInvoke($worker.AsyncResult)
        }
    }
    catch {
        Write-Debug "Flare refresh worker cleanup failed: $($_.Exception.Message)"
    }
    finally {
        if ($disposeWorker) {
            $worker.PowerShell.Dispose()
            $worker.Requests.Dispose()
        }
    }
}

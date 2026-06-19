. $PSScriptRoot/promptSymbols.ps1

# Shared dictionary for background job to store results
$global:flare_resultCache = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()

# Cache for what was last rendered, to be used to compare with result cache
$global:flare_lastRenderCache = @{}

# Last refresh time for fast pieces that update the cache synchronously.
$global:flare_fastRefreshTimestamps = [System.Collections.Concurrent.ConcurrentDictionary[string, datetime]]::new()

# Items we can calculate on the main thread, but should also ignore when comparing changes from the background job
$global:flare_mainThread = @('os', 'date', 'lastCommand', 'pwd')

# Fast pieces that should refresh every prompt because their state can change without touching prompt caches.
if ($null -eq $global:flare_alwaysRefreshFastPieces) {
    $global:flare_alwaysRefreshFastPieces = @('git')
}

# Use a concurrent collection to track all background jobs
$global:flare_backgroundJobs = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

# Background prompt refreshes are best-effort; don't let slow pieces stack up.
$global:flare_backgroundJobTimeout ??= [TimeSpan]::FromSeconds(10)

$global:flare_lastDirectory = $null

$global:flare_redrawing = $false

$defaultStyle = "`e[0m"
$foregroundStyles = [ordered]@{
    'default'       = "`e[39m"
    'white'         = "`e[37m"
    'red'           = "`e[31m"
    'black'         = "`e[30m"
    'yellow'        = "`e[33m"
    'magenta'       = "`e[35m"
    'cyan'          = "`e[36m"
    'brightBlack'   = "`e[90m"
    'brightRed'     = "`e[91m"
    'brightGreen'   = "`e[92m"
    'brightYellow'  = "`e[93m"
    'brightBlue'    = "`e[94m"
    'brightMagenta' = "`e[95m"
    'brightCyan'    = "`e[96m"
    'green'         = "`e[32m"
    'blue'          = "`e[34m"
    'brightWhite'   = "`e[97m"
}

$backgroundStyles = [ordered]@{
    'default'       = "`e[49m"
    'white'         = "`e[47m"
    'red'           = "`e[41m"
    'black'         = "`e[40m"
    'yellow'        = "`e[43m"
    'magenta'       = "`e[45m"
    'cyan'          = "`e[46m"
    'brightBlack'   = "`e[100m"
    'brightRed'     = "`e[101m"
    'brightGreen'   = "`e[102m"
    'brightYellow'  = "`e[103m"
    'brightBlue'    = "`e[104m"
    'brightMagenta' = "`e[105m"
    'brightCyan'    = "`e[106m"
    'green'         = "`e[42m"
    'blue'          = "`e[44m"
    'brightWhite'   = "`e[107m"
}

$escapeRegex = "(`e\[\d+\w)"

. $PSScriptRoot/utils/invokeUtils.ps1

function Get-LeftPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$Parts
    )

    $left = $global:flare_topPrefix

    $count = 1
    foreach ($pieceName in $global:flare_leftPieces) {
        $pieceResult = $Parts[$pieceName]
        if ($pieceResult) {
            $background = $backgroundStyles.Values[($backgroundStyles.Count - $count) % $backgroundStyles.Count]
            $foreground = $foregroundStyles['brightBlack']
            $separatorColor = $foregroundStyles.Values[($foregroundStyles.Count - $(if (($count - 1) -gt 0) { $count - 1 } else { $count })) % $foregroundStyles.Count]
            $separator = "$separatorColor$(if (($count - 1) -gt 0) { "$background$global:flare_promptSeparatorsLeft" } else { "$global:flare_promptTailLeft" })"
            $left += "$separator$background$foreground "
            $icon = Get-Variable -Name "flare_icons_$pieceName" -Scope Global -ValueOnly -ErrorAction SilentlyContinue
            if ($icon) {
                $left += "$icon "
            }
            $left += "$pieceResult "
            $count += 1
        }
    }

    $foreground = $foregroundStyles.Values[($foregroundStyles.Count - ($count - 1)) % $foregroundStyles.Count]
    $left += "$($backgroundStyles['default'])$foreground$global:flare_promptHeadLeft"

    return $left
}

function Get-RightPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$Parts
    )

    $right = ''
    $count = 1
    foreach ($pieceName in $global:flare_rightPieces) {
        $pieceResult = $Parts[$pieceName]
        if ($pieceResult) {
            $background = $backgroundStyles.Values[($backgroundStyles.Count - $count) % $backgroundStyles.Count]
            $foreground = $foregroundStyles['brightBlack']
            $separatorColor = $foregroundStyles.Values[($foregroundStyles.Count - $(if (($count - 1) -gt 0) { $count - 1 } else { $count })) % $foregroundStyles.Count]
            $separator = "$separatorColor$(if (($count - 1) -gt 0) { "$background$global:flare_promptSeparatorsRight" } else { "$($backgroundStyles['default'])$global:flare_promptTailRight" })"
            $right = "$pieceResult $separator$right"
            $icon = Get-Variable -Name "flare_icons_$pieceName" -Scope Global -ValueOnly -ErrorAction SilentlyContinue
            if ($icon) {
                $right = "$icon $right"
            }
            $right = "$background$foreground $right"
            $count += 1
        }
    }

    $foreground = $foregroundStyles.Values[($foregroundStyles.Count - ($count - 1)) % $foregroundStyles.Count]
    $right = "$($backgroundStyles['default'])$foreground$global:flare_promptSeparatorsRight$right"

    return $right
}

function Get-PromptLine {
    # Check if the last command was successful
    # Get exit status from command history if available
    $lastCommand = Get-History -Count 1 -ErrorAction SilentlyContinue
    $promptColor = if ($lastCommand -and $lastCommand.ExecutionStatus -eq 'Failed') {
        $foregroundStyles['brightRed']
    }
    else {
        $foregroundStyles['brightGreen']
    }

    return "$defaultStyle$global:flare_bottomPrefix$($promptColor)$($global:flare_promptArrow * ($nestedPromptLevel + 1))$defaultStyle"
}

function Get-FlareGitMetadataPrefix {
    param([string]$Value)

    if (-not $Value) {
        return ''
    }

    return ($Value -replace ' (?:⇣|⇡|\*|~|\+|!|\?)\d+(?: .*)?$', '')
}

function Update-MainThreadPieces {
    $allPieces = $global:flare_leftPieces + $global:flare_rightPieces
    # Find the intersection of all prompt pieces and main thread items
    $mainThreadPieces = $allPieces | Where-Object { $_ -in $global:flare_mainThread }
    $mainThreadPieces += $allPieces | Where-Object {
        ($_ -notin $global:flare_mainThread) -and
        (($_ -in $global:flare_alwaysRefreshFastPieces) -or (-not $global:flare_resultCache.ContainsKey($_)))
    } | ForEach-Object { "${_}_fast" }
    $mainThreadPieces = $mainThreadPieces | Select-Object -Unique

    $mainThreadResults = Get-PromptPieceResults -Pieces $mainThreadPieces

    foreach ($piece in $mainThreadPieces) {
        # Support "fast" versions of pieces when there's no cache data available
        if ($piece -like '*_fast') {
            $pieceFast = $piece
            $piece = $piece -replace '_fast', ''
            # Most fast results are fallbacks; selected pieces use them for cheap, synchronous freshness.
            if (($piece -in $global:flare_alwaysRefreshFastPieces) -or (-not $global:flare_resultCache.ContainsKey($piece))) {
                $fastResult = $mainThreadResults[$pieceFast]
                $cachedResult = $null
                if (
                    ($piece -eq 'git') -and
                    $fastResult -and
                    $global:flare_resultCache.TryGetValue($piece, [ref]$cachedResult) -and
                    ((Get-FlareGitMetadataPrefix $cachedResult) -eq $fastResult)
                ) {
                    # Keep completed background status counts when only cheap git metadata was refreshed.
                }
                else {
                    $global:flare_resultCache[$piece] = $fastResult
                }
                if ($piece -in $global:flare_alwaysRefreshFastPieces) {
                    $global:flare_fastRefreshTimestamps[$piece] = Get-Date
                }
            }
        }
        else {
            $global:flare_resultCache[$piece] = $mainThreadResults[$piece]
        }
    }
}

function Update-BackgroundThreadPieces {
    $allPieces = $global:flare_leftPieces + $global:flare_rightPieces
    # Find the intersection of all prompt pieces and main thread items
    $backgroundThreadPieces = $allPieces | Where-Object { $_ -notin $global:flare_mainThread }
    if ($backgroundThreadPieces.Count -eq 0) {
        return
    }

    # Capture the working directory at the time the job is created.
    # Background jobs run in another runspace and may not inherit the caller's location,
    # which can cause pieces like `git` to be computed for the wrong directory.
    $workingDirectory = $PWD.Path

    # Generate a timestamp for this job
    $timestamp = Get-Date

    $hasActiveCurrentDirectoryJob = $false
    $jobsToKeep = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    foreach ($existingJob in $global:flare_backgroundJobs) {
        if (-not (Test-FlareBackgroundJobTerminalState $existingJob)) {
            $jobWorkingDirectoryProperty = $existingJob.PSObject.Properties['WorkingDirectory']
            $jobTimestampProperty = $existingJob.PSObject.Properties['Timestamp']
            $jobWorkingDirectory = if ($jobWorkingDirectoryProperty) { $jobWorkingDirectoryProperty.Value } else { $null }
            $jobTimestamp = if ($jobTimestampProperty) { $jobTimestampProperty.Value } else { $timestamp }

            if (
                ($jobWorkingDirectory -eq $workingDirectory) -and
                ($global:flare_backgroundJobTimeout -gt [TimeSpan]::Zero) -and
                (($timestamp - $jobTimestamp) -gt $global:flare_backgroundJobTimeout)
            ) {
                try {
                    Stop-Job -Job $existingJob -Force -ErrorAction SilentlyContinue
                    Remove-Job -Job $existingJob -Force -ErrorAction SilentlyContinue
                }
                catch {
                    # Ignore failures; the next idle cleanup can handle jobs that already changed state.
                }
                continue
            }

            if ($jobWorkingDirectory -eq $workingDirectory) {
                $hasActiveCurrentDirectoryJob = $true
            }
        }

        $jobsToKeep.Add($existingJob)
    }
    $global:flare_backgroundJobs = $jobsToKeep

    if ($hasActiveCurrentDirectoryJob) {
        return
    }

    $job = Start-ThreadJob -Name "Flare Background Update $(Get-Date -Format 'HH:mm:ss.fff')" -ScriptBlock {
        param($pieces, $results, $timestamp, $workingDirectory)
        Write-Output "Updating background pieces: $pieces at timestamp $timestamp"
        . $using:PSScriptRoot/utils/invokeUtils.ps1

        # Ensure piece evaluation happens in the directory that created the job.
        try {
            if ($workingDirectory) {
                Set-Location -LiteralPath $workingDirectory -ErrorAction Stop
            }
        }
        catch {
            # If we can't cd (directory removed, permissions, etc.), continue. Pieces should fail closed.
        }

        $piecesResults = Get-PromptPieceResults -Pieces $pieces -PiecesPath $using:PSScriptRoot/pieces

        # Create a results package with timestamp
        $resultsPackage = @{
            Timestamp        = $timestamp
            WorkingDirectory = $workingDirectory
            Results          = @{}
        }

        foreach ($piece in $pieces) {
            Write-Output "Piece: $piece, Result: $($piecesResults[$piece])"
            $resultsPackage.Results[$piece] = $piecesResults[$piece]
        }

        # Store the entire package
        $results["_package_$timestamp"] = $resultsPackage
    } -ArgumentList $backgroundThreadPieces, $global:flare_resultCache, $timestamp, $workingDirectory

    # Add the new job and its timestamp to our tracking collection
    $job | Add-Member -NotePropertyName Timestamp -NotePropertyValue $timestamp
    $job | Add-Member -NotePropertyName WorkingDirectory -NotePropertyValue $workingDirectory
    $global:flare_backgroundJobs.Add($job)
}

function Get-PromptTopLine {
    param(
        [bool]$DisableBackground = $false
    )

    Update-MainThreadPieces
    if (-not $DisableBackground) {
        Update-BackgroundThreadPieces
    }

    $results = @{}
    # Take a snapshot of keys to avoid enumeration issues with concurrent modifications
    foreach ($piece in @($global:flare_resultCache.Keys)) {
        # Skip our package keys when building prompt data
        if (-not $piece.StartsWith('_package_')) {
            $value = $null
            if ($global:flare_resultCache.TryGetValue($piece, [ref]$value)) {
                $results[$piece] = $value
            }
        }
    }

    $left = Get-LeftPrompt -Parts $results
    $right = Get-RightPrompt -Parts $results

    # Figure out spacing between left and right prompts
    # Get the window width and subtract the current cursor position
    $spaces = $Host.UI.RawUI.WindowSize.Width - ($($left -replace $escapeRegex).Length + $($right -replace $escapeRegex).Length)

    if ($spaces -lt 0) { 
        # Not enough space to also have right prompt
        "$left"
    }
    else {
        "$left$defaultStyle$(' ' * $spaces)$right"
    }
}

function Test-FlareBackgroundJobTerminalState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Job
    )

    $Job.State -in @(
        [System.Management.Automation.JobState]::Completed,
        [System.Management.Automation.JobState]::Failed,
        [System.Management.Automation.JobState]::Stopped
    )
}

Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    # Check if there are any background jobs to process
    if ($global:flare_backgroundJobs.Count -eq 0) {
        return
    }

    # Only terminal jobs are safe to wait on. Queued jobs can sit in NotStarted,
    # and Wait-Job on those would block the interactive runspace.
    $completedJobs = $global:flare_backgroundJobs | Where-Object { Test-FlareBackgroundJobTerminalState $_ }
    if ($completedJobs.Count -eq 0) {
        return
    }

    # Find the newest completed job
    $newestCompletedJob = $completedJobs | Sort-Object -Property Timestamp -Descending | Select-Object -First 1

    # Process the newest job first to get its results
    if ($newestCompletedJob) {
        $null = Wait-Job -Job $newestCompletedJob -ErrorAction SilentlyContinue

        # Find and extract the package with the timestamp from the result cache
        # Take a snapshot of keys to avoid enumeration issues with concurrent modifications
        $packageKeys = @($global:flare_resultCache.Keys) | Where-Object { $_ -like '_package_*' }

        # Find the newest package for the CURRENT working directory by timestamp.
        # Without this, a job created in a previous directory can complete later and
        # overwrite the cache, reintroducing stale data (notably the `git` piece).
        $newestPackage = $null
        $newestPackageTimestamp = [DateTime]::MinValue

        $currentWorkingDirectory = (Get-Location).Path

        foreach ($key in $packageKeys) {
            $package = $null
            if (-not $global:flare_resultCache.TryGetValue($key, [ref]$package)) {
                continue
            }
            if ($null -eq $package) {
                continue
            }

            if ($package.WorkingDirectory -ne $currentWorkingDirectory) {
                continue
            }

            if ($package.Timestamp -gt $newestPackageTimestamp) {
                $newestPackageTimestamp = $package.Timestamp
                $newestPackage = $package
            }
        }

        # Only apply results from the newest completed job
        if ($newestPackage) {
            # Apply the results to the main cache
            foreach ($piece in $newestPackage.Results.Keys) {
                $lastFastRefresh = $null
                if ($piece -eq 'git') {
                    $currentGitValue = $null
                    $newGitValue = $newestPackage.Results[$piece]
                    if (
                        $global:flare_resultCache.TryGetValue($piece, [ref]$currentGitValue) -and
                        ((Get-FlareGitMetadataPrefix $newGitValue) -ne (Get-FlareGitMetadataPrefix $currentGitValue))
                    ) {
                        continue
                    }
                }
                elseif ($global:flare_fastRefreshTimestamps.TryGetValue($piece, [ref]$lastFastRefresh) -and $newestPackage.Timestamp -lt $lastFastRefresh) {
                    continue
                }

                $global:flare_resultCache[$piece] = $newestPackage.Results[$piece]
            }

            # Clean up packages that are no longer needed (including other directories).
            foreach ($key in $packageKeys) {
                $null = $global:flare_resultCache.TryRemove($key, [ref]$null)
            }
        }
        else {
            # No applicable package for the current directory; still clean up packages so
            # completed jobs from other directories cannot apply later.
            foreach ($key in $packageKeys) {
                $null = $global:flare_resultCache.TryRemove($key, [ref]$null)
            }
        }
    }

    # Wait for and clean up all completed jobs
    foreach ($job in $completedJobs) {
        $null = Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }

    # Remove completed jobs from our tracking collection
    $newBag = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    foreach ($job in ($global:flare_backgroundJobs | Where-Object { -not (Test-FlareBackgroundJobTerminalState $_) })) {
        $newBag.Add($job)
    }
    $global:flare_backgroundJobs = $newBag

    $allPieces = $global:flare_leftPieces + $global:flare_rightPieces
    $comparisonPieces = $allPieces | Where-Object { $_ -notin $global:flare_mainThread }
    # Check if there are changes between caches for background pieces
    $hasChanges = $false
    foreach ($piece in $comparisonPieces) {
        $cachedValue = $null
        # Use TryGetValue for atomic check-and-read to avoid race conditions
        if ($global:flare_resultCache.TryGetValue($piece, [ref]$cachedValue)) {
            # If piece is in result cache but not in render cache or values differ
            if ($cachedValue -ne $global:flare_lastRenderCache[$piece]) {
                $hasChanges = $true
                break
            }
        }
    }

    # Only redraw prompt if changes were detected
    if ($hasChanges) {
        # Update the lastRenderCache with current values
        foreach ($piece in $comparisonPieces) {
            $cachedValue = $null
            if ($global:flare_resultCache.TryGetValue($piece, [ref]$cachedValue)) {
                $global:flare_lastRenderCache[$piece] = $cachedValue
            }
        }

        # Redraw the prompt - wrap in try-catch to prevent blocking if PSReadLine is in an inconsistent state
        $global:flare_redrawing = $true
        try {
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
        catch {
            # Silently ignore - prompt will be redrawn on next command anyway
        }
        $global:flare_redrawing = $false
    }
}

# Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
#     New-Event -SourceIdentifier Flare.Redraw -Sender $Sender
# }

# Register a cleanup event handler for when the module is removed
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    Get-EventSubscriber | Unregister-Event
    # Clean up all background jobs
    foreach ($job in $global:flare_backgroundJobs) {
        Stop-Job -Job $job -Force -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }

    $global:flare_backgroundJobs = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
}

function Prompt {
    if ($global:flare_lastDirectory) {
        if ($PWD.Path -ne $global:flare_lastDirectory.Path) {
            # Clear the last render cache when the directory changes
            $global:flare_lastRenderCache.Clear()
            $global:flare_resultCache.Clear()
            $global:flare_fastRefreshTimestamps.Clear()

            # Cancel any in-flight background jobs created for the previous directory.
            # If we don't, a slower job can complete after cd and OnIdle can reapply
            # stale results for the old directory.
            foreach ($job in $global:flare_backgroundJobs) {
                try {
                    Stop-Job -Job $job -Force -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                }
                catch {
                    # Ignore failures; jobs may have already completed/been removed.
                }
            }
            $global:flare_backgroundJobs = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        }
    }

    $global:flare_lastDirectory = $PWD


    $topLine = Get-PromptTopLine -DisableBackground $global:flare_redrawing
    $line = Get-PromptLine

    Set-PSReadLineOption -ExtraPromptLineCount 1

    "`r$topLine`n$line "
}

# Add module exports
Export-ModuleMember -Function @('Prompt')

# Use Set-PSReadLineKeyHandler to clear the prompt and rewrite the user's input when the user submits a command
Set-PSReadLineKeyHandler -Key Enter -BriefDescription 'Clear prompt and rewrite input on Enter' -ScriptBlock {
    # Prepare references for the input line and cursor position
    $inputLineRef = [ref]''
    $cursorPositionRef = [ref]0

    # Retrieve the current input from the command line buffer using GetBufferState
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState($inputLineRef, $cursorPositionRef)
    $inputLine = $inputLineRef.Value

    # Check if the input is multiline
    if ($inputLine -join '' -match "`n") {
        # If multiline, invoke the default Enter key behavior without clearing the prompt
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        return
    }

    # Move the cursor up by two lines to clear the two-line prompt
    [System.Console]::SetCursorPosition(0, [System.Console]::CursorTop - 1)

    # Get the console width to overwrite the lines with spaces
    $consoleWidth = [System.Console]::BufferWidth

    # Clear the current line and the next line by overwriting with spaces
    [System.Console]::Write(' ' * $consoleWidth * 2)

    # Rewrite the user's input prefixed with '>'
    [System.Console]::SetCursorPosition(0, [System.Console]::CursorTop - 1)
    Write-Host "$(Get-PromptLine) $($inputLine -join '')" -NoNewline

    # Execute the command by invoking the default Enter key behavior
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

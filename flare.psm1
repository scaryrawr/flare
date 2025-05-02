. $PSScriptRoot/promptSymbols.ps1

# Shared dictionary for background job to store results
$global:flare_resultCache = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()

# Cache for what was last rendered, to be used to compare with result cache
$global:flare_lastRenderCache = @{}

# Items we can calculate on the main thread, but should also ignore when comparing changes from the background job
$global:flare_mainThread = @('os', 'date', 'lastCommand', 'pwd')

# Use a concurrent collection to track all background jobs
$global:flare_backgroundJobs = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

# Track the timestamp of the most recently started job
$global:flare_lastJobTimestamp = [DateTime]::MinValue

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

function Update-MainThreadPieces {
    $allPieces = $global:flare_leftPieces + $global:flare_rightPieces
    # Find the intersection of all prompt pieces and main thread items
    $mainThreadPieces = $allPieces | Where-Object { $_ -in $global:flare_mainThread }
    $mainThreadPieces += $allPieces | Where-Object { ($_ -notin $global:flare_mainThread) -and (-not $global:flare_resultCache.ContainsKey($_)) } | ForEach-Object { "${_}_fast" }

    $mainThreadResults = Get-PromptPieceResults -Pieces $mainThreadPieces

    foreach ($piece in $mainThreadPieces) {
        # Support "fast" versions of pieces when there's no cache data available
        if ($piece -like '*_fast') {
            $pieceFast = $piece
            $piece = $piece -replace '_fast', ''
            # Fast results are only valid when we don't have a cached actual result.
            if (-not $global:flare_resultCache.ContainsKey($piece)) {
                $global:flare_resultCache[$piece] = $mainThreadResults[$pieceFast]
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
    $mainRunspace = [runspace]::DefaultRunspace

    # Generate a timestamp for this job
    $timestamp = Get-Date

    $job = Start-ThreadJob -Name "Flare Background Update $(Get-Date -Format 'HH:mm:ss.fff')" -ScriptBlock {
        param($pieces, $results, $defaultRunspace, $timestamp)
        Write-Output "Updating background pieces: $pieces at timestamp $timestamp"
        . $using:PSScriptRoot/utils/invokeUtils.ps1

        $piecesResults = Get-PromptPieceResults -Pieces $pieces -PiecesPath $using:PSScriptRoot/pieces

        # Create a results package with timestamp
        $resultsPackage = @{
            Timestamp = $timestamp
            Results   = @{}
        }

        foreach ($piece in $pieces) {
            Write-Output "Piece: $piece, Result: $($piecesResults[$piece])"
            $resultsPackage.Results[$piece] = $piecesResults[$piece]
        }

        # Store the entire package
        $results["_package_$timestamp"] = $resultsPackage
        $defaultRunspace.Events.GenerateEvent('Flare.Redraw', $_, $null, $null)
        Write-Output 'Flare.Redraw event triggered'
    } -ArgumentList $backgroundThreadPieces, $global:flare_resultCache, $mainRunspace, $timestamp

    # Update the last job timestamp
    $global:flare_lastJobTimestamp = $timestamp

    # Add the new job and its timestamp to our tracking collection
    $job | Add-Member -NotePropertyName Timestamp -NotePropertyValue $timestamp
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
    foreach ($piece in $global:flare_resultCache.Keys) {
        # Skip our package keys when building prompt data
        if (-not $piece.StartsWith('_package_')) {
            $results[$piece] = $global:flare_resultCache[$piece]
        }
    }

    $left = Get-LeftPrompt -Parts $results
    $right = Get-RightPrompt -Parts $results

    # Figure out spacing between left and right prompts
    # Get the window width and subtract the current cursor position
    $spaces = $Host.UI.RawUI.WindowSize.Width - ($($left -replace $escapeRegex).Length + $($right -replace $escapeRegex).Length)

    # Ensure spaces is not negative
    if ($spaces -lt 0) { $spaces = 0 }

    "$left$defaultStyle$(' ' * $spaces)$right"
}

Register-EngineEvent -SourceIdentifier Flare.Redraw -Action {
    # Check if there are any background jobs to process
    if ($global:flare_backgroundJobs.Count -eq 0) {
        return
    }

    # Process completed jobs
    $completedJobs = $global:flare_backgroundJobs | Where-Object { $_.State -ne 'Running' }
    if ($completedJobs.Count -eq 0) {
        return
    }

    # Find the newest completed job
    $newestCompletedJob = $completedJobs | Sort-Object -Property Timestamp -Descending | Select-Object -First 1

    # Process the newest job first to get its results
    if ($newestCompletedJob) {
        $null = Wait-Job -Job $newestCompletedJob -ErrorAction SilentlyContinue

        # Find and extract the package with the timestamp from the result cache
        $packageKeys = $global:flare_resultCache.Keys | Where-Object { $_ -like '_package_*' }

        # Find the newest package by timestamp
        $newestPackage = $null
        $newestPackageTimestamp = [DateTime]::MinValue

        foreach ($key in $packageKeys) {
            $package = $global:flare_resultCache[$key]
            if ($package.Timestamp -gt $newestPackageTimestamp) {
                $newestPackageTimestamp = $package.Timestamp
                $newestPackage = $package
            }
        }

        # Only apply results from the newest completed job
        if ($newestPackage) {
            # Apply the results to the main cache
            foreach ($piece in $newestPackage.Results.Keys) {
                $global:flare_resultCache[$piece] = $newestPackage.Results[$piece]
            }

            # Clean up packages that are no longer needed
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
    foreach ($job in ($global:flare_backgroundJobs | Where-Object { $_.State -eq 'Running' })) {
        $newBag.Add($job)
    }
    $global:flare_backgroundJobs = $newBag

    $allPieces = $global:flare_leftPieces + $global:flare_rightPieces
    $comparisonPieces = $allPieces | Where-Object { $_ -notin $global:flare_mainThread }
    # Check if there are changes between caches for background pieces
    $hasChanges = $false
    foreach ($piece in $comparisonPieces) {
        if ($global:flare_resultCache.ContainsKey($piece)) {
            # If piece is in result cache but not in render cache or values differ
            if ($global:flare_resultCache[$piece] -ne $global:flare_lastRenderCache[$piece]) {
                $hasChanges = $true
                break
            }
        }
    }

    # Only redraw prompt if changes were detected
    if ($hasChanges) {
        # Update the lastRenderCache with current values
        foreach ($piece in $comparisonPieces) {
            if ($global:flare_resultCache.ContainsKey($piece)) {
                $global:flare_lastRenderCache[$piece] = $global:flare_resultCache[$piece]
            }
        }

        # Redraw the prompt
        $global:flare_redrawing = $true
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
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
        if (-not $PWD.Path.StartsWith($global:flare_lastDirectory.Path)) {
            # Clear the last render cache when the directory changes
            $global:flare_lastRenderCache.Clear()
            $global:flare_resultCache.Clear()
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

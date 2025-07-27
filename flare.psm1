. $PSScriptRoot/promptSymbols.ps1

# Unified state management for the prompt system
$global:flare_promptState = @{
    ResultCache    = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    ActiveJobs     = [System.Collections.Concurrent.ConcurrentDictionary[string, System.Management.Automation.Job]]::new()
    LastRenderHash = $null
    LastDirectory  = $null
    IsRedrawing    = $false
    LastRedrawTime = [DateTime]::MinValue
}

# Items we can calculate on the main thread, but should also ignore when comparing changes from the background job
$global:flare_mainThread = @('os', 'date', 'lastCommand', 'pwd')

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

function Get-PromptStateHash {
    param([System.Collections.Concurrent.ConcurrentDictionary[string, object]]$ResultCache)
    
    # Create a simple hash of all background pieces for change detection
    $allPieces = $global:flare_leftPieces + $global:flare_rightPieces
    $backgroundPieces = $allPieces | Where-Object { $_ -notin $global:flare_mainThread }
    
    $values = $backgroundPieces | ForEach-Object { 
        $value = if ($ResultCache.ContainsKey($_)) { $ResultCache[$_] } else { '' }
        "$_=$value" 
    }
    return ($values -join '|').GetHashCode()
}

function Start-PieceJob {
    param([string]$PieceName)
    
    # Cancel existing job for this piece if running
    if ($global:flare_promptState.ActiveJobs.ContainsKey($PieceName)) {
        $existingJob = $global:flare_promptState.ActiveJobs[$PieceName]
        if ($existingJob.State -eq 'Running') {
            Stop-Job -Job $existingJob -Force -ErrorAction SilentlyContinue
        }
        Remove-Job -Job $existingJob -Force -ErrorAction SilentlyContinue
        $null = $global:flare_promptState.ActiveJobs.TryRemove($PieceName, [ref]$null)
    }
    
    # Start new job
    $job = Start-ThreadJob -Name "Flare-$PieceName" -ScriptBlock {
        param($pieceName, $resultCache)
        . $using:PSScriptRoot/utils/invokeUtils.ps1
        
        $result = Invoke-FlarePiece -PieceName $pieceName -PiecesPath $using:PSScriptRoot/pieces
        
        # Direct update to cache - no packages needed
        $resultCache[$pieceName] = $result
        
        # Return piece name so we know what was updated
        return $pieceName
    } -ArgumentList $PieceName, $global:flare_promptState.ResultCache
    
    $global:flare_promptState.ActiveJobs[$PieceName] = $job
}

function Request-PromptRedraw {
    $now = Get-Date
    # Debounce rapid redraws (100ms minimum interval)
    if (($now - $global:flare_promptState.LastRedrawTime).TotalMilliseconds -lt 100) {
        return
    }
    
    $global:flare_promptState.LastRedrawTime = $now
    $global:flare_promptState.IsRedrawing = $true
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    $global:flare_promptState.IsRedrawing = $false
}

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
    $mainThreadPieces += $allPieces | Where-Object { 
        ($_ -notin $global:flare_mainThread) -and 
        (-not $global:flare_promptState.ResultCache.ContainsKey($_)) 
    } | ForEach-Object { "${_}_fast" }

    $mainThreadResults = Get-PromptPieceResults -Pieces $mainThreadPieces

    foreach ($piece in $mainThreadPieces) {
        # Support "fast" versions of pieces when there's no cache data available
        if ($piece -like '*_fast') {
            $pieceFast = $piece
            $piece = $piece -replace '_fast', ''
            # Fast results are only valid when we don't have a cached actual result.
            if (-not $global:flare_promptState.ResultCache.ContainsKey($piece)) {
                $global:flare_promptState.ResultCache[$piece] = $mainThreadResults[$pieceFast]
            }
        }
        else {
            $global:flare_promptState.ResultCache[$piece] = $mainThreadResults[$piece]
        }
    }
}

function Update-BackgroundThreadPieces {
    $allPieces = $global:flare_leftPieces + $global:flare_rightPieces
    $backgroundThreadPieces = $allPieces | Where-Object { $_ -notin $global:flare_mainThread }

    foreach ($piece in $backgroundThreadPieces) {
        # Only start job if not already running
        if (-not $global:flare_promptState.ActiveJobs.ContainsKey($piece) -or 
            $global:flare_promptState.ActiveJobs[$piece].State -ne 'Running') {
            Start-PieceJob -PieceName $piece
        }
    }
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
    foreach ($piece in $global:flare_promptState.ResultCache.Keys) {
        $results[$piece] = $global:flare_promptState.ResultCache[$piece]
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

Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    # Check if there are any active jobs to process
    if ($global:flare_promptState.ActiveJobs.Count -eq 0) {
        return
    }

    # Get completed jobs
    $completedJobs = $global:flare_promptState.ActiveJobs.GetEnumerator() | Where-Object { $_.Value.State -ne 'Running' }
    if ($completedJobs.Count -eq 0) {
        return
    }

    $hasUpdates = $false

    # Process completed jobs
    foreach ($jobPair in $completedJobs) {
        $job = $jobPair.Value
        $pieceName = $jobPair.Key

        # Wait for job and clean up
        $null = Wait-Job -Job $job -ErrorAction SilentlyContinue
        $null = Receive-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

        # Remove from active jobs
        $null = $global:flare_promptState.ActiveJobs.TryRemove($pieceName, [ref]$null)
        $hasUpdates = $true
    }

    # Check if we need to redraw based on hash comparison
    if ($hasUpdates) {
        $currentHash = Get-PromptStateHash -ResultCache $global:flare_promptState.ResultCache
        if ($currentHash -ne $global:flare_promptState.LastRenderHash) {
            $global:flare_promptState.LastRenderHash = $currentHash
            Request-PromptRedraw
        }
    }
}

# Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
#     New-Event -SourceIdentifier Flare.Redraw -Sender $Sender
# }

# Register a cleanup event handler for when the module is removed
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    Get-EventSubscriber | Unregister-Event
    # Clean up all background jobs
    foreach ($jobPair in $global:flare_promptState.ActiveJobs.GetEnumerator()) {
        $job = $jobPair.Value
        Stop-Job -Job $job -Force -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
    $global:flare_promptState.ActiveJobs.Clear()
}

function Prompt {
    if ($global:flare_promptState.LastDirectory) {
        if ($PWD.Path -ne $global:flare_promptState.LastDirectory.Path) {
            # Clear caches when the directory changes
            $global:flare_promptState.ResultCache.Clear()
            $global:flare_promptState.LastRenderHash = $null
        }
    }

    $global:flare_promptState.LastDirectory = $PWD

    $topLine = Get-PromptTopLine -DisableBackground $global:flare_promptState.IsRedrawing
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

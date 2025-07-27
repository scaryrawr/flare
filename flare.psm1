. $PSScriptRoot/promptSymbols.ps1

# Unified state management for the prompt system
$global:flare_promptState = @{
    ResultCache       = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    BackgroundJob     = $null
    LastRenderHash    = $null
    LastDirectory     = $null
    IsRedrawing       = $false
    LastRedrawTime    = [DateTime]::MinValue
    AllPieces         = $null
    BackgroundPieces  = $null
    MainThreadPieces  = $null
    StyleCache        = @{}
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

function Initialize-PieceCollections {
    if ($null -eq $global:flare_promptState.AllPieces) {
        $global:flare_promptState.AllPieces = $global:flare_leftPieces + $global:flare_rightPieces
        $global:flare_promptState.BackgroundPieces = $global:flare_promptState.AllPieces | Where-Object { $_ -notin $global:flare_mainThread }
        $global:flare_promptState.MainThreadPieces = $global:flare_promptState.AllPieces | Where-Object { $_ -in $global:flare_mainThread }
    }
}

function Get-PromptStateHash {
    param([System.Collections.Concurrent.ConcurrentDictionary[string, object]]$ResultCache)
    
    Initialize-PieceCollections
    
    # Use string builder for better performance with multiple concatenations
    $values = [System.Text.StringBuilder]::new()
    foreach ($piece in $global:flare_promptState.BackgroundPieces) {
        $value = if ($ResultCache.ContainsKey($piece)) { $ResultCache[$piece] } else { '' }
        $null = $values.Append("$piece=$value|")
    }
    return $values.ToString().GetHashCode()
}

function Start-BackgroundJob {
    # Cancel existing background job if running
    if ($global:flare_promptState.BackgroundJob) {
        if ($global:flare_promptState.BackgroundJob.State -eq 'Running') {
            $global:flare_promptState.BackgroundJob | Stop-Job -Force -ErrorAction SilentlyContinue
        }
        $global:flare_promptState.BackgroundJob | Remove-Job -Force -ErrorAction SilentlyContinue
        $global:flare_promptState.BackgroundJob = $null
    }
    
    # Start single background job for all pieces
    $global:flare_promptState.BackgroundJob = Start-ThreadJob -Name "Flare-Background" -ScriptBlock {
        param($backgroundPieces, $resultCache)
        . $using:PSScriptRoot/utils/invokeUtils.ps1
        
        # Process all background pieces
        foreach ($pieceName in $backgroundPieces) {
            $result = Invoke-FlarePiece -PieceName $pieceName -PiecesPath $using:PSScriptRoot/pieces
            $resultCache[$pieceName] = $result
        }
        
        return 'background'
    } -ArgumentList $global:flare_promptState.BackgroundPieces, $global:flare_promptState.ResultCache
}

function Update-BackgroundThreadPieces {
    Initialize-PieceCollections

    # Only start job if not already running
    if (-not $global:flare_promptState.BackgroundJob -or 
        $global:flare_promptState.BackgroundJob.State -ne 'Running') {
        Start-BackgroundJob
    }
}
        $existingJob | Remove-Job -Force -ErrorAction SilentlyContinue
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

function Get-StyleForIndex {
    param([int]$Index, [int]$Count)
    
    $cacheKey = "$Index-$Count"
    if ($global:flare_promptState.StyleCache.ContainsKey($cacheKey)) {
        return $global:flare_promptState.StyleCache[$cacheKey]
    }
    
    $backgroundIndex = ($backgroundStyles.Count - $Count) % $backgroundStyles.Count
    $foregroundIndex = ($foregroundStyles.Count - $(if (($Count - 1) -gt 0) { $Count - 1 } else { $Count })) % $foregroundStyles.Count
    $separatorIndex = ($foregroundStyles.Count - $(if (($Count - 1) -gt 0) { $Count - 1 } else { $Count })) % $foregroundStyles.Count
    
    $style = @{
        Background     = $backgroundStyles.Values[$backgroundIndex]
        Foreground     = $foregroundStyles['brightBlack']
        SeparatorColor = $foregroundStyles.Values[$separatorIndex]
    }
    
    $global:flare_promptState.StyleCache[$cacheKey] = $style
    return $style
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
            $style = Get-StyleForIndex -Index $count -Count $count
            $separator = "$($style.SeparatorColor)$(if (($count - 1) -gt 0) { "$($style.Background)$global:flare_promptSeparatorsLeft" } else { "$global:flare_promptTailLeft" })"
            $left += "$separator$($style.Background)$($style.Foreground) "
            
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
            $style = Get-StyleForIndex -Index $count -Count $count
            $separator = "$($style.SeparatorColor)$(if (($count - 1) -gt 0) { "$($style.Background)$global:flare_promptSeparatorsRight" } else { "$($backgroundStyles['default'])$global:flare_promptTailRight" })"
            $right = "$pieceResult $separator$right"
            
            $icon = Get-Variable -Name "flare_icons_$pieceName" -Scope Global -ValueOnly -ErrorAction SilentlyContinue
            if ($icon) {
                $right = "$icon $right"
            }
            $right = "$($style.Background)$($style.Foreground) $right"
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
    Initialize-PieceCollections
    
    # Combine main thread pieces with fast fallbacks for uncached background pieces
    $piecesToCalculate = [System.Collections.Generic.List[string]]::new($global:flare_promptState.MainThreadPieces)
    
    foreach ($piece in $global:flare_promptState.BackgroundPieces) {
        if (-not $global:flare_promptState.ResultCache.ContainsKey($piece)) {
            $piecesToCalculate.Add("${piece}_fast")
        }
    }

    if ($piecesToCalculate.Count -eq 0) { return }
    
    $mainThreadResults = Get-PromptPieceResults -Pieces $piecesToCalculate

    foreach ($piece in $piecesToCalculate) {
        if ($piece -like '*_fast') {
            $actualPiece = $piece -replace '_fast', ''
            # Fast results are only valid when we don't have a cached actual result
            if (-not $global:flare_promptState.ResultCache.ContainsKey($actualPiece)) {
                $global:flare_promptState.ResultCache[$actualPiece] = $mainThreadResults[$piece]
            }
        }
        else {
            $global:flare_promptState.ResultCache[$piece] = $mainThreadResults[$piece]
        }
    }
}

function Update-BackgroundThreadPieces {
    Initialize-PieceCollections

    foreach ($piece in $global:flare_promptState.BackgroundPieces) {
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

    # Convert ConcurrentDictionary to Hashtable for type compatibility
    $results = @{}
    foreach ($key in $global:flare_promptState.ResultCache.Keys) {
        $results[$key] = $global:flare_promptState.ResultCache[$key]
    }

    $left = Get-LeftPrompt -Parts $results
    $right = Get-RightPrompt -Parts $results

    # Cache the regex-stripped lengths to avoid recalculation
    $leftLength = ($left -replace $escapeRegex).Length
    $rightLength = ($right -replace $escapeRegex).Length
    $totalLength = $leftLength + $rightLength
    
    # Calculate spacing
    $spaces = $Host.UI.RawUI.WindowSize.Width - $totalLength
    if ($spaces -lt 0) { $spaces = 0 }

    "$left$defaultStyle$(' ' * $spaces)$right"
}

Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    # Early exit if no background job
    if (-not $global:flare_promptState.BackgroundJob) {
        return
    }

    # Check if background job is completed
    if ($global:flare_promptState.BackgroundJob.State -ne 'Running') {
        # Clean up completed background job
        $null = Wait-Job -Job $global:flare_promptState.BackgroundJob -ErrorAction SilentlyContinue
        $null = Receive-Job -Job $global:flare_promptState.BackgroundJob -ErrorAction SilentlyContinue
        Remove-Job -Job $global:flare_promptState.BackgroundJob -Force -ErrorAction SilentlyContinue
        $global:flare_promptState.BackgroundJob = $null

        # Check if we need to redraw based on hash comparison
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
    Get-EventSubscriber | Where-Object { $_.SourceIdentifier -eq 'PowerShell.OnIdle' } | Unregister-Event
    # Clean up background job if running
    if ($global:flare_promptState.BackgroundJob) {
        $global:flare_promptState.BackgroundJob | Stop-Job -Force -ErrorAction SilentlyContinue
        $global:flare_promptState.BackgroundJob | Remove-Job -Force -ErrorAction SilentlyContinue
        $global:flare_promptState.BackgroundJob = $null
    }
}

function Prompt {
    # Check for directory changes and clear cache if needed
    if ($global:flare_promptState.LastDirectory -and 
        $PWD.Path -ne $global:flare_promptState.LastDirectory.Path) {
        $global:flare_promptState.ResultCache.Clear()
        $global:flare_promptState.LastRenderHash = $null
        $global:flare_promptState.StyleCache.Clear()
        # Reset piece collections to force recalculation
        $global:flare_promptState.AllPieces = $null
        $global:flare_promptState.BackgroundPieces = $null
        $global:flare_promptState.MainThreadPieces = $null
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

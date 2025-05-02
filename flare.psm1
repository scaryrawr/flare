. $PSScriptRoot/promptSymbols.ps1

# Shared dictionary for background job to store results
$global:flare_resultCache = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()

# Cache for what was last rendered, to be used to compare with result cache
$global:flare_lastRenderCache = @{}

# Items we can calculate on the main thread, but should also ignore when comparing changes from the background job
$global:flare_mainThread = @('os', 'date', 'lastCommand', 'pwd')

$global:flare_backgroundJob = $null

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
    $mainThreadPieces += $allPieces | Where-Object { $_ -notin $global:flare_mainThread } | ForEach-Object { "${_}_fast" }
    $mainThreadResults = Get-PromptPieceResults -Pieces $mainThreadPieces

    foreach ($piece in $mainThreadPieces) {
        # Support "fast" versions of pieces when there's no cache data available
        if ($piece -like '*_fast') {
            $pieceFast = $piece
            $piece = $piece -replace '_fast', ''
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
    if ($global:flare_backgroundJob) {
        Stop-Job -Job $global:flare_backgroundJob -ErrorAction SilentlyContinue
        Remove-Job -Job $global:flare_backgroundJob -ErrorAction SilentlyContinue
    }

    $global:flare_backgroundJob = Start-ThreadJob -Name 'Flare Background Update' -ScriptBlock {
        param($pieces, $results, $defaultRunspace)
        Write-Output "Updating background pieces: $pieces"
        . $using:PSScriptRoot/utils/invokeUtils.ps1

        $piecesResults = Get-PromptPieceResults -Pieces $pieces -PiecesPath $using:PSScriptRoot/pieces
        foreach ($piece in $pieces) {
            Write-Output "Piece: $piece, Result: $($piecesResults[$piece])"
            $results[$piece] = $piecesResults[$piece]
        }
    } -ArgumentList $backgroundThreadPieces, $global:flare_resultCache, $mainRunspace
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
        $results[$piece] = $global:flare_resultCache[$piece]
    }

    $left = Get-LeftPrompt -Parts $results
    $right = Get-RightPrompt -Parts $results

    # Figure out spacing between left and right prompts
    # Get the window width and subtract the current cursor position
    $width = $Host.UI.RawUI.WindowSize.Width - $Host.UI.RawUI.CursorPosition.X
    $spaces = $width - ($($left -replace $escapeRegex).Length + $($right -replace $escapeRegex).Length)

    # Ensure spaces is not negative
    if ($spaces -lt 0) { $spaces = 0 }

    "$left$defaultStyle$(' ' * $spaces)$right"
}

Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    # No need to refresh while the job is running, or if there was no background job
    if (-not $global:flare_backgroundJob -or (($global:flare_backgroundJob -and $global:flare_backgroundJob.State -eq 'Running'))) {
        return
    }

    $null = Wait-Job -Job $global:flare_backgroundJob -ErrorAction SilentlyContinue
    $null = Remove-Job -Job $global:flare_backgroundJob -Force -ErrorAction SilentlyContinue

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

# Register a cleanup event handler for when the module is removed
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    Get-EventSubscriber | Unregister-Event
    if ($global:flare_backgroundJob) {
        Stop-Job -Job $global:flare_backgroundJob -Force -ErrorAction SilentlyContinue
    }
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

    "$topLine`n$line "
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

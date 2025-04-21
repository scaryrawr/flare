. $PSScriptRoot/promptSymbols.ps1

# Cache variables for prompt pieces
$script:cachedLeftPrompt = $null
$script:cachedRightPrompt = $null
$script:isCalculating = $false
$script:needsRedraw = $false

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

$flare_leftPieces | ForEach-Object {
    . "$PSScriptRoot/pieces/$_.ps1"
}

function Get-LeftPrompt {
    # If immediate mode is requested, always calculate
    param([switch]$NoCache)
    
    # Return cached prompt if available and not explicitly bypassing cache
    if (-not $NoCache -and $script:cachedLeftPrompt -and -not $script:needsRedraw) {
        return $script:cachedLeftPrompt
    }
    
    $leftPieces = $flare_leftPieces | ForEach-Object {
        try {
            $command = "flare_$_"
            & $command -ErrorAction SilentlyContinue
        }
        catch {
            return ""
        }
    } | Where-Object { $_ }
    
    $left = "${flare_topPrefix}"

    $count = 1
    foreach ($piece in $leftPieces) {
        $background = $backgroundStyles.Values[($backgroundStyles.Count - $count) % $backgroundStyles.Count]
        $foreground = $foregroundStyles['brightBlack']
        $separatorColor = $foregroundStyles.Values[($foregroundStyles.Count - $(if (($count - 1) -gt 0) { $count - 1 } else { $count })) % $foregroundStyles.Count]
        $separator = "$separatorColor$(if (($count - 1) -gt 0) { "$background$flare_promptSeparatorsLeft" } else { "$flare_promptTailLeft" })"
        $left += "$separator$background$foreground $piece "
        $count += 1
    }

    $foreground = $foregroundStyles.Values[($foregroundStyles.Count - ($count - 1)) % $foregroundStyles.Count]
    $left += "$($backgroundStyles['default'])$foreground$flare_promptHeadLeft"

    # Cache the left prompt if we're doing a full calculation (not a quick default)
    if (-not $NoCache) {
        $script:cachedLeftPrompt = $left
    }

    $left
}

$flare_rightPieces | ForEach-Object {
    . "$PSScriptRoot/pieces/$_.ps1"
}

function Get-RightPrompt {
    # If immediate mode is requested, always calculate
    param([switch]$NoCache)
    
    # Return cached prompt if available and not explicitly bypassing cache
    if (-not $NoCache -and $script:cachedRightPrompt -and -not $script:needsRedraw) {
        return $script:cachedRightPrompt
    }
    
    $rightPieces = $flare_rightPieces | ForEach-Object {
        try {
            $command = "flare_$_"
            & $command -ErrorAction SilentlyContinue
        }
        catch {
            return ""
        }
    } | Where-Object { $_ }
    
    $right = ""
    $count = 1
    foreach ($piece in $rightPieces) {
        $background = $backgroundStyles.Values[($backgroundStyles.Count - $count) % $backgroundStyles.Count]
        $foreground = $foregroundStyles['brightBlack']
        $separatorColor = $foregroundStyles.Values[($foregroundStyles.Count - $(if (($count - 1) -gt 0) { $count - 1 } else { $count })) % $foregroundStyles.Count]
        $separator = "$separatorColor$(if (($count - 1) -gt 0) { "$background$flare_promptSeparatorsRight" } else { "$($backgroundStyles['default'])$flare_promptTailRight" })"
        $right = "$background$foreground $piece $separator$right"
        $count += 1
    }

    $foreground = $foregroundStyles.Values[($foregroundStyles.Count - ($count - 1)) % $foregroundStyles.Count]
    $right = "$($backgroundStyles['default'])$foreground$flare_promptSeparatorsRight$right"

    # Cache the right prompt if we're doing a full calculation (not a quick default)
    if (-not $NoCache) {
        $script:cachedRightPrompt = $right
    }

    $right
}

function Get-PromptLine {
    return "$defaultStyle$flare_bottomPrefix$($foregroundStyles['brightGreen'])$($flare_promptArrow * ($nestedPromptLevel + 1))$defaultStyle"
}

function Prompt {
    # First time or when redraw is needed, use cached values (or lightweight defaults if no cache)
    $useCache = -not $script:needsRedraw
    $left = Get-LeftPrompt -NoCache:(-not $useCache)
    $right = Get-RightPrompt -NoCache:(-not $useCache)

    $line = Get-PromptLine

    # Figure out spacing between left and right prompts
    $width = $Host.UI.RawUI.WindowSize.Width
    $spaces = $width - ($($left -replace $escapeRegex).Length + $($right -replace $escapeRegex).Length)
    
    # Ensure spaces is not negative
    if ($spaces -lt 0) { $spaces = 0 }

    # Schedule async calculation and redraw if not currently calculating
    if (-not $script:isCalculating) {
        $script:isCalculating = $true
        $script:needsRedraw = $true
        
        # Register our idle callback to calculate and redraw the prompt
        Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
            try {
                # Calculate new prompt pieces in the background
                $newLeft = Get-LeftPrompt -NoCache
                $newRight = Get-RightPrompt -NoCache
                
                # Only redraw if the prompt has changed
                $currentLeft = $script:cachedLeftPrompt
                $currentRight = $script:cachedRightPrompt
                
                if ($currentLeft -ne $newLeft -or $currentRight -ne $newRight) {
                    # Update the cached values
                    $script:cachedLeftPrompt = $newLeft
                    $script:cachedRightPrompt = $newRight
                    
                    # Force the prompt to redraw with new values
                    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
                }
            }
            finally {
                $script:isCalculating = $false
                $script:needsRedraw = $false
            }
        } | Out-Null
    }

    "$left$defaultStyle$(' ' * $spaces)$right`n$line "
}

# Force a prompt recalculation on the next prompt display
function Reset-FlarePromptCache {
    $script:needsRedraw = $true
    $script:isCalculating = $false
}

# Register handler to reset prompt cache after command execution
$ExecutionContext.SessionState.Module.OnRemove = {
    Remove-Module PSReadLine
}

# Hook into PSReadLine to reset prompt cache after command execution
$scriptBlock = {
    param($key, $arg)
    # Force recalculation on next prompt
    Reset-FlarePromptCache
    # Call original AcceptLine
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

# Add module exports
Export-ModuleMember -Function @('Prompt', 'Reset-FlarePromptCache')

# Use Set-PSReadLineKeyHandler to clear the prompt and rewrite the user's input when the user submits a command
Set-PSReadLineKeyHandler -Key Enter -BriefDescription "Clear prompt and rewrite input on Enter" -ScriptBlock {
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
    [System.Console]::Write(" " * $consoleWidth * 2)
    [System.Console]::SetCursorPosition(0, [System.Console]::CursorTop - 1)

    # Rewrite the user's input prefixed with '>'
    Write-Host "$(Get-PromptLine) $($inputLine -join '')" -NoNewline

    # Reset the prompt cache to force recalculation on next display
    Reset-FlarePromptCache

    # Execute the command by invoking the default Enter key behavior
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

. $PSScriptRoot/promptSymbols.ps1

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

# Store pieces that have been initialized for cleanup later
$script:initializedPieces = @()

@($flare_leftPieces, $flare_rightPieces) | ForEach-Object {
    $_ | ForEach-Object {
        . "$PSScriptRoot/pieces/$_.ps1"
        if (Get-Command "flare_init_$_" -ErrorAction SilentlyContinue) {
            & "flare_init_$_"
            $script:initializedPieces += $_
        }
    }
}

# Register a cleanup event that runs when the module is removed
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    # Call cleanup functions for each piece that was initialized
    foreach ($piece in $script:initializedPieces) {
        if (Get-Command "flare_cleanup_$piece" -ErrorAction SilentlyContinue) {
            & "flare_cleanup_$piece"
        }
    }
}

function Invoke-FlarePiece {
    param(
        [string]$PieceName
    )
    try {
        $command = "flare_$PieceName"
        $result = $null
        $timing = $null
        $timing = [System.Diagnostics.Stopwatch]::StartNew()
        $result = & $command -ErrorAction SilentlyContinue
        $timing.Stop()
        if ($global:flare_includeTime) {
            if ($result -ne '') {
                $elapsed = [math]::Round($timing.Elapsed.TotalMilliseconds, 2)
                return "$result ($elapsed ms)"
            }
            else {
                return ''
            }
        }
        else {
            return $result
        }
    }
    catch {
        return ''
    }
}

function Get-LeftPrompt {
    $leftPieces = $flare_leftPieces | ForEach-Object {
        Invoke-FlarePiece $_
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

    return $left
}

function Get-RightPrompt {
    $rightPieces = $flare_rightPieces | ForEach-Object {
        Invoke-FlarePiece $_
    } | Where-Object { $_ }
    
    $right = ''
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

    return $right
}

function Get-PromptLine {
    return "$defaultStyle$flare_bottomPrefix$($foregroundStyles['brightGreen'])$($flare_promptArrow * ($nestedPromptLevel + 1))$defaultStyle"
}

function Prompt {
    $left = Get-LeftPrompt
    $right = Get-RightPrompt

    $line = Get-PromptLine

    # Figure out spacing between left and right prompts
    $width = $Host.UI.RawUI.WindowSize.Width
    $spaces = $width - ($($left -replace $escapeRegex).Length + $($right -replace $escapeRegex).Length)
    
    # Ensure spaces is not negative
    if ($spaces -lt 0) { $spaces = 0 }

    "$left$defaultStyle$(' ' * $spaces)$right`n$line "
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

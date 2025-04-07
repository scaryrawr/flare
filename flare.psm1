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

function Get-LeftPrompt {
    $leftPieces = ${flare_leftPieces} | ForEach-Object {
        try {
            & "$PSScriptRoot/pieces/$_.ps1" -ErrorAction SilentlyContinue
        }
        catch {
            return ""
        }
    } | Where-Object { $_ }

    $left = "${flare_topPrefix}"

    $count = 1
    foreach ($piece in $leftPieces) {
        $background = $backgroundStyles.Values[($backgroundStyles.Count - $count) % $backgroundStyles.Count]
        $foreground = $foregroundStyles['brightBlack']#$foregroundStyles.Values[$count % $foregroundStyles.Count]

        $separatorColor = $foregroundStyles.Values[($foregroundStyles.Count - $(if (($count - 1) -gt 0) { $count - 1 } else { $count })) % $foregroundStyles.Count]
        $separator = "$separatorColor$(if (($count - 1) -gt 0) { "$background$flare_promptSeparatorsLeft" } else { "$flare_promptTailLeft" })"

        $left += "$separator$background$foreground $piece "
        $count += 1
    }

    $foreground = $foregroundStyles.Values[($foregroundStyles.Count - ($count - 1)) % $foregroundStyles.Count]
    $left += "$($backgroundStyles['default'])$foreground$flare_promptHeadLeft"

    $left
}

function Get-RightPrompt {
    $rightPieces = ${flare_rightPieces} | ForEach-Object {
        try {
            & "$PSScriptRoot/pieces/$_.ps1" -ErrorAction SilentlyContinue
        }
        catch {
            return ""
        }
    } | Where-Object { $_ }

    $right = ""
    $count = 1
    foreach ($piece in $rightPieces) {
        $background = $backgroundStyles.Values[($backgroundStyles.Count - $count) % $backgroundStyles.Count]
        $foreground = $foregroundStyles['brightBlack']#$foregroundStyles.Values[$count % $foregroundStyles.Count]

        $separatorColor = $foregroundStyles.Values[($foregroundStyles.Count - $(if (($count - 1) -gt 0) { $count - 1 } else { $count })) % $foregroundStyles.Count]
        $separator = "$separatorColor$(if (($count - 1) -gt 0) { "$background$flare_promptSeparatorsRight" } else { "$($backgroundStyles['default'])$flare_promptTailRight" })"

        $right = "$background$foreground $piece $separator$right"
        $count += 1
    }

    $foreground = $foregroundStyles.Values[($foregroundStyles.Count - ($count - 1)) % $foregroundStyles.Count]
    $right = "$($backgroundStyles['default'])$foreground$flare_promptSeparatorsRight$right"

    $right
}

function Get-PromptLine {
    return "$defaultStyle$flare_bottomPrefix$($foregroundStyles['brightGreen'])$($flare_promptArrow * ($nestedPromptLevel + 1))$defaultStyle"
}

function Prompt {
    $left = Get-LeftPrompt
    $right = "$(Get-RightPrompt)"
    $line = Get-PromptLine

    # Figure out spacing between left and right prompts
    $width = $Host.UI.RawUI.WindowSize.Width
    $spaces = $width - ($($left -replace $escapeRegex).Length + $($right -replace $escapeRegex).Length)

    "$left$defaultStyle$(' ' * $spaces)$right`n$line "
}

# Use Set-PSReadLineKeyHandler to clear the prompt and rewrite the user's input when the user submits a command
Set-PSReadLineKeyHandler -Key Enter -BriefDescription "Clear prompt and rewrite input on Enter" -ScriptBlock {
    # Prepare references for the input line and cursor position
    $inputLineRef = [ref]''
    $cursorPositionRef = [ref]0

    # Retrieve the current input from the command line buffer using GetBufferState
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState($inputLineRef, $cursorPositionRef)
    $inputLine = $inputLineRef.Value

    # Move the cursor up by two lines to clear the two-line prompt
    [System.Console]::SetCursorPosition(0, [System.Console]::CursorTop - 1)

    # Get the console width to overwrite the lines with spaces
    $consoleWidth = [System.Console]::BufferWidth

    # Clear the current line and the next line by overwriting with spaces
    [System.Console]::Write(" " * $consoleWidth * 2)
    #[System.Console]::Write(" " * $consoleWidth)
    [System.Console]::SetCursorPosition(0, [System.Console]::CursorTop - 1)

    # Rewrite the user's input prefixed with '>'
    Write-Host "$(Get-PromptLine) $($inputLine -join '')" -NoNewline

    # Execute the command by invoking the default Enter key behavior
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

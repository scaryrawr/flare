. $PSScriptRoot/promptSymbols.ps1
. $PSScriptRoot/git.ps1

function Get-GitBranch {
    $branch = git --no-optional-locks rev-parse --abbrev-ref HEAD 2> $null
    if ($branch) {
        return "$flare_gitIcon $branch $(Get-GitStatus)"
    }
    else {
        return ""
    }
}

function Get-LastCommandTime {
    $lastCommand = Get-History -Count 1
    if (-not $lastCommand) { return "" }

    $totalTime = ($lastCommand.EndExecutionTime - $lastCommand.StartExecutionTime)
    $seconds = $totalTime.TotalSeconds
    if ($seconds -lt 0.25) { return "" }

    if ($seconds -lt 60) {
        return $seconds.ToString("F2") + " s"
    }

    $minutes = [math]::Floor($seconds / 60)
    $seconds = $seconds % 60
    if ($minutes -lt 60) {
        return "${minutes}m $($seconds.ToString('F2'))s"
    }

    $hours = [math]::Floor($minutes / 60)
    $minutes = $minutes % 60

    return "${hours}h ${minutes}m $($seconds.ToString('F2'))s"
}

$defaultStyle = "`e[0m"
$foregroundStyles = [ordered]@{
    'default'       = "`e[39m"
    'black'         = "`e[30m"
    'red'           = "`e[31m"
    'green'         = "`e[32m"
    'yellow'        = "`e[33m"
    'blue'          = "`e[34m"
    'magenta'       = "`e[35m"
    'cyan'          = "`e[36m"
    'white'         = "`e[37m"
    'brightBlack'   = "`e[90m"
    'brightRed'     = "`e[91m"
    'brightGreen'   = "`e[92m"
    'brightYellow'  = "`e[93m"
    'brightBlue'    = "`e[94m"
    'brightMagenta' = "`e[95m"
    'brightCyan'    = "`e[96m"
    'brightWhite'   = "`e[97m"
}

$backgroundStyles = [ordered]@{
    'default'       = "`e[49m"
    'black'         = "`e[40m"
    'red'           = "`e[41m"
    'green'         = "`e[42m"
    'yellow'        = "`e[43m"
    'blue'          = "`e[44m"
    'magenta'       = "`e[45m"
    'cyan'          = "`e[46m"
    'white'         = "`e[47m"
    'brightBlack'   = "`e[100m"
    'brightRed'     = "`e[101m"
    'brightGreen'   = "`e[102m"
    'brightYellow'  = "`e[103m"
    'brightBlue'    = "`e[104m"
    'brightMagenta' = "`e[105m"
    'brightCyan'    = "`e[106m"
    'brightWhite'   = "`e[107m"
}

$flare_dateFormat ??= 'HH:mm:ss'

$escapeRegex = "(`e\[\d+\w)"

function Get-LeftPrompt {
    $leftPieces = @(
        "$flare_osIcon"
        "$($executionContext.SessionState.Path.CurrentLocation.ToString().Replace($HOME, '~'))"
        "$(Get-GitBranch)"
    ) | Where-Object { $_ }

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
    $rightPieces = @(
        "$(Get-Date -Format $flare_dateFormat)"
        "$(Get-LastCommandTime)"
    ) | Where-Object { $_ }

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

function Prompt {
    $left = Get-LeftPrompt
    $right = "$(Get-RightPrompt)"
    $line = "$defaultStyle$flare_bottomPrefix$($foregroundStyles.brightGreen)$($flare_promptArrow * ($nestedPromptLevel + 1))$defaultStyle"

    # Figure out spacing between left and right prompts
    $width = $Host.UI.RawUI.WindowSize.Width
    $spaces = $width - ($($left -replace $escapeRegex).Length + $($right -replace $escapeRegex).Length)

    "$left$defaultStyle$(' ' * $spaces)$right`n$line "
}

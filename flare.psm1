$flare_promptSeparatorsLeft ??= ""
$flare_promptHeadLeft ??= ""
$flare_promptTailLeft ??= "░▒▓"
$flare_promptSeparatorsRight ??= ""
$flare_promptHeadRight ??= ""
$flare_promptTailRight ??= "▓▒░"
$flare_gitIcon ??= ""

function Get-LinuxDistro {
    $distro = "$(grep '^ID=' /etc/*release | cut -d'=' -f2)".Trim().ToLower();
    if ($distro) {
        return $distro;
    }
    else {
        return "Linux";
    }
}

function Get-OSIcon {
    if ($IsWindows) { return "" }
    if ($IsMacOS) { return "" }
    if ($IsLinux) {
        switch ($(Get-LinuxDistro)) {
            "arch" { return "" }
            "debian" { return "" }
            "fedora" { return "" }
            "gentoo" { return "" }
            "ubuntu" { return "" }
            Default { return "" }
        }
    }

    return ""
}

function Get-GitBranch {
    $branch = git rev-parse --abbrev-ref HEAD 2> $null;
    if ($branch) {
        return "$flare_gitIcon $branch";
    }
    else {
        return "";
    }
}

function Get-LastCommandTime {
    $lastCommand = Get-History -Count 1;
    if (-not $lastCommand) { return "" }

    $seconds = ($lastCommand.EndExecutionTime - $lastCommand.StartExecutionTime).TotalSeconds
    if ($seconds -lt 0.25) { return "" }

    $seconds.ToString("F2") + "s";
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

$flare_osIcon ??= "$(Get-OSIcon)";
$flare_topPrefix ??= "╭─";
$flare_bottomPrefix ??= "╰─";
$flare_promptArrow ??= "";
$flare_dateFormat ??= 'HH:mm:ss';

$escapeRegex = "(`e\[\d+\w)"

function Get-LeftPrompt {
    $leftPieces = @(
        "$flare_osIcon"
        "$($executionContext.SessionState.Path.CurrentLocation)"
        "$(Get-GitBranch)"
    );

    $left = "${flare_topPrefix}";

    $count = 1;
    foreach ($piece in $leftPieces) {
        $background = $backgroundStyles.Values[($backgroundStyles.Count - $count) % $backgroundStyles.Count];
        $foreground = $foregroundStyles.Values[$count % $foregroundStyles.Count];

        $separatorColor = $foregroundStyles.Values[($foregroundStyles.Count - $(if (($count - 1) -gt 0) { $count - 1 } else { $count })) % $foregroundStyles.Count];
        $separator = "$separatorColor$(if (($count - 1) -gt 0) { "$background$flare_promptSeparatorsLeft" } else { "$flare_promptTailLeft" })";

        if (! $piece) {
            continue;
        }

        $left += "$separator$background$foreground$piece";
        $count += 1;
    }

    $foreground = $foregroundStyles.Values[($foregroundStyles.Count - ($count - 1)) % $foregroundStyles.Count];
    $left += "$($backgroundStyles['default'])$foreground$flare_promptHeadLeft";

    $left;
}
function Prompt {
    $left = Get-LeftPrompt;
    $right = "$(Get-LastCommandTime) $(Get-Date -Format $flare_dateFormat)";
    $line = "$defaultStyle$flare_bottomPrefix$($foregroundStyles.brightGreen)$($flare_promptArrow * ($nestedPromptLevel + 1))$defaultStyle";

    # Figure out spacing between left and right prompts
    $width = $Host.UI.RawUI.WindowSize.Width;
    $spaces = $width - ($($left -replace $escapeRegex).Length + $($right -replace $escapeRegex).Length);

    "$left$defaultStyle$(' ' * $spaces)$right`n$line ";
}

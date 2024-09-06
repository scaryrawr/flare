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

function Get-LastCommandTime {
    $lastCommand = Get-History -Count 1;
    if (-not $lastCommand) { return "" }

    $seconds = ($lastCommand.EndExecutionTime - $lastCommand.StartExecutionTime).TotalSeconds
    if ($seconds -lt 0.25) { return "" }

    $seconds.ToString("F2") + "s";
}

$colors = [enum]::GetValues([System.ConsoleColor])
$flare_promptSeparatorsLeft = "▶"
$flare_promptHeadLeft = "▶"
$flare_promptTailLeft = "◖"
$flare_promptSeparatorsRight = "◀"
$flare_promptHeadRight = "◀"
$flare_promptTailRight = "◗"

$flare_osIcon ??= "$(Get-OSIcon)";
$flare_topPrefix ??= "╭─";
$flare_bottomPrefix ??= "╰─";
$flare_promptArrow ??= "";
$flare_dateFormat ??= 'HH:mm:ss';
function Prompt {
    $left = "${flare_topPrefix} ${flare_osIcon} $($executionContext.SessionState.Path.CurrentLocation)";
    $right = "$(Get-LastCommandTime)$(Get-Date -Format $flare_dateFormat)";
    $line = "${flare_bottomPrefix}$(${flare_promptArrow} * ($nestedPromptLevel + 1))";
    $width = $Host.UI.RawUI.WindowSize.Width;
    $spaces = $width - ($left.Length + $right.Length);
    "$left$(' ' * $spaces)$right`n$line ";
}

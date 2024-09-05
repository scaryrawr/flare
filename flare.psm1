$ConfigRoot = $env:XDG_CONFIG_HOME ?? $env:LOCAL_APP_DATA ?? "$env:HOME/.cache";
$ConfigDir = "$ConfigRoot/flare";
$ConfigFile = "$ConfigDir/flare.ps1";

if (Test-Path $ConfigFile) {
    . $ConfigFile;
}

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

function Prompt {  
    "$(Get-OSIcon) $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "  
}

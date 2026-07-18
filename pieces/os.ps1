<#
.SYNOPSIS
Gets the normalized Linux distribution identifier.
.OUTPUTS
System.String
#>
function Get-LinuxDistro {
  $script:distro ??= "$(grep '^ID=' /etc/*release | cut -d'=' -f2)".Trim().ToLower()
  if ($script:distro) {
    return $script:distro
  }
  else {
    return "Linux"
  }
}


<#
.SYNOPSIS
Shows the icon for the current operating system or Linux distribution.
.OUTPUTS
System.String
#>
function flare_os {
  if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') { return "" }
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

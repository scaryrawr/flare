function Get-OSIcon {
  if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') { return "" }
  if ($IsMacOS) { return "" }
  if ($IsLinux) {
    . $PSScriptRoot/linux/distro.ps1
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
function Get-LinuxDistro {
  $distro = "$(grep '^ID=' /etc/*release | cut -d'=' -f2)".Trim().ToLower()
  if ($distro) {
    return $distro
  }
  else {
    return "Linux"
  }
}


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

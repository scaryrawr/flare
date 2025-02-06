function Get-LinuxDistro {
  $distro = "$(grep '^ID=' /etc/*release | cut -d'=' -f2)".Trim().ToLower()
  if ($distro) {
    return $distro
  }
  else {
    return "Linux"
  }
}

Export-ModuleMember -Function Get-LinuxDistro
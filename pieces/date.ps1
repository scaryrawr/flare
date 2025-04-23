function flare_date {
  $global:flare_dateFormat ??= 'HH:mm:ss'
  return Get-Date -Format $global:flare_dateFormat
}
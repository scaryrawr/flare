function flare_date {
  $flare_dateFormat ??= 'HH:mm:ss'
  return Get-Date -Format $flare_dateFormat
}
function flare_lastCommand {
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

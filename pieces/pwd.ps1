function flare_pwd {
  $currentPath = $executionContext.SessionState.Path.CurrentLocation.ToString()
  $userHome = [Environment]::GetFolderPath('UserProfile')
  
  # Replace home path with ~
  if ($currentPath.StartsWith($userHome)) {
    $currentPath = $currentPath.Replace($userHome, '~')
  }
  
  $sep = [System.IO.Path]::DirectorySeparatorChar
  
  # Split the path and handle empty parts (from absolute paths)
  $parts = if ($currentPath.StartsWith($sep)) {
    @('') + ($currentPath.Substring(1) -split [regex]::Escape($sep))
  }
  else {
    $currentPath -split [regex]::Escape($sep)
  }
  
  # Process path parts with pipeline
  $result = $parts | ForEach-Object -Begin { $i = 0 } -Process {
    $part = $_
    $isLastPart = ($i -eq $parts.Count - 1)
    $i++
    
    if ($part -eq '' -and $i -eq 1) {
      return $sep  # Root directory for absolute paths
    }
    elseif ($part -eq '~') {
      return '~'
    }
    elseif ($isLastPart) {
      return $part  # Keep the final directory name intact
    }
    elseif ($part -ne '') {
      return $part[0]  # First character of parent directories
    }
  }
  
  # Join the parts back together
  $result -join $sep
}
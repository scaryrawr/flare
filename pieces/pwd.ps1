function flare_pwd {
  $currentPath = $executionContext.SessionState.Path.CurrentLocation.ToString()
  $userHome = [Environment]::GetFolderPath('UserProfile')
  
  # Replace home path with ~
  $currentPath = $currentPath.Replace($userHome, '~')
  
  # Split the path and handle empty parts (from absolute paths)
  $parts = $currentPath -split [regex]::Escape([System.IO.Path]::DirectorySeparatorChar)
  
  # Process path parts with pipeline
  $i = 0
  $result = $parts | ForEach-Object {
    $part = $_
    $isLastPart = ($i -eq $parts.Count - 1)
    $i++
    
    if ($isLastPart) {
      return $part  # Keep the final directory name intact
    }
    else {
      return $part[0]  # First character of parent directories
    }
  }
  
  # Join the parts back together
  " $($result -join [System.IO.Path]::DirectorySeparatorChar)"
}

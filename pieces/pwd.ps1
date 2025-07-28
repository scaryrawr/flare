function flare_pwd {
    try {
        # Use optimized path retrieval
        $currentPath = $executionContext.SessionState.Path.CurrentLocation.ToString()
        $userHome = [Environment]::GetFolderPath('UserProfile')
        
        # Replace home path with ~ for better readability
        if ($currentPath.StartsWith($userHome, [System.StringComparison]::OrdinalIgnoreCase)) {
            $currentPath = $currentPath.Replace($userHome, '~')
        }
        
        # Enhanced path shortening with better logic
        $separator = [System.IO.Path]::DirectorySeparatorChar
        $parts = $currentPath -split [regex]::Escape($separator) | Where-Object { $_ }
        
        if ($parts.Count -le 2) {
            # Short path, return as-is
            return $currentPath
        }
        
        # Use PowerShell pipeline for efficient processing
        $shortenedParts = for ($i = 0; $i -lt $parts.Count; $i++) {
            $part = $parts[$i]
            $isLastPart = ($i -eq $parts.Count - 1)
            $isSecondToLast = ($i -eq $parts.Count - 2)
            
            if ($isLastPart -or $isSecondToLast -or $part.EndsWith(':') -or $part -eq '~') {
                $part  # Keep important parts intact
            }
            else {
                # Shorten intermediate directories to first character
                if ($part.Length -gt 1) {
                    $part.Substring(0, 1)
                } else {
                    $part
                }
            }
        }
        
        # Reconstruct path with proper separator handling
        $result = $shortenedParts -join $separator
        
        # Handle root path cases
        if ($currentPath.StartsWith($separator) -and -not $result.StartsWith($separator)) {
            $result = $separator + $result
        }
        
        return $result
    }
    catch {
        # Robust fallback
        return $PWD.Path -replace [regex]::Escape($HOME), '~'
    }
}

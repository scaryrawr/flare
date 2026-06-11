. $PSScriptRoot/../utils/fileUtils.ps1

function Get-GitRepoInfo {
  param([string]$Path = (Get-Location))
  
  # Find .git (file or directory)
  $gitPath = FindFileInParentDirectories '.git' $Path
  if (-not $gitPath) {
    return @{ RepoPath = $null; GitDir = $null }
  }
  
  $repoPath = Split-Path -Parent $gitPath
  $gitDir = $gitPath
  
  # Handle worktrees/submodules where .git is a file
  if (Test-Path $gitPath -PathType Leaf) {
    try {
      $gitFileContent = Get-Content -Path $gitPath -Raw -ErrorAction Stop
      if ($gitFileContent -match 'gitdir:\s*(.+)') {
        $gitDir = $Matches[1].Trim()
        # Make relative paths absolute
        if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
          $gitDir = Join-Path $repoPath $gitDir
        }
      }
    }
    catch {
      return @{ RepoPath = $null; GitDir = $null }
    }
  }
  
  return @{ 
    RepoPath = $repoPath
    GitDir = $gitDir
  }
}

function Get-TagForCommit {
  param([string]$GitDir, [string]$CommitHash)
  
  try {
    # Check packed-refs first (most common)
    $packedRefs = Join-Path $GitDir 'packed-refs'
    if (Test-Path $packedRefs -PathType Leaf) {
      $packedContent = [System.IO.File]::ReadAllText($packedRefs)
      foreach ($line in $packedContent -split "`n") {
        if ($line.StartsWith($CommitHash) -and $line.Contains('refs/tags/')) {
          if ($line -match 'refs/tags/(.+)$') {
            return $Matches[1]
          }
        }
      }
    }
    
    # Check individual tag refs
    $tagsDir = Join-Path $GitDir 'refs/tags'
    if (Test-Path $tagsDir -PathType Container) {
      $tagFiles = Get-ChildItem $tagsDir -File -ErrorAction SilentlyContinue
      foreach ($tagFile in $tagFiles) {
        try {
          $tagContent = [System.IO.File]::ReadAllText($tagFile.FullName).Trim()
          if ($tagContent -eq $CommitHash) {
            return $tagFile.Name
          }
        }
        catch { continue }
      }
    }
  }
  catch { }
  
  return $null
}

function Get-GitOperationStatus {
  param([string]$GitDir)
  
  $operation = $null
  $step = $null
  $totalSteps = $null
  
  # Check rebase-merge (interactive rebase)
  $rebaseMerge = Join-Path $GitDir 'rebase-merge'
  if (Test-Path $rebaseMerge -PathType Container) {
    try {
      $stepFile = Join-Path $rebaseMerge 'msgnum'
      $totalFile = Join-Path $rebaseMerge 'end'
      if ((Test-Path $stepFile -PathType Leaf) -and (Test-Path $totalFile -PathType Leaf)) {
        $step = [System.IO.File]::ReadAllText($stepFile).Trim()
        $totalSteps = [System.IO.File]::ReadAllText($totalFile).Trim()
      }
      
      $interactive = Join-Path $rebaseMerge 'interactive'
      if (Test-Path $interactive -PathType Leaf) {
        $operation = 'rebase-i'
      } else {
        $operation = 'rebase-m'
      }
    }
    catch {
      $operation = 'rebase'
    }
  }
  # Check rebase-apply (am/rebase)
  elseif (Test-Path (Join-Path $GitDir 'rebase-apply') -PathType Container) {
    $rebaseApply = Join-Path $GitDir 'rebase-apply'
    try {
      $nextFile = Join-Path $rebaseApply 'next'
      $lastFile = Join-Path $rebaseApply 'last'
      if ((Test-Path $nextFile -PathType Leaf) -and (Test-Path $lastFile -PathType Leaf)) {
        $step = [System.IO.File]::ReadAllText($nextFile).Trim()
        $totalSteps = [System.IO.File]::ReadAllText($lastFile).Trim()
      }
      
      if (Test-Path (Join-Path $rebaseApply 'rebasing') -PathType Leaf) {
        $operation = 'rebase'
      } elseif (Test-Path (Join-Path $rebaseApply 'applying') -PathType Leaf) {
        $operation = 'am'
      } else {
        $operation = 'am/rebase'
      }
    }
    catch {
      $operation = 'rebase'
    }
  }
  # Check other operations
  elseif (Test-Path (Join-Path $GitDir 'MERGE_HEAD') -PathType Leaf) {
    $operation = 'merge'
  }
  elseif (Test-Path (Join-Path $GitDir 'CHERRY_PICK_HEAD') -PathType Leaf) {
    $operation = 'cherry-pick'
  }
  elseif (Test-Path (Join-Path $GitDir 'REVERT_HEAD') -PathType Leaf) {
    $operation = 'revert'
  }
  elseif (Test-Path (Join-Path $GitDir 'BISECT_LOG') -PathType Leaf) {
    $operation = 'bisect'
  }
  
  return @{
    Operation = $operation
    Step = $step
    TotalSteps = $totalSteps
  }
}

function Get-StashCount {
  param([string]$GitDir)
  
  try {
    $stashRef = Join-Path $GitDir 'refs/stash'
    if (Test-Path $stashRef -PathType Leaf) {
      return 1  # Basic detection - has stashes
    }
    
    # Check logs/refs/stash for more accurate count
    $stashLog = Join-Path $GitDir 'logs/refs/stash'
    if (Test-Path $stashLog -PathType Leaf) {
      $lines = [System.IO.File]::ReadAllLines($stashLog)
      return $lines.Length
    }
  }
  catch { }
  
  return 0
}

function Read-GitIndexUInt32 {
  param(
    [byte[]]$Bytes,
    [int]$Offset
  )

  return [uint32](
    ([uint32]$Bytes[$Offset] -shl 24) -bor
    ([uint32]$Bytes[$Offset + 1] -shl 16) -bor
    ([uint32]$Bytes[$Offset + 2] -shl 8) -bor
    [uint32]$Bytes[$Offset + 3]
  )
}

function Read-GitIndexUInt16 {
  param(
    [byte[]]$Bytes,
    [int]$Offset
  )

  return [uint16]((([uint16]$Bytes[$Offset]) -shl 8) -bor [uint16]$Bytes[$Offset + 1])
}

function Get-GitIndexEntries {
  param([string]$GitDir)

  $entries = @{}
  $indexPath = Join-Path $GitDir 'index'
  if (-not (Test-Path $indexPath -PathType Leaf)) {
    return $entries
  }

  try {
    $bytes = [System.IO.File]::ReadAllBytes($indexPath)
    if ($bytes.Length -lt 12) {
      return $entries
    }

    $signature = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
    $version = Read-GitIndexUInt32 $bytes 4
    if (($signature -ne 'DIRC') -or ($version -notin @(2, 3))) {
      return $entries
    }

    $count = Read-GitIndexUInt32 $bytes 8
    $offset = 12

    for ($i = 0; $i -lt $count; $i++) {
      $entryStart = $offset
      if ($offset + 62 -gt $bytes.Length) {
        break
      }

      $mtime = Read-GitIndexUInt32 $bytes ($offset + 8)
      $size = Read-GitIndexUInt32 $bytes ($offset + 36)
      $objectId = [System.BitConverter]::ToString($bytes, $offset + 40, 20).Replace('-', '').ToLowerInvariant()
      $flags = Read-GitIndexUInt16 $bytes ($offset + 60)
      $pathLength = $flags -band 0x0fff
      $pathStart = $offset + 62
      if (($flags -band 0x4000) -ne 0) {
        $pathStart += 2
      }

      if ($pathStart -ge $bytes.Length) {
        break
      }

      $pathEnd = $pathStart
      if ($pathLength -eq 0x0fff) {
        while (($pathEnd -lt $bytes.Length) -and ($bytes[$pathEnd] -ne 0)) {
          $pathEnd++
        }
      }
      else {
        $pathEnd = [Math]::Min($pathStart + $pathLength, $bytes.Length)
      }

      if ($pathEnd -le $pathStart) {
        break
      }

      $path = [System.Text.Encoding]::UTF8.GetString($bytes, $pathStart, $pathEnd - $pathStart)
      $entries[$path] = @{
        MTime = [uint64]$mtime
        Oid   = $objectId
        Size  = [uint64]$size
      }

      while (($pathEnd -lt $bytes.Length) -and ($bytes[$pathEnd] -ne 0)) {
        $pathEnd++
      }

      $offset = $pathEnd + 1
      while ((($offset - $entryStart) % 8 -ne 0) -and ($offset -lt $bytes.Length)) {
        $offset++
      }
    }
  }
  catch [System.IO.IOException], [System.UnauthorizedAccessException], [System.Security.SecurityException] {
    return @{}
  }

  return $entries
}

function ConvertTo-GitRelativePath {
  param(
    [string]$RepoPath,
    [string]$Path
  )

  $repoFullPath = [System.IO.Path]::GetFullPath($RepoPath).TrimEnd(@(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  ))
  $pathFullPath = [System.IO.Path]::GetFullPath($Path)
  $comparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
    [System.StringComparison]::OrdinalIgnoreCase
  }
  else {
    [System.StringComparison]::Ordinal
  }
  $prefix = "$repoFullPath$([System.IO.Path]::DirectorySeparatorChar)"

  if ($pathFullPath.StartsWith($prefix, $comparison)) {
    $relativePath = $pathFullPath.Substring($prefix.Length)
  }
  else {
    $repoUriPath = if ($repoFullPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
      $repoFullPath
    }
    else {
      "$repoFullPath$([System.IO.Path]::DirectorySeparatorChar)"
    }
    $repoUri = [System.Uri]::new($repoUriPath)
    $pathUri = [System.Uri]::new($pathFullPath)
    $relativePath = [System.Uri]::UnescapeDataString($repoUri.MakeRelativeUri($pathUri).ToString())
  }

  return ($relativePath -replace '\\', '/')
}

function Get-GitBlobSha1ForContent {
  param([byte[]]$Content)

  $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($Content.Length)")
  $bytes = [byte[]]::new($header.Length + 1 + $Content.Length)
  [System.Buffer]::BlockCopy($header, 0, $bytes, 0, $header.Length)
  $bytes[$header.Length] = 0
  [System.Buffer]::BlockCopy($Content, 0, $bytes, $header.Length + 1, $Content.Length)

  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  try {
    return [System.BitConverter]::ToString($sha1.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
  }
  finally {
    $sha1.Dispose()
  }
}

function Get-GitBlobSha1Candidates {
  param([System.IO.FileInfo]$File)

  try {
    $content = [System.IO.File]::ReadAllBytes($File.FullName)
    $hashes = @(Get-GitBlobSha1ForContent $content)

    $text = [System.Text.Encoding]::UTF8.GetString($content)
    if ($text.Contains("`r`n")) {
      $normalizedContent = [System.Text.Encoding]::UTF8.GetBytes(($text -replace "`r`n", "`n"))
      $hashes += Get-GitBlobSha1ForContent $normalizedContent
    }

    return $hashes | Select-Object -Unique
  }
  catch [System.Text.DecoderFallbackException] {
    return @()
  }
  catch [System.IO.IOException], [System.UnauthorizedAccessException], [System.Security.SecurityException] {
    return @()
  }
}

function Get-UntrackedFileCount {
  param(
    [System.IO.DirectoryInfo]$Directory,
    [int]$Limit = 1000
  )

  $count = 0
  $stack = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
  $stack.Push($Directory)

  while (($stack.Count -gt 0) -and ($count -lt $Limit)) {
    $currentDirectory = $stack.Pop()
    try {
      foreach ($file in $currentDirectory.EnumerateFiles()) {
        if ($file.Name -eq '.git') {
          continue
        }

        $count += 1
        if ($count -ge $Limit) {
          break
        }
      }

      if ($count -ge $Limit) {
        break
      }

      foreach ($childDirectory in $currentDirectory.EnumerateDirectories()) {
        if (($childDirectory.Name -eq '.git') -or (($childDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
          continue
        }

        $stack.Push($childDirectory)
      }
    }
    catch [System.IO.IOException], [System.UnauthorizedAccessException], [System.Security.SecurityException] {
      continue
    }
  }

  return $count
}

function Get-GitFastWorkingTreeStatus {
  param(
    [string]$RepoPath,
    [string]$GitDir
  )

  $status = @{
    Dirty     = 0
    Untracked = 0
  }

  $indexEntries = Get-GitIndexEntries $GitDir
  if ($indexEntries.Count -eq 0) {
    return $status
  }

  $comparer = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
    [System.StringComparer]::OrdinalIgnoreCase
  }
  else {
    [System.StringComparer]::Ordinal
  }

  $trackedPaths = [System.Collections.Generic.HashSet[string]]::new($comparer)
  $trackedDirectories = [System.Collections.Generic.HashSet[string]]::new($comparer)

  foreach ($path in $indexEntries.Keys) {
    $null = $trackedPaths.Add($path)
    $directory = [System.IO.Path]::GetDirectoryName($path) -replace '\\', '/'
    while ($directory) {
      $null = $trackedDirectories.Add($directory)
      $directory = [System.IO.Path]::GetDirectoryName($directory) -replace '\\', '/'
    }
  }

  $stack = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
  $stack.Push([System.IO.DirectoryInfo]::new($RepoPath))

  while ($stack.Count -gt 0) {
    $directory = $stack.Pop()
    try {
      foreach ($childDirectory in $directory.EnumerateDirectories()) {
        if (($childDirectory.Name -eq '.git') -or (($childDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
          continue
        }

        $relativePath = ConvertTo-GitRelativePath $RepoPath $childDirectory.FullName
        if ($trackedDirectories.Contains($relativePath)) {
          $stack.Push($childDirectory)
        }
        else {
          $status.Untracked += Get-UntrackedFileCount $childDirectory
        }
      }

      foreach ($file in $directory.EnumerateFiles()) {
        if ($file.Name -eq '.git') {
          continue
        }

        $relativePath = ConvertTo-GitRelativePath $RepoPath $file.FullName
        if ($trackedPaths.Contains($relativePath)) {
          $entry = $indexEntries[$relativePath]
          $lastWriteSeconds = [uint64][Math]::Floor(($file.LastWriteTimeUtc - [datetime]'1970-01-01Z').TotalSeconds)
          if ([uint64]$file.Length -ne $entry.Size) {
            $status.Dirty += 1
          }
          elseif ($lastWriteSeconds -ne $entry.MTime) {
            $blobShaCandidates = @(Get-GitBlobSha1Candidates $file)
            if (($blobShaCandidates.Count -eq 0) -or ($entry.Oid -notin $blobShaCandidates)) {
              $status.Dirty += 1
            }
          }
        }
        else {
          $status.Untracked += 1
        }
      }
    }
    catch [System.IO.IOException], [System.UnauthorizedAccessException], [System.Security.SecurityException] {
      continue
    }
  }

  return $status
}

function flare_git_fast {
  # Get repository info
  $repoInfo = Get-GitRepoInfo
  
  if (-not $repoInfo.RepoPath) { 
    return '' 
  }

  $gitDir = $repoInfo.GitDir
  $headFile = Join-Path $gitDir 'HEAD'

  # Fast file existence and content check
  if (-not (Test-Path $headFile -PathType Leaf)) {
    return ''
  }

  try {
    # Read HEAD file efficiently
    $headContent = [System.IO.File]::ReadAllText($headFile).Trim()
    
    $location = ''
    
    # Branch reference (most common case)
    if ($headContent.StartsWith('ref: refs/heads/')) {
      $location = $headContent.Substring(16)
    }
    # Handle detached HEAD with commit hash
    elseif ($headContent -match '^[0-9a-f]{40}$|^[0-9a-f]{7,40}$') {
      # Try to find a tag pointing to this commit
      $tag = Get-TagForCommit $gitDir $headContent
      if ($tag) {
        $location = "#$tag"
      } else {
        # Use short hash for detached HEAD
        $location = "@" + $headContent.Substring(0, 7)
      }
    }
    
    if (-not $location) {
      return ''
    }
    
    # Get operation status
    $opStatus = Get-GitOperationStatus $gitDir
    
    # Build output
    $output = $location
    
    # Add operation info
    if ($opStatus.Operation) {
      $output += " $($opStatus.Operation)"
      if ($opStatus.Step -and $opStatus.TotalSteps) {
        $output += " $($opStatus.Step)/$($opStatus.TotalSteps)"
      }
    }
    
    $workingTreeStatus = Get-GitFastWorkingTreeStatus $repoInfo.RepoPath $gitDir

    # Add status indicators (matching tide order where available: stash, dirty, untracked)
    $statusParts = @()

    # Add stash indicator
    $stashCount = Get-StashCount $gitDir
    if ($stashCount -gt 0) {
      $statusParts += "*$stashCount"
    }
    if ($workingTreeStatus.Dirty -gt 0) { $statusParts += "!$($workingTreeStatus.Dirty)" }
    if ($workingTreeStatus.Untracked -gt 0) { $statusParts += "?$($workingTreeStatus.Untracked)" }

    if ($statusParts.Count -gt 0) {
      $output += " " + ($statusParts -join " ")
    }
    
    return $output
  }
  catch {
    return ''
  }
}

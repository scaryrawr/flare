function Invoke-FlarePiece {
  param(
    [string]$PieceName,
    [string]$PiecesPath = "$PSScriptRoot/../pieces",
    [bool]$IncludeTime = $false
  )
  try {
    # Source the piece script file
    . "$PiecesPath/$PieceName.ps1"
        
    # Prepare to execute the command
    $command = "flare_$PieceName"
        
    # Time the execution
    $timing = [System.Diagnostics.Stopwatch]::StartNew()
    $result = & $command -ErrorAction SilentlyContinue
    $timing.Stop()
        
    # Format the result based on user settings
    if ($IncludeTime -and $result -ne '') {
      $elapsed = [math]::Round($timing.Elapsed.TotalMilliseconds, 2)
      return "$result ($elapsed ms)"
    }
    else {
      return $result
    }
  }
  catch {
    return ''
  }
}


function Get-PromptPieceResults {
  param(
    [string[]]$Pieces,
    [string]$PiecesPath = "$PSScriptRoot/../pieces",
    [bool]$IncludeTime = $false
  )
    
  $results = @{}
    
  foreach ($piece in $Pieces) {
    $result = Invoke-FlarePiece -PieceName $piece -PiecesPath $PiecesPath -IncludeTime $IncludeTime
    if ($result) {
      $results[$piece] = $result
    }
  }
    
  return $results
}
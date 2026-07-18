if (-not $script:flare_pieceCommands) {
  $script:flare_pieceCommands = @{}
}

<#
.SYNOPSIS
Invokes one prompt piece by name.
.DESCRIPTION
Resolves and caches the piece function, executes it, and optionally appends its
elapsed time. Missing, hidden, or failed pieces return an empty string.
.PARAMETER PieceName
The piece suffix used to resolve a flare_<name> function.
.PARAMETER PiecesPath
The directory containing piece scripts.
.PARAMETER IncludeTime
Appends elapsed milliseconds to a non-empty result.
.OUTPUTS
System.Object
#>
function Invoke-FlarePiece {
  param(
    [string]$PieceName,
    [string]$PiecesPath = "$PSScriptRoot/../pieces",
    [bool]$IncludeTime = $false
  )
  try {
    $cacheKey = "$PiecesPath::$PieceName"
    $command = "flare_$PieceName"

    if (-not $script:flare_pieceCommands.ContainsKey($cacheKey)) {
      $commandInfo = Get-Command $command -CommandType Function -ErrorAction SilentlyContinue
      if (-not $commandInfo) {
        $piecePath = Join-Path $PiecesPath "$PieceName.ps1"
        if (-not (Test-Path $piecePath)) {
          return ''
        }

        . $piecePath
        $commandInfo = Get-Command $command -CommandType Function -ErrorAction SilentlyContinue
        if (-not $commandInfo) {
          return ''
        }
      }

      $script:flare_pieceCommands[$cacheKey] = $commandInfo
    }
    
    # Time the execution
    $timing = [System.Diagnostics.Stopwatch]::StartNew()
    $pieceCommand = $script:flare_pieceCommands[$cacheKey]
    $result = & $pieceCommand -ErrorAction SilentlyContinue
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


<#
.SYNOPSIS
Evaluates a collection of prompt pieces.
.PARAMETER Pieces
Names of the pieces to evaluate.
.PARAMETER PiecesPath
The directory containing piece scripts.
.PARAMETER IncludeTime
Appends elapsed milliseconds to each non-empty result.
.OUTPUTS
System.Collections.Hashtable
#>
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
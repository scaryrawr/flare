. $PSScriptRoot/promptSymbols.ps1

# Enhanced unified state management for the prompt system
$global:flare_promptState = @{
    ResultCache         = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    BackgroundJob       = $null
    LastRenderHash      = $null
    LastDirectory       = $null
    IsRedrawing         = $false
    LastRedrawTime      = [DateTime]::MinValue
    AllPieces           = $null
    BackgroundPieces    = $null
    MainThreadPieces    = $null
    StyleCache          = @{}
    PerformanceStats    = @{
        TotalRenders    = 0
        AverageTime     = 0
        LastRenderTime  = 0
    }
    Configuration       = @{
        EnablePerformanceMonitoring = $false
        DebounceIntervalMs          = 50
        ShowPerformanceMetrics      = $false
    }
    ActiveJobs          = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
}

# Items we can calculate on the main thread, but should also ignore when comparing changes from the background job
$global:flare_mainThread = @('os', 'date', 'lastCommand', 'pwd')

$defaultStyle = "`e[0m"
$foregroundStyles = [ordered]@{
    'default'       = "`e[39m"
    'white'         = "`e[37m"
    'red'           = "`e[31m"
    'black'         = "`e[30m"
    'yellow'        = "`e[33m"
    'magenta'       = "`e[35m"
    'cyan'          = "`e[36m"
    'brightBlack'   = "`e[90m"
    'brightRed'     = "`e[91m"
    'brightGreen'   = "`e[92m"
    'brightYellow'  = "`e[93m"
    'brightBlue'    = "`e[94m"
    'brightMagenta' = "`e[95m"
    'brightCyan'    = "`e[96m"
    'green'         = "`e[32m"
    'blue'          = "`e[34m"
    'brightWhite'   = "`e[97m"
}

$backgroundStyles = [ordered]@{
    'default'       = "`e[49m"
    'white'         = "`e[47m"
    'red'           = "`e[41m"
    'black'         = "`e[40m"
    'yellow'        = "`e[43m"
    'magenta'       = "`e[45m"
    'cyan'          = "`e[46m"
    'brightBlack'   = "`e[100m"
    'brightRed'     = "`e[101m"
    'brightGreen'   = "`e[102m"
    'brightYellow'  = "`e[103m"
    'brightBlue'    = "`e[104m"
    'brightMagenta' = "`e[105m"
    'brightCyan'    = "`e[106m"
    'green'         = "`e[42m"
    'blue'          = "`e[44m"
    'brightWhite'   = "`e[107m"
}

$escapeRegex = "(`e\[\d+\w)"

. $PSScriptRoot/utils/invokeUtils.ps1

function Initialize-PieceCollections {
    if ($null -eq $global:flare_promptState.AllPieces) {
        $global:flare_promptState.AllPieces = $global:flare_leftPieces + $global:flare_rightPieces
        $global:flare_promptState.BackgroundPieces = $global:flare_promptState.AllPieces | Where-Object { $_ -notin $global:flare_mainThread }
        $global:flare_promptState.MainThreadPieces = $global:flare_promptState.AllPieces | Where-Object { $_ -in $global:flare_mainThread }
    }
}

function Get-PromptStateHash {
    param([System.Collections.Concurrent.ConcurrentDictionary[string, object]]$ResultCache)
    
    Initialize-PieceCollections
    
    # Use string builder for better performance with multiple concatenations
    $values = [System.Text.StringBuilder]::new()
    foreach ($piece in $global:flare_promptState.BackgroundPieces) {
        $value = if ($ResultCache.ContainsKey($piece)) { $ResultCache[$piece] } else { '' }
        $null = $values.Append("$piece=$value|")
    }
    return $values.ToString().GetHashCode()
}

function Start-BackgroundJob {
    # Cancel existing background job if running
    if ($global:flare_promptState.BackgroundJob) {
        if ($global:flare_promptState.BackgroundJob.State -eq 'Running') {
            $global:flare_promptState.BackgroundJob | Stop-Job -Force -ErrorAction SilentlyContinue
        }
        $global:flare_promptState.BackgroundJob | Remove-Job -Force -ErrorAction SilentlyContinue
        $global:flare_promptState.BackgroundJob = $null
    }
    
    # Start single background job for all pieces
    $global:flare_promptState.BackgroundJob = Start-ThreadJob -Name "Flare-Background" -ScriptBlock {
        param($backgroundPieces, $resultCache, $psScriptRoot)
        . $psScriptRoot/utils/invokeUtils.ps1
        
        # Process all background pieces
        foreach ($pieceName in $backgroundPieces) {
            try {
                $result = Invoke-FlarePiece -PieceName $pieceName -PiecesPath $psScriptRoot/pieces
                $resultCache[$pieceName] = $result
            }
            catch {
                # Silently fail for background jobs to avoid blocking
                $resultCache[$pieceName] = ''
            }
        }
        
        return 'background'
    } -ArgumentList $global:flare_promptState.BackgroundPieces, $global:flare_promptState.ResultCache, $PSScriptRoot
}

function Start-PieceJob {
    param([string]$PieceName)
    
    # Clean up existing job if it exists
    if ($global:flare_promptState.ActiveJobs.ContainsKey($PieceName)) {
        $existingJob = $global:flare_promptState.ActiveJobs[$PieceName]
        $existingJob | Stop-Job -Force -ErrorAction SilentlyContinue
        $existingJob | Remove-Job -Force -ErrorAction SilentlyContinue
        $null = $global:flare_promptState.ActiveJobs.TryRemove($PieceName, [ref]$null)
    }
    
    # Start new job
    $job = Start-ThreadJob -Name "Flare-$PieceName" -ScriptBlock {
        param($pieceName, $resultCache, $psScriptRoot)
        . $psScriptRoot/utils/invokeUtils.ps1
        
        try {
            $result = Invoke-FlarePiece -PieceName $pieceName -PiecesPath $psScriptRoot/pieces
            $resultCache[$pieceName] = $result
            return $pieceName
        }
        catch {
            $resultCache[$pieceName] = ''
            return $pieceName
        }
    } -ArgumentList $PieceName, $global:flare_promptState.ResultCache, $PSScriptRoot
    
    $global:flare_promptState.ActiveJobs[$PieceName] = $job
}

function Update-BackgroundThreadPieces {
    Initialize-PieceCollections

    # Only start job if not already running
    if (-not $global:flare_promptState.BackgroundJob -or 
        $global:flare_promptState.BackgroundJob.State -ne 'Running') {
        Start-BackgroundJob
    }
}

function Request-PromptRedraw {
    $now = Get-Date
    # Enhanced debouncing with configurable interval
    $debounceInterval = $global:flare_promptState.Configuration.DebounceIntervalMs
    if (($now - $global:flare_promptState.LastRedrawTime).TotalMilliseconds -lt $debounceInterval) {
        return
    }
    
    $global:flare_promptState.LastRedrawTime = $now
    $global:flare_promptState.IsRedrawing = $true
    
    try {
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }
    catch {
        # Gracefully handle InvokePrompt failures
        Write-Debug "Prompt redraw failed: $($_.Exception.Message)"
    }
    finally {
        $global:flare_promptState.IsRedrawing = $false
    }
}


function Get-LeftPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$Parts
    )

    $left = $global:flare_topPrefix
    $count = 1
    
    foreach ($pieceName in $global:flare_leftPieces) {
        $pieceResult = $Parts[$pieceName]
        if ($pieceResult) {
            # Use original color calculation logic from main branch
            $background = $backgroundStyles.Values[($backgroundStyles.Count - $count) % $backgroundStyles.Count]
            $foreground = $foregroundStyles['brightBlack']
            $separatorColor = $foregroundStyles.Values[($foregroundStyles.Count - $(if (($count - 1) -gt 0) { $count - 1 } else { $count })) % $foregroundStyles.Count]
            $separator = "$separatorColor$(if (($count - 1) -gt 0) { "$background$global:flare_promptSeparatorsLeft" } else { "$global:flare_promptTailLeft" })"
            $left += "$separator$background$foreground "
            
            $icon = Get-Variable -Name "flare_icons_$pieceName" -Scope Global -ValueOnly -ErrorAction SilentlyContinue
            if ($icon) {
                $left += "$icon "
            }
            $left += "$pieceResult "
            $count += 1
        }
    }

    $foreground = $foregroundStyles.Values[($foregroundStyles.Count - ($count - 1)) % $foregroundStyles.Count]
    $left += "$($backgroundStyles['default'])$foreground$global:flare_promptHeadLeft"

    return $left
}

function Get-RightPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$Parts
    )

    $right = ''
    $count = 1
    
    # Add performance metrics if enabled
    if ($global:flare_promptState.Configuration.ShowPerformanceMetrics) {
        $perfMetrics = Get-PerformanceMetrics
        if ($perfMetrics) {
            $Parts['perf'] = $perfMetrics
            $global:flare_rightPieces = @('perf') + $global:flare_rightPieces
        }
    }
    
    foreach ($pieceName in $global:flare_rightPieces) {
        $pieceResult = $Parts[$pieceName]
        if ($pieceResult) {
            # Use original color calculation logic from main branch
            $background = $backgroundStyles.Values[($backgroundStyles.Count - $count) % $backgroundStyles.Count]
            $foreground = $foregroundStyles['brightBlack']
            $separatorColor = $foregroundStyles.Values[($foregroundStyles.Count - $(if (($count - 1) -gt 0) { $count - 1 } else { $count })) % $foregroundStyles.Count]
            $separator = "$separatorColor$(if (($count - 1) -gt 0) { "$background$global:flare_promptSeparatorsRight" } else { "$($backgroundStyles['default'])$global:flare_promptTailRight" })"
            $right = "$pieceResult $separator$right"
            
            $icon = Get-Variable -Name "flare_icons_$pieceName" -Scope Global -ValueOnly -ErrorAction SilentlyContinue
            if ($icon) {
                $right = "$icon $right"
            }
            $right = "$background$foreground $right"
            $count += 1
        }
    }

    $foreground = $foregroundStyles.Values[($foregroundStyles.Count - ($count - 1)) % $foregroundStyles.Count]
    $right = "$($backgroundStyles['default'])$foreground$global:flare_promptSeparatorsRight$right"

    return $right
}

function Get-PerformanceMetrics {
    if (-not $global:flare_promptState.Configuration.EnablePerformanceMonitoring) {
        return $null
    }
    
    $stats = $global:flare_promptState.PerformanceStats
    if ($stats.TotalRenders -gt 0) {
        return "$([math]::Round($stats.AverageTime, 1))ms"
    }
    return $null
}

function Update-PerformanceStats {
    param([double]$RenderTimeMs)
    
    if (-not $global:flare_promptState.Configuration.EnablePerformanceMonitoring) {
        return
    }
    
    $stats = $global:flare_promptState.PerformanceStats
    $stats.TotalRenders++
    $stats.LastRenderTime = $RenderTimeMs
    
    # Calculate rolling average
    if ($stats.TotalRenders -eq 1) {
        $stats.AverageTime = $RenderTimeMs
    } else {
        $stats.AverageTime = ($stats.AverageTime * 0.9) + ($RenderTimeMs * 0.1)
    }
}

function Get-PromptLine {
    # Check if the last command was successful
    # Get exit status from command history if available
    $lastCommand = Get-History -Count 1 -ErrorAction SilentlyContinue
    $promptColor = if ($lastCommand -and $lastCommand.ExecutionStatus -eq 'Failed') {
        $foregroundStyles['brightRed']
    }
    else {
        $foregroundStyles['brightGreen']
    }

    return "$defaultStyle$global:flare_bottomPrefix$($promptColor)$($global:flare_promptArrow * ($nestedPromptLevel + 1))$defaultStyle"
}

function Update-MainThreadPieces {
    Initialize-PieceCollections
    
    # Combine main thread pieces with fast fallbacks for uncached background pieces
    $piecesToCalculate = [System.Collections.Generic.List[string]]::new()
    foreach ($piece in $global:flare_promptState.MainThreadPieces) {
        $piecesToCalculate.Add($piece)
    }
    
    foreach ($piece in $global:flare_promptState.BackgroundPieces) {
        if (-not $global:flare_promptState.ResultCache.ContainsKey($piece)) {
            $piecesToCalculate.Add("${piece}_fast")
        }
    }

    if ($piecesToCalculate.Count -eq 0) { return }
    
    $mainThreadResults = Get-PromptPieceResults -Pieces $piecesToCalculate

    foreach ($piece in $piecesToCalculate) {
        if ($piece -like '*_fast') {
            $actualPiece = $piece -replace '_fast', ''
            # Fast results are only valid when we don't have a cached actual result
            if (-not $global:flare_promptState.ResultCache.ContainsKey($actualPiece)) {
                $global:flare_promptState.ResultCache[$actualPiece] = $mainThreadResults[$piece]
            }
        }
        else {
            $global:flare_promptState.ResultCache[$piece] = $mainThreadResults[$piece]
        }
    }
}

function Get-PromptTopLine {
    param(
        [bool]$DisableBackground = $false
    )

    $renderStart = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        Update-MainThreadPieces
        if (-not $DisableBackground) {
            Update-BackgroundThreadPieces
        }

        # Convert ConcurrentDictionary to Hashtable for type compatibility
        $results = @{}
        foreach ($key in $global:flare_promptState.ResultCache.Keys) {
            $results[$key] = $global:flare_promptState.ResultCache[$key]
        }

        $left = Get-LeftPrompt -Parts $results
        $right = Get-RightPrompt -Parts $results

        # Optimized length calculation with caching
        $leftLength = ($left -replace $escapeRegex).Length
        $rightLength = ($right -replace $escapeRegex).Length
        $totalLength = $leftLength + $rightLength
        
        # Calculate spacing with proper terminal width detection
        $terminalWidth = $Host.UI.RawUI.WindowSize.Width
        if ($terminalWidth -le 0) { $terminalWidth = 80 } # Fallback for environments where width isn't available
        
        $spaces = [Math]::Max(0, $terminalWidth - $totalLength)

        return "$left$defaultStyle$(' ' * $spaces)$right"
    }
    finally {
        $renderStart.Stop()
        Update-PerformanceStats -RenderTimeMs $renderStart.Elapsed.TotalMilliseconds
    }
}

# Enhanced event handling with better error management
Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    try {
        # Early exit if no background job
        if (-not $global:flare_promptState.BackgroundJob) {
            return
        }

        # Check if background job is completed
        if ($global:flare_promptState.BackgroundJob.State -ne 'Running') {
            # Clean up completed background job
            $null = Wait-Job -Job $global:flare_promptState.BackgroundJob -ErrorAction SilentlyContinue
            $null = Receive-Job -Job $global:flare_promptState.BackgroundJob -ErrorAction SilentlyContinue
            Remove-Job -Job $global:flare_promptState.BackgroundJob -Force -ErrorAction SilentlyContinue
            $global:flare_promptState.BackgroundJob = $null

            # Check if we need to redraw based on hash comparison
            $currentHash = Get-PromptStateHash -ResultCache $global:flare_promptState.ResultCache
            if ($currentHash -ne $global:flare_promptState.LastRenderHash) {
                $global:flare_promptState.LastRenderHash = $currentHash
                Request-PromptRedraw
            }
        }
        
        # Clean up completed individual jobs
        $completedJobs = @()
        foreach ($kvp in $global:flare_promptState.ActiveJobs.GetEnumerator()) {
            if ($kvp.Value.State -ne 'Running') {
                $completedJobs += $kvp.Key
                $null = Wait-Job -Job $kvp.Value -ErrorAction SilentlyContinue
                $null = Receive-Job -Job $kvp.Value -ErrorAction SilentlyContinue
                Remove-Job -Job $kvp.Value -Force -ErrorAction SilentlyContinue
            }
        }
        
        foreach ($jobName in $completedJobs) {
            $null = $global:flare_promptState.ActiveJobs.TryRemove($jobName, [ref]$null)
        }
    }
    catch {
        # Silently handle errors to prevent disrupting the user experience
        Write-Debug "Flare OnIdle event error: $($_.Exception.Message)"
    }
}

# Configuration management functions
function Set-FlareConfiguration {
    param(
        [hashtable]$Configuration
    )
    
    foreach ($key in $Configuration.Keys) {
        if ($global:flare_promptState.Configuration.ContainsKey($key)) {
            $global:flare_promptState.Configuration[$key] = $Configuration[$key]
        }
    }
    
    # Clear caches when configuration changes
    $global:flare_promptState.StyleCache.Clear()
    $global:flare_promptState.ResultCache.Clear()
}

function Get-FlareConfiguration {
    return $global:flare_promptState.Configuration.Clone()
}

function Reset-FlareCache {
    $global:flare_promptState.ResultCache.Clear()
    $global:flare_promptState.StyleCache.Clear()
    $global:flare_promptState.LastRenderHash = $null
}

function Get-FlareStatistics {
    return @{
        TotalRenders = $global:flare_promptState.PerformanceStats.TotalRenders
        AverageRenderTime = $global:flare_promptState.PerformanceStats.AverageTime
        LastRenderTime = $global:flare_promptState.PerformanceStats.LastRenderTime
        CachedItems = $global:flare_promptState.ResultCache.Count
        ActiveBackgroundJobs = if ($global:flare_promptState.BackgroundJob) { 1 } else { 0 }
        ActivePieceJobs = $global:flare_promptState.ActiveJobs.Count
    }
}

# Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
#     New-Event -SourceIdentifier Flare.Redraw -Sender $Sender
# }

# Enhanced cleanup with comprehensive job management
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    try {
        # Unregister events
        Get-EventSubscriber | Where-Object { $_.SourceIdentifier -eq 'PowerShell.OnIdle' } | Unregister-Event -Force -ErrorAction SilentlyContinue
        
        # Clean up background job if running
        if ($global:flare_promptState.BackgroundJob) {
            $global:flare_promptState.BackgroundJob | Stop-Job -Force -ErrorAction SilentlyContinue
            $global:flare_promptState.BackgroundJob | Remove-Job -Force -ErrorAction SilentlyContinue
            $global:flare_promptState.BackgroundJob = $null
        }
        
        # Clean up all active piece jobs
        foreach ($job in $global:flare_promptState.ActiveJobs.Values) {
            $job | Stop-Job -Force -ErrorAction SilentlyContinue
            $job | Remove-Job -Force -ErrorAction SilentlyContinue
        }
        $global:flare_promptState.ActiveJobs.Clear()
        
        # Clear all caches
        $global:flare_promptState.ResultCache.Clear()
        $global:flare_promptState.StyleCache.Clear()
    }
    catch {
        # Silently handle cleanup errors
        Write-Debug "Flare cleanup error: $($_.Exception.Message)"
    }
}

function Prompt {
    try {
        # Performance timing
        $promptStart = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Check for directory changes and clear cache if needed
        if ($global:flare_promptState.LastDirectory -and 
            $PWD.Path -ne $global:flare_promptState.LastDirectory.Path) {
            Reset-FlareCache
            # Reset piece collections to force recalculation
            $global:flare_promptState.AllPieces = $null
            $global:flare_promptState.BackgroundPieces = $null
            $global:flare_promptState.MainThreadPieces = $null
        }

        $global:flare_promptState.LastDirectory = $PWD

        $topLine = Get-PromptTopLine -DisableBackground $global:flare_promptState.IsRedrawing
        $line = Get-PromptLine

        Set-PSReadLineOption -ExtraPromptLineCount 1

        $promptStart.Stop()
        
        # Update performance stats for the full prompt
        if ($global:flare_promptState.Configuration.EnablePerformanceMonitoring) {
            Update-PerformanceStats -RenderTimeMs $promptStart.Elapsed.TotalMilliseconds
        }

        return "`r$topLine`n$line "
    }
    catch {
        # Fallback prompt in case of errors
        Write-Debug "Flare prompt error: $($_.Exception.Message)"
        return "PS $($PWD.Path -replace [regex]::Escape($HOME), '~')> "
    }
}

# Enhanced module exports with configuration functions
Export-ModuleMember -Function @(
    'Prompt'
    'Set-FlareConfiguration'
    'Get-FlareConfiguration' 
    'Reset-FlareCache'
    'Get-FlareStatistics'
)

# Use Set-PSReadLineKeyHandler to clear the prompt and rewrite the user's input when the user submits a command
Set-PSReadLineKeyHandler -Key Enter -BriefDescription 'Clear prompt and rewrite input on Enter' -ScriptBlock {
    # Prepare references for the input line and cursor position
    $inputLineRef = [ref]''
    $cursorPositionRef = [ref]0

    # Retrieve the current input from the command line buffer using GetBufferState
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState($inputLineRef, $cursorPositionRef)
    $inputLine = $inputLineRef.Value

    # Check if the input is multiline
    if ($inputLine -join '' -match "`n") {
        # If multiline, invoke the default Enter key behavior without clearing the prompt
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        return
    }

    # Move the cursor up by two lines to clear the two-line prompt
    [System.Console]::SetCursorPosition(0, [System.Console]::CursorTop - 1)

    # Get the console width to overwrite the lines with spaces
    $consoleWidth = [System.Console]::BufferWidth

    # Clear the current line and the next line by overwriting with spaces
    [System.Console]::Write(' ' * $consoleWidth * 2)

    # Rewrite the user's input prefixed with '>'
    [System.Console]::SetCursorPosition(0, [System.Console]::CursorTop - 1)
    Write-Host "$(Get-PromptLine) $($inputLine -join '')" -NoNewline

    # Execute the command by invoking the default Enter key behavior
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

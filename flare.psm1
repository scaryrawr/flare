. $PSScriptRoot/promptSymbols.ps1

# Prompt results are applied only on the interactive runspace.
$global:flare_resultCache = @{}

# Items calculated on the interactive runspace rather than the slow refresh worker
$global:flare_mainThread = @('os', 'date', 'lastCommand', 'pwd')

# Fast pieces that should refresh every prompt because their state can change without touching prompt caches.
if ($null -eq $global:flare_alwaysRefreshFastPieces) {
    $global:flare_alwaysRefreshFastPieces = @('git')
}

$global:flare_lastDirectory = $null

$global:flare_redrawing = $false

$script:flare_nextRefreshRequestId = 0
$script:flare_latestRefreshRequestId = 0

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
foreach ($pieceFile in Get-ChildItem (Join-Path $PSScriptRoot 'pieces') -Filter '*.ps1' -File) {
    . $pieceFile.FullName
}
. $PSScriptRoot/utils/refreshWorker.ps1

<#
.SYNOPSIS
Renders the configured left-side prompt pieces.
.PARAMETER Parts
Cached piece values keyed by piece name.
.OUTPUTS
System.String
#>
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

<#
.SYNOPSIS
Renders the configured right-side prompt pieces.
.PARAMETER Parts
Cached piece values keyed by piece name.
.OUTPUTS
System.String
#>
function Get-RightPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$Parts
    )

    $right = ''
    $count = 1
    foreach ($pieceName in $global:flare_rightPieces) {
        $pieceResult = $Parts[$pieceName]
        if ($pieceResult) {
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

<#
.SYNOPSIS
Renders the bottom prompt line and command-status arrow.
.OUTPUTS
System.String
#>
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

<#
.SYNOPSIS
Extracts the fast Git metadata portion of a rendered Git value.
.PARAMETER Value
The rendered Git piece value, optionally including slow status counts.
.OUTPUTS
System.String
#>
function Get-FlareGitMetadataPrefix {
    param([string]$Value)

    if (-not $Value) {
        return ''
    }

    return ($Value -replace ' (?:⇣|⇡|\*|~|\+|!|\?)\d+(?: .*)?$', '')
}

<#
.SYNOPSIS
Evaluates synchronous and fast prompt pieces and updates the render cache.
.OUTPUTS
None
#>
function Update-MainThreadPieces {
    $allPieces = $global:flare_leftPieces + $global:flare_rightPieces
    # Find the intersection of all prompt pieces and main thread items
    $mainThreadPieces = $allPieces | Where-Object { $_ -in $global:flare_mainThread }
    $fastPieceCandidates = $allPieces | Where-Object {
        ($_ -notin $global:flare_mainThread) -and
        (($_ -in $global:flare_alwaysRefreshFastPieces) -or (-not $global:flare_resultCache.ContainsKey($_)))
    }
    $mainThreadPieces += $fastPieceCandidates |
        Where-Object { Test-Path (Join-Path $PSScriptRoot "pieces/${_}_fast.ps1") } |
        ForEach-Object { "${_}_fast" }
    $mainThreadPieces = $mainThreadPieces | Select-Object -Unique

    $mainThreadResults = Get-PromptPieceResults -Pieces $mainThreadPieces

    foreach ($piece in $mainThreadPieces) {
        # Support "fast" versions of pieces when there's no cache data available
        if ($piece -like '*_fast') {
            $pieceFast = $piece
            $piece = $piece -replace '_fast', ''
            # Most fast results are fallbacks; selected pieces use them for cheap, synchronous freshness.
            if (($piece -in $global:flare_alwaysRefreshFastPieces) -or (-not $global:flare_resultCache.ContainsKey($piece))) {
                $fastResult = $mainThreadResults[$pieceFast]
                if (
                    ($piece -eq 'git') -and
                    $fastResult -and
                    $global:flare_resultCache.ContainsKey($piece) -and
                    ((Get-FlareGitMetadataPrefix $global:flare_resultCache[$piece]) -eq $fastResult)
                ) {
                    # Keep completed background status counts when only cheap git metadata was refreshed.
                }
                elseif ($fastResult) {
                    $global:flare_resultCache[$piece] = $fastResult
                }
                else {
                    $global:flare_resultCache.Remove($piece)
                }
            }
        }
        elseif ($mainThreadResults[$piece]) {
            $global:flare_resultCache[$piece] = $mainThreadResults[$piece]
        }
        else {
            $global:flare_resultCache.Remove($piece)
        }
    }
}

<#
.SYNOPSIS
Submits the current slow-piece snapshot to the durable refresh worker.
.OUTPUTS
None
#>
function Update-BackgroundThreadPieces {
    $allPieces = $global:flare_leftPieces + $global:flare_rightPieces
    $backgroundThreadPieces = $allPieces | Where-Object { $_ -notin $global:flare_mainThread }
    if ($backgroundThreadPieces.Count -eq 0) {
        return
    }

    $script:flare_latestRefreshRequestId = Send-FlareRefreshRequest `
        -WorkingDirectory $PWD.Path `
        -Pieces $backgroundThreadPieces `
        -ModuleRoot $PSScriptRoot
}

<#
.SYNOPSIS
Builds the top prompt line from current fast and cached slow results.
.PARAMETER DisableBackground
Prevents a new slow refresh request, such as during an idle redraw.
.OUTPUTS
System.String
#>
function Get-PromptTopLine {
    param(
        [bool]$DisableBackground = $false
    )

    Update-MainThreadPieces
    if (-not $DisableBackground) {
        Update-BackgroundThreadPieces
    }

    $results = @{}
    foreach ($piece in $global:flare_resultCache.Keys) {
        $results[$piece] = $global:flare_resultCache[$piece]
    }

    $left = Get-LeftPrompt -Parts $results
    $right = Get-RightPrompt -Parts $results

    # Figure out spacing between left and right prompts
    # Get the window width and subtract the current cursor position
    $spaces = $Host.UI.RawUI.WindowSize.Width - ($($left -replace $escapeRegex).Length + $($right -replace $escapeRegex).Length)

    if ($spaces -lt 0) { 
        # Not enough space to also have right prompt
        "$left"
    }
    else {
        "$left$defaultStyle$(' ' * $spaces)$right"
    }
}

<#
.SYNOPSIS
Applies the newest valid worker result and redraws changed prompt content.
.PARAMETER DisableRedraw
Applies accepted results without invoking a PSReadLine prompt redraw.
.OUTPUTS
System.Boolean
#>
function Update-FlareBackgroundResults {
    param([switch]$DisableRedraw)

    $currentWorkingDirectory = $PWD.Path
    $acceptedResult = @(Receive-FlareRefreshResult) |
        Where-Object {
            $_.RequestId -eq $script:flare_latestRefreshRequestId -and
            $_.WorkingDirectory -eq $currentWorkingDirectory
        } |
        Select-Object -Last 1

    if (-not $acceptedResult) {
        return $false
    }

    if (-not $acceptedResult.Succeeded) {
        Write-Debug "Flare background refresh failed: $($acceptedResult.Error)"
        return $false
    }

    $hasChanges = $false
    foreach ($piece in $acceptedResult.Pieces) {
        $newValue = $acceptedResult.Results[$piece]
        if ($newValue) {
            if (-not $global:flare_resultCache.ContainsKey($piece) -or $global:flare_resultCache[$piece] -ne $newValue) {
                $hasChanges = $true
            }
            $global:flare_resultCache[$piece] = $newValue
        }
        elseif ($global:flare_resultCache.ContainsKey($piece)) {
            $global:flare_resultCache.Remove($piece)
            $hasChanges = $true
        }
    }

    if ($hasChanges -and -not $DisableRedraw) {
        $global:flare_redrawing = $true
        try {
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
        catch {
            Write-Debug "Flare prompt redraw failed: $($_.Exception.Message)"
        }
        finally {
            $global:flare_redrawing = $false
        }
    }

    return $hasChanges
}

$script:flare_idleCallback = {
    $null = Update-FlareBackgroundResults
}
$script:flare_idleEventJob = Register-EngineEvent `
    -SourceIdentifier PowerShell.OnIdle `
    -Action {
        & $flareIdleCallback
    }
$script:flare_idleEventJob.Module.SessionState.PSVariable.Set('flareIdleCallback', $script:flare_idleCallback)
$script:flare_idleSubscriptionId = Get-EventSubscriber |
    Where-Object { $_.Action -eq $script:flare_idleEventJob } |
    Select-Object -ExpandProperty SubscriptionId -First 1

$script:flare_exitCallback = {
    Stop-FlareRefreshWorker
}
$script:flare_exitEventJob = Register-EngineEvent `
    -SourceIdentifier PowerShell.Exiting `
    -Action {
        & $flareExitCallback
    }
$script:flare_exitEventJob.Module.SessionState.PSVariable.Set('flareExitCallback', $script:flare_exitCallback)
$script:flare_exitSubscriptionId = Get-EventSubscriber |
    Where-Object { $_.Action -eq $script:flare_exitEventJob } |
    Select-Object -ExpandProperty SubscriptionId -First 1

# Register a cleanup event handler for when the module is removed
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    foreach ($subscriptionId in @($script:flare_idleSubscriptionId, $script:flare_exitSubscriptionId)) {
        if ($subscriptionId) {
            Unregister-Event -SubscriptionId $subscriptionId -ErrorAction SilentlyContinue
        }
    }
    foreach ($eventJob in @($script:flare_idleEventJob, $script:flare_exitEventJob)) {
        if ($eventJob) {
            Remove-Job -Job $eventJob -Force -ErrorAction SilentlyContinue
        }
    }
    Stop-FlareRefreshWorker
}

<#
.SYNOPSIS
Renders Flare's two-line PowerShell prompt.
.DESCRIPTION
Clears incompatible cache data after directory changes, renders the fast path,
and submits slow pieces to the background refresh worker.
.OUTPUTS
System.String
#>
function Prompt {
    $currentDirectory = $PWD.Path
    if ($global:flare_lastDirectory) {
        if ($currentDirectory -ne $global:flare_lastDirectory) {
            $global:flare_resultCache.Clear()
        }
    }

    $global:flare_lastDirectory = $currentDirectory

    $topLine = Get-PromptTopLine -DisableBackground $global:flare_redrawing
    $line = Get-PromptLine

    Set-PSReadLineOption -ExtraPromptLineCount 1

    "`r$topLine`n$line "
}

# Add module exports
Export-ModuleMember -Function @('Prompt')

# filepath: /Users/mike/GitHub/flare/testPiecesTiming.ps1
# Measure the execution time of individual prompt pieces

# Import the module to access all pieces
try {
    Import-Module "$PSScriptRoot/flare.psm1" -Force -ErrorAction Stop
    Write-Host "✅ Flare module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to load the Flare module: $_" -ForegroundColor Red
    exit 1
}

# Get all piece files from the pieces directory
$pieceFiles = Get-ChildItem -Path "$PSScriptRoot/pieces" -Filter "*.ps1"
if (-not $pieceFiles -or $pieceFiles.Count -eq 0) {
    Write-Host "❌ No piece files found in the pieces directory" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Found $($pieceFiles.Count) piece files" -ForegroundColor Green

$iterations = 100 # Number of times to run each test
$results = @{}
$anyFailures = $false

Write-Host "Testing individual pieces performance..."
Write-Host ""

# Test with SL locally since it's the most expensive
# z sl

foreach ($pieceFile in $pieceFiles) {
    # Get piece name without extension
    $pieceName = [System.IO.Path]::GetFileNameWithoutExtension($pieceFile.Name)
    $functionName = "flare_$pieceName"
    
    Write-Host "Testing $pieceName piece..."
    
    # Verify the function exists
    if (-not (Get-Command $functionName -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Function $functionName not found - piece failed to load properly" -ForegroundColor Red
        $anyFailures = $true
        $results[$pieceName] = @{
            Average = 0
            Minimum = 0
            Maximum = 0
            Status = "Failed"
        }
        continue
    }
    
    $times = @()
    $pieceFailures = 0
    
    for ($i = 0; $i -lt $iterations; $i++) {
        # Measure execution time
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $null = & $functionName -ErrorAction Stop
        } catch {
            # If a piece function fails, track it and count the failure
            Write-Host "  ❌ Error executing $functionName on iteration ${i}: $_" -ForegroundColor Red
            $pieceFailures++
            $anyFailures = $true
        }
        $sw.Stop()
        $times += $sw.Elapsed.TotalMilliseconds
    }
    
    # Report if this piece had any failures
    if ($pieceFailures -gt 0) {
        Write-Host "  ❌ $pieceName had $pieceFailures failures out of $iterations iterations" -ForegroundColor Red
    } else {
        Write-Host "  ✅ $pieceName executed successfully for all iterations" -ForegroundColor Green
    }
    
    # Calculate statistics
    $avg = ($times | Measure-Object -Average).Average
    $min = ($times | Measure-Object -Minimum).Minimum
    $max = ($times | Measure-Object -Maximum).Maximum
    
    # Store results for sorting later
    $results[$pieceName] = @{
        Average = $avg
        Minimum = $min
        Maximum = $max
        Status = if ($pieceFailures -gt 0) { "Failed ($pieceFailures failures)" } else { "Success" }
    }
    
    # Print individual piece results
    Write-Host "  Average: $([math]::Round($avg,2)) ms"
    Write-Host "  Min:     $([math]::Round($min,2)) ms"
    Write-Host "  Max:     $([math]::Round($max,2)) ms"
    Write-Host "  Status:  $($results[$pieceName].Status)"
    Write-Host ""
}

# cd -

# Sort results by average execution time (descending)
$sortedResults = $results.GetEnumerator() | Sort-Object { $_.Value.Average } -Descending

# Display sorted summary
Write-Host "Performance Summary (sorted by average execution time):"
Write-Host "===================================================="
foreach ($result in $sortedResults) {
    $pieceName = $result.Key
    $stats = $result.Value
    $statusColor = if ($stats.Status -eq "Success") { "Green" } else { "Red" }
    Write-Host ("{0,-15} {1,10:N2} ms (min: {2,8:N2} ms, max: {3,8:N2} ms) - " -f $pieceName, $stats.Average, $stats.Minimum, $stats.Maximum) -NoNewline
    Write-Host "$($stats.Status)" -ForegroundColor $statusColor
}

# Optional: Compare to full prompt execution
Write-Host ""
Write-Host "Comparing to full Prompt function execution:"
Write-Host "=========================================="

# Verify the Prompt function exists
if (-not (Get-Command Prompt -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Prompt function not found - full prompt failed to load properly" -ForegroundColor Red
    $anyFailures = $true
    $fullAvg = 0
    $fullMin = 0
    $fullMax = 0
    $promptStatus = "Failed"
} else {
    $fullTimes = @()
    $fullPromptFailures = 0
    
    for ($i = 0; $i -lt $iterations; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $null = Prompt -ErrorAction Stop
        } catch {
            Write-Host "  ❌ Error executing full Prompt on iteration ${i}: $_" -ForegroundColor Red
            $fullPromptFailures++
            $anyFailures = $true
        }
        $sw.Stop()
        $fullTimes += $sw.Elapsed.TotalMilliseconds
    }
    
    $fullAvg = ($fullTimes | Measure-Object -Average).Average
    $fullMin = ($fullTimes | Measure-Object -Minimum).Minimum
    $fullMax = ($fullTimes | Measure-Object -Maximum).Maximum
    $promptStatus = if ($fullPromptFailures -gt 0) { "Failed ($fullPromptFailures failures)" } else { "Success" }
    
    # Report if full prompt had any failures
    if ($fullPromptFailures -gt 0) {
        Write-Host "  ❌ Full Prompt had $fullPromptFailures failures out of $iterations iterations" -ForegroundColor Red
    } else {
        Write-Host "  ✅ Full Prompt executed successfully for all iterations" -ForegroundColor Green
    }
}

$statusColor = if ($promptStatus -eq "Success") { "Green" } else { "Red" }
Write-Host "  Full Prompt Average: $([math]::Round($fullAvg,2)) ms"
Write-Host "  Full Prompt Min:     $([math]::Round($fullMin,2)) ms"
Write-Host "  Full Prompt Max:     $([math]::Round($fullMax,2)) ms"
Write-Host "  Status:              $promptStatus" -ForegroundColor $statusColor

# Calculate the sum of individual pieces
$sumAvg = ($sortedResults | Measure-Object -Property {$_.Value.Average} -Sum).Sum
Write-Host ""
Write-Host "Sum of individual pieces: $([math]::Round($sumAvg,2)) ms"
Write-Host "Overhead (full - sum):    $([math]::Round($fullAvg - $sumAvg,2)) ms"

# Provide final summary and exit with appropriate code
Write-Host ""
if ($anyFailures) {
    Write-Host "❌ TEST FAILED: One or more pieces or the full prompt failed to load or execute correctly" -ForegroundColor Red
    exit 1
} else {
    Write-Host "✅ TEST PASSED: All pieces and the full prompt loaded and executed successfully" -ForegroundColor Green
    exit 0
}

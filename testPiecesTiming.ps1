# filepath: /Users/mike/GitHub/flare/testPiecesTiming.ps1
# Measure the execution time of individual prompt pieces

# Import the module to access all pieces
Import-Module "$PSScriptRoot/flare.psm1" -Force

# Get all piece files from the pieces directory
$pieceFiles = Get-ChildItem -Path "$PSScriptRoot/pieces" -Filter "*.ps1"
$iterations = 100 # Number of times to run each test
$results = @{}

Write-Host "Testing individual pieces performance..."
Write-Host ""

# Test with SL locally since it's the most expensive
# z sl

foreach ($pieceFile in $pieceFiles) {
    # Get piece name without extension
    $pieceName = [System.IO.Path]::GetFileNameWithoutExtension($pieceFile.Name)
    $functionName = "flare_$pieceName"
    
    Write-Host "Testing $pieceName piece..."
    
    $times = @()
    for ($i = 0; $i -lt $iterations; $i++) {
        # Measure execution time
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $null = & $functionName -ErrorAction SilentlyContinue
        } catch {
            # If a piece function fails, we still want to track it but with a 0 time
            Write-Host "  Error executing $functionName on iteration $i"
        }
        $sw.Stop()
        $times += $sw.Elapsed.TotalMilliseconds
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
    }
    
    # Print individual piece results
    Write-Host "  Average: $([math]::Round($avg,2)) ms"
    Write-Host "  Min:     $([math]::Round($min,2)) ms"
    Write-Host "  Max:     $([math]::Round($max,2)) ms"
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
    Write-Host ("{0,-15} {1,10:N2} ms (min: {2,8:N2} ms, max: {3,8:N2} ms)" -f $pieceName, $stats.Average, $stats.Minimum, $stats.Maximum)
}

# Optional: Compare to full prompt execution
Write-Host ""
Write-Host "Comparing to full Prompt function execution:"
Write-Host "=========================================="

$fullTimes = @()
for ($i = 0; $i -lt $iterations; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Prompt
    $sw.Stop()
    $fullTimes += $sw.Elapsed.TotalMilliseconds
}

$fullAvg = ($fullTimes | Measure-Object -Average).Average
$fullMin = ($fullTimes | Measure-Object -Minimum).Minimum
$fullMax = ($fullTimes | Measure-Object -Maximum).Maximum

Write-Host "  Full Prompt Average: $([math]::Round($fullAvg,2)) ms"
Write-Host "  Full Prompt Min:     $([math]::Round($fullMin,2)) ms"
Write-Host "  Full Prompt Max:     $([math]::Round($fullMax,2)) ms"

# Calculate the sum of individual pieces
$sumAvg = ($sortedResults | Measure-Object -Property {$_.Value.Average} -Sum).Sum
Write-Host ""
Write-Host "Sum of individual pieces: $([math]::Round($sumAvg,2)) ms"
Write-Host "Overhead (full - sum):    $([math]::Round($fullAvg - $sumAvg,2)) ms"

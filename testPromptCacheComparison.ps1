# filepath: /Users/mike/GitHub/flare/testPromptCacheComparison.ps1
# Compare performance between cached and uncached prompt execution
$iterations = 100
$initialTimes = @()
$cachedTimes = @()

Import-Module "$PSScriptRoot/flare.psm1" -Force -DisableNameChecking

# Test with SL locally since it's the most expensive
# z sl

Write-Host "====== Testing Initial (Uncached) Prompt Performance ======"
Write-Host "This simulates the first prompt display after starting PowerShell"
# Force prompt recalculation by resetting cache each time
for ($i = 0; $i -lt $iterations; $i++) {
    # Force prompt cache reset to simulate first-time execution
    Reset-FlarePromptCache
    
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Prompt
    $sw.Stop()
    $initialTimes += $sw.Elapsed.TotalMilliseconds
    
    # Output progress
    if ($i % 10 -eq 0) {
        Write-Host "  Progress: $i/$iterations" -ForegroundColor Cyan
    }
}

Write-Host "`n====== Testing Cached Prompt Performance ======"
Write-Host "This simulates subsequent prompt displays with cached values"
# First generate a cached prompt
$null = Prompt
# Then measure performance with cache
for ($i = 0; $i -lt $iterations; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Prompt
    $sw.Stop()
    $cachedTimes += $sw.Elapsed.TotalMilliseconds
    
    # Output progress
    if ($i % 10 -eq 0) {
        Write-Host "  Progress: $i/$iterations" -ForegroundColor Cyan
    }
}

# cd -

# Calculate statistics for initial prompt
$initialAvg = ($initialTimes | Measure-Object -Average).Average
$initialMin = ($initialTimes | Measure-Object -Minimum).Minimum
$initialMax = ($initialTimes | Measure-Object -Maximum).Maximum

# Calculate statistics for cached prompt
$cachedAvg = ($cachedTimes | Measure-Object -Average).Average
$cachedMin = ($cachedTimes | Measure-Object -Minimum).Minimum
$cachedMax = ($cachedTimes | Measure-Object -Maximum).Maximum

# Calculate improvement percentage
$improvementPct = 100 * (1 - ($cachedAvg / $initialAvg))

Write-Host "`n====== Performance Results ======"
Write-Host "`nUncached Prompt (initial display) over $iterations runs:"
Write-Host "  Average: $([math]::Round($initialAvg,2)) ms"
Write-Host "  Min:     $([math]::Round($initialMin,2)) ms"
Write-Host "  Max:     $([math]::Round($initialMax,2)) ms"

Write-Host "`nCached Prompt (subsequent displays) over $iterations runs:"
Write-Host "  Average: $([math]::Round($cachedAvg,2)) ms"
Write-Host "  Min:     $([math]::Round($cachedMin,2)) ms"
Write-Host "  Max:     $([math]::Round($cachedMax,2)) ms"

Write-Host "`nPerformance improvement with caching: $([math]::Round($improvementPct,2))%"

# Sample prompt output
Write-Host "`nSample prompt output:"
"$(Prompt)"

# Testing for async updates - this test requires manual observation
Write-Host "`n====== Testing Async Prompt Updates ======"
Write-Host "The following test will demonstrate the async prompt redraw:"
Write-Host "1. Initial prompt is displayed (using cache)"
Write-Host "2. After 2 seconds, the console should be idle, and the prompt should update"
Write-Host "3. You'll see if the prompt was redrawn via idle event"
Write-Host ""

# Force a reset to ensure we get a fresh calculation
Reset-FlarePromptCache
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Prompt
Write-Host "Initial prompt displayed in $([math]::Round($sw.Elapsed.TotalMilliseconds,2)) ms"
Write-Host "Waiting for idle refresh (should happen automatically)..."
Start-Sleep -Seconds 3
Write-Host "If you saw the prompt update above, the idle event is working correctly!"

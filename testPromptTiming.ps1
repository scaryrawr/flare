# Measure the execution time of the Prompt function
$iterations = 100
$times = @()

Import-Module "$PSScriptRoot/flare.psm1" -Force

# Test with SL locally since it's the most expensive
# z sl

for ($i = 0; $i -lt $iterations; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Prompt
    $sw.Stop()
    $times += $sw.Elapsed.TotalMilliseconds
}

# cd -

$avg = ($times | Measure-Object -Average).Average
$min = ($times | Measure-Object -Minimum).Minimum
$max = ($times | Measure-Object -Maximum).Maximum

Write-Host "Prompt timing over $iterations runs:"
Write-Host "  Average: $([math]::Round($avg,2)) ms"
Write-Host "  Min:     $([math]::Round($min,2)) ms"
Write-Host "  Max:     $([math]::Round($max,2)) ms"

"$(Prompt)"
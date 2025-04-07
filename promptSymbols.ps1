. $PSScriptRoot/osicon.ps1

# Rounded corners for the prompt
#$global:flare_promptSeparatorsLeft ??= ""
#$global:flare_promptHeadLeft ??= ""
#$global:flare_promptSeparatorsRight ??= ""
#$global:flare_promptHeadRight ??= ""

$global:flare_promptSeparatorsLeft ??= ""
$global:flare_promptHeadLeft ??= ""
$global:flare_promptTailLeft ??= "░▒▓"
$global:flare_promptSeparatorsRight ??= ""
$global:flare_promptHeadRight ??= ""
$global:flare_promptTailRight ??= "▓▒░"
$global:flare_gitIcon ??= ""
$global:flare_osIcon ??= "$(Get-OSIcon)"
$global:flare_topPrefix ??= "╭─"
$global:flare_bottomPrefix ??= "╰─"
$global:flare_promptArrow ??= ""

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
$global:flare_topPrefix ??= "╭─"
$global:flare_bottomPrefix ??= "╰─"
$global:flare_promptArrow ??= ""

$global:flare_gitIcon ??= ""
$global:flare_dateFormat ??= 'HH:mm:ss'

$global:flare_leftPieces ??= @(
  "os"
  "pwd"
  "git"
)

$global:flare_rightPieces ??= @(
  "date"
  "node"
  "rust"
  "zig"
  "lastCommand"
)
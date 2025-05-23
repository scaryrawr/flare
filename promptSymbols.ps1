# Rounded corners for the prompt
#$global:flare_promptSeparatorsLeft ??= ""
#$global:flare_promptHeadLeft ??= ""
#$global:flare_promptSeparatorsRight ??= ""
#$global:flare_promptHeadRight ??= ""

$global:flare_promptSeparatorsLeft ??= ''
$global:flare_promptHeadLeft ??= ''
$global:flare_promptTailLeft ??= '░▒▓'
$global:flare_promptSeparatorsRight ??= ''
$global:flare_promptHeadRight ??= ''
$global:flare_promptTailRight ??= '▓▒░'
$global:flare_topPrefix ??= '╭─'
$global:flare_bottomPrefix ??= '╰─'
$global:flare_promptArrow ??= ''

$global:flare_icons_pwd ??= ''
$global:flare_icons_git ??= ''
$global:flare_icons_zig ??= ''
$global:flare_icons_rust ??= ''
$global:flare_icons_node ??= '󰎙'
$global:flare_icons_python ??= ''

# $global:flare_icons_bun ??= ''
$global:flare_icons_java ??= ''

$global:flare_icons_go ??= ''

$global:flare_dateFormat ??= 'HH:mm:ss'

$global:flare_leftPieces ??= @(
  'os'
  'pwd'
  'git'
)

$global:flare_rightPieces ??= @(
  'date'
  'node'
  'rust'
  'zig'
  'go'
  'bun'
  'java'
  'python'
  'lastCommand'
)
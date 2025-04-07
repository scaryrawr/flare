# Flare Prompt

A work in progress.

A powershell native prompt designed to mimic the look and _someday_ feel of [tide](https://github.com/IlanCosman/tide) and/or [powerlevel10k](https://github.com/romkatv/powerlevel10k).

Very little exists here at the moment, and development may be slower as I use Windows less and less.

![Prompt Appearance](./preview.png)

Currently, it uses base16 colors that it inherits from your terminal.

## Customization

### Separators, Heads, and Tails

Right now, before loading flare, you can customize the prompt separators, the defaults are below:

```pwsh
$global:flare_promptSeparatorsLeft ??= ""
$global:flare_promptHeadLeft ??= ""
$global:flare_promptTailLeft ??= "░▒▓"
$global:flare_promptSeparatorsRight ??= ""
$global:flare_promptHeadRight ??= ""
$global:flare_promptTailRight ??= "▓▒░"
$global:flare_gitIcon ??= ""
$global:flare_topPrefix ??= "╭─"
$global:flare_bottomPrefix ??= "╰─"
$global:flare_promptArrow ??= ""
```

You can set the pieces to different symbols/characters/strings.

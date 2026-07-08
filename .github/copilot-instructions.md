# Copilot instructions for Flare Prompt

## What this repo is
- Flare is a PowerShell module exporting `Prompt` (in `flare.psm1`) that renders a **two-line** prompt: a top “powerline” segment line + a bottom status/arrow line.

## How prompt rendering works
- `Prompt` calls `Get-PromptTopLine` + `Get-PromptLine`, sets `Set-PSReadLineOption -ExtraPromptLineCount 1`, and returns ``"`r$topLine`n$line "``.
- Left/right segments come from `$global:flare_leftPieces` / `$global:flare_rightPieces` in `promptSymbols.ps1`.
- Segment styling is ANSI escapes; visible-width math strips escapes via `$escapeRegex = "(`e\[\d+\w)"`.
- A custom PSReadLine Enter handler clears the old 2-line prompt and reprints the entered command (see bottom of `flare.psm1`).

## Pieces (segments) contract
- Each piece is `pieces/<name>.ps1` defining `function flare_<name> { ... }`. Return `''` to hide.
- Pieces are dot-sourced and invoked by `utils/invokeUtils.ps1` (`Invoke-FlarePiece`, `Get-PromptPieceResults`): avoid global side effects and avoid `Write-Host`.
- Prefer gating on tool availability with `Get-Command` (e.g., `pieces/node.ps1` checks `node`; `pieces/git.ps1` checks `git`).
- For slow/IO work, add a fast fallback: `pieces/<name>_fast.ps1` → `flare_<name>_fast`.
  - `Update-MainThreadPieces` uses `*_fast` only when there’s no cached “real” result yet (example: `python_fast` / `git_fast`).

## Caching + background updates
- Main-thread pieces are listed in `$global:flare_mainThread` (defaults: `os`, `date`, `lastCommand`, `pwd`). Others run in `Start-ThreadJob`.
- Background jobs write a timestamped `_package_<timestamp>` into `$global:flare_resultCache` (a `ConcurrentDictionary`); `PowerShell.OnIdle` applies only the newest package, then redraws if values differ from `$global:flare_lastRenderCache`.
- `PowerShell.OnIdle` event actions run as event jobs and may keep their own stale location/function scope; keep the registered action self-contained and use the last rendered prompt directory (`$global:flare_lastDirectory.Path`) when matching background packages.
- Avoid `[ref]`-based `ConcurrentDictionary.TryGetValue` calls in prompt redraw/event-job paths; prefer `ContainsKey` plus indexed reads because event-job execution can fail PowerShell overload binding for those calls.
- When `$PWD` changes, `Prompt` clears caches to avoid stale repo-specific results.

## Customization knobs
- Edit `promptSymbols.ps1` for separators/heads/tails, icons (`$global:flare_icons_<piece>`), date format (`$global:flare_dateFormat`), and piece ordering.

## Tech Stack
- PowerShell 7+ (cross-platform)
- No external dependencies required (uses built-in PowerShell modules)
- Relies on `PSReadLine` module for prompt handling
- Uses `Start-ThreadJob` for background execution

## Coding Conventions
- Use PowerShell approved verbs for function names (e.g., `Get-`, `Set-`, `Invoke-`)
- Prefix all piece functions with `flare_` (e.g., `flare_git`, `flare_node`)
- Prefix all global variables with `$global:flare_` (e.g., `$global:flare_icons_git`)
- Use PowerShell null-coalescing operator `??=` for default values
- Avoid `Write-Host` in pieces; return strings instead
- Check tool availability with `Get-Command` before invoking external tools
- Use ANSI escape sequences for colors: `` `e[<code>m`` format

## File Structure
- `flare.psm1` - Main module file, entry point for the prompt
- `promptSymbols.ps1` - Configuration for symbols, icons, separators, and piece ordering
- `pieces/*.ps1` - Individual prompt segment implementations
- `utils/*.ps1` - Helper utilities for invoking pieces and managing state
- Test scripts at root: `test*.ps1`, `debug*.ps1`

### Do Not Modify
- ANSI color codes in `$foregroundStyles` and `$backgroundStyles` unless fixing a bug
- The core prompt rendering logic in `Prompt` function unless fixing a bug
- PSReadLine handler logic unless fixing a bug

## Testing & Validation
All commands should be run from repository root with PowerShell 7+:

### Import and Load Module
```pwsh
Import-Module ./flare.psm1
```

### Local Testing Commands
- `./testPiecesTiming.ps1` - Creates a temp git repo + fixture files like `package.json`, `go.mod`, `Cargo.toml`, `build.zig`, etc. to exercise all pieces
- `./testGitStates.ps1` - Covers merge/rebase/cherry-pick + ahead/behind + status counts for `pieces/git.ps1`
- `./debugPieceTiming.ps1 -WorkingDirectory <path> -Iterations 50` - Timing in a real repo
- `./testPromptTiming.ps1` - End-to-end `Prompt` timing

### CI Workflow
- Workflow: `.github/workflows/validation.yml`
- Runs on Windows, macOS, and Ubuntu (all platforms must pass)
- Installs Zig for testing the Zig piece
- Imports `flare.psm1`, runs `testPiecesTiming.ps1`, then `testGitStates.ps1`

## Common Patterns

### Adding a New Piece
1. Create `pieces/<name>.ps1` with `function flare_<name> { ... }`
2. Add icon in `promptSymbols.ps1`: `$global:flare_icons_<name> ??= '󰊠'`
3. Add piece name to `$global:flare_leftPieces` or `$global:flare_rightPieces`
4. Return empty string `''` when piece should be hidden
5. Check tool availability: `if (-not (Get-Command <tool> -ErrorAction SilentlyContinue)) { return '' }`
6. For slow operations, create `pieces/<name>_fast.ps1` with quick fallback

### Example Piece Structure
```pwsh
function flare_example {
    # Check if tool is available
    if (-not (Get-Command example-tool -ErrorAction SilentlyContinue)) {
        return ''
    }
    
    # Get information
    $info = example-tool --version
    
    # Return formatted string with icon
    return "$global:flare_icons_example $info"
}
```

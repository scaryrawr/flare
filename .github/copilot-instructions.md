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
- When `$PWD` changes, `Prompt` clears caches to avoid stale repo-specific results.

## Customization knobs
- Edit `promptSymbols.ps1` for separators/heads/tails, icons (`$global:flare_icons_<piece>`), date format (`$global:flare_dateFormat`), and piece ordering.

## Dev workflows (what CI runs)
- CI: `.github/workflows/validation.yml` imports `flare.psm1`, runs `testPiecesTiming.ps1`, then `testGitStates.ps1` (Zig is installed in CI).
- Run locally (pwsh, repo root):
  - `./testPiecesTiming.ps1` (creates a temp git repo + fixture files like `package.json`, `go.mod`, `Cargo.toml`, `build.zig`, etc. to exercise pieces)
  - `./testGitStates.ps1` (covers merge/rebase/cherry-pick + ahead/behind + status counts for `pieces/git.ps1`)
  - `./debugPieceTiming.ps1 -WorkingDirectory <path> -Iterations 50` (timing in a real repo)
  - `./testPromptTiming.ps1` (end-to-end `Prompt` timing)

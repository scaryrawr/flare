# Flare PowerShell Prompt - Agent Guidelines

## Build/Test Commands
- **Test all pieces**: `./testPiecesTiming.ps1` - Validates all prompt pieces work correctly
- **Test git functionality**: `./testGitStates.ps1` - Tests git piece across various states  
- **Debug timing**: `./debugPieceTiming.ps1` - Performance testing for individual pieces
- **Load module**: `Import-Module ./flare.psm1` - Import the prompt module
- **CI validation**: Uses GitHub Actions workflow in `.github/workflows/validation.yml`

## Architecture
- **Main module**: `flare.psm1` - Core prompt engine with async background jobs
- **Pieces**: Individual prompt components in `pieces/` directory (git.ps1, node.ps1, etc.)
- **Utils**: Helper functions in `utils/` (invokeUtils.ps1, fileUtils.ps1)
- **Pattern**: Each piece implements `flare_<name>` function that returns string or empty

## Code Style
- **Functions**: PascalCase (Get-PromptLine, Start-PieceJob)
- **Variables**: camelCase with descriptive names ($promptColor, $gitDir)  
- **Globals**: Prefix with `global:flare_` ($global:flare_promptState)
- **Error handling**: Use `-ErrorAction SilentlyContinue` and return empty strings on failure
- **Performance**: Async background jobs for slow operations, main thread for fast pieces
- **Comments**: Minimal, only for complex logic or performance notes
- **Imports**: Use dot-sourcing `. $PSScriptRoot/path/file.ps1` for script inclusion
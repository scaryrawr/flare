function flare_python_fast {
    # Enhanced virtual environment detection with multiple methods
    $venvName = $null
    
    # Method 1: Standard VIRTUAL_ENV variable
    if ($env:VIRTUAL_ENV) {
        $venvPath = $env:VIRTUAL_ENV
        $venvName = Split-Path -Path $venvPath -Leaf
        
        # Handle nested virtual environments (like in .venv folders)
        if ($venvName -eq '.venv' -or $venvName -eq 'venv') {
            $parentDir = Split-Path -Path (Split-Path -Path $venvPath -Parent) -Leaf
            $venvName = "$parentDir($venvName)"
        }
    }
    # Method 2: Conda environment
    elseif ($env:CONDA_DEFAULT_ENV -and $env:CONDA_DEFAULT_ENV -ne 'base') {
        $venvName = $env:CONDA_DEFAULT_ENV
    }
    # Method 3: Poetry virtual environment
    elseif ($env:POETRY_ACTIVE) {
        # Try to get poetry env name
        $poetryEnv = try { poetry env info --name 2>$null } catch { $null }
        if ($poetryEnv) {
            $venvName = $poetryEnv.Trim()
        } else {
            $venvName = "poetry"
        }
    }
    # Method 4: Pipenv virtual environment
    elseif ($env:PIPENV_ACTIVE) {
        $venvName = "pipenv"
    }
    # Method 5: Python version from pyenv
    elseif ($env:PYENV_VERSION) {
        $venvName = "py:$($env:PYENV_VERSION)"
    }
    
    if ($venvName) {
        return "($venvName)"
    }
    
    return ''
}
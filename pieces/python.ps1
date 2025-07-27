. $PSScriptRoot/python_fast.ps1

function Test-PythonProject {
    # Check for Python project indicators
    $indicators = @(
        'requirements.txt',
        'Pipfile',
        'pyproject.toml',
        'setup.py',
        'setup.cfg',
        'environment.yml',
        'conda.yaml',
        'poetry.lock',
        '.python-version'
    )
    
    foreach ($indicator in $indicators) {
        if (Test-Path $indicator) {
            return $true
        }
    }
    
    # Check for .py files in current directory
    $pyFiles = Get-ChildItem -Filter "*.py" -ErrorAction SilentlyContinue | Select-Object -First 1
    return $null -ne $pyFiles
}

function flare_python {
    $venvName = flare_python_fast
    
    # Always show virtual environment if active
    if ($venvName) {
        # Try different Python commands in order of preference
        $pythonCommands = @('python', 'python3', 'py')
        $version = $null
        
        foreach ($cmd in $pythonCommands) {
            if (Get-Command $cmd -ErrorAction SilentlyContinue) {
                try {
                    $versionOutput = & $cmd --version 2>&1
                    if ($versionOutput -and $versionOutput -match 'Python\s+(\d+\.\d+\.\d+)') {
                        $version = $Matches[1]
                        break
                    }
                }
                catch {
                    # Continue to next command
                    continue
                }
            }
        }
        
        if ($version) {
            return "$version $venvName"
        }
        return $venvName
    }
    
    # Only show Python version if we're in a Python project
    if (Test-PythonProject) {
        # Try different Python commands
        $pythonCommands = @('python', 'python3', 'py')
        
        foreach ($cmd in $pythonCommands) {
            if (Get-Command $cmd -ErrorAction SilentlyContinue) {
                try {
                    $versionOutput = & $cmd --version 2>&1
                    if ($versionOutput -and $versionOutput -match 'Python\s+(\d+\.\d+\.\d+)') {
                        return $Matches[1]
                    }
                }
                catch {
                    continue
                }
            }
        }
    }
    
    return ''
}
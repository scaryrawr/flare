. $PSScriptRoot/python_fast.ps1

function flare_python {
  $venv_name = flare_python_fast
  if (-not $venv_name) {
    return ''
  }

  if (Get-Command python -ErrorAction SilentlyContinue) {
    $python_version = python --version 2>&1 | Select-String -Pattern '(\d+\.\d+\.\d+)' | ForEach-Object { $_.Matches.Groups[1].Value }
  }
  elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
    $python_version = & python3 --version 2>&1 | Select-String -Pattern '(\d+\.\d+\.\d+)' | ForEach-Object { $_.Matches.Groups[1].Value }
  }
  else {
    return $venv_name
  }

  return "$python_version $venv_name"
}
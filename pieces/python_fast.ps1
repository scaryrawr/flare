function flare_python_fast {
  if ($env:VIRTUAL_ENV) {
    $venv_folder = Split-Path -Path $env:VIRTUAL_ENV -Parent
    return "($(Split-Path -Path $venv_folder -Leaf))"
  }

  return ''
}
function flare_pwd {
  return "$($executionContext.SessionState.Path.CurrentLocation.ToString().Replace($HOME, '~'))"
}
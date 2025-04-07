function Get-GitStatus {
  $status = git --no-optional-locks status -sb --porcelain 2> $null
  if ($status) {
    $added = 0
    $modified = 0
    $deleted = 0
    $renamed = 0
    $copied = 0
    $unmerged = 0
    $untracked = 0
    $ahead = 0;
    $behind = 0;

    $status -split "`n" | ForEach-Object {
      if ($_ -match "^\s*([AMDRCU?]+)\s+(.*)") {
        # $file = $Matches[2]
        $status = $Matches[1]
        switch ($status) {
          "A" { $added += 1 }
          "M" { $modified += 1 }
          "D" { $deleted += 1 }
          "R" { $renamed += 1 }
          "C" { $copied += 1 }
          "U" { $unmerged += 1 }
          "??" { $untracked += 1 }
        }
      }
      elseif ($_ -match "(ahead|behind) (\d+)") {
        $status = $Matches[1]
        $count = $Matches[2]
        switch ($status) {
          "ahead" { $ahead += $count }
          "behind" { $behind += $count }
        }
      }
    }

    $script:statusString = ""
    function Add-Status($icon, $count) {
      if ($count -eq 0) { return }
      if ($script:statusString) { $script:statusString += " " }
      $script:statusString += "$icon $count"
    }

    Add-Status "" $ahead
    Add-Status "" $behind
    Add-Status "" $added
    Add-Status "" $modified
    Add-Status "󰆴" $deleted
    Add-Status "󰑕" $renamed
    Add-Status "" $copied
    Add-Status "" $unmerged
    Add-Status "" $untracked

    return $script:statusString
  }

  return ""
}

function Get-GitBranch {
  $branch = git --no-optional-locks rev-parse --abbrev-ref HEAD 2> $null
  if ($branch) {
    return "$flare_gitIcon $branch $(Get-GitStatus)"
  }
  else {
    return ""
  }
}
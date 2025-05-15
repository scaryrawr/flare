. $PSScriptRoot/../utils/fileUtils.ps1

function flare_java {
  $pomXmlPath = FindFileInParentDirectories -fileName 'pom.xml'
  $buildGradlePath = FindFileInParentDirectories -fileName 'build.gradle'
  $buildGradleKtsPath = FindFileInParentDirectories -fileName 'build.gradle.kts'

  if ($pomXmlPath -or $buildGradlePath -or $buildGradleKtsPath) {
    if (Get-Command java -ErrorAction SilentlyContinue) {
      return java -version 2>&1 | Select-String -Pattern 'version "([\d._]+)"' | ForEach-Object { $_.Matches.Groups[1].Value }
    }
  }

  return ''
}

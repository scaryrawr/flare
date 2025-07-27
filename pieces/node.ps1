. $PSScriptRoot/../utils/fileUtils.ps1

function flare_node {
    # Check for Node.js project indicators
    $packageJsonPath = FindFileInParentDirectories -fileName 'package.json'
    $nodeModulesPath = FindFileInParentDirectories -fileName 'node_modules'
    $packageLockPath = FindFileInParentDirectories -fileName 'package-lock.json'
    $yarnLockPath = FindFileInParentDirectories -fileName 'yarn.lock'
    
    # Only show Node version if we're in a Node.js project
    if ($packageJsonPath -or $nodeModulesPath -or $packageLockPath -or $yarnLockPath) {
        # Check if the node command is available
        $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
        if (-not $nodeCmd) {
            return ''
        }
        
        try {
            # Get version
            $version = & node --version 2>$null
            if ($version -and $version -match 'v?(\d+\.\d+\.\d+)') {
                $cleanVersion = $Matches[1]
                
                # Add package manager indicator
                $manager = ""
                if ($yarnLockPath) {
                    $manager = " yarn"
                }
                elseif ($packageLockPath) {
                    $manager = " npm"
                }
                
                return "$cleanVersion$manager"
            }
        }
        catch {
            # Silently handle errors
        }
    }

    return ''
}

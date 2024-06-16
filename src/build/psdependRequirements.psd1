@{
    PSDependOptions           = @{
        Target = 'CurrentUser'
    }
    'Pester'                  = @{
        Version    = 'latest'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
    'platyPS'                 = @{
        Version = 'latest'
    }
    'psake'                   = @{
        Version = 'latest'
    }
    'BuildHelpers'            = @{
        Version = 'latest'
    }
    'PowerShellBuild'         = @{
        Version = 'latest'
    }
    'PSScriptAnalyzer'        = @{
        Version = 'latest'
    }
    'Microsoft.WinGet.Client' = @{
        Version = 'latest'
    }
    'WinGetDependencies'      = @{
        DependencyType = 'task'
        Target         = './psdependTask_winget.ps1 -WinGetPackageId "Inkscape.Inkscape"'
        DependsOn      = 'Microsoft.WinGet.Client'
    }
}

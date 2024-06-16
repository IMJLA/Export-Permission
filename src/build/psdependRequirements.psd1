@{
    PSDependOptions           = @{
        Target = 'CurrentUser'
    }
    'Pester'                  = @{
        # Pester is used for unit testing.
        Version    = 'latest'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
    'PlatyPS'                 = @{
        # PlatyPS is used to convert comment-based help into Markdown and Updateable help.
        Version = 'latest'
    }
    'psake'                   = @{
        # psake is used to orchestrate the build process.
        Version = 'latest'
    }
    'BuildHelpers'            = @{
        # BuildHelpers is a dependency of PowerShellBuild
        Version = 'latest'
    }
    'PowerShellBuild'         = @{
        Version = 'latest'
    }
    'PSScriptAnalyzer'        = @{
        # PSScriptAnalyzer is used for linting.
        Version = 'latest'
    }
    'ChangelogManagement'     = @{
        # ChangelogManagement is used to update the release notes with each build.
        Version = 'latest'
    }
    'Microsoft.WinGet.Client' = @{
        # Microsoft.WinGet.Client is used to install Inkscape on Windows.
        Version = 'latest'
    }
    'WinGetDependencies'      = @{
        # Inkscape is used for SVG to PNG conversion.
        DependencyType = 'task'
        Target         = './psdependTask_winget.ps1 -WinGetPackageId "Inkscape.Inkscape"'
        DependsOn      = 'Microsoft.WinGet.Client'
    }
}

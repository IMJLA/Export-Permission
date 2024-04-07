# Initialize the BuildHelpers environment variables here so they are usable in all child scopes including the psake properties block
#BuildHelpers\Set-BuildEnvironment -Force

properties {

    # Default Locale used for help generation, defaults to en-US
    # Get-UICulture doesn't return a name on Linux so default to en-US
    $HelpDefaultLocale = if (-not (Get-UICulture).Name) { 'en-US' } else { (Get-UICulture).Name }

    $NoPublish = $false

    $PortableVersionGuid = $null

    # Convert project readme into the module about file
    $HelpConvertReadMeToAboutHelp = $true

    # Directory PlatyPS markdown documentation will be saved to
    $HelpRootDir = [IO.Path]::Combine($PSScriptRoot, 'docs')

    # Path to updatable help CAB
    $HelpUpdatableHelpOutDir = [IO.Path]::Combine($HelpRootDir, 'UpdatableHelp')

    $TestRootDir = [IO.Path]::Combine($PSScriptRoot, 'tests')

    $TestOutputFile = 'out/testResults.xml'

    # Enable/disable use of PSScriptAnalyzer to perform script analysis
    $TestLintEnabled = $true

    # When PSScriptAnalyzer is enabled, control which severity level will generate a build failure.
    # Valid values are Error, Warning, Information and None.  "None" will report errors but will not
    # cause a build failure.  "Error" will fail the build only on diagnostic records that are of
    # severity error.  "Warning" will fail the build on Warning and Error diagnostic records.
    # "Any" will fail the build on any diagnostic record, regardless of severity.
    $TestLintFailBuildOnSeverityLevel = 'Error'

    # Path to the PSScriptAnalyzer settings file.
    $TestLintSettingsPath = [IO.Path]::Combine($PSScriptRoot, 'tests\ScriptAnalyzerSettings.psd1')

    $TestEnabled = $true

    $TestOutputFormat = 'NUnitXml'

    # Enable/disable Pester code coverage reporting.
    $TestCodeCoverageEnabled = $false

    # Fail Pester code coverage test if below this threshold
    $TestCodeCoverageThreshold = .75

    # CodeCoverageFiles specifies the files to perform code coverage analysis on. This property
    # acts as a direct input to the Pester -CodeCoverage parameter, so will support constructions
    # like the ones found here: https://pester.dev/docs/usage/code-coverage.
    $TestCodeCoverageFiles = @()

    # Path to write code coverage report to
    $TestCodeCoverageOutputFile = [IO.Path]::Combine($TestRootDir, 'out', 'codeCoverage.xml')

    # The code coverage output format to use
    $TestCodeCoverageOutputFileFormat = 'JaCoCo'

    $TestImportModuleFirst = $false

    # PowerShell repository name to publish modules to
    $PublishPSRepository = 'PSGallery'

    # API key to authenticate to PowerShell repository with
    $PublishPSRepositoryApiKey = $env:PSGALLERY_API_KEY

    # Credential to authenticate to PowerShell repository with
    $PublishPSRepositoryCredential = $null

    $NewLine = [System.Environment]::NewLine

    $SourceCodePath = "$PSScriptRoot\src"

    $MainScript = Get-ChildItem -LiteralPath $SourceCodePath -Include *.ps1

    # Version of the script in the src directory before the build is run and the version is updated
    Write-Host "Test-ScriptFileInfo -LiteralPath $($MainScript.FullName)"
    $ScriptFileInfo = Test-ScriptFileInfo -LiteralPath $MainScript.FullName

    # List of files (regular expressions) to exclude from output directory
    $BuildExclude = @('gitkeep', "$($ScriptFileInfo.Name).psm1")

    # Controls whether to "compile" module into single PSM1 or not
    $BuildCompileModule = $true

    $BuildCompileHeader

    $BuildCompileFooter

    $BuildCompileScriptHeader

    $BuildCompileScriptFooter

    # List of directories that if BuildCompileModule is $true, will be concatenated into the PSM1
    $BuildCompileDirectories = @('classes', 'enums', 'filters', 'functions/private', 'functions/public')

    # List of directories that will always be copied "as is" to output directory
    $BuildCopyDirectories = @() #@('bin', 'config', 'data', 'lib')

    # Output directory when building a module
    $BuildOutDir = [IO.Path]::Combine($PSScriptRoot, 'dist')

    $AllPowerShellCodeFiles = Get-ChildItem -Path $SourceCodePath -Directory -Exclude bin, config, data, en-US, UpdatableHelp |
    Get-ChildItem -Include *.ps1, *.psm1, *.psd1 -Recurse

    $ModuleManifests = $AllPowerShellCodeFiles |
    Where-Object {
        $_.Extension -eq '.psd1'
    } |
    Sort-Object -Property FullName

}

FormatTaskName {
    param($taskName)
    Write-Host 'Task: ' -ForegroundColor Cyan -NoNewline
    Write-Host $taskName -ForegroundColor Blue
}

task Default -depends Publish

$analyzePreReqs = {
    $result = $true
    if (-not $TestLintEnabled) {
        Write-Warning 'Script analysis is not enabled.'
        $result = $false
    }
    if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable)) {
        Write-Warning 'PSScriptAnalyzer module is not installed'
        $result = $false
    }
    $result
}

task Lint -precondition $analyzePreReqs {
    $analyzeParams = @{
        Path              = $SourceCodePath
        SeverityThreshold = $TestLintFailBuildOnSeverityLevel
        SettingsPath      = $TestLintSettingsPath
    }
    Test-PSBuildScriptAnalysis @analyzeParams
} -description 'Execute PSScriptAnalyzer tests'

task DetermineNewVersionNumber -Depends Lint {

    "`tOld Version: $($ScriptFileInfo.Version)"
    $OldVersion = [version]$ScriptFileInfo.Version
    if ($IncrementMajorVersion) {
        "`tThis is a new major version"
        [version]$script:NewVersion = "$([int]$OldVersion.Major + 1).0.0"
    } elseif ($IncrementMinorVersion) {
        "`tThis is a new minor version"
        [version]$script:NewVersion = "$([int]$OldVersion.Major).$([int]$OldVersion.Minor + 1).0"
    } else {
        "`tThis is a new build"
        [version]$script:NewVersion = "$([int]$OldVersion.Major).$([int]$OldVersion.Minor).$([int]$OldVersion.Build + 1)"
    }
    "`tNew Version: $script:NewVersion$NewLine"

    $script:BuildOutputFolder = [IO.Path]::Combine(
        $BuildOutDir,
        $script:NewVersion,
        $ScriptFileInfo.Name
    )
    $script:BuildOutputFolderForPortableVersion = [IO.Path]::Combine(
        $BuildOutDir,
        $script:NewVersion,
        "$($ScriptFileInfo.Name)Portable"
    )

} -description 'Increment the version'

task UpdateScriptVersion -Depends DetermineNewVersionNumber {
    Update-ScriptFileInfo -Path $MainScript.FullName -Version $script:NewVersion -ReleaseNotes $CommitMessage

    # Supposedly will be resolved in 3.0.15 but right now there is a bug in Update-ScriptFileInfo that adds blank lines after the PSScriptInfo block
    # This RegEx was going to be used to help remove those lines but for now I am just awaiting the new version
    # https://github.com/PowerShell/PowerShellGet/issues/347
    # $RegEx = '#>[\s\S]*<#\n\.SYNOPSIS'
} -description 'Update PSScriptInfo with the new version'

task RotateBuilds -depends UpdateScriptVersion {
    $BuildVersionsToRetain = 1
    Get-ChildItem -Directory -Path $BuildOutDir |
    Sort-Object -Property Name |
    Select-Object -SkipLast ($BuildVersionsToRetain - 1) |
    ForEach-Object {
        "`tDeleting old build .\$((($_.FullName -split '\\') | Select-Object -Last 2) -join '\')"
        $_ | Remove-Item -Recurse -Force
    }
    $NewLine
} -description 'Rotate old builds out of the output directory'

task UpdateChangeLog -depends RotateBuilds -Action {
    <#
TODO
    This task runs before the Test task so that tests of the change log will pass
    But I also need one that runs *after* the build to compare it against the previous build
    The post-build UpdateChangeLog will automatically add to the change log any:
        New/removed exported commands
        New/removed files
#>
    $ChangeLog = "$PSScriptRoot\CHANGELOG.md"
    $NewChanges = "## [$script:NewVersion] - $(Get-Date -format 'yyyy-MM-dd') - $CommitMessage$NewLine"
    "`tChange Log:  $ChangeLog"
    "`tNew Changes: $NewChanges"
    [string[]]$ChangeLogContents = Get-Content -Path $ChangeLog
    $LineNumberOfLastChange = Select-String -Path $ChangeLog -Pattern '^\#\# \[\d*\.\d*\.\d*\]' |
    Select-Object -First 1 -ExpandProperty LineNumber
    $HeaderLineCount = $LineNumberOfLastChange - 1
    $NewChangeLogContents = [System.Collections.Specialized.StringCollection]::new()
    $null = $NewChangeLogContents.AddRange(($ChangeLogContents |
            Select-Object -First $HeaderLineCount))
    $null = $NewChangeLogContents.Add($NewChanges)
    $null = $NewChangeLogContents.AddRange(($ChangeLogContents |
            Select-Object -Skip $HeaderLineCount))
    $NewChangeLogContents | Out-File -FilePath $ChangeLog -Encoding utf8 -Force
}

task BuildReleaseForDistribution -depends UpdateChangeLog {

    # Create a new output directory
    $null = New-Item -Path $script:BuildOutputFolder -ItemType Directory
    $FolderName = $script:BuildOutputFolder | Split-Path -Leaf

    # Copy the source script to the output folder
    $MainScript |
    Copy-Item -Destination $script:BuildOutputFolder

    $script:ReleasedScript = Get-ChildItem -LiteralPath $script:BuildOutputFolder -Include *.ps1

    if ($PortableVersionGuid) {
        # Create a new output directory
        $null = New-Item -Path $script:BuildOutputFolderForPortableVersion -ItemType Directory

        # Read in the current contents of the script
        $MainScriptContent = $MainScript |
        Get-Content -Raw

        # Read the metadata of the script (we will use it to enumerate required modules)
        $MainScriptFileInfoTest = Test-ScriptFileInfo -LiteralPath $MainScript.FullName -ErrorAction Continue

        # Prep an empty collection of strings to store our new portable script
        $PortableScriptContent = [System.Collections.Generic.List[string]]::New()

        # Find the place in our script we intend to insert all the module code
        $RegExOptions = [System.Text.RegularExpressions.RegexOptions]::Singleline
        $RegEx = '(.*\#----------------\[ Functions ]------------------).*(\#----------------\[ Logging ]----------------.*)'
        $Matches = [regex]::Match($MainScriptContent, $RegEx, $RegExOptions)

        # Add the first half of the script to our target collection (everything up until the place in our script we intend to insert all the module code)
        $null = $PortableScriptContent.Add($Matches.Groups[1].Value)

        # Add the constituent code of each module
        ForEach ($ThisModuleName in $MainScriptFileInfoTest.RequiredModules.Name) {

            # Get the latest version of the module
            $ThisModule = Get-Module -Name $ThisModuleName -ListAvailable |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

            # Find the .psm1 file
            $ThisModuleFile = Get-ChildItem -LiteralPath $ThisModule.ModuleBase -Include *.psm1

            # Load the contents of the .psm1 file
            $ThisModuleDefinition = $ThisModuleFile |
            Get-Content -Raw

            if ($ThisModuleDefinition) {
                # Remove Export-ModuleMember from the module code since it has no purpose inside the script
                $ThisModuleDefinition = $ThisModuleDefinition -replace 'Export-ModuleMember.*\n[\S]*.*', ''

                # Add this module code to our target collection
                $null = $PortableScriptContent.Add("# Definition of Module '$ThisModuleName' Version '$($ThisModule.Version)' is below")
                $null = $PortableScriptContent.Add($ThisModuleDefinition.Trim())

                # Remove the Requires statement for this module
                $PortableScriptContent[0] = $PortableScriptContent[0] -replace [regex]::Escape("#Requires -Module $ThisModuleName"), ''
            }
        }

        # Prepare to add a line to the SYNOPSIS indicating this is a portable version of the script
        $RegEx = '(\.SYNOPSIS)(.*)(\.DESCRIPTION)'
        $Matches2 = [regex]::Match($PortableScriptContent[0], $RegEx, $RegExOptions)
        $Replacement = $Matches2.Groups[1].Value,
        "    Portable version of $FolderName with all ScriptModule dependencies rolled up into this single .ps1 file",
        $Matches2.Groups[2].Value,
        $Matches2.Groups[3].Value -join "`r`n"

        # Add a line to the SYNOPSIS indicating this is a portable version of the script
        $RegEx = '\.SYNOPSIS(.|\n)*\.DESCRIPTION'
        $PortableScriptContent[0] = $PortableScriptContent[0] -replace $RegEx, $Replacement

        # Add the second half of the script to our target collection (everything after the place in our script we intend to insert all the module code)
        $null = $PortableScriptContent.Add($Matches.Groups[2].Value)

        $Result = $PortableScriptContent -join "`r`n`r`n"

        #Update-ScriptFileInfo does not allow us to remove RequiredModules or ExternalModuleDependencies so we'll do it ourselves
        $Result = $Result -replace
        '\.EXTERNALMODULEDEPENDENCIES.*', '.EXTERNALMODULEDEPENDENCIES' -replace
        '\.REQUIREDMODULES.*', '.REQUIREDMODULES'

        # ---BEGIN SECTION TO PARTIALLY MINIFY THE CODE DUE TO PSGALLERY 10k LINE LIMIT---
        # Parse the PowerShell code
        $Tokens = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput(
            $Result,
            [ref]$Tokens,
            [ref]$null
        )

        # Find all the comments.
        # Filter out the Script File Info block which must remain for publishing to PSGallery.
        # Sort the comments by length in descending order.
        # This way the shortest comments (which are potentially just a # with nothing else) are removed last.
        # If '#' were removed first, nothing else would be a comment
        $Comments = $Tokens.Where({ $_.kind -eq 'comment' }).Text |
        #Where-Object -FilterScript {
        #    -not ([regex]::Match($_, '(\.LICENSEURI)(.*)(\.PROJECTURI)', $RegExOptions)).Success
        #} |
        Sort-Object -Property Length -Descending -Unique

        # Remove the comments
        ForEach ($Comment in $Comments) {
            if ($Comment -eq '#') {
                $escaped = '^\s*#$' # Need to avoid the Script File Info block <# ... #>
            } else {
                $escaped = [regex]::Escape($Comment)
            }
            $Result = $Result -replace $escaped , ''
        }

        # Remove blank lines
        $Result = $Result -replace '\r\n[\s]*\r\n', "`r`n" -replace '\r\n[\s]*\r\n', "`r`n" -replace '\r\n\[\s]*r\n', "`r`n"
        # ---END SECTION TO PARTIALLY MINIFY THE CODE DUE TO PSGALLERY 10k LINE LIMIT---

        # Write the output to file
        $script:PortableScriptFilePath = "$script:BuildOutputFolderForPortableVersion\$FolderName`Portable.ps1"
        $Result | Out-File -LiteralPath $PortableScriptFilePath

        # Assign the correct GUID to the portable version of the script (it should be unique, not shared with the other script)
        $Properties = @{
            Version      = $MainScriptFileInfoTest.Version
            Description  = $MainScriptFileInfoTest.Description
            Author       = $MainScriptFileInfoTest.Author
            CompanyName  = $MainScriptFileInfoTest.CompanyName
            Copyright    = $MainScriptFileInfoTest.Copyright
            Tags         = $MainScriptFileInfoTest.Tags
            ReleaseNotes = [string]$MainScriptFileInfoTest.ReleaseNotes
            LicenseUri   = $MainScriptFileInfoTest.LicenseUri
            ProjectUri   = $MainScriptFileInfoTest.ProjectUri
        }
        New-PSScriptFileInfo -Path $PortableScriptFilePath -Guid $PortableVersionGuid -Force @Properties
    }

} -description 'Build a monolithic PowerShell script based on the source script and its ScriptModule dependencies'

$genMarkdownPreReqs = {
    $result = $true
    if (-not (Get-Module PlatyPS -ListAvailable)) {
        Write-Warning "PlatyPS module is not installed. Skipping [$($psake.context.currentTaskName)] task."
        $result = $false
    }
    $result
}

task DeleteMarkdownHelp -depends BuildReleaseForDistribution -precondition $genMarkdownPreReqs {
    $MarkdownDir = [IO.Path]::Combine($HelpRootDir, $HelpDefaultLocale)
    "`tDeleting folder: '$MarkdownDir'"
    Get-ChildItem -Path $MarkdownDir -Recurse | Remove-Item
    $NewLine
} -description 'Delete existing .md files to prepare for PlatyPS to build new ones'

task BuildMarkdownHelp -depends DeleteMarkdownHelp {

    if (-not (Test-Path -LiteralPath $HelpRootDir)) {
        New-Item -Path $HelpRootDir -ItemType Directory > $null
    }

    $newMDParams = @{
        AlphabeticParamsOrder = $true
        # ErrorAction set to SilentlyContinue so this command will not overwrite an existing MD file.
        ErrorAction           = 'SilentlyContinue'
        Force                 = $true
        Command               = ".\src\$($ScriptFileInfo.Name).ps1"
        Metadata              = @{
            'script guid'  = $ScriptFileInfo.Guid
            locale         = $HelpDefaultLocale
            'help version' = $ScriptFileInfo.Version
            #'download help link' = 'N/A'
        }
        # TODO: Using GitHub pages as a container for PowerShell Updatable Help https://gist.github.com/TheFreeman193/fde11aee6998ad4c40a314667c2a3005
        # OnlineVersionUrl = $GitHubPagesLinkForThisModule
        OutputFolder          = [IO.Path]::Combine($HelpRootDir, $HelpDefaultLocale)
        UseFullTypeName       = $true
        Verbose               = $VerbosePreference
    }
    $MarkdownHelp = New-MarkdownHelp @newMDParams

    # Workaround a bug in New-MarkdownHelp with the Command ParameterSet
    $Markdown = Get-Content -LiteralPath $MarkdownHelp.FullName -Raw
    $NewMarkdown = $Markdown -replace 'Module Name:', "script name: $($MainScript.Name)"
    $NewMarkdown = $NewMarkdown -replace 'Module Guid:', "script guid: $($MainScript.Name)"

    # Workaround a bug since PS 7.4 introduced the ProgressAction common param which is not yet supported by PlatyPS
    $ParamToRemove = '-ProgressAction'
    $Pattern = "### $ParamToRemove\r?\n[\S\s\r\n]*?(?=#{2,3}?)"
    $NewMarkdown = [regex]::replace($NewMarkdown, $pattern, '')
    $Pattern = [regex]::Escape('[-ProgressAction <ActionPreference>] ')
    $NewMarkdown = [regex]::replace($NewMarkdown, $Pattern, '')

    $NewMarkdown | Set-Content -LiteralPath $MarkdownHelp.FullName

    # Use the help for the script as the readme for the script
    $MarkdownHelp | Copy-Item -Destination .\README.md -Force

} -description 'Generate markdown files from the script help'

$genHelpFilesPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($psake.context.currentTaskName)] task."
        $result = $false
    }
    $result
}

task BuildMAMLHelp -depends BuildMarkdownHelp -precondition $genHelpFilesPreReqs {
    Write-Host "Build-PSBuildMAMLHelp -Path '$HelpRootDir' -DestinationPath '$script:BuildOutputFolder'"
    Build-PSBuildMAMLHelp -Path $HelpRootDir -DestinationPath $script:BuildOutputFolder
} -description 'Generates MAML-based help from PlatyPS markdown files'

# Disabled this task for now, it does not work because New-ExternalHelp (invoked above by Build-PSBuildMAMLHelp) is not generating any xml help files from the markdown.
#task BuildUpdatableHelp -depends BuildMAMLHelp {
task BuildUpdatableHelp {

    $OS = (Get-CimInstance -ClassName CIM_OperatingSystem).Caption
    if ($OS -notmatch 'Windows') {
        Write-Warning 'MakeCab.exe is only available on Windows. Cannot create help cab.'
        return
    }

    $helpLocales = (Get-ChildItem -Path $HelpRootDir -Directory -Exclude 'UpdatableHelp').Name

    if ($null -eq $HelpUpdatableHelpOutDir) {
        $HelpUpdatableHelpOutDir = [IO.Path]::Combine($HelpRootDir, 'UpdatableHelp')
    }

    # Create updatable help output directory
    if (-not (Test-Path -LiteralPath $HelpUpdatableHelpOutDir)) {
        New-Item $HelpUpdatableHelpOutDir -ItemType Directory -Verbose:$VerbosePreference > $null
    } else {
        Write-Verbose "Removing existing directory: [$HelpUpdatableHelpOutDir]."
        Get-ChildItem $HelpUpdatableHelpOutDir | Remove-Item -Recurse -Force -Verbose:$VerbosePreference
    }

    # Generate updatable help files.  Note: this will currently update the version number in the module's MD
    # file in the metadata.
    foreach ($locale in $helpLocales) {
        Write-Information "'$([IO.Path]::Combine($HelpRootDir, $locale, "$($MainScript.Name).md"))'"
        $cabParams = @{
            CabFilesFolder  = [IO.Path]::Combine($script:BuildOutputFolder, $locale)
            LandingPagePath = [IO.Path]::Combine($HelpRootDir, $locale, "$($MainScript.Name).md")
            OutputFolder    = $HelpUpdatableHelpOutDir
            Verbose         = $VerbosePreference
            ErrorAction     = 'Continue'
        }
        New-ExternalHelpCab @cabParams 2> $null
    }

} -description 'Create updatable help .cab file based on PlatyPS markdown help'


$pesterPreReqs = {
    $result = $true
    if (-not $TestEnabled) {
        Write-Warning 'Pester testing is not enabled.'
        $result = $false
    }
    if (-not (Get-Module -Name Pester -ListAvailable)) {
        Write-Warning 'Pester module is not installed'
        $result = $false
    }
    if (-not (Test-Path -Path $TestRootDir)) {
        Write-Warning "Test directory [$TestRootDir)] not found"
        $result = $false
    }
    return $result
}

task UnitTests -depends BuildMAMLHelp -precondition $pesterPreReqs {
    $pesterParams = @{
        Run          = @{
            Path = $TestRootDir
        }
        CodeCoverage = @{
            CoveragePercentTarget = $TestCodeCoverageThreshold
            Enabled               = $TestCodeCoverageEnabled
            OutputFormat          = $TestCodeCoverageOutputFormat
            OutputPath            = $TestCodeCoverageOutputFile
            Path                  = $TestCodeCoverageFiles
        }
        Output       = @{
            Verbosity = 'Diagnostic'
        }
        TestResult   = @{
            Enabled      = $true
            OutputPath   = $TestOutputFile
            OutputFormat = $TestOutputFormat
        }
    }

    $Config = New-PesterConfiguration -Hashtable $pesterParams
    Invoke-Pester -Configuration $Config
} -description 'Execute Pester tests'

task SourceControl -depends UnitTests {
    $CurrentBranch = git branch --show-current
    # Commit to Git
    git add .
    git commit -m $CommitMessage
    git push origin $CurrentBranch
} -description 'git add, commit, and push'

#task Publish -depends SourceControl {
task Publish -depends SourceControl {
    Assert -conditionToCheck ($PublishPSRepositoryApiKey -or $PublishPSRepositoryCredential) -failureMessage "API key or credential not defined to authenticate with [$PublishPSRepository)] with."

    $publishParams = @{
        Path       = $script:ReleasedScript.FullName
        Repository = $PublishPSRepository
        Verbose    = $VerbosePreference
    }
    if ($PublishPSRepositoryApiKey) {
        $publishParams.NuGetApiKey = $PublishPSRepositoryApiKey
    }

    if ($PublishPSRepositoryCredential) {
        $publishParams.Credential = $PublishPSRepositoryCredential
    }

    # Only publish a release if we are working on the main branch
    $CurrentBranch = git branch --show-current
    if ($NoPublish -eq $false -and $CurrentBranch -eq 'main') {
        # Publish to PSGallery
        Publish-Script @publishParams
        $publishParams['Path'] = $script:PortableScriptFilePath
        Publish-Script @publishParams
    }
} -description 'Publish module to the defined PowerShell repository'

task ? -description 'Lists the available tasks' {
    'Available tasks:'
    $psake.context.Peek().Tasks.Keys | Sort-Object
}

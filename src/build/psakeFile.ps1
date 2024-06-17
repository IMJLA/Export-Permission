properties {

    [boolean]$IncrementMajorVersion = $false

    [boolean]$IncrementMinorVersion = $false

    # Folder containing the script .ps1 file
    [System.IO.DirectoryInfo]$SourceCodeDir = [IO.Path]::Combine( '..', 'script' )

    # If specified, a self-contained portable version of the script with no external module dependencies will be created with this GUID.
    # This will be passed to the Guid parameter of New-ScriptFileInfo.
    [string]$PortableVersionGuid = $null

    # This character sequence will be used to separate lines in the console output.
    $NewLine = [System.Environment]::NewLine



    # PlatyPS (Markdown and Updateable help)

    # Default Locale used for help generation
    [string]$HelpDefaultLocale = 'en-US'

    # Convert project readme into the module 'about file'
    [boolean]$HelpConvertReadMeToAboutHelp = $true

    # Markdown-formatted Help will be created in this folder
    [System.IO.DirectoryInfo]$MarkdownHelpDir = [IO.Path]::Combine('..', '..', 'docs', 'Markdown')

    # .CAB-formatted Updatable Help will be created in this folder
    [System.IO.DirectoryInfo]$UpdatableHelpDir = [IO.Path]::Combine('..', '..', 'docs', 'updateable')



    # Pester (Unit Testing)

    # Unit tests found here will be performed using Pester.
    [System.IO.DirectoryInfo]$TestsDir = [IO.Path]::Combine('..', '..', 'tests')

    # Unit test results will be saved to this file by Pester.
    [System.IO.DirectoryInfo]$TestsResultFile = [IO.Path]::Combine('..', '..', 'out', 'testResults.xml')

    # Whether or not to perform unit tests using Pester.
    [Boolean]$TestEnabled = $true

    <#
    Test results will be output in this format.
    This is the Pester ConfigurationProperty TestResult.OutputFormat.
    As of Pester v5, valid values are:
        NUnitXml
        JUnitXml
    #>

    enum TestOutputFormat {
        NUnitXml # NUnit-compatible XML
        JUnitXml # JUnit-compatible XML
    }
    [TestOutputFormat]$TestOutputFormat = 'NUnitXml'

    # Enable/disable Pester code coverage reporting.
    [boolean]$TestCodeCoverageEnabled = $false

    # Fail Pester code coverage test if below this threshold
    [single]$TestCodeCoverageThreshold = .75

    # CodeCoverageFiles specifies the files to perform code coverage analysis on. This property
    # acts as a direct input to the Pester -CodeCoverage parameter, so will support constructions
    # like the ones found here: https://pester.dev/docs/usage/code-coverage.
    [System.IO.FileInfo[]]$TestCodeCoverageFiles = @()

    # Path to write code coverage report to
    [System.IO.FileInfo]$TestCodeCoverageOutputFile = [IO.Path]::Combine($TestsDir, 'out', 'codeCoverage.xml')

    # Format to use for code coverage report
    enum TestCodeCoverageOutputFormat {
        JaCoCo
        CoverageGutters
    }
    [TestCodeCoverageOutputFormat]$TestCodeCoverageOutputFormat = 'JaCoCo'



    # PSScriptAnalyzer (Linting)

    # Whether or not to perform linting with PSScriptAnalyzer using PowerShellBuild
    [boolean]$LintEnabled = $true

    # When PSScriptAnalyzer is enabled, control which severity level will generate a build failure.
    # Valid values are Error, Warning, Information and None.

    enum LintSeverity {
        None # Report errors but do not fail the build.
        ParseError # This diagnostic is caused by an actual parsing error, and is generated only by the engine.  The build will fail.
        Error # Fail the build only on Error diagnostic records.
        Warning # Fail the build on Warning and Error diagnostic records.
        Information # Fail the build on any diagnostic record, regardless of severity.
    }
    [LintSeverity]$LintSeverityThreshold = 'Error'

    # Path to the PSScriptAnalyzer settings file.
    [System.IO.FileInfo]$LintSettingsFile = [IO.Path]::Combine($TestsDir, 'ScriptAnalyzerSettings.psd1')



    # PowerShellBuild (Compilation, Build Processes, and MAML help)

    # The PowerShell script package will be created in this folder.
    [System.IO.DirectoryInfo]$BuildOutDir = [IO.Path]::Combine('..', '..', 'dist')



    # PowerShell Repository (Publication and Distribution)

    # Whether or not to publish the resultant scripts to any PowerShell repositories
    [boolean]$Publish = $true

    # PowerShell repository name to publish modules to
    $PublishPSRepository = 'PSGallery'

    # API key to authenticate to PowerShell repository with
    $PublishPSRepositoryApiKey = $env:PSGALLERY_API_KEY

    # Credential to authenticate to PowerShell repository with
    $PublishPSRepositoryCredential = $null



    # Docusaurus (Online help)

    # Online help website will be created in this folder.
    [System.IO.DirectoryInfo]$OnlineHelpDir = [IO.Path]::Combine('..', '..', 'docs', 'online')



    # Calculated Properties

    # File path of the source script .ps1 file
    $SearchPath = [IO.Path]::Combine($SourceCodeDir, '*.ps1')
    $FoundScript = Get-ChildItem -Path $SearchPath -Include *.ps1
    $MainScript = [IO.Path]::Combine($SourceCodeDir, $FoundScript.Name)

}

FormatTaskName {
    param($TaskName)
    Write-Host "$NewLine`Executing task $TaskName" -ForegroundColor Cyan
}

task Default -depends FindLinter, FindBuildModule, FindPlatyPS, DetectOperatingSystem, SourceControl

task FindLinter -precondition { $LintEnabled } {

    $script:FindLinter = [boolean](Get-Module -Name PSScriptAnalyzer -ListAvailable)

} -description 'Find the prerequisite PSScriptAnalyzer PowerShell module.'

task FindBuildModule -precondition { $script:FindLinter } {

    $script:FindBuildModule = [boolean](Get-Module -Name PowerShellBuild -ListAvailable)

} -description 'Find the prerequisite PSScriptAnalyzer PowerShellBuild module.'

task FindPlatyPS {

    $script:PlatyPS = [boolean](Get-Module -Name PlatyPS -ListAvailable)

} -description 'Determine whether the PlatyPS PowerShell module is installed.'

task DetectOperatingSystem {
    $script:OS = (Get-CimInstance -ClassName CIM_OperatingSystem).Caption
} -description 'Detect the operating system to determine whether MakeCab.exe is available to produce updateable help.'

task GetScriptFileInfo {

    Write-Host "`t`$Script:OldScriptFileInfo = Test-ScriptFileInfo -LiteralPath '$MainScript'"
    $Script:OldScriptFileInfo = Test-ScriptFileInfo -LiteralPath $MainScript

} -description 'Parse the ScriptFileInfo block at the beginning of the script.'

task Lint -depends GetScriptFileInfo -precondition { $script:FindBuildModule } {

    Write-Host "`tTest-PSBuildScriptAnalysis -Path '$SourceCodeDir' -SeverityThreshold '$LintSeverityThreshold' -SettingsPath '$LintSettingsFile'$NewLine"
    Test-PSBuildScriptAnalysis -Path $SourceCodeDir -SeverityThreshold $LintSeverityThreshold -SettingsPath $LintSettingsFile

} -description 'Perform linting with PSScriptAnalyzer invoked by PowerShellBuild.'

task DetermineNewVersionNumber -depends Lint {

    $ScriptToRun = [IO.Path]::Combine('.', 'Find-NewVersion.ps1')
    Write-Host "`t. $ScriptToRun -OldVersion $($Script:OldScriptFileInfo.Version) -IncrementMajorVersion `$$IncrementMajorVersion -IncrementMinorVersion `$$IncrementMinorVersion"
    $script:NewVersion = . $ScriptToRun -OldVersion $Script:OldScriptFileInfo.Version -IncrementMajorVersion $IncrementMajorVersion -IncrementMinorVersion $IncrementMinorVersion -NewLine $NewLine

} -description 'Determine the new version number.'

task UpdateScriptVersion -depends DetermineNewVersionNumber {

    Write-Host "`tUpdate-ScriptFileInfo -Path '$MainScript' -Version $script:NewVersion -ReleaseNotes '$CommitMessage'"
    Update-ScriptFileInfo -Path $MainScript -Version $script:NewVersion -ReleaseNotes $CommitMessage

    # Supposedly will be resolved in 3.0.15 but right now there is a bug in Update-ScriptFileInfo that adds blank lines after the PSScriptInfo block
    # This RegEx was going to be used to help remove those lines but for now I am just awaiting the new version
    # https://github.com/PowerShell/PowerShellGet/issues/347 (deleted now)
    # https://github.com/PowerShell/PowerShellGet/issues/316 (deleted now, potentially related according to one person on GitHub)
    # https://github.com/PowerShell/PSResourceGet/issues/347 (supposedly resolved...guess I need to check and see if it still happens)
    # https://github.com/PowerShell/PSResourceGet/pull/708 supposedly the resolution
    # $RegEx = '#>[\s\S]*<#\n\.SYNOPSIS'

} -description 'Update PSScriptInfo with the new version.'

task DeleteOldBuilds -depends UpdateScriptVersion {

    Write-Host "`tGet-ChildItem -Directory -Path '$BuildOutDir' | Remove-Item -Recurse -Force"
    Get-ChildItem -Directory -Path $BuildOutDir |
    Remove-Item -Recurse -Force

} -description 'Rotate old builds out of the output directory.'

task UpdateChangeLog -depends DeleteOldBuilds -Action {

    $ScriptToRun = [IO.Path]::Combine('.', 'Update-ChangeLog.ps1')
    Write-Host "`t. $ScriptToRun -Version $script:NewVersion -CommitMessage '$CommitMessage'"
    . $ScriptToRun -NewLine $NewLine -Version $script:NewVersion -CommitMessage $CommitMessage

} -description 'Add an entry to the the Change Log.'

task CreateReleaseFolder -depends UpdateChangeLog {

    $script:BuildOutputFolder = [IO.Path]::Combine(
        $BuildOutDir,
        $Script:OldScriptFileInfo.Name
    )

    Write-Host "`tNew-Item -Path '$script:BuildOutputFolder' -ItemType Directory"
    $null = New-Item -Path $script:BuildOutputFolder -ItemType Directory

} -description 'Create a new folder for this release of the script.'

task CreatePortableReleaseFolder -depends CreateReleaseFolder -precondition { [boolean]$PortableVersionGuid } {

    $script:BuildOutputFolderForPortableVersion = [IO.Path]::Combine(
        $BuildOutDir,
        "$($Script:OldScriptFileInfo.Name)Portable"
    )

    Write-Host "`tNew-Item -Path '$script:BuildOutputFolderForPortableVersion' -ItemType Directory"
    $null = New-Item -Path $script:BuildOutputFolderForPortableVersion -ItemType Directory

} -description 'Create a new folder for this release of the portable script.'

task BuildRelease -depends CreatePortableReleaseFolder {

    # Copy the source script to the output folder
    Write-Host "`tCopy-Item -Path '$MainScript' -Destination '$script:BuildOutputFolder'"
    Copy-Item -Path $MainScript -Destination $script:BuildOutputFolder
    $script:ReleasedScript = Get-ChildItem -LiteralPath $script:BuildOutputFolder -Include *.ps1

} -description 'Copy the updated script to the output folder.'

task BuildPortableRelease -depends BuildRelease -precondition { [boolean]$PortableVersionGuid } {

    $ScriptToRun = [IO.Path]::Combine('.', 'New-PortableScript.ps1')
    $ScriptResult = . $ScriptToRun -BuildOutputFolder $script:BuildOutputFolder -MainScript $MainScript
    $script:NewScriptFileInfo = $ScriptResult.NewScriptFileInfo
    $script:PortableScriptFilePath = $ScriptResult.PortableScriptFilePath

} -description 'Build a monolithic PowerShell script based on the source script and its ScriptModule dependencies.'

task CreateMarkdownHelpFolder -depends BuildPortableRelease -precondition { -not (Test-Path -LiteralPath $MarkdownHelpDir) } {

    Write-Host "`tNew-Item -Path '$MarkdownHelpDir' -ItemType Directory"
    $null = New-Item -Path $MarkdownHelpDir -ItemType Directory

} -description 'Create a new folder for the Markdown help documentation.'

task DeleteMarkdownHelp -depends CreateMarkdownHelpFolder -precondition { $script:PlatyPS } {

    $MarkdownDir = [IO.Path]::Combine($MarkdownHelpDir, $HelpDefaultLocale)
    Write-Host "`tGet-ChildItem -Path '$MarkdownDir' -Recurse | Remove-Item"
    Get-ChildItem -Path $MarkdownDir -Recurse | Remove-Item

} -description 'Delete existing Markdown files to prepare for PlatyPS to build new ones.'

task BuildMarkdownHelp -depends DeleteMarkdownHelp {

    $MarkdownParams = @{
        AlphabeticParamsOrder = $true
        Command               = $MainScript
        ErrorAction           = 'SilentlyContinue' # ErrorAction set to SilentlyContinue so this command will not overwrite an existing MD file.
        Force                 = $true
        Metadata              = @{
            'help version' = $Script:NewScriptFileInfo.Version
            locale         = $HelpDefaultLocale
            'script guid'  = $Script:NewScriptFileInfo.Guid
            #'download help link' = 'N/A'
        }
        # TODO: Using GitHub pages as a container for PowerShell Updatable Help https://gist.github.com/TheFreeman193/fde11aee6998ad4c40a314667c2a3005
        # OnlineVersionUrl = $GitHubPagesLinkForThisModule
        OutputFolder          = [IO.Path]::Combine($MarkdownHelpDir, $HelpDefaultLocale)
        UseFullTypeName       = $true
        Verbose               = $VerbosePreference
    }

    Write-Host "`tNew-MarkdownHelp -Command '$MainScript' -OutputFolder '$($MarkdownParams['OutputFolder'])'..."
    $script:MarkdownHelp = New-MarkdownHelp @MarkdownParams

} -description 'Generate Markdown files from the comment-based help.'

task FixMarkdownHelp -depends BuildMarkdownHelp {

    # Workaround a bug in New-MarkdownHelp with the Command ParameterSet
    $Markdown = Get-Content -LiteralPath $script:MarkdownHelp.FullName -Raw
    $NewMarkdown = $Markdown -replace 'Module Name:', "script name: $($MainScript.Name)"
    $NewMarkdown = $NewMarkdown -replace 'Module Guid:', "script guid: $($Script:NewScriptFileInfo.Guid)"

    # Workaround a bug since PS 7.4 introduced the ProgressAction common param which is not yet supported by PlatyPS
    $ParamToRemove = '-ProgressAction'
    $Pattern = "### $ParamToRemove\r?\n[\S\s\r\n]*?(?=#{2,3}?)"
    $NewMarkdown = [regex]::replace($NewMarkdown, $pattern, '')
    $Pattern = [regex]::Escape('[-ProgressAction <ActionPreference>] ')
    $NewMarkdown = [regex]::replace($NewMarkdown, $Pattern, '')

    Write-Host "`t`$NewMarkdown | Set-Content -LiteralPath '$($script:MarkdownHelp.FullName)'"
    $NewMarkdown | Set-Content -LiteralPath $script:MarkdownHelp.FullName

} -description 'Fix issues with the Markdown files that were not handled by New-MarkdownHelp.'

task BuildReadMe -depends FixMarkdownHelp {

    $ReadMe = [IO.Path]::Combine('..', '..', 'README.md')
    Write-Host "`tCopy-Item -Path '$script:MarkdownHelp' -Destination '$ReadMe' -Force"
    Copy-Item -Path $script:MarkdownHelp -Destination $ReadMe -Force

} -description 'Use the help for the script as the readme for the script'

task BuildMAMLHelp -depends BuildReadMe -precondition { $script:PlatyPS } {
    Write-Host "`tBuild-PSBuildMAMLHelp -Path '$MarkdownHelpDir' -DestinationPath '$script:BuildOutputFolder'"
    Build-PSBuildMAMLHelp -Path $MarkdownHelpDir -DestinationPath $script:BuildOutputFolder
} -description 'Generates MAML-based help from PlatyPS Markdown files using PowerShellBuild to call New-ExternalHelp.'

# Disabled this task for now, it does not work because New-ExternalHelp (invoked above by Build-PSBuildMAMLHelp) is not generating any MAML help files from the Markdown.
#task BuildUpdatableHelp -depends BuildMAMLHelp {
task BuildUpdatableHelp -precondition { $script:OS -match 'Windows' } {

    $helpLocales = (Get-ChildItem -Path $MarkdownHelpDir -Directory -Exclude 'UpdatableHelp').Name

    if ($null -eq $UpdatableHelpDir) {
        $UpdatableHelpDir = [IO.Path]::Combine($MarkdownHelpDir, 'UpdatableHelp')
    }

    # Create updatable help output directory
    if (-not (Test-Path -LiteralPath $UpdatableHelpDir)) {
        New-Item $UpdatableHelpDir -ItemType Directory -Verbose:$VerbosePreference > $null
    } else {
        Write-Verbose "Removing existing directory: [$UpdatableHelpDir]."
        Get-ChildItem $UpdatableHelpDir | Remove-Item -Recurse -Force -Verbose:$VerbosePreference
    }

    # Generate updatable help files.  Note: this will currently update the version number in the module's MD
    # file in the metadata.
    foreach ($locale in $helpLocales) {
        Write-Information "'$([IO.Path]::Combine($MarkdownHelpDir, $locale, "$($MainScript.Name).md"))'"
        $cabParams = @{
            CabFilesFolder  = [IO.Path]::Combine($script:BuildOutputFolder, $locale)
            LandingPagePath = [IO.Path]::Combine($MarkdownHelpDir, $locale, "$($MainScript.Name).md")
            OutputFolder    = $UpdatableHelpDir
            Verbose         = $VerbosePreference
            ErrorAction     = 'Continue'
        }
        New-ExternalHelpCab @cabParams 2> $null
    }

} -description 'Build an updatable .cab help file based on the Markdown help files.'

task BuildOnlineHelp -depends BuildMAMLHelp {

} -description 'Build an Online help website based on the Markdown help files using Docusaurus.'

task BuildArt -depends BuildOnlineHelp {
    $ScriptToRun = [IO.Path]::Combine('..', 'img', 'favicon.ps1')
    $Script:OutputDir = [IO.Path]::Combine($OnlineHelpDir, 'static', 'img')
    Write-Host "`t. $ScriptToRun -OutputDir '$OutputDir'"
    . $ScriptToRun -OutputDir $OutputDir
} -description 'Build SVG art using PSSVG.'

task ConvertArt -depends BuildArt {
    $ScriptToRun = [IO.Path]::Combine('.', 'ConvertFrom-SVG.ps1')
    $sourceSVG = [IO.Path]::Combine($Script:OutputDir, "favicon.svg")
    Write-Host "`t. $ScriptToRun -Path '$sourceSVG' -ExportWidth 512"
    . $ScriptToRun -Path $sourceSVG -ExportWidth 512
} -description 'Convert SVGs to PNG using Inkscape.'

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
    if (-not (Test-Path -Path $TestsDir)) {
        Write-Warning "Test directory [$TestsDir)] not found"
        $result = $false
    }
    return $result
}

task UnitTests -depends ConvertArt -precondition $pesterPreReqs {

    Write-Host "`tInvoke-Pester -Configuration `$PesterConfiguration$NewLine"

    $PesterConfigParams = @{
        Run          = @{
            Path = "$TestsDir"
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
            OutputPath   = $TestsResultFile
            OutputFormat = $TestOutputFormat
        }
    }

    $PesterConfiguration = New-PesterConfiguration -Hashtable $PesterConfigParams
    Invoke-Pester -Configuration $PesterConfiguration

} -description 'Execute Pester tests'

task SourceControl -depends UnitTests {

    Write-Host "`tgit branch --show-current$NewLine"
    $CurrentBranch = git branch --show-current
    Write-Host "$CurrentBranch$NewLine"

    Write-Host "`tgit add ../.."
    git add ../..

    Write-Host "`tgit commit -m $CommitMessage$NewLine"
    git commit -m $CommitMessage

    Write-Host "$NewLine`tgit push origin $CurrentBranch$NewLine"
    git push origin $CurrentBranch

} -description 'git add, commit, and push'

task Publish {

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
    if ($Publish -eq $true -and $CurrentBranch -eq 'main') {
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

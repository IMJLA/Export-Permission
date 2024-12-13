BeforeDiscovery {

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'MetaFixers.psm1') -Verbose:$false -Force

    $SourceCodePath = [IO.Path]::Combine($PSScriptRoot.Replace('tests', 'src'), 'script')

    $MainScript = Get-ChildItem -LiteralPath $SourceCodePath -Include *.ps1
    #Write-Information "MainScript: $($MainScript | Format-List * | Out-String)"

    $MainScriptFileInfoTest = Test-ScriptFileInfo -LiteralPath $MainScript.FullName -ErrorAction Continue

    $AllPowerShellCodeFiles = Get-ChildItem -Path $SourceCodePath -Directory -Exclude bin, config, data, en-US, UpdatableHelp |
    Get-ChildItem -Include *.ps1, *.psm1, *.psd1 -Recurse |
    ForEach-Object {
        $RawContents = Get-Content -LiteralPath $_.FullName -Raw
        $_ | Add-Member -NotePropertyName RawContent -NotePropertyValue $RawContents -PassThru
    }
    Write-Information "AllPowerShellCodeFiles: $(($AllPowerShellCodeFiles | Measure-Object).Count)"

    # Read in the contents of the script file for tinkering
    [string]$ScriptContents = Get-Content -LiteralPath $MainScript.FullName -Raw

    # Create a temporary file to avoid modifying our source code
    #NOTE: Cannot use .tmp extension for Get-Help
    $TempFilePath = [System.IO.Path]::GetTempPath()
    $TempFile = Join-Path -Path $TempFilePath -ChildPath $MainScript.Name

    # Remove the PSScriptInfo block required by PSGallery because it conflicts with Get-Help
    ($ScriptContents -replace '^\<\#PSScriptInfo[\s\S]*?\n\#\>', '') |
    Set-Content -LiteralPath $TempFile -Force

    # Run Get-Help
    $commandHelp = Get-Help -Name $TempFile -ErrorAction Stop

    # Delete the temporary file
    Remove-Item -LiteralPath $TempFile -Confirm:$false

    $ModuleManifests = $AllPowerShellCodeFiles |
    Where-Object {
        $_.Extension -eq '.psd1'
    } |
    Sort-Object -Property FullName
    #Write-Information "ModuleManifests: $(($ModuleManifests | Measure-Object).Count)"

    $ModuleFiles = $AllPowerShellCodeFiles |
    Where-Object {
        $_.Extension -eq '.psm1'
    } |
    Sort-Object -Property FullName
    #Write-Information "ModuleFiles: $(($ModuleFiles | Measure-Object).Count)"

    $ScriptFiles = $AllPowerShellCodeFiles |
    Where-Object {
        $_.Extension -eq '.ps1'
    } |
    Sort-Object -Property FullName
    #Write-Information "ScriptFiles: $(($ScriptFiles | Measure-Object).Count)"

}

Describe "PowerShell script file info for '<_.Name>'" -ForEach $MainScriptFileInfoTest {
    It ' Specify a valid version' {
        $_.Version -as [Version] | Should -Not -BeNullOrEmpty
    }

    It ' Specify an author' {
        $_.Author | Should -Not -BeNullOrEmpty
    }

    It ' Specify a valid guid' {
        { [guid]::Parse($_.Guid) } | Should -Not -Throw
    }

    It ' Specify a copyright' {
        $_.CopyRight | Should -Not -BeNullOrEmpty
    }

    It ' Specify a company name' {
        $_.CompanyName | Should -Not -BeNullOrEmpty
    }

    It ' Specify a valid license URI' {
        { [uri]::new($_.LicenseUri) } | Should -Not -Throw
    }

    It ' Specify a valid project URI' {
        { [uri]::new($_.ProjectUri) } | Should -Not -Throw
    }
}

Describe "PowerShell module manifest file '<_.Name>'" -ForEach $ModuleManifests {
    BeforeEach {
        # Suppress errors because the tests will reveal any issues
        $ManifestTest = Test-ModuleManifest -Path $_.FullName -Verbose:$false -ErrorAction Stop -WarningAction SilentlyContinue
        $PowershellDataFile = Import-PowerShellDataFile -Path $_.FullName -ErrorAction SilentlyContinue
    }

    Context '- Key-Value Pairs' {

        It ' Specify valid key-value pairs' {
            $PowershellDataFile | Should -Not -BeNullOrEmpty
        }

        It ' Specify a root module name that matches the manifest name' {
            $PowershellDataFile.RootModule | Should -Be $(($_.Name -split '\.') | Select-Object -SkipLast 1)
        }

        It ' Specify a valid version' {
            $PowershellDataFile.ModuleVersion -as [Version] | Should -Not -BeNullOrEmpty
        }

        It ' Specify an author' {
            $PowershellDataFile.Author | Should -Not -BeNullOrEmpty
        }

        It ' Specify a valid guid' {
            { [guid]::Parse($PowershellDataFile.Guid) } | Should -Not -Throw
        }

        It ' Specify a copyright' {
            $PowershellDataFile.CopyRight | Should -Not -BeNullOrEmpty
        }
    }

    Context '- Ensure manifests accurately describe module contents' {

        It 'is a valid manifest' {
            $ManifestTest | Should -Not -BeNullOrEmpty
        }

        It 'has a valid name in the manifest' {
            $ManifestTest.Name | Should -Be $(($_.Name -split '\.') | Select-Object -SkipLast 1)
        }

        It 'has a description' {
            $ManifestTest.Description | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "PowerShell module file '<_.Name>'" -ForEach $ModuleFiles {
    It ' Can be imported without any errors' {
        { Import-Module -Name $_.FullName -Force -ErrorAction Stop } | Should -Not -Throw
    }

    Context '- Functions' {
        BeforeDiscovery {
            $FunctionTestCases = $ScriptFiles | ForEach-Object {
                # TestCases are splatted to the script so we need hashtables
                @{ThisScript = $_ }
            }
        }
        #It " Runs without throwing errors: <ThisScript.Name>" -ForEach $FunctionTestCases {
        #    { . $ThisScript.FullName } | Should -Not -Throw
        #}
    }

}

Describe "PowerShell source code file '<_.Name>'" -ForEach $AllPowerShellCodeFiles {

    It ' Can be tokenized by the PowerShell parser without any errors' {
        $Errors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($_.RawContent, [ref]$Errors)
        $Errors.Count | Should -Be 0
    }

    It ' Runs without throwing errors (or is not a .ps1)' {
        if ($_.Extension -eq '.ps1') {
            { . $_.FullName } | Should -Not -Throw
        }
    }

    It ' Uses spaces instead of tabs' {
        $_.RawContent -match '\t' | Should -Be $false
    }

    It ' Is not UTF16-encoded' {
        Test-FileUnicode -FileInfo $_.FullName | Should -Be $false
    }

}

Describe "help for '<_.Name>'" -ForEach $MainScript {

    BeforeDiscovery {
        function FilterOutCommonParams {
            param ($Params)
            $commonParams = @(
                'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable',
                'OutBuffer', 'OutVariable', 'PipelineVariable', 'ProgressAction', 'Verbose', 'WarningAction',
                'WarningVariable', 'Confirm', 'Whatif'
            )
            $params | Where-Object { $_.Name -notin $commonParams } | Sort-Object -Property Name -Unique
        }

        if ($commandHelp) {
            Write-Information 'success getting command help'
            #Write-Information "$($commandHelp | fl * | out-string)"
        } else {
            Write-Information 'failure getting command help'
            #Write-Information "First 2 lines of file: $((Get-Content -LiteralPath $TempFile | Select-Object -First 2))"
            #Write-Information "Get-Help -Name '$TempFile'"
        }

        $MainScriptExternalScriptInfo = Get-Command -Name $_.FullName
        $commandParameters = FilterOutCommonParams -Params $MainScriptExternalScriptInfo.ParameterSets.Parameters
        $helpParameters = FilterOutCommonParams -Params $commandHelp.Parameters.Parameter

        $commandParameterTestCases = $commandParameters |
        ForEach-Object {
            @{
                commandHelp      = $commandHelp
                commandParameter = $_
                helpParameters   = $helpParameters
            }
        }

        $helpParameterTestCases = $helpParameters |
        ForEach-Object {
            @{
                helpParameter     = $_
                commandParameters = $commandParameters
            }
        }
    }

    It ' Exists' -ForEach @{'commandHelp' = $commandHelp } {
        $commandHelp | Should -Not -BeNullOrEmpty
    }

    It ' Is not auto-generated, or for a conceptual help article' -ForEach @{'commandHelp' = $commandHelp } {
        $commandHelp.GetType().FullName | Should -Not -Be 'System.String'
    }

    # Should be a description for every function
    It ' Has a description' -ForEach @{'commandHelp' = $commandHelp } {
        $commandHelp.Description | Should -Not -BeNullOrEmpty
    }

    # Should be at least one example
    It ' Has example code' -ForEach @{'commandHelp' = $commandHelp } {
        ($commandHelp.Examples.Example | Select-Object -First 1).Code | Should -Not -BeNullOrEmpty
    }

    # Should be at least one example description
    It ' Has example help' -ForEach @{'commandHelp' = $commandHelp } {
        ($commandHelp.Examples.Example.Remarks | Select-Object -First 1).Text | Should -Not -BeNullOrEmpty
    }

    It " Has valid link URLs '<commandHelp.relatedLinks.navigationLink.uri>'" -ForEach @{'commandHelp' = $commandHelp } {
        $commandHelp.relatedLinks.navigationLink.uri | ForEach-Object {
            (Invoke-WebRequest -Uri $_ -UseBasicParsing).StatusCode | Should -Be '200'
        }
    }

    Context "- Help for parameter '<_.commandParameter.Name>'" -ForEach $commandParameterTestCases {

        BeforeEach {
            $parameterHelp = $commandHelp.parameters.parameter | Where-Object Name -EQ $commandParameter.Name
            $parameterHelpType = if ($parameterHelp.ParameterValue) { $parameterHelp.ParameterValue.Trim() }
        }

        # Should be a description for every parameter
        It 'has a description' -ForEach @{'parameterHelp' = $parameterHelp } {
            $parameterHelp.Description.Text | Should -Not -BeNullOrEmpty
        }

        # Required value in Help should match IsMandatory property of parameter
        It 'has the correct [mandatory] value' -ForEach @{'parameterHelp' = $parameterHelp } {
            $codeMandatory = $commandParameter.IsMandatory.toString()
            $parameterHelp.Required | Should -Be $codeMandatory
        }

        # Parameter type in help should match code
        It 'has the correct parameter type' -ForEach @{'parameterHelpType' = $parameterHelpType } {
            $parameterHelpType | Should -Be $commandParameter.ParameterType.Name
        }

    }

    Context '- Extraneous Parameters in Help' {

        # Shouldn't find extra parameters in help.
        It ' Parameter found in the Help docs also exists in the code: <helpParameter.Name>' -ForEach $helpParameterTestCases {
            $helpParameter.Name -in $commandParameters.Name | Should -Be $true
        }

    }

    #TODO: Add a test to ensure there is an example that demonstrates using the pipeline to provide input to the script

}

Describe 'change log' {

    Context '- Version' {
        BeforeDiscovery {
            $changelogPath = "$PSScriptRoot\..\CHANGELOG.md"
            Get-Content $changelogPath | ForEach-Object {
                if ($_ -match '^##\s\[(?<Version>(\d+\.){1,3}\d+)\]') {
                    $changelogVersion = $matches.Version
                    break
                }
            }
        }

        It "has a valid version '<changelogVersion>'" {
            $changelogVersion | Should -Not -BeNullOrEmpty
            $changelogVersion -as [Version] | Should -Not -BeNullOrEmpty
        }

        It "has the same version as the manifest '<changelogVersion>'" {
            $changelogVersion -as [Version] | Should -Be ( $MainScriptFileInfoTest.Version -as [Version] )
        }

    }

}

Describe 'source control' -Skip {

    BeforeDiscovery {

        $gitTagVersion = $null

        if ($git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue) {
            $thisCommit = & $git log --decorate --oneline HEAD~1..HEAD
            if ($thisCommit -match 'tag:\s*(\d+(?:\.\d+)*)') { $gitTagVersion = $matches[1] }
        }

    }
    Context "- Git tag version '$gitTagVersion'" {

        It 'is a valid version' {
            $gitTagVersion | Should -Not -BeNullOrEmpty
            $gitTagVersion -as [Version] | Should -Not -BeNullOrEmpty
        }

        It 'matches the script version' {
            $gitTagVersion -as [Version] | Should -Be ( $MainScriptFileInfoTest.Version -as [Version] )
        }
    }
}

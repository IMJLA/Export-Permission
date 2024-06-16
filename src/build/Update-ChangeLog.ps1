#requires -Module ChangelogManagement

param (
    [version]$Version,
    [string]$CommitMessage
)

switch -Wildcard ($CommitMessage) {
    "add*" { $Type = 'Added' }
    "bug*" { $Type = 'Fixed' }
    "change*" { $Type = 'Changed' }
    "deprecate*" { $Type = 'Deprecated' }
    "delete*" { $Type = 'Removed' }
    "fix*" { $Type = 'Fixed' }
    "implement*" { $Type = 'Added' }
    "remove*" { $Type = 'Removed' }
    "*security*" { $Type = 'Security' }
    default { $Type = 'Changed' }
}

$ChangeLog = [IO.Path]::Combine('..', '..', 'CHANGELOG.md')
"`tAdd-ChangelogData -Type '$Type' -Path '$ChangeLog' -Data '$CommitMessage'"
Add-ChangelogData -Type $Type -Data $CommitMessage -Path $ChangeLog
"`tUpdate-Changelog -Version '$Version' -LinkMode 'None' -Path '$ChangeLog'"
Update-Changelog -ReleaseVersion $Version -LinkMode 'None' -Path $ChangeLog

<#
$NewChanges = "## [$Version] - $(Get-Date -format 'yyyy-MM-dd')$NewLine### Changed$NewLine- $CommitMessage"
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
#>

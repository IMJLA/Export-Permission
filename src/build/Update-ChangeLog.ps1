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

param (
    [version]$OldVersion,
    [boolean]$IncrementMajorVersion,
    [boolean]$IncrementMinorVersion,
    [string]$NewLine = ([System.Environment]::NewLine)
)

if ($IncrementMajorVersion) {
    [version]$NewVersion = "$([int]$OldVersion.Major + 1).0.0"
} elseif ($IncrementMinorVersion) {
    [version]$NewVersion = "$([int]$OldVersion.Major).$([int]$OldVersion.Minor + 1).0"
} else {
    [version]$NewVersion = "$([int]$OldVersion.Major).$([int]$OldVersion.Minor).$([int]$OldVersion.Build + 1)"
}

Write-Host "$NewLine`New version:" -ForegroundColor Yellow

# For reasons unknown, if we return the $script:NewVersion object here it holds up the pipeline and does not come out until several tasks later
# This messes up the console output, preventing other stdout output from appearing in the console.
# PSScriptAnalyzer does not do this; its object returns to the pipeline in the correct sequence
[string[]]$VersionTableLines = ($NewVersion | Format-Table | Out-String).Split($NewLine)
$VersionTableLines[0..2] | Write-Host -ForegroundColor Green
$VersionTableLines[3..$($VersionTableLines.Length - 2)] | Write-Host

return $NewVersion

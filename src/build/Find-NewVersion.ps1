param (
    [version]$OldVersion,
    [boolean]$IncrementMajorVersion,
    [boolean]$IncrementMinorVersion
)

if ($IncrementMajorVersion) {
    Write-Host "`tThis is a new major version"
    [version]$NewVersion = "$([int]$OldVersion.Major + 1).0.0"
} elseif ($IncrementMinorVersion) {
    Write-Host "`tThis is a new minor version"
    [version]$NewVersion = "$([int]$OldVersion.Major).$([int]$OldVersion.Minor + 1).0"
} else {
    Write-Host "`tThis is a new build"
    [version]$NewVersion = "$([int]$OldVersion.Major).$([int]$OldVersion.Minor).$([int]$OldVersion.Build + 1)"
}
return $NewVersion

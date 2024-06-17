param (
    [version]$OldVersion,
    [boolean]$IncrementMajorVersion,
    [boolean]$IncrementMinorVersion
)

if ($IncrementMajorVersion) {
    [version]$NewVersion = "$([int]$OldVersion.Major + 1).0.0"
} elseif ($IncrementMinorVersion) {
    [version]$NewVersion = "$([int]$OldVersion.Major).$([int]$OldVersion.Minor + 1).0"
} else {
    [version]$NewVersion = "$([int]$OldVersion.Major).$([int]$OldVersion.Minor).$([int]$OldVersion.Build + 1)"
}
return $NewVersion

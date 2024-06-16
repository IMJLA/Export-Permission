param (
    [string[]]$WingetPackageId
)

# Install Winget package dependencies
ForEach ($id in $WingetPackageId) {
    $pkg = Get-WinGetPackage -Id $id
    if (-not $pkg) {
        Install-WinGetPackage -Id $id
    }
    $pkg = Get-WinGetPackage -Id $id
    if (-not $pkg) {
        Write-Warning "Missing Dependency: $id"
    }
}


param (

    [System.IO.FileInfo]$Path

)

# Workaround a bug in New-MarkdownHelp with the Command ParameterSet, the Module Name, and as a result the External Help File
# ToDo: Report that bug
Write-Host "`t`$Lines = Get-Content -LiteralPath '$Path'"
$Lines = Get-Content -LiteralPath $Path

$replacements = @{}

foreach ($line in $Lines) {

    if ($line -match '#Requires -Module(?:s*)(.+)') {

        $StringToReplace = $matches[0]
        $moduleName = $matches[1].Trim()

        if ($moduleName -match 'ModuleName[^;=]*=([^;}]*)') {
            $moduleName = $matches[1].Trim()
        }

        $moduleVersion = Get-Module -Name $moduleName -ListAvailable |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1 -ExpandProperty Version

        if ($moduleVersion) {
            $replacements[$StringToReplace] = "#Requires -Module @{ ModuleName = '$moduleName' ; RequiredVersion = '$moduleVersion' }"
        }

        Write-Host "`t`$($replacements[$StringToReplace])'"

    }

}

Write-Host "`t`$Content = Get-Content -LiteralPath '$Path' -Raw"
$Content = Get-Content -LiteralPath $Path -Raw

ForEach ($StringToReplace in $replacements.Keys) {
    Write-Host "`t`$Content = $Content.Replace('$StringToReplace', '$($replacements[$StringToReplace])')"
    $Content = $Content.Replace($StringToReplace, $replacements[$StringToReplace])
}

# Update the file
Write-Host "`t`$Content | Set-Content -Path '$Path'"
$Content | Set-Content -Path $Path

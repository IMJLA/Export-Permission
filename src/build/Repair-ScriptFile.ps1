param (

    [System.IO.FileInfo]$Path

)

# Workaround a bug in New-MarkdownHelp with the Command ParameterSet, the Module Name, and as a result the External Help File
# ToDo: Report that bug
Write-Host "`t`$Content = Get-Content -LiteralPath '$Path' -Raw"
$Content = Get-Content -LiteralPath $Path -Raw

# Module name is blank for a script because it has no manifest to get it from. Remove this invalid field.
Write-Host "`t`while (`$Content.Contains("``r``n``r``n``r``n")) { `$Content = `$Content.Replace("``r``n``r``n``r``n", "``r``n``r``n") }"
while ($Content.Contains("`r`n`r`n`r`n")) {
    $Content = $Content.Replace("`r`n`r`n`r`n", "`r`n`r`n")
}

# Update the file
Write-Host "`t`$Content | Set-Content -Path '$Path'"
$Content | Set-Content -Path $Path

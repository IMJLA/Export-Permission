param (

    [System.IO.FileInfo]$Path,

    [string]$ScriptName,

    [guid]$ScriptGuid

)

# Workaround a bug in New-MarkdownHelp with the Command ParameterSet
# ToDo: Report that bug
$Markdown = Get-Content -LiteralPath $Path -Raw
$NewMarkdown = $Markdown -replace 'Module Name:', "script name: $ScriptName"
$NewMarkdown = $NewMarkdown -replace 'Module Guid:', "script guid: $ScriptGuid"

# Workaround a bug since PS 7.4 introduced the ProgressAction common param which is not yet supported by PlatyPS
$ParamToRemove = '-ProgressAction'
$Pattern = "### $ParamToRemove\r?\n[\S\s\r\n]*?(?=#{2,3}?)"
$NewMarkdown = [regex]::replace($NewMarkdown, $Pattern, '')
$Pattern = [regex]::Escape('[-ProgressAction <ActionPreference>] ')
$NewMarkdown = [regex]::replace($NewMarkdown, $Pattern, '')

# Add PowerShell syntax highlighting
$NewMarkdown = $NewMarkdown -replace '\x60\x60\x60\r*\n(?!\r*\n)', "``````powershell`n"

Write-Host "`t`$NewMarkdown | Set-Content -LiteralPath '$Path'"
$NewMarkdown | Set-Content -LiteralPath $Path

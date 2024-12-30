param (

    [System.IO.FileInfo]$Path,

    [string]$ScriptName,

    [guid]$ScriptGuid

)

# Workaround a bug in New-MarkdownHelp with the Command ParameterSet, the Module Name, and as a result the External Help File
# ToDo: Report that bug
$Markdown = Get-Content -LiteralPath $Path -Raw

# Module name is blank for a script because it has no manifest to get it from. Remove this invalid field.
$NewMarkdown = $Markdown.Replace("Module Name:`r`n", "`r`n")

# The blank module name results in a malformed external help file name. Fix this by using the script name.
# Cannot specify this using the New-MarkdownHelp cmdlet's -Metadata parameter due to the following error:
# Error: 12/30/2024 10:37:45 AM: At C:\Users\Owner\Documents\PowerShell\Modules\platyPS\0.14.2\platyPS.psm1:238 char:140 + … -ExcludeDontShow:$ExcludeDontShow.IsPresent | processMamlObjectToFile + ~~~~~~~~~~~~~~~~~~~~~~~ [<<==>>] Exception: Item has already been added. Key in dictionary: 'external help file' Key being added: 'external help file'
$NewMarkdown = $NewMarkdown -replace 'external help file: -help.xml', "external help file: $($ScriptName.Split('.')[0])-help.xml"

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

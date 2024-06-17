param (
    $BuildOutputFolder,
    $MainScript
)


$FolderName = $BuildOutputFolder | Split-Path -Leaf

# Read in the current contents of the script
$MainScriptContent = Get-Content -LiteralPath $MainScript -Raw

# Prep an empty collection of strings to store our new portable script
$PortableScriptContent = [System.Collections.Generic.List[string]]::New()

# Find the place in our script we intend to insert all the module code
$RegExOptions = [System.Text.RegularExpressions.RegexOptions]::Singleline
$RegEx = '(.*\#----------------\[ Functions ]------------------).*(\#----------------\[ Logging ]----------------.*)'
$Matches = [regex]::Match($MainScriptContent, $RegEx, $RegExOptions)

# Add the first half of the script to our target collection (everything up until the place in our script we intend to insert all the module code)
$null = $PortableScriptContent.Add($Matches.Groups[1].Value)

# Get updated Script metadata
$NewScriptFileInfo = Test-ScriptFileInfo -LiteralPath $MainScript

# Add the constituent code of each module
ForEach ($ThisModuleName in $NewScriptFileInfo.RequiredModules.Name) {

    # Get the latest version of the module
    $ThisModule = Get-Module -Name $ThisModuleName -ListAvailable |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1

    # Find the .psm1 file
    $ThisModuleFile = Get-ChildItem -LiteralPath $ThisModule.ModuleBase -Include *.psm1

    # Load the contents of the .psm1 file
    $ThisModuleDefinition = $ThisModuleFile |
    Get-Content -Raw

    if ($ThisModuleDefinition) {
        # Remove Export-ModuleMember from the module code since it has no purpose inside the script
        $ThisModuleDefinition = $ThisModuleDefinition -replace 'Export-ModuleMember.*\n[\S]*.*', ''

        # Add this module code to our target collection
        $null = $PortableScriptContent.Add("# Definition of Module '$ThisModuleName' Version '$($ThisModule.Version)' is below")
        $null = $PortableScriptContent.Add($ThisModuleDefinition.Trim())

        # Remove the Requires statement for this module
        $PortableScriptContent[0] = $PortableScriptContent[0] -replace [regex]::Escape("#Requires -Module $ThisModuleName"), ''
    }
}

# Prepare to add a line to the SYNOPSIS indicating this is a portable version of the script
$RegEx = '(\.SYNOPSIS)(.*)(\.DESCRIPTION)'
$Matches2 = [regex]::Match($PortableScriptContent[0], $RegEx, $RegExOptions)
$Replacement = $Matches2.Groups[1].Value,
"    Portable version of $FolderName with all ScriptModule dependencies rolled up into this single .ps1 file",
$Matches2.Groups[2].Value,
$Matches2.Groups[3].Value -join "`r`n"

# Add a line to the SYNOPSIS indicating this is a portable version of the script
$RegEx = '\.SYNOPSIS(.|\n)*\.DESCRIPTION'
$PortableScriptContent[0] = $PortableScriptContent[0] -replace $RegEx, $Replacement

# Add the second half of the script to our target collection (everything after the place in our script we intend to insert all the module code)
$null = $PortableScriptContent.Add($Matches.Groups[2].Value)

$Result = $PortableScriptContent -join "`r`n`r`n"

#Update-ScriptFileInfo does not allow us to remove RequiredModules or ExternalModuleDependencies so we'll do it ourselves
$Result = $Result -replace
'\.EXTERNALMODULEDEPENDENCIES.*', '.EXTERNALMODULEDEPENDENCIES' -replace
'\.REQUIREDMODULES.*', '.REQUIREDMODULES'

# ---BEGIN SECTION TO PARTIALLY MINIFY THE CODE DUE TO PSGALLERY 10k LINE LIMIT---
# Parse the PowerShell code
$Tokens = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput(
    $Result,
    [ref]$Tokens,
    [ref]$null
)

# Find all the comments.
# Filter out the Script File Info block which must remain for publishing to PSGallery.
# Sort the comments by length in descending order.
# This way the shortest comments (which are potentially just a # with nothing else) are removed last.
# If '#' were removed first, nothing else would be a comment
$Comments = $Tokens.Where({ $_.kind -eq 'comment' }).Text |
#Where-Object -FilterScript {
#    -not ([regex]::Match($_, '(\.LICENSEURI)(.*)(\.PROJECTURI)', $RegExOptions)).Success
#} |
Sort-Object -Property Length -Descending

# Remove the comments
ForEach ($Comment in $Comments) {
    if ($Comment -eq '#') {
        $escaped = '^\s*#\s*$' # Need to avoid the Script File Info block <# ... #>
    } else {
        $escaped = [regex]::Escape($Comment)
    }
    $Result = $Result -replace $escaped , ''
}

# Remove blank lines
$Result = $Result -replace '\r\n[\s]*\r\n', "`r`n" -replace '\r\n[\s]*\r\n', "`r`n" -replace '\r\n\[\s]*r\n', "`r`n"
# ---END SECTION TO PARTIALLY MINIFY THE CODE DUE TO PSGALLERY 10k LINE LIMIT---

$PortableScriptFilePath = [IO.Path]::Combine( $script:BuildOutputFolderForPortableVersion, "$FolderName`Portable.ps1" )

# Assign the correct GUID to the portable version of the script (it should be unique, not shared with the other script)
$Properties = @{
    Version      = $NewScriptFileInfo.Version
    Description  = $NewScriptFileInfo.Description
    Author       = $NewScriptFileInfo.Author
    CompanyName  = $NewScriptFileInfo.CompanyName
    Copyright    = $NewScriptFileInfo.Copyright
    Tags         = $NewScriptFileInfo.Tags
    ReleaseNotes = [string]$NewScriptFileInfo.ReleaseNotes
    LicenseUri   = $NewScriptFileInfo.LicenseUri
    ProjectUri   = $NewScriptFileInfo.ProjectUri
}
Write-Host "`t`New-ScriptFileInfo -Path '$PortableScriptFilePath' -Version '$($NewScriptFileInfo.Version)' -Guid '$PortableVersionGuid' -Force"
New-ScriptFileInfo -Path $PortableScriptFilePath -Guid $PortableVersionGuid -Force @Properties

# New-PSScriptFileInfo creates a file which is not accepted by Test-ScriptFileInfo (and therefore not accepted by PSGallery)
# New-ScriptFileInfo does not have this problem but it generates a param() block which must be erased before we append our own
$NewScriptFileContent = Get-Content -LiteralPath $PortableScriptFilePath -Raw
    ($NewScriptFileContent -replace 'Param\(\)', '').Trim() | Out-File -LiteralPath $PortableScriptFilePath -Force

# Write the output to file
$Result.Trim() | Out-File -LiteralPath $PortableScriptFilePath -Append

return [PSCustomObject]@{
    NewScriptFileInfo      = $NewScriptFileInfo
    PortableScriptFilePath = $PortableScriptFilePath
}

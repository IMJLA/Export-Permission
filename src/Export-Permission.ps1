<#PSScriptInfo

.VERSION 0.0.109

.GUID fd2d03cf-4d29-4843-bb1c-0fba86b0220a

.AUTHOR Jeremy La Camera

.COMPANYNAME Jeremy La Camera

.COPYRIGHT (c) Jeremy La Camera. All rights reserved.

.TAGS adsi ntfs acl

.LICENSEURI https://github.com/IMJLA/Export-Permission/blob/main/LICENSE

.PROJECTURI https://github.com/IMJLA/Export-Permission

.ICONURI

.EXTERNALMODULEDEPENDENCIES Adsi,SimplePrtg,PsNtfs,PsLogMessage,PsRunspace,PsDfs,PsBootstrapCss,Permission 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
Parameter cleanup. Breaking changes.

.PRIVATEDATA

#> 

#Requires -Module Adsi
#Requires -Module SimplePrtg
#Requires -Module PsNtfs
#Requires -Module PsLogMessage
#Requires -Module PsRunspace
#Requires -Module PsDfs
#Requires -Module PsBootstrapCss
#Requires -Module Permission


<#
.SYNOPSIS
    Create CSV, HTML, and XML reports of permissions
.DESCRIPTION
    Gets all permissions for the target folder

    Gets non-inherited permissions for subfolders (if specified)

    Exports the permissions to a .csv file

    Uses ADSI to get information about the accounts and groups listed in the permissions

    Exports information about the accounts and groups to a .csv file

    Uses ADSI to recursively retrieve the members of nested groups

    Exports information about all accounts with access to a .csv file

    Exports information about all accounts with access to a report generated as a .html file

    Outputs an XML-formatted list of common misconfigurations for use in Paessler PRTG Network Monitor as a custom XML sensor
.INPUTS
    None. Pipeline input is not accepted.
.OUTPUTS
    [System.String] XML PRTG sensor output
.NOTES
    TODO: Investigate - Looks like I am filtering out ignored domains in 2 separate places?  redundant?

    TODO: Bug - Logic Flaw for Owner.
                Currently we search folders for non-inherited access rules, then we manually add a FullControl access rule for the Owner.
                This misses folders with only inherited access rules but a different owner.

    TODO: Bug - Doesn't work for AD users' default group/primary group (which is typically Domain Users).
                The user's default group is not listed in their memberOf attribute so I need to fix the LDAP search filter to include the primary group attribute.

    TODO: Bug - For a fake group created by New-FakeDirectoryEntry in the Adsi module, in the report its name will end up as an NT Account (CONTOSO\User123).
                If it is a fake user, its name will correctly appear without the domain prefix (User123)

    TODO: Bug - Fix bug in PlatyPS New-MarkdownHelp with multi-line param descriptions (?and example help maybe affected also?).
                When provided the same comment-based help as input, Get-Help respects the line breaks but New-MarkdownHelp does not.
                New-MarkdownHelp generates an inaccurate markdown representation by converting multiple lines to a single line.
                Declared as wontfix https://github.com/PowerShell/platyPS/issues/314
                Need to fix it myself because that makes no sense
                workaround is to include markdown syntax in PowerShell comment-based help
                That is why there are so many extra blank lines in the commented metadata in this script

    TODO: Feature - List any excluded accounts at the end

    TODO: Feature - Remove all usage of Add-Member to improve performance (create new pscustomobjects instead, nest original object inside)

    TODO: Feature - Parameter to specify properties to include in report

    TODO: Feature - This script does NOT account for individual file permissions.  Only folder permissions are considered.

    TODO: Feature - This script does NOT account for file share permissions. Only NTFS permissions are considered.

    TODO: Feature - Support ACLs from Registry or AD objects

    TODO: Feature - psake task to update Release Notes in the script metadata to the github commit message
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -ExcludeAccount 'BUILTIN\\Administrator'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Exclude the built-in Administrator account from the HTML report

    The ExcludeAccount parameter uses RegEx, so the \ in BUILTIN\Administrator needed to be escaped.

    The RegEx escape character is \ so that is why the regular expression needed for the parameter is 'BUILTIN\\Administrator'
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -ExcludeEmptyGroups

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Exclude empty groups from the HTML report (leaving accounts only)
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -IgnoreDomain 'CONTOSO'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Remove the CONTOSO domain prefix from associated accounts and groups
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -LogDir C:\Logs

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Redirect logs and output files to C:\Logs instead of the default location in AppData
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -LevelsOfSubfolders 0

    Generate reports on the NTFS permissions for the folder C:\Test only (no subfolders)
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -LevelsOfSubfolders 2

    Generate reports on the NTFS permissions for the folder C:\Test

    Only include subfolders to a maximum of 2 levels deep (C:\Test\Level1\Level2)
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -Title 'New Custom Report Title'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Change the title of the HTML report to 'New Custom Report Title'
#>
param (

    # Path to the folder whose permissions to report (only tested with local paths, UNC may work, unknown)
    [string]$TargetPath = 'C:\Test',
    #[string]$TargetPath = '\\ad.contoso.com\coh\Test2\FolderWithoutTarget\FolderWithTarget\',

    # Regular expressions that will identify Users or Groups you do not want included in the Html report
    [string[]]$ExcludeAccount,
    <#[string[]]$ExcludeAccount = @(
        'BUILTIN\\Administrators',
        'BUILTIN\\Administrator',
        'CREATOR OWNER',
        'NT AUTHORITY\\SYSTEM'
    )#>

    # Exclude empty groups from the HTML report
    [switch]$ExcludeEmptyGroups,

    <#
    Domains to ignore (they will be removed from the username)

    Intended when a user has matching SamAccountNames in multiple domains but you only want them to appear once on the report.
    #>
    [string[]]$IgnoreDomain, # = @('CONTOSO1\\','CONTOSO2\\'),

    # Path to save the logs and reports generated by this script
    [string]$LogDir = "$env:AppData\Export-Permission\Logs",

    # Do not get group members (only report the groups themselves)
    [switch]$NoGroupMembers,

    <#
    How many levels of subfolder to enumerate

        Set to 0 to ignore all subfolders

        Set to -1 (default) to recurse infinitely

        Set to any whole number to enumerate that many levels
    #>
    [int]$SubfolderLevels = -1,

    # Title at the top of the HTML report
    [string]$Title = "Folder Permissions Report",

    <#
    Valid group names that are allowed to appear in ACEs

    Specify as a ScriptBlock meant for the FilterScript parameter of Where-Object

    In the scriptblock, use string comparisons on the Name property

    e.g. {$_.Name -like 'CONTOSO\Group1*' -or $_.Name -eq 'CONTOSO\Group23'}

    The naming format that will be used for the groups is CONTOSO\Group1

    where CONTOSO is the NetBIOS name of the domain, and Group1 is the samAccountName of the group

    By default, this is a scriptblock that always evaluates to $true so it doesn't evaluate any naming convention compliance
    #>
    [scriptblock]$GroupNamingConvention = { $true },

    # Open the HTML report after the script is finished using Invoke-Item (only useful interactively)
    [switch]$OpenReportAtEnd,

    <#
    If all four of the PRTG parameters are specified,

    the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    #>
    [string]$PrtgProbe,

    <#
    If all four of the PRTG parameters are specified,

    the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    #>
    [string]$PrtgSensorProtocol,

    <#
    If all four of the PRTG parameters are specified,

    the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    #>
    [int]$PrtgSensorPort,

    <#
    If all four of the PRTG parameters are specified,

    the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    #>
    [string]$PrtgSensorToken

)

#----------------[ Functions ]------------------

# This is where the function definitions will be inserted in the portable version of this script

#----------------[ Logging ]----------------

$LogDir = New-DatedSubfolder -Root $LogDir
$TranscriptFile = "$LogDir\Transcript.log"
Start-Transcript $TranscriptFile *>$null
Write-Information $TranscriptFile

#----------------[ Declarations ]----------------

$DirectoryEntryCache = [hashtable]::Synchronized(@{})
$IdentityReferenceCache = [hashtable]::Synchronized(@{})
$AdsiServerCache = [hashtable]::Synchronized(@{})
$Permissions = $null
$FolderTargets = $null
$SecurityPrincipals = $null
$FormattedSecurityPrincipals = $null
$DedupedUserPermissions = $null
$FolderPermissions = $null

#----------------[ Main Execution ]---------------

$ReportDescription = Get-ReportDescription -LevelsOfSubfolders $SubfolderLevels
$FolderTableHeader = Get-FolderTableHeader -LevelsOfSubfolders $SubfolderLevels
Write-Verbose "$(Get-Date -Format s)`t$(hostname)`tExport-Permission`tTarget Folder: '$TargetPath'"
$FolderTargets = Get-FolderTarget -FolderPath $TargetPath
$Permissions = Get-FolderAccessList -FolderTargets $FolderTargets -LevelsOfSubfolders $SubfolderLevels

# If $TargetPath was on a local disk such as C:\
# The Get-FolderTarget cmdlet has replaced that local disk path with the corresponding UNC path \\$(hostname)\C$
# Unfortunately if it is the root of that local disk, Get-Item is unable to retrieve a DirectoryInfo object for the root of the share
# (error: "Could not find item")
# As a workaround here we will instead get the folder ACL for the original $TargetPath
# But I don't think this solves it since it won't work for actual remote paths at the root of the share: \\server\share
if ($null -eq $Permissions) {
    $Permissions = Get-FolderAccessList -FolderTargets $TargetPath -LevelsOfSubfolders $SubfolderLevels
}

# Save a CSV of the raw NTFS ACEs, showing non-inherited ACEs only except for the root folder $TargetPath
$CsvFilePath = "$LogDir\1-AccessControlEntries.csv"

$Permissions |
Select-Object -Property @{
    Label      = 'Path'
    Expression = { $_.SourceAccessList.Path }
}, IdentityReference, AccessControlType, FileSystemRights, IsInherited, PropagationFlags, InheritanceFlags |
Export-Csv -NoTypeInformation -LiteralPath $CsvFilePath

Write-Information $CsvFilePath

# Identify unique directory servers to populate into the AdsiServerCache
# This prevents threads that start near the same time from finding the cache empty and attempting costly operations to populate it
# This prevents repetitive queries to the same directory servers
$UniqueServerNames = $Permissions.SourceAccessList.Path |
Sort-Object -Unique |
ForEach-Object { Find-ServerNameInPath -LiteralPath $_ } |
Sort-Object -Unique

# Populate the AdsiServerCache
$GetAdsiServer = @{
    Command        = 'Get-AdsiServer'
    InputObject    = $UniqueServerNames
    InputParameter = 'AdsiServer'
    AddParam       = @{
        KnownServers = $AdsiServerCache
    }
}
$null = Split-Thread @GetAdsiServer

# Resolve the IdentityReference in each Access Control Entry (e.g. CONTOSO\user1, or a SID) to their associated SIDs/Names
# The resolved name includes the domain name (or local computer name for local accounts)
$ResolveAce = @{
    Command              = 'Resolve-Ace'
    InputObject          = $Permissions
    InputParameter       = 'InputObject'
    ObjectStringProperty = 'IdentityReference'
    AddParam             = @{
        KnownServers = $AdsiServerCache
    }
}
$PermissionsWithResolvedIdentityReferences = Split-Thread @ResolveAce

# Save a CSV report of the resolved identity references
$CsvFilePath = "$LogDir\2-AccessControlEntriesWithResolvedIdentityReferences.csv"

$PermissionsWithResolvedIdentityReferences |
Select-Object -Property @{
    Label      = 'Path'
    Expression = { $_.SourceAccessList.Path }
}, * |
Export-Csv -NoTypeInformation -LiteralPath $CsvFilePath

Write-Information $CsvFilePath

# Group the Access Control Entries by their resolved identity references
# This avoids repeat ADSI lookups for the same security principal
$GroupedIdentities = $PermissionsWithResolvedIdentityReferences |
Group-Object -Property IdentityReferenceResolved

# Use ADSI to collect more information about each resolved identity reference
$ExpandIdentityReference = @{
    Command              = 'Expand-IdentityReference'
    InputObject          = $GroupedIdentities
    InputParameter       = 'AccessControlEntry'
    AddParam             = @{
        DirectoryEntryCache    = $DirectoryEntryCache
        IdentityReferenceCache = $IdentityReferenceCache
    }
    ObjectStringProperty = 'Name'
}
if ($NoGroupMembers) {
    $ExpandIdentityReference['AddSwitch'] = 'NoGroupMembers'
}
$SecurityPrincipals = Split-Thread @ExpandIdentityReference

# Format Security Principals (distinguish group members from users directly listed in the NTFS DACLs)
# Filter out groups (their members have already been retrieved)
$FormatSecurityPrincipal = @{
    Command              = 'Format-SecurityPrincipal'
    InputObject          = $SecurityPrincipals
    InputParameter       = 'SecurityPrincipal'
    Timeout              = 1200
    ObjectStringProperty = 'Name'
}
$FormattedSecurityPrincipals = Split-Thread @FormatSecurityPrincipal

# Expand the collection of security principals from Format-SecurityPrincipal
# back into a collection of access control entries (one per ACE per principal)
# This operation is a bunch simple type conversions, no queries are being performed
# That makes it fast enough that it is not worth multi-threading
$ExpandedAccountPermissions = Expand-AccountPermission -AccountPermission $FormattedSecurityPrincipals

# Save a CSV report of the expanded account permissions
#TODO: Expand DirectoryEntry objects in the DirectoryEntry and Members properties
$CsvFilePath = "$LogDir\3-AccessControlEntriesWithResolvedAndExpandedIdentityReferences.csv"

$ExpandedAccountPermissions |
Select-Object -Property @{
    Label      = 'SourceAclPath'
    Expression = { $_.ACESourceAccessList.Path }
}, * |
Export-Csv -NoTypeInformation -LiteralPath $CsvFilePath

Write-Information $CsvFilePath

$Accounts = $FormattedSecurityPrincipals |
Group-Object -Property User |
Sort-Object -Property Name

# Ensure accounts only appear once on the report if they exist in multiple domains
$DedupedUserPermissions = $Accounts |
Remove-DuplicatesAcrossIgnoredDomains -DomainToIgnore $IgnoreDomain

# Group the user permissions back into folder permissions for the report
$FolderPermissions = Format-FolderPermission -UserPermission $DedupedUserPermissions |
Group-Object -Property Folder |
Sort-Object -Property Name

$HtmlTableOfFolders = Select-FolderTableProperty -InputObject $FolderPermissions |
ConvertTo-Html -Fragment |
New-BootstrapTable

$GetFolderPermissionsBlock = @{
    FolderPermissions  = $FolderPermissions
    ExcludeAccount     = $ExcludeAccount
    ExcludeEmptyGroups = $ExcludeEmptyGroups
    IgnoreDomain       = $IgnoreDomain
}
$HtmlFolderPermissions = Get-FolderPermissionsBlock @GetFolderPermissionsBlock

##Commented the two lines below because actually keeping semicolons means it copy/pastes better into Excel
### Convert-ToHtml will not expand in-line HTML, so we had to use semicolons as placeholders and will now replace them with line breaks.
##$HtmlFolderPermissions = $HtmlFolderPermissions -replace ' ; ','<br>'

$ReportDescription = "$(New-BootstrapAlert -Class Dark -Text $TargetPath) $ReportDescription"
$FolderList = Get-HtmlFolderList -FolderTableHeader $FolderTableHeader -HtmlTableOfFolders $HtmlTableOfFolders
[string]$Body = Get-HtmlBody -FolderList $FolderList -HtmlFolderPermissions $HtmlFolderPermissions

$ReportParameters = @{
    Title       = $Title
    Description = $ReportDescription
    Body        = $Body
}
$Report = New-BootstrapReport @ReportParameters

# Save the Html report
$ReportFile = "$LogDir\FolderPermissionsReport.html"
$Report | Set-Content -LiteralPath $ReportFile

# Output the name of the report file to the Information stream
Write-Information $ReportFile

# Report common issues with NTFS permissions (formatted as XML for PRTG)
# TODO: Users with ownership
$NtfsIssueParams = @{
    FolderPermissions     = $FolderPermissions
    UserPermissions       = $Accounts
    GroupNamingConvention = $GroupNamingConvention
}
$NtfsIssues = New-NtfsAclIssueReport @NtfsIssueParams

# Format the information as a custom XML sensor for Paessler PRTG Network Monitor
$XMLOutput = Get-PrtgXmlSensorOutput -NtfsIssues $NtfsIssues

# Save the result of the custom XML sensor for Paessler PRTG Network Monitor
$XmlFile = "$LogDir\PrtgSensorResult.xml"
$XMLOutput | Set-Content -LiteralPath $XmlFile

# Output the name of the report file to the Information stream
Write-Information $XmlFile

# Send the XML to a PRTG Custom XML Push sensor for tracking
$PrtgSensorParams = @{
    XmlOutput          = $XMLOutput
    PrtgProbe          = $PrtgProbe
    PrtgSensorProtocol = $PrtgSensorProtocol
    PrtgSensorPort     = $PrtgSensorPort
    PrtgSensorToken    = $PrtgSensorToken
}
Send-PrtgXmlSensorOutput @PrtgSensorParams

# Open the HTML report file (useful only interactively)
if ($OpenReportAtEnd) {
    Invoke-Item $ReportFile
}

Stop-Transcript  *>$null

# Output the XML so the script can be directly used as a PRTG sensor
# Caution: This use may be a problem for a PRTG probe because of how long the script can run on large folders/domains
# Recommendation: Specify the appropriate parameters to run this as a PRTG push sensor instead
return $XMLOutput

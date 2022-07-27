<#PSScriptInfo

.VERSION 0.0.87

.GUID fd2d03cf-4d29-4843-bb1c-0fba86b0220a

.AUTHOR Jeremy La Camera

.COMPANYNAME Jeremy La Camera

.COPYRIGHT (c) Jeremy La Camera. All rights reserved.

.TAGS

.LICENSEURI https://github.com/IMJLA/ExportPermission/blob/main/LICENSE

.PROJECTURI https://github.com/IMJLA/ExportPermission

.ICONURI

.EXTERNALMODULEDEPENDENCIES Adsi,SimplePrtg,PsNtfs,PsLogMessage,PsRunspace,PsDfs,PsBootstrapCss,Permission 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


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
    Exports the permissions to CSV
    Uses ADSI to get information about the accounts and groups listed in the permissions
    Exports information about the accounts and groups to CSV
    Uses ADSI to recursively retrieve the members of nested groups
    Creates an HTML report showing the resultant access of individual accounts
    Exports information about all accounts with NTFS access to CSV
    Creates an HTML report of all accounts with NTFS access
    Outputs an XML-formatted list of common misconfigurations for use win Paessler PRTG Network Monitor as a custom XML sensor
.INPUTS
    None. Pipeline input is not accepted.
.OUTPUTS
    [System.String] XML PRTG sensor output
.NOTES
    TODO: Bug - Logic Flaw for Owner.  Currently we search folders for non-inherited access rules, then we manually add a FullControl access rule for the Owner.  This misses folders with only inherited access rules but a different owner.
    TODO: Bug - Doesn't work for AD users' default group/primary group (which is typically Domain Users).  The user's default group is not listed in their memberOf attribute so I need to fix the LDAP search filter to include the primary group attribute.
    TODO: Bug - For a fake group created by New-FakeDirectoryEntry in the Adsi module, in the report its name will end up as an NT Account (CONTOSO\User123).  If it is a fake user, its name will correctly appear without the domain prefix (User123)
    TODO: Feature - List any excluded accounts at the end
    TODO: Feature - Remove all usage of Add-Member to improve performance (create new pscustomobjects instead, nest original object inside)
    TODO: Feature - Parameter to specify properties to include in report
    TODO: Feature - This script does NOT account for individual file permissions.  Only folder permissions are considered.
    TODO: Feature - This script does NOT account for file share permissions. Only NTFS permissions are considered.
    TODO: Feature - Support ACLs from Registry or AD objects
    TODO: Feature - psake task to update Release Notes in the script metadata to the github commit message
.EXAMPLE
    .\Export-Permission.ps1 -TargetPath C:\Test

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders
.EXAMPLE
    .\Export-Permission.ps1 -TargetPath C:\Test -AccountsToSkip 'BUILTIN\\Administrator'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders
    Exclude the built-in Administrator account from the HTML report
    The AccountsToSkip parameter uses RegEx, so the \ in BUILTIN\Administrator needed to be escaped.
    The RegEx escape character is \ so that is why the regular expression needed for the parameter is 'BUILTIN\\Administrator'
.EXAMPLE
    .\Export-Permission.ps1 -TargetPath C:\Test -ExcludeEmptyGroups

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders
    Exclude empty groups from the HTML report (leaving accounts only)
.EXAMPLE
    .\Export-Permission.ps1 -TargetPath C:\Test -DomainToIgnore 'CONTOSO'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders
    Remove the CONTOSO domain prefix from associated accounts and groups
.EXAMPLE
    .\Export-Permission.ps1 -TargetPath C:\Test -LogDir C:\Logs

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders
    Redirect logs and output files to C:\Logs instead of the default location in AppData
.EXAMPLE
    .\Export-Permission.ps1 -TargetPath C:\Test -LevelsOfSubfolders 0

    Generate reports on the NTFS permissions for the folder C:\Test only (no subfolders)
.EXAMPLE
    .\Export-Permission.ps1 -TargetPath C:\Test -LevelsOfSubfolders 2

    Generate reports on the NTFS permissions for the folder C:\Test
    Only include subfolders to a maximum of 2 levels deep (C:\Test\Level1\Level2)
.EXAMPLE
    .\Export-Permission.ps1 -TargetPath C:\Test -Title 'New Custom Report Title'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders
    Change the title of the HTML report to 'New Custom Report Title'
#>
param (

    # Path to the folder whose permissions to report (only tested with local paths, UNC may work, unknown)
    [string]$TargetPath = 'C:\Test',
    #[string]$TargetPath = '\\ad.contoso.com\coh\Test2\FolderWithoutTarget\FolderWithTarget\',

    # Regular expressions that will identify Users or Groups you do not want included in the Html report
    [string[]]$AccountsToSkip<# = @(
        'BUILTIN\\Administrators',
        'BUILTIN\\Administrator',
        'CREATOR OWNER',
        'NT AUTHORITY\\SYSTEM'
    )#>,

    # Exclude empty groups from the HTML report
    [switch]$ExcludeEmptyGroups,

    # Domains to ignore (they will be removed from the username)
    # Intended when a user has matching SamAccountNames in multiple domains but you only want them to appear once on the report.
    [string[]]$DomainToIgnore, # = @('CONTOSO1\\','CONTOSO2\\'),

    # Path to save the logs and reports generated by this script
    [string]$LogDir = "$env:AppData\Export-Permission\Logs",

    # Path containing the required modules for this script
    # Each module must match proper PowerShell module folder structure (module folder name matches the name of the .psm1 file)
    [string]$ModulesDir = '$PSScriptRoot\Modules',

    # Get group members
    [switch]$NoGroupMembers,

    <#
    How many levels of subfolder to enumerate
        Set to 0 to ignore all subfolders
        Set to -1 (default) to recurse infinitely
        Set to any whole number to enumerate that many levels
    #>
    [int]$LevelsOfSubfolders = -1,

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

    # If all four of the PRTG parameters are specified,
    # the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    [string]$PrtgProbe,

    # If all four of the PRTG parameters are specified,
    # the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    [string]$PrtgSensorProtocol,

    # If all four of the PRTG parameters are specified,
    # the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    [int]$PrtgSensorPort,

    # If all four of the PRTG parameters are specified,
    # the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    [string]$PrtgSensorToken

)

#----------------[ Initialization ]----------------

# $PSScriptRoot is usually null inside the param block so I can't use the double-quotes up there to expand it
# doing it this way allows comment-based help to accurately reflect the default values of these parameters
if ($ModulesDir -eq '$PSScriptRoot\Modules') {
    $ModulesDir = "$PSScriptRoot\Modules"
}

#----------------[ Functions ]------------------

# Load all modules contained in the specified directory
Get-ChildItem -Directory -LiteralPath $ModulesDir |
ForEach-Object {
    Remove-Module $_.Name -Force -ErrorAction SilentlyContinue *>$null
    Import-Module $_.FullName -ErrorAction Stop #*>$null
}

#----------------[ Logging ]----------------

$LogDir = New-DatedSubfolder -Root $LogDir
Start-Transcript "$LogDir\Transcript.log"

#----------------[ Declarations ]----------------

$DirectoryEntryCache = [hashtable]::Synchronized(@{})
$IdentityReferenceCache = [hashtable]::Synchronized(@{})
$AdsiServerCache = [hashtable]::Synchronized(@{})
$Permissions = $null
$FolderTargets = $null
$SecurityPrincipals = $null
$AccountPermissions = $null
$DedupedUserPermissions = $null
$FolderPermissions = $null

#----------------[ Main Execution ]---------------

Write-Verbose "$(Get-Date -Format s)`t$(hostname)`tExport-Permission`tTarget Folder: '$TargetPath'"
$FolderTargets = Get-FolderTarget -FolderPath $TargetPath
$ReportDescription = Get-ReportDescription -LevelsOfSubfolders $LevelsOfSubfolders
$FolderTableHeader = Get-FolderTableHeader -LevelsOfSubfolders $LevelsOfSubfolders
$Permissions = Get-FolderAccessList -FolderTargets $FolderTargets -LevelsOfSubfolders $LevelsOfSubfolders

# If $TargetPath was on a local disk such as C:\
# The Get-FolderTarget cmdlet has replaced that local disk path with the corresponding UNC path \\$(hostname)\C$
# Unfortunately if it is the root of that local disk, Get-Item is unable to retrieve a DirectoryInfo object for the root of the share
# (error: "Could not find item")
# As a workaround here we will instead get the folder ACL for the original $TargetPath
# But I don't think this solves it since it won't work for actual remote paths at the root of the share: \\server\share
if ($null -eq $Permissions) {
    $Permissions = Get-FolderAccessList -FolderTargets $TargetPath -LevelsOfSubfolders $LevelsOfSubfolders
}

# Save a CSV of the raw NTFS ACEs, showing non-inherited ACEs only except for the root folder $TargetPath
$NtfsAccessControlEntriesCsv = "$LogDir\NtfsAccessControlEntries.csv"

$Permissions |
Select-Object -Property @{
    Label      = 'Path'
    Expression = { $_.SourceAccessList.Path }
}, IdentityReference, AccessControlType, FileSystemRights, IsInherited, PropagationFlags, InheritanceFlags |
Export-Csv -NoTypeInformation -LiteralPath $NtfsAccessControlEntriesCsv

Write-Information $NtfsAccessControlEntriesCsv

# Resolve the Identity References directly from the NTFS ACEs to their associated SIDs/Names
$ResolveAce = @{
    Command              = 'Resolve-Ace'
    InputObject          = $Permissions
    InputParameter       = 'InputObject'
    ObjectStringProperty = 'IdentityReference'
    AddParam             = @{
        KnownServers = $AdsiServerCache
    }
}
$Identities = Split-Thread @ResolveAce

# Save a CSV report of the resolved identity references
$IdentityReferencesCsv = "$LogDir\NtfsIdentityReferences.csv"

$Identities |
Select-Object -Property @{
    Label      = 'Path'
    Expression = { $_.SourceAccessList.Path }
}, * |
Export-Csv -NoTypeInformation -LiteralPath $IdentityReferencesCsv

Write-Information $IdentityReferencesCsv

$GroupedIdentities = $Identities |
Group-Object -Property IdentityReferenceResolved

# Use ADSI to collect more information about each IdentityReference (e.g. CONTOSO\user1) in NTFS Access Control Entries
$ExpandIdentityReference = @{
    Command              = 'Expand-IdentityReference'
    InputObject          = $GroupedIdentities
    InputParameter       = 'AccessControlEntry'
    AddParam             = @{
        NoGroupMembers         = $NoGroupMembers
        DirectoryEntryCache    = $DirectoryEntryCache
        IdentityReferenceCache = $IdentityReferenceCache
    }
    ObjectStringProperty = 'Name'
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
$AccountPermissions = Split-Thread @FormatSecurityPrincipal

$ExpandedAccountPermissions = Expand-AccountPermission -AccountPermission $AccountPermissions

# Save a CSV report of the expanded account permissions
#TODO: Expand DirectoryEntry objects in the DirectoryEntry and Members properties
$ExpandedAccountPermissionsCsv = "$LogDir\ResultantAccountPermissions.csv"

$ExpandedAccountPermissions |
Select-Object -Property @{
    Label      = 'SourceAclPath'
    Expression = { $_.ACESourceAccessList.Path }
}, * |
Export-Csv -NoTypeInformation -LiteralPath $ExpandedAccountPermissionsCsv

Write-Information $ExpandedAccountPermissionsCsv

$Accounts = $AccountPermissions |
Group-Object -Property User |
Sort-Object -Property Name

# Ensure accounts only appear once on the report if they exist in multiple domains
$DedupedUserPermissions = $Accounts |
Remove-DuplicatesAcrossIgnoredDomains -DomainToIgnore $DomainToIgnore

# Group the user permissions back into folder permissions for the report
$FolderPermissions = Format-FolderPermission -UserPermission $DedupedUserPermissions |
Group-Object -Property Folder |
Sort-Object -Property Name

$HtmlTableOfFolders = Select-FolderTableProperty -InputObject $FolderPermissions |
ConvertTo-Html -Fragment |
New-BootstrapTable

$GetFolderPermissionsBlock = @{
    FolderPermissions  = $FolderPermissions
    AccountsToSkip     = $AccountsToSkip
    ExcludeEmptyGroups = $ExcludeEmptyGroups
    DomainToIgnore     = $DomainToIgnore
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

Stop-Transcript

# Output the XML so the script can be directly used as a PRTG sensor
Invoke-Item $ReportFile

# Output the XML so the script can be directly used as a PRTG sensor
return $XMLOutput

<#PSScriptInfo

.VERSION 0.0.589

.GUID fd2d03cf-4d29-4843-bb1c-0fba86b0220a

.AUTHOR Jeremy La Camera

.COMPANYNAME Jeremy La Camera

.COPYRIGHT (c) Jeremy La Camera. All rights reserved.

.TAGS adsi ldap winnt ntfs acl

.LICENSEURI https://github.com/IMJLA/Export-Permission/blob/main/LICENSE

.PROJECTURI https://github.com/IMJLA/Export-Permission

.ICONURI https://imjla.github.io/Export-Permission/img/logo.svg

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
update docs

.PRIVATEDATA

#> 

#Requires -Module @{ ModuleName = 'PsDfs' ; RequiredVersion = '1.0.18' }
#Requires -Module @{ ModuleName = 'Adsi' ; RequiredVersion = '4.0.522' }
#Requires -Module @{ ModuleName = 'Permission' ; RequiredVersion = '0.0.1189' }
#Requires -Module @{ ModuleName = 'PsBootstrapCss' ; RequiredVersion = '1.0.53' }
#Requires -Module @{ ModuleName = 'PsLogMessage' ; RequiredVersion = '1.0.119' }
#Requires -Module @{ ModuleName = 'PsNtfs' ; RequiredVersion = '2.0.227' }
#Requires -Module @{ ModuleName = 'PsRunspace' ; RequiredVersion = '1.0.124' }
#Requires -Module @{ ModuleName = 'SimplePrtg' ; RequiredVersion = '1.0.13' }

<#
.SYNOPSIS
    Create CSV, HTML, JSON, and XML exports of permissions
.DESCRIPTION
    Present complex nested permissions and group memberships in a report that is easy to read

    Provide additional properties of each account such as Name, Description, Title, Department, Company, or any specified property

    Multithreaded with in-process caching for fast results

    Works as a scheduled task

    Works as a custom sensor script for Paessler PRTG Network Monitor (Push sensor recommended due to execution time)

    Supports:
    - Active Directory domain trusts
    - Unresolved SIDs for deleted accounts
    - Service SID resolution
    - Group memberships via an account's Primary Group as well as its memberOf property
    - ACL Owners (shown in the report as having Full Control originating from Ownership)

    Does not support these scenarios:
    - Unsupported SDDL Components:
        - The System Access Control List (SACL) containing ACL Auditors is not reported.
        - The Primary Group is not reported.
    - File permissions (ToDo enhancement; for now only folder permissions are reported)
    - Share permissions (ToDo enhancement; for now only NTFS permissions are reported)

    Behavior:
    - Resolves each path in the SourcePath parameter
      - Local paths become UNC paths using the administrative shares, so the computer name is shown in reports
      - DFS paths become all of their UNC folder targets, including disabled ones
      - Mapped network drives become their UNC paths
    - Gets children of the resolved paths to the specified RecurseDepth
    - Gets all permissions for the parent paths
    - Gets non-inherited permissions for the discovered children
    - Uses CIM and ADSI to get information about the accounts and groups listed in the permissions
    - Uses ADSI to recursively retrieve group members
      - Retrieves group members using both the memberOf and primaryGroupId attributes
      - Members of nested groups are retrieved and returned as members of the group listed in the permissions.
          - Their hierarchy of nested group memberships is not retrieved (for performance reasons).
    - Exports permissions to files of the specified File Formats, using the specified report Detail levels
    - Outputs permissions to the pipeline in the specified Output Format and using the highest specified report Detail level
.INPUTS
    [System.IO.DirectoryInfo[]] SourcePath parameter

    Strings can be passed to this parameter and will be re-cast as DirectoryInfo objects.
.OUTPUTS
    [PSCustomObject] Items, permissions, and accounts formatted according to specified parameters.
.NOTES
    This code has not been reviewed or audited by a third party

    This code has limited or no tests

    It was designed for presenting reports to non-technical management or administrative staff

    It is convenient for that purpose but it is not recommended for compliance reporting or similar formal uses
.EXAMPLE
    Export-Permission.ps1 -SourcePath C:\Test

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders
.EXAMPLE
    Export-Permission.ps1 -SourcePath C:\Test -ExcludeAccount 'BUILTIN\\Administrator'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Exclude the built-in Administrator account from the HTML report

    The ExcludeAccount parameter uses RegEx, so the \ in BUILTIN\Administrator needed to be escaped.

    The RegEx escape character is \ so the regular expression needed for the parameter is 'BUILTIN\\Administrator'
.EXAMPLE
    Export-Permission.ps1 -SourcePath C:\Test -ExcludeAccount @(
        'BUILTIN\\Administrators',
        'BUILTIN\\Administrator',
        'CREATOR OWNER',
        'NT AUTHORITY\\SYSTEM'
    )

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Exclude from the HTML report:
    - The built-in Administrator account
    - The built-in Administrators group and its members (unless they appear elsewhere in the permissions)
    - The CREATOR OWNER security principal
    - The computer account (NT AUTHORITY\SYSTEM)

    Note: CREATOR OWNER will still be reported as an alarm in the PRTG XML output
.EXAMPLE
    Export-Permission.ps1 -SourcePath C:\Test -ExcludeClass @('computer')

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Include empty groups on the HTML report (rather than the default setting which would exclude computers and groups)
.EXAMPLE
    Export-Permission.ps1 -SourcePath C:\Test -NoGroupMembers -ExcludeClass @('computer')

    Generate reports on the NTFS permissions for the folder C:\Test

    Do not spend time retrieving group members

    Include groups on the report, but exclude computers (rather than the default setting which would exclude computers and groups)
.EXAMPLE
    Export-Permission.ps1 -SourcePath C:\Test -IgnoreDomain 'CONTOSO'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Remove the CONTOSO domain prefix from associated accounts and groups
.EXAMPLE
    Export-Permission.ps1 -SourcePath C:\Test -IgnoreDomain 'CONTOSO1','CONTOSO2'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Remove the CONTOSO1\ and CONTOSO2\ domain prefixes from associated accounts and groups

    Across the two domains, accounts with the same samAccountNames will be considered equivalent

    Across the two domains, groups with the same Names will be considered equivalent
.EXAMPLE
    Export-Permission.ps1 -SourcePath C:\Test -LogDir C:\Logs

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Redirect logs and output files to C:\Logs instead of the default location in AppData
.EXAMPLE
    Export-Permission.ps1 -SourcePath C:\Test -RecurseDepth 0

    Generate reports on the NTFS permissions for the folder C:\Test only (no subfolders)
.EXAMPLE
    Export-Permission.ps1 -SourcePath C:\Test -RecurseDepth 2

    Generate reports on the NTFS permissions for the folder C:\Test

    Only include subfolders to a maximum of 2 levels deep (C:\Test\Level1\Level2)
.EXAMPLE
    Export-Permission.ps1 -SourcePath C:\Test -Title 'New Custom Report Title'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Change the title of the HTML report to 'New Custom Report Title'
.EXAMPLE
    Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace\DfsFolderWithTarget'

    The source path is a DFS folder with folder targets

    Generate reports on the NTFS permissions for the DFS folder targets associated with this path
.EXAMPLE
    Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget\DfsSubfolderWithTarget'

    The source path is a DFS subfolder with folder targets

    Generate reports on the NTFS permissions for the DFS folder targets associated with this path
.EXAMPLE
    Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget\DfsSubfolderWithTarget\Subfolder'

    The source path is a subfolder of a DFS subfolder with folder targets

    Generate reports on the NTFS permissions for the DFS folder targets associated with this path
.EXAMPLE
    Export-Permission.ps1 -SourcePath '\\ad.contoso.com\'

    This is an edge case that is not currently supported

    The source path is the root of an AD domain

    Generate reports on the NTFS permissions for the root of an AD domain.  TODO: param validation? or otherwise handle error.
.EXAMPLE
    Export-Permission.ps1 -SourcePath '\\computer.ad.contoso.com\'

    This is an edge case that is not currently supported

    The source path is the root of a SMB server

    Generate reports on the NTFS permissions for the root of a SMB server.  TODO: param validation? or otherwise handle error.
.EXAMPLE
    Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace'

    This is an edge case that is not currently supported

    The source path is a DFS namespace

    Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

    Add a warning that they are permissions from the DFS namespace server and could be confusing
.EXAMPLE
    Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget'

    This is an edge case that is not currently supported.

    The source path is a DFS folder without a folder target

    Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

    Add a warning that they are permissions from the DFS namespace server and could be confusing
.EXAMPLE
    Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget'

    This is an edge case that is not currently supported.

    The source path is a DFS subfolder without a folder target.

    Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

    Add a warning that they are permissions from the DFS namespace server and could be confusing
.LINK
    https://imjla.github.io/Export-Permission
.LINK
    https://github.com/IMJLA/Export-Permission
#>

[OutputType([PSCustomObject])]
[CmdletBinding(HelpURI = 'https://imjla.github.io/Export-Permission')]

param (

    <#
    Path to the item whose permissions to export

    Supports:
    - NTFS folder paths
        - Local folder paths
        - UNC folder paths
        - DFS folder paths
        - Mapped network drives

    Does Not Support (ToDo):
    - same sources as Get-Acl (AD, Registry, StorageSubSystem)
    - M365 sources (SP sites, Teams, etc)
    #>
    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateScript({ Test-Path $_ })]
    [System.IO.DirectoryInfo[]]$SourcePath,

    <#
    How many levels of child items to enumerate
    - Set to 0 to ignore all children
    - Set to -1 (default) to recurse through all children
    - Set to any whole number to enumerate that many levels of children
    #>
    [int]$RecurseDepth = -1,

    <#
    Regular expressions matching names of accounts to include in the HTML report

    If this parameter is specified, only accounts whose names match these regular expressions will be included
    #>
    [string[]]$IncludeAccount,

    # Regular expressions matching names of accounts to exclude from the HTML report
    [string[]]$ExcludeAccount = '\\SYSTEM$',

    <#
    Accounts whose objectClass property is in this list are excluded from the HTML report

    Note on the 'group' class:

    By default, a group with members is replaced in the report by its members unless the -NoGroupMembers switch is used.

    Any remaining groups are empty and not useful to see in the middle of a list of users/job titles/departments/etc).

    So the 'group' class is excluded here by default.
    #>
    [string[]]$ExcludeClass = @('group', 'computer'),

    # Properties of each account to display on the report (left out: managedBy, operatingSystem)
    [string[]]$AccountProperty = @('DisplayName', 'Company', 'Department', 'Title', 'Description'),

    <#
    Do not get group members (only report the groups themselves)

    Note: By default, the -ExcludeClass parameter will exclude groups from the report.

    If using -NoGroupMembers, you most likely want to modify the value of -ExcludeClass.

    Remove the 'group' class from ExcludeClass in order to see groups on the report.
    #>
    [switch]$NoMembers,

    <#
    Domain(s) to ignore (they will be removed from the username)

    Can be used:
    - to ensure accounts only appear once on the report when they have matching SamAccountNames in multiple domains.
    - when the domain is often the same and doesn't need to be displayed
    #>
    [string[]]$IgnoreDomain,

    # Path to the folder to save the logs and reports generated by this script
    [System.IO.DirectoryInfo]$OutputDir = "$env:AppData\Export-Permission",

    # Title at the top of the HTML report
    [string]$Title = 'Permissions Report',

    <#
    How to split up the exported files:

    | Value   | Behavior |
    |---------|----------|
    | none    | generate 1 report file with all permissions |
    | account | generate 1 report file per account |
    | source  | generate 1 report file per source path (default) |
    #>
    [ValidateSet('account', 'none', 'source')]
    [string[]]$SplitBy = 'source',

    <#
    How to group the permissions in the output stream and within each exported file. Interacts with the SplitBy parameter:

    | SplitBy | GroupBy | Behavior |
    |---------|---------|----------|
    | none    | none    | 1 file with all permissions in a flat list |
    | none    | account | 1 file with all permissions grouped by account |
    | none    | item    | 1 file with all permissions grouped by item |
    | none    | source    | 1 file with all permissions grouped by source path |
    | account | none    | 1 file per account; in each file, sort permissions by item path |
    | account | account | (same as -SplitBy account -GroupBy none) |
    | account | item    | 1 file per account; in each file, group permissions by item and sort by item path |
    | account | source  | 1 file per account; in each file, group permissions by source path and sort by item path |
    | source  | none    | 1 file per source path; in each file, sort permissions by item path |
    | source  | account | 1 file per source path; in each file, group permissions by account and sort by account name |
    | source  | item    | 1 file per source path; in each file, group permissions by item and sort by item path |
    | source  | source  | (same as -SplitBy source -GroupBy none) |
    #>
    [ValidateSet('account', 'item', 'none', 'source')]
    [string]$GroupBy = 'item',

    # File format(s) to export
    [ValidateSet('csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
    [string[]]$FileFormat = 'js',

    # Type of output returned to the output stream
    [ValidateSet('passthru', 'none', 'csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
    [string]$OutputFormat = 'passthru',

    <#
    Level of detail to export to file

    | Value | Behavior |
    |-------|----------|
    | 0     | Source paths |
    | 1     | Resolved source paths (server names resolved, DFS targets resolved) |
    | 2     | Expanded resolved source paths (parent paths expanded into children) |
    | 3     | Access lists |
    | 4     | Access rules (server names resolved, inheritance flags resolved) |
    | 5     | Accounts with access |
    | 6     | Expanded access rules (expanded with account info) |
    | 7     | Formatted permissions |
    | 8     | Best Practice issues |
    | 9     | Custom sensor output for Paessler PRTG Network Monitor |
    | 10    | Permission Report |
    #>
    [int[]]$Detail = 10,

    <#
    Valid accounts that are allowed to appear in ACEs

    Specify as a ScriptBlock meant for the FilterScript parameter of Where-Object

    By default, this is a ScriptBlock that always evaluates to $true so it doesn't evaluate any account convention compliance

    In the ScriptBlock, any account properties are available for evaluation:

    { $_.DomainNetbios -eq 'CONTOSO' }
     Accounts used in ACEs should be in the CONTOSO domain

    { $_.Name -eq 'Group23' }
    Accounts used in ACEs should be named Group23

    { $_.ResolvedAccountName -like 'CONTOSO\Group1*' -or $_.ResolvedAccountName -eq 'CONTOSO\Group23' }
    Accounts used in ACEs should be in the CONTOSO domain and named Group1something or Group23

    The format of the ResolvedAccountName property is CONTOSO\Group1 where:
    - CONTOSO is the NetBIOS name of the domain (the computer name for local accounts)
    - Group1 is the samAccountName of the account
    #>
    [scriptblock]$AccountConvention = { $true },

    <#
    If all four of the PRTG parameters are specified,

    the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    #>
    [string]$PrtgProbe,

    <#
    If all four of the PRTG parameters are specified,

    the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    #>
    [string]$PrtgProtocol,

    <#
    If all four of the PRTG parameters are specified,

    the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    #>
    [uint16]$PrtgPort,

    <#
    If all four of the PRTG parameters are specified,

    the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    #>
    [string]$PrtgToken,

    <#
    Number of asynchronous threads to use

    Recommended starting with the # of logical CPUs:

    { (Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum }
    #>
    [uint16]$ThreadCount = 1,

    # Open the HTML report after the script is finished using Invoke-Item (only useful interactively)
    [switch]$Interactive,

    # Workaround for https://github.com/PowerShell/PowerShell/issues/20657
    [switch]$NoProgress

)

begin {

    # To avoid generating inaccurate reports, halt the script upon encountering any errors.
    $ErrorActionPreference = 'Stop'

    # Workaround for https://github.com/PowerShell/PowerShell/issues/20657
    if ($NoProgress) {
        $ProgressPreference = 'Ignore'
    }

    # Create a splat of the constant Write-Progress parameters for script readability.
    $Progress = @{
        'Activity' = 'Export-Permission'
        'Id'       = 0
    }

    # Create a splat of the variable Write-Progress parameters for script readability.
    $ProgressUpdate = @{
        'CurrentOperation' = 'Initializing'
        'PercentComplete'  = 0
        'Status'           = '0% (step 1 of 20)'
    }

    # Start the progress bar.
    Write-Progress @Progress @ProgressUpdate

    #----------------[ Functions ]------------------

    # This is where the function definitions will be inserted in the portable version of this script.

    #----------------[ Logging ]----------------

    # Start a timer to measure progress and performance.
    $StopWatch = [System.Diagnostics.Stopwatch]::new()
    $null = $StopWatch.Start()

    # Generate a unique ID for this run of the script.
    $ReportInstanceId = [guid]::NewGuid().ToString()

    # Create a folder to store logs.
    $ReportDir = New-DatedSubfolder -Root $OutputDir.FullName -Suffix "_$ReportInstanceId"

    <# Start the PowerShell transcript.
        PowerShell cannot redirect the Success stream of Start-Transcript to the Information stream
        But it can redirect it to $null, and then send the Transcript file path to Write-Information
    #>
    $TranscriptFile = Join-Path -Path $ReportDir -ChildPath 'PowerShellTranscript.log'
    Start-Transcript -Path $TranscriptFile *>$null
    Write-Information $TranscriptFile

    #----------------[ Declarations ]----------------

    $LogFile = Join-Path -Path $ReportDir -ChildPath 'Export-Permission.log'

    <#
    Create an in-process cache to reduce calls to other processes, disk, or network,
    and to store common parameters for better readability of code and logs.
    #>
    $Cmd = @{
        'ThreadCount'    = $ThreadCount
        'OutputDir'      = $ReportDir
        'TranscriptFile' = $TranscriptFile
    }
    $PermissionCache = Initialize-PermissionCache @Cmd

    # Create a splat of the cache parameter to pass to various functions for script readability.
    $Cache = [ref]$PermissionCache
    $Cached = @{ 'Cache' = $Cache }
    $EmptyMap = @{ 'ExpansionMap' = $PermissionCache['LogEmptyMap'].Value }
    $CacheMap = @{ 'ExpansionMap' = $PermissionCache['LogCacheMap'].Value }
    $StopWatchMap = @{ 'ExpansionMap' = $PermissionCache['LogStopWatchMap'].Value }
    $SourceMap = @{ 'ExpansionMap' = $PermissionCache['LogSourcePathMap'].Value }
    $FormatMap = @{ 'ExpansionMap' = $PermissionCache['LogFormattedMap'].Value }
    $LogAnalysisMap = @{ 'ExpansionMap' = $PermissionCache['LogAnalysisMap'].Value }
    Write-LogMsg -Text "`$Cache = [ref](Initialize-PermissionCache" -Suffix ') # This command was already run but is now being logged' -Expand $Cmd @Cached @EmptyMap

    # Get the FQDN of the computer running the script.
    $Cmd = @{
        'ComputerName' = $PermissionCache['ThisHostname'].Value
    }
    Write-LogMsg -Text 'ConvertTo-PermissionFqdn -ThisFqdn' -Expand $Cmd, $Cached @Cached @CacheMap
    $null = ConvertTo-PermissionFqdn -ThisFqdn @Cmd @Cached

    # Discover any domains trusted by the domain of the computer running the script.
    Write-LogMsg -Text 'Get-PermissionTrustedDomain' -Expand $Cached @Cached @CacheMap
    Get-PermissionTrustedDomain @Cached

}

process {

    #----------------[ Main Execution ]---------------
    $ProgressUpdate = @{
        'CurrentOperation' = 'Resolve source paths to network paths such as UNC paths (including all DFS folder targets)'
        'PercentComplete'  = 5
        'Status'           = '5% (step 2 of 20) Resolve-PermissionSource'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'SourcePath' = $SourcePath
    }
    $SourceCount = $SourcePath.Count
    Write-LogMsg -Text 'Resolve-PermissionSource' -Suffix " # for $SourceCount source paths" -Expand $Cmd, $Cached @Cached @CacheMap
    Resolve-PermissionSource @Cmd @Cached

}

end {

    $ProgressUpdate = @{
        'CurrentOperation' = 'Expand parent paths into the paths of their children'
        'PercentComplete'  = 10
        'Status'           = '10% (step 3 of 20) Expand-PermissionSource'
    }
    Write-Progress @Progress @ProgressUpdate
    $ParentCount = $PermissionCache['ParentBySourcePath'].Value.Values.Count
    $Cmd = @{
        'RecurseDepth' = $RecurseDepth
    }
    Write-LogMsg -Text '$Items = Expand-PermissionSource' -Suffix " # for $ParentCount Parents" -Expand $Cmd, $Cached @Cached @CacheMap
    $Items = Expand-PermissionSource @Cmd @Cached

    $ProgressUpdate = @{
        'CurrentOperation' = 'Get the FQDN of this computer, each trusted domain, and each server in the paths'
        'PercentComplete'  = 15
        'Status'           = '15% (step 4 of 20) Find-ServerFqdn'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'ParentCount' = $ParentCount
    }
    Write-LogMsg -Text '$ServerFqdns = Find-ServerFqdn' -Suffix " # for $ParentCount Parents" -Expand $Cmd, $Cached @Cached @CacheMap
    $ServerFqdns = Find-ServerFqdn @Cmd @Cached

    $ProgressUpdate = @{
        'CurrentOperation' = 'Get the ACL of each path'
        'PercentComplete'  = 20
        'Status'           = '20% (step 5 of 20) Get-AccessControlList'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'ErrorAction' = 'Stop'
        'SourcePath'  = $Items
    }
    $ChildCount = $Items.Values.GetEnumerator().Count
    $ItemCount = $ParentCount + $ChildCount
    Write-LogMsg -Text 'Get-AccessControlList' -Suffix " # for $ItemCount Items" -Expand $Cmd, $Cached @Cached @SourceMap
    Get-AccessControlList @Cmd @Cached

    $ProgressUpdate = @{
        'CurrentOperation' = 'Query each FQDN to pre-populate caches, avoiding redundant ADSI and CIM queries'
        'PercentComplete'  = 25
        'Status'           = '25% (step 6 of 20) Optimize-PermissionCache'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'Fqdn' = $ServerFqdns
    }
    $FqdnCount = $ServerFqdns.Count
    Write-LogMsg -Text 'Optimize-PermissionCache' -Suffix " # for $FqdnCount Server FQDNs" -Expand $Cmd, $Cached @Cached @CacheMap
    Optimize-PermissionCache @Cmd @Cached

    # The resolved name will include the domain name (or local computer name for local accounts)
    $ProgressUpdate = @{
        'CurrentOperation' = 'Resolve each identity reference to its SID and NTAccount name'
        'PercentComplete'  = 30
        'Status'           = '30% (step 7 of 20) Resolve-AccessControlList'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'AccountProperty' = $AccountProperty
    }
    $AclCount = $PermissionCache['AclByPath'].Value.Keys.Count
    Write-LogMsg -Text 'Resolve-AccessControlList' -Suffix " # for $AclCount ACLs" -Expand $Cached, $Cmd @Cached @CacheMap
    Resolve-AccessControlList @Cmd @Cached

    $ProgressUpdate = @{
        'CurrentOperation' = 'Get the current domain'
        'PercentComplete'  = 35
        'Status'           = '35% (step 8 of 20) Get-CurrentDomain'
    }
    Write-Progress @Progress @ProgressUpdate
    Write-LogMsg -Text 'Get-CurrentDomain' -Expand $Cached @Cached @CacheMap
    $null = Get-CurrentDomain @Cached

    $ProgressUpdate = @{
        'CurrentOperation' = 'Use ADSI to get details about each resolved identity reference'
        'PercentComplete'  = 40
        'Status'           = '40% (step 9 of 20) Get-PermissionPrincipal'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'AccountProperty' = $AccountProperty
        'NoGroupMembers'  = $NoMembers
    }
    $AceCount = $PermissionCache['AceByGuid'].Value.Keys.Count
    $IdCount = $PermissionCache['AceGuidById'].Value.Keys.Count
    Write-LogMsg -Text 'Get-PermissionPrincipal' -Suffix " # for $IdCount resolved Identity References" -Expand $Cmd, $Cached @Cached @CacheMap
    Get-PermissionPrincipal @Cmd @Cached

    $ProgressUpdate = @{
        'CurrentOperation' = 'Join access rules with their associated accounts'
        'PercentComplete'  = 45
        'Status'           = '45% (step 10 of 20) Expand-Permission'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'Children' = $Items
        'GroupBy'  = $GroupBy
        'SplitBy'  = $SplitBy
    }
    Write-LogMsg -Text "`$Permissions = Expand-Permission" -Suffix " # for $AceCount ACEs in $AclCount ACLs" -Expand $Cmd, $Cached @Cached @CacheMap
    $Permissions = Expand-Permission @Cmd @Cached

    $ProgressUpdate = @{
        'CurrentOperation' = 'Hide domain names and include/exclude accounts as specified in the report parameters'
        'PercentComplete'  = 50
        'Status'           = '50% (step 11 of 20) Select-UniqueAccountPermission'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'ExcludeAccount' = $ExcludeAccount
        'IgnoreDomain'   = $IgnoreDomain
        'IncludeAccount' = $IncludeAccount
    }
    $PrincipalCount = $PermissionCache['PrincipalByID'].Value.Keys.Count
    Write-LogMsg -Text 'Select-PermissionPrincipal' -Suffix " # for $PrincipalCount accounts" -Expand $Cmd, $Cached @Cached @CacheMap
    Select-PermissionPrincipal @Cmd @Cached

    $ProgressUpdate = @{
        'CurrentOperation' = 'Analyze the permissions against established best practices'
        'PercentComplete'  = 55
        'Status'           = '55% (step 12 of 20) Invoke-PermissionAnalyzer'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'AllowDisabledInheritance' = $Items
        'AccountConvention'        = $AccountConvention
    }
    Write-LogMsg -Text '$PermissionAnalysis = Invoke-PermissionAnalyzer' -Expand $Cmd, $Cached @Cached @CacheMap
    $PermissionAnalysis = Invoke-PermissionAnalyzer @Cmd @Cached

    $ProgressUpdate = @{
        'CurrentOperation' = 'Format the permissions'
        'PercentComplete'  = 60
        'Status'           = '60 % (step 13 of 20) Format-Permission'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'AccountProperty' = $AccountProperty
        'Analysis'        = $PermissionAnalysis
        'FileFormat'      = $FileFormat
        'GroupBy'         = $GroupBy
        'IgnoreDomain'    = $IgnoreDomain
        'OutputFormat'    = $OutputFormat
        'Permission'      = $Permissions
    }
    Write-LogMsg -Text '$FormattedPermissions = Format-Permission' -Expand $Cmd, $Cached @Cached @LogAnalysisMap
    $FormattedPermissions = Format-Permission @Cmd @Cached

    $ProgressUpdate = @{
        'CurrentOperation' = 'Export the report files'
        'PercentComplete'  = 65
        'Status'           = '65 % (step 14 of 20) Out-PermissionFile'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{

        # Objects as they progressed through the data pipeline
        'Analysis' = $PermissionAnalysis; 'FormattedPermission' = $FormattedPermissions ;
        'Permission' = $Permissions ; 'SourcePath' = $SourcePath ;

        # Parameters
        'AccountProperty' = $AccountProperty ; 'Detail' = $Detail ; 'ExcludeAccount' = $ExcludeAccount ; 'ExcludeClass' = $ExcludeClass ;
        'FileFormat' = $FileFormat ; 'GroupBy' = $GroupBy ; 'IgnoreDomain' = $IgnoreDomain ; 'OutputDir' = $ReportDir ; 'Title' = $Title ;
        'OutputFormat' = $OutputFormat ; 'NoMembers' = $NoMembers ; 'RecurseDepth' = $RecurseDepth ; 'SplitBy' = $SplitBy ;

        # Cached variables in memory
        'LogFileList' = $TranscriptFile, $LogFile ; 'StopWatch' = $StopWatch ; 'ReportInstanceId' = $ReportInstanceId ;

        # Measurements taken
        'SourceCount' = $SourceCount ; 'ParentCount' = $ParentCount ; 'ChildCount' = $ChildCount ; 'FqdnCount' = $FqdnCount ;
        'AclCount' = $AclCount ; 'AceCount' = $AceCount ; 'IdCount' = $IdCount ; 'PrincipalCount' = $PrincipalCount ; 'ItemCount' = $ItemCount

    }
    Write-LogMsg -Text 'Out-PermissionFile' -Suffix " # for $IdCount Access Control Entries" -Expand $Cmd, $Cached @Cached @StopWatchMap
    $ReportFile = Out-PermissionFile @Cmd @Cached

    $ProgressUpdate = @{
        'CurrentOperation' = 'Open the HTML report file (if the -Interactive switch was used)'
        'PercentComplete'  = 70
        'Status'           = '70 % (step 15 of 20) Invoke-Item'
    }
    Write-Progress @Progress @ProgressUpdate
    if ($Interactive -and $ReportFile) {
        Write-LogMsg -Text "Invoke-Item -Path '$ReportFile'" @Cached
        Invoke-Item -Path $ReportFile
    }

    $ProgressUpdate = @{
        'CurrentOperation' = 'Send the results to a PRTG Custom XML Push sensor for tracking'
        'PercentComplete'  = 75
        'Status'           = '75 % (step 16 of 20) Send-PrtgXmlSensorOutput'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'XmlOutput'    = $XMLOutput
        'PrtgProbe'    = $PrtgProbe
        'PrtgProtocol' = $PrtgProtocol
        'PrtgPort'     = $PrtgPort
        'PrtgToken'    = $PrtgToken
    }
    Write-LogMsg -Text 'Send-PrtgXmlSensorOutput' -Expand $Cmd @Cached @EmptyMap
    Send-PrtgXmlSensorOutput @Cmd

    $ProgressUpdate = @{
        'CurrentOperation' = 'Output the result to the pipeline'
        'PercentComplete'  = 80
        'Status'           = '80 % (step 17 of 20) Out-Permission'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        'FormattedPermission' = $FormattedPermissions
        'GroupBy'             = $GroupBy
        'OutputFormat'        = $OutputFormat
    }
    Write-LogMsg -Text 'Out-Permission' -Expand $Cmd @Cached @FormatMap
    Out-Permission @Cmd

    $ProgressUpdate = @{
        'CurrentOperation' = 'Cleanup CIM sessions'
        'PercentComplete'  = 85
        'Status'           = '85 % (step 18 of 20) Remove-CachedCimSession'
    }
    Write-Progress @Progress @ProgressUpdate
    Write-LogMsg -Text 'Remove-CachedCimSession -CimCache $CimCache' @Cached
    Remove-CachedCimSession -CimCache $CimCache

    $ProgressUpdate = @{
        'CurrentOperation' = 'Export the buffered log messages to a CSV file'
        'PercentComplete'  = 90
        'Status'           = '90 % (step 19 of 20) Export-LogCsv'
    }
    Write-Progress @Progress @ProgressUpdate
    Write-LogMsg -Text "Export-LogCsv -LogFile '$LogFile'" -Expand $Cached @Cached @CacheMap
    Export-LogCsv -LogFile $LogFile @Cached

    Stop-Transcript  *>$null
    Write-Progress @Progress -Completed

}




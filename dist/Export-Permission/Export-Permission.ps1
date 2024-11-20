<#PSScriptInfo

.VERSION 0.0.409

.GUID fd2d03cf-4d29-4843-bb1c-0fba86b0220a

.AUTHOR Jeremy La Camera

.COMPANYNAME Jeremy La Camera

.COPYRIGHT (c) Jeremy La Camera. All rights reserved.

.TAGS adsi ldap winnt ntfs acl

.LICENSEURI https://github.com/IMJLA/Export-Permission/blob/main/LICENSE

.PROJECTURI https://github.com/IMJLA/Export-Permission

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
expand cache usage

.PRIVATEDATA

#> 

#Requires -Module PsDfs
#Requires -Module Adsi
#Requires -Module Permission
#Requires -Module PsBootstrapCss
#Requires -Module PsLogMessage
#Requires -Module PsNtfs
#Requires -Module PsRunspace
#Requires -Module SimplePrtg





<#
.SYNOPSIS
    Create CSV, HTML, and XML reports of permissions
.DESCRIPTION
    Present complex nested permissions and group memberships in a report that is easy to read
    Provide additional information about each account such as Name, Department, Title
    Multithreaded with caching for fast results
    Works as a scheduled task
    Works as a custom sensor script for Paessler PRTG Network Monitor (Push sensor recommended due to execution time)

    Supports:
    - Local folder paths
    - UNC folder paths
    - DFS folder paths
    - Mapped network drives
    - Active Directory domain trusts
    - Unresolved SIDs for deleted accounts
    - Group memberships via the Primary Group as well as the memberOf property

    Does not support these scenarios:
    - ACL Owners or Groups (ToDo enhancement; for now only the DACL is reported)
    - File permissions (ToDo enhancement; for now only folder permissions are reported)
    - Share permissions (ToDo enhancement; for now only NTFS permissions are reported)

    Behavior:
    - Resolves each path in the TargetPath parameter
      - Local paths become UNC paths using the administrative shares, so the computer name is shown in reports
      - DFS paths become all of their UNC folder targets, including disabled ones
      - Mapped network drives become their UNC paths
    - Gets all permissions for the resolved paths
    - Gets non-inherited permissions for subfolders (if specified)
    - Exports the permissions to a .csv file
    - Uses ADSI to get information about the accounts and groups listed in the permissions
    - Exports information about the accounts and groups to a .csv file
    - Uses ADSI to recursively retrieve group members
      - Retrieves group members using both the memberOf and primaryGroupId attributes
      - Members of nested groups are retrieved as members of the group listed in the permissions.
          - Their hierarchy of nested group memberships is not retrieved (for performance reasons).
    - Exports information about all accounts with access to a .csv file
    - Exports information about all accounts with access to a report generated as a .html file
    - Outputs an XML-formatted list of common misconfigurations for use in Paessler PRTG Network Monitor as a custom XML sensor
.INPUTS
    [System.IO.DirectoryInfo[]] TargetPath parameter

    Strings can be passed to this parameter and will be re-cast as DirectoryInfo objects.
.OUTPUTS
    [PSCustomObject] Items, permissions, and accounts formatted according to specified parameters.
.NOTES
    This code has not been reviewed or audited by a third party

    This code has limited or no tests

    It was designed for presenting reports to non-technical management or administrative staff

    It is convenient for that purpose but it is not recommended for compliance reporting or similar formal uses

    ToDo bugs/enhancements: https://github.com/IMJLA/Export-Permission/issues
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -ExcludeAccount 'BUILTIN\\Administrator'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Exclude the built-in Administrator account from the HTML report

    The ExcludeAccount parameter uses RegEx, so the \ in BUILTIN\Administrator needed to be escaped.

    The RegEx escape character is \ so the regular expression needed for the parameter is 'BUILTIN\\Administrator'
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -ExcludeAccount @(
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
    Export-Permission.ps1 -TargetPath C:\Test -ExcludeClass @('computer')

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Include empty groups on the HTML report (rather than the default setting which would exclude computers and groups)
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -NoGroupMembers -ExcludeClass @('computer')

    Generate reports on the NTFS permissions for the folder C:\Test

    Do not spend time retrieving group members

    Include groups on the report, but exclude computers (rather than the default setting which would exclude computers and groups)
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -IgnoreDomain 'CONTOSO'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Remove the CONTOSO domain prefix from associated accounts and groups
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -IgnoreDomain 'CONTOSO1','CONTOSO2'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Remove the CONTOSO1\ and CONTOSO2\ domain prefixes from associated accounts and groups

    Across the two domains, accounts with the same samAccountNames will be considered equivalent

    Across the two domains, groups with the same Names will be considered equivalent
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -LogDir C:\Logs

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Redirect logs and output files to C:\Logs instead of the default location in AppData
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -RecurseDepth 0

    Generate reports on the NTFS permissions for the folder C:\Test only (no subfolders)
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -RecurseDepth 2

    Generate reports on the NTFS permissions for the folder C:\Test

    Only include subfolders to a maximum of 2 levels deep (C:\Test\Level1\Level2)
.EXAMPLE
    Export-Permission.ps1 -TargetPath C:\Test -Title 'New Custom Report Title'

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Change the title of the HTML report to 'New Custom Report Title'
.EXAMPLE
    Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithTarget'

    The target path is a DFS folder with folder targets

    Generate reports on the NTFS permissions for the DFS folder targets associated with this path
.EXAMPLE
    Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget\DfsSubfolderWithTarget'

    The target path is a DFS subfolder with folder targets

    Generate reports on the NTFS permissions for the DFS folder targets associated with this path
.EXAMPLE
    Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget\DfsSubfolderWithTarget\Subfolder'

    The target path is a subfolder of a DFS subfolder with folder targets

    Generate reports on the NTFS permissions for the DFS folder targets associated with this path
.EXAMPLE
    Export-Permission.ps1 -TargetPath '\\ad.contoso.com\'

    This is an edge case that is not currently supported

    The target path is the root of an AD domain

    Generate reports on the NTFS permissions for the root of an AD domain.  TODO: param validation? or otherwise handle error.
.EXAMPLE
    Export-Permission.ps1 -TargetPath '\\computer.ad.contoso.com\'

    This is an edge case that is not currently supported

    The target path is the root of a SMB server

    Generate reports on the NTFS permissions for the root of a SMB server.  TODO: param validation? or otherwise handle error.
.EXAMPLE
    Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace'

    This is an edge case that is not currently supported

    The target path is a DFS namespace

    Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

    Add a warning that they are permissions from the DFS namespace server and could be confusing
.EXAMPLE
    Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget'

    This is an edge case that is not currently supported.

    The target path is a DFS folder without a folder target

    Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

    Add a warning that they are permissions from the DFS namespace server and could be confusing
.EXAMPLE
    Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget'

    This is an edge case that is not currently supported.

    The target path is a DFS subfolder without a folder target.

    Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

    Add a warning that they are permissions from the DFS namespace server and could be confusing
#>

[OutputType([PSCustomObject])]
[CmdletBinding()]

param (

    <#
    Path to the NTFS folder whose permissions to export

    Currently supports NTFS folders
    TODO: support same targets as Get-Acl (AD, Registry, StorageSubSystem)
    #>
    [Parameter(ValueFromPipeline)]
    [ValidateScript({ Test-Path $_ })]
    [System.IO.DirectoryInfo[]]$TargetPath,

    # Regular expressions matching names of security principals to exclude from the HTML report
    [string[]]$ExcludeAccount = 'SYSTEM',

    <#
    Regular expressions matching names of security principals to include in the HTML report

    Only security principals with names matching these regular expressions will be returned
    #>
    [string[]]$IncludeAccount,

    <#
    Accounts whose objectClass property is in this list are excluded from the HTML report

    Note on the 'group' class:
      By default, a group with members is replaced in the report by its members unless the -NoGroupMembers switch is used.
      Any remaining groups are empty and not useful to see in the middle of a list of users/job titles/departments/etc).
      So the 'group' class is excluded here by default.
    #>
    [string[]]$ExcludeClass = @('group', 'computer'),

    <#
    Domain(s) to ignore (they will be removed from the username)

    Can be used:
      to ensure accounts only appear once on the report when they have matching SamAccountNames in multiple domains.
      when the domain is often the same and doesn't need to be displayed
    #>
    [string[]]$IgnoreDomain,

    # Path to the folder to save the logs and reports generated by this script
    [string]$OutputDir = "$env:AppData\Export-Permission",

    <#
    Do not get group members (only report the groups themselves)

    Note: By default, the -ExcludeClass parameter will exclude groups from the report.
      If using -NoGroupMembers, you most likely want to modify the value of -ExcludeClass.
      Remove the 'group' class from ExcludeClass in order to see groups on the report.
    #>
    [switch]$NoMembers,

    <#
    How many levels of children to enumerate

      Set to 0 to ignore all children
      Set to -1 (default) to recurse through all children
      Set to any whole number to enumerate that many levels of children
    #>
    [int]$RecurseDepth = -1,

    # Title at the top of the HTML report
    [string]$Title = 'Permissions Report',

    <#
    Valid accounts that are allowed to appear in ACEs

    Specify as a ScriptBlock meant for the FilterScript parameter of Where-Object

    By default, this is a ScriptBlock that always evaluates to $true so it doesn't evaluate any account convention compliance

    In the ScriptBlock, any account properties are available for evaluation:

    e.g. {$_.DomainNetbios -eq 'CONTOSO'} # Accounts used in ACEs should be in the CONTOSO domain
    e.g. {$_.Name -eq 'Group23'} # Accounts used in ACEs should be named Group23
    e.g. {$_.ResolvedAccountName -like 'CONTOSO\Group1*' -or $_.ResolvedAccountName -eq 'CONTOSO\Group23'}

    The format of the ResolvedAccountName property is CONTOSO\Group1
      where
        CONTOSO is the NetBIOS name of the domain (the computer name for local accounts)
        and
        Group1 is the samAccountName of the account
    #>
    [scriptblock]$AccountConvention = { $true },

    <#
    Number of asynchronous threads to use
    Recommended starting with the # of logical CPUs:
    (Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum
    #>
    [uint16]$ThreadCount = 1,

    # Open the HTML report after the script is finished using Invoke-Item (only useful interactively)
    [switch]$Interactive,

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
    How to split up the exported files:
        none    generate 1 report file with all permissions
        target  generate 1 report file per target (default)
        item    generate 1 report file per item
        account generate 1 report file per account
        all     generate 1 report file per target and 1 file per item and 1 file per account and 1 file with all permissions.
    #>
    [ValidateSet('account', 'item', 'none', 'target')]
    [string[]]$SplitBy = 'target',

    <#
    How to group the permissions in the output stream and within each exported file

        SplitBy	GroupBy
        none	none	$FlatPermissions all in 1 file
        none	account	$AccountPermissions all in 1 file
        none	item	$ItemPermissions all in 1 file

        account	none	1 file per item in $AccountPermissions.  In each file, $_.Access | sort path
        account	account	(same as -SplitBy account -GroupBy none)
        account	item	1 file per item in $AccountPermissions.  In each file, $_.Access | group item | sort name

        item	none	1 file per item in $ItemPermissions.  In each file, $_.Access | sort account
        item	account	1 file per item in $ItemPermissions.  In each file, $_.Access | group account | sort name
        item	item	(same as -SplitBy item -GroupBy none)

        target	none	1 file per $TargetPath.  In each file, sort ACEs by item path then account name
        target	account	1 file per $TargetPath.  In each file, group ACEs by account and sort by account name
        target	item	1 file per $TargetPath.  In each file, group ACEs by item and sort by item path
        target  target  (same as -SplitBy target -GroupBy none)
    #>
    [ValidateSet('account', 'item', 'none', 'target')]
    [string]$GroupBy = 'item',

    # File format(s) to export
    [ValidateSet('csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
    [string[]]$FileFormat = 'js',

    # Type of output returned to the output stream
    [ValidateSet('passthru', 'none', 'csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
    [string]$OutputFormat = 'passthru',

    <#
    Level of detail to export to file
        0   Item paths
        1   Resolved item paths (server names resolved, DFS targets resolved)
        2   Expanded resolved item paths (parent paths expanded into children)
        3   Access lists
        4   Access rules (server names resolved, inheritance flags resolved)
        5   Accounts with access
        6   Expanded access rules (expanded with account info)
        7   Formatted permissions
        8   Best Practice issues
        9   Custom sensor output for Paessler PRTG Network Monitor
        10  Permission Report
    #>
    [int[]]$Detail = 10,

    # String translations indexed by value in the [System.Security.AccessControl.InheritanceFlags] enum
    # Parameter default value is on a single line as a workaround to a PlatyPS bug
    # TODO: Move to i18n
    [string[]]$InheritanceFlagResolved = @('this folder but not subfolders', 'this folder and subfolders', 'this folder and files, but not subfolders', 'this folder, subfolders, and files'),

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
        Activity = 'Export-Permission'
        Id       = 0
    }

    # Create a splat of the variable Write-Progress parameters for script readability.
    $ProgressUpdate = @{
        CurrentOperation = 'Initializing'
        PercentComplete  = 0
        Status           = '0% (step 1 of 20)'
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
    $OutputDir = New-DatedSubfolder -Root $OutputDir -Suffix "_$ReportInstanceId"

    <# Start the PowerShell transcript.
        PowerShell cannot redirect the Success stream of Start-Transcript to the Information stream
        But it can redirect it to $null, and then send the Transcript file path to Write-Information
    #>
    $TranscriptFile = Join-Path -Path $OutputDir -ChildPath 'PowerShellTranscript.log'
    Start-Transcript $TranscriptFile *>$null
    Write-Information $TranscriptFile

    #----------------[ Declarations ]----------------

    $LogFile = Join-Path -Path $OutputDir -ChildPath 'Export-Permission.log'

    # Create an in-process cache to reduce calls to other processes or to disk.
    $PermissionCache = New-PermissionCache

    # Create a splat of the cache parameter to pass to various functions for script readability.
    $Cache = @{ Cache = [ref]$PermissionCache }

    # Get the hostname of the computer running the script.
    $ThisHostname = HOSTNAME.EXE

    # Get the NTAccount caption of the user running the script, with the correct capitalization.
    $WhoAmI = Get-PermissionWhoAmI -ThisHostname $ThisHostname

    # Create a splat of the ThreadCount parameter to pass to various functions for script readability.
    $Threads = @{ ThreadCount = $ThreadCount }

    # Create a splat of log-related parameters to pass to various functions for script readability.
    $LogThis = @{ ThisHostname = $ThisHostname ; WhoAmI = $WhoAmI }

    # Create a splat of constant Write-LogMsg parameters for script readability.
    $LogBuffer = [ref]$PermissionCache['LogBuffer']
    $Log = @{ ThisHostname = $ThisHostname ; Type = 'Debug' ; Buffer = $LogBuffer ; WhoAmI = $WhoAmI }

    # Store the ExpandKeyMap parameter value in memory to avoid scriptblock evaluation in each Write-LogMsg call.
    $LogMap = @{ ExpandKeyMap = @{ Cache = '([ref]$PermissionCache)' } }
    $LogEmptyMap = @{ ExpandKeyMap = @{} }

    # These events already happened but we will log them now that we have the correct capitalization of the user.
    Write-LogMsg -Text '$StopWatch = [System.Diagnostics.Stopwatch]::new() ; $StopWatch.Start() # This command was already run but is now being logged' @Log @LogEmptyMap
    Write-LogMsg -Text '$PermissionCache = New-PermissionCache # This command was already run but is now being logged' @Log @LogEmptyMap
    Write-LogMsg -Text '$ThisHostname = HOSTNAME.EXE # This command was already run but is now being logged' @Log @LogEmptyMap
    Write-LogMsg -Text "`$WhoAmI = Get-PermissionWhoAmI -ThisHostName '$ThisHostname'" -Suffix ' # This command was already run but is now being logged' @Log @LogEmptyMap

    # Get the FQDN of the computer running the script.
    Write-LogMsg -Text "`$ThisFqdn = ConvertTo-PermissionFqdn -ComputerName $ThisHostname" -Expand $LogThis, $Cache @Log @LogMap
    $ThisFqdn = ConvertTo-PermissionFqdn -ComputerName $ThisHostname @Cache @LogThis

    # Create a splat of the ThisFqdn parameter to pass to various functions for script readability.
    $Fqdn = @{ ThisFqdn = $ThisFqdn }

    # Discover any domains trusted by the domain of the computer running the script.
    Write-LogMsg -Text 'Get-PermissionTrustedDomain' -Expand $Cache, $LogThis @Log @LogMap
    Get-PermissionTrustedDomain @Cache @LogThis

    # Initialize the parent progress bar ID to pass to various functions for progress bar nesting.
    $LogThis['ProgressParentId'] = 0

}

process {

    #----------------[ Main Execution ]---------------
    $ProgressUpdate = @{
        CurrentOperation = 'Resolve target paths to network paths such as UNC paths (including all DFS folder targets)'
        PercentComplete  = 5
        Status           = '5% (step 2 of 20) Resolve-PermissionTarget'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        TargetPath = $TargetPath
    }
    $TargetCount = $TargetPath.Count
    Write-LogMsg -Text 'Resolve-PermissionTarget' -Suffix " # for $TargetCount Target Paths" -Expand $Cmd, $LogThis, $Cache @Log @LogMap
    Resolve-PermissionTarget @Cmd @Cache @LogThis

}

end {

    $ProgressUpdate = @{
        CurrentOperation = 'Expand parent paths into the paths of their children'
        PercentComplete  = 10
        Status           = '10% (step 3 of 20) Expand-PermissionTarget'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        RecurseDepth = $RecurseDepth
    }
    $ParentCount = $PermissionCache['ParentByTargetPath'].Value.Values.Count
    Write-LogMsg -Text '$Items = Expand-PermissionTarget' -Suffix " # for $ParentCount Parents" -Expand $Cmd, $Threads, $LogThis, $Cache @Log @LogMap
    $Items = Expand-PermissionTarget @Cmd @Cache @LogThis @Threads

    $ProgressUpdate = @{
        CurrentOperation = 'Get the ACL of each path'
        PercentComplete  = 15
        Status           = '15% (step 4 of 20) Get-AccessControlList'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        ErrorAction = 'Stop'
        TargetPath  = $Items
    }
    $ChildCount = $Items.Values.GetEnumerator().Count
    $ItemCount = $ParentCount + $ChildCount
    $ExpandKeyMap = @{ TargetPath = '$Items' ; Cache = '[ref]$PermissionCache' }
    Write-LogMsg -Text 'Get-AccessControlList' -Suffix " # for $ItemCount Items" -Expand $Cmd, $Threads, $LogThis, $Cache -ExpandKeyMap $ExpandKeyMap @Log
    Get-AccessControlList @Cmd @Cache @LogThis @Threads

    $ProgressUpdate = @{
        CurrentOperation = 'Get the FQDN of this computer, each trusted domain, and each server in the paths'
        PercentComplete  = 20
        Status           = '20% (step 5 of 20) Find-ServerFqdn'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        ParentCount = $ParentCount
        ThisFqdn    = $ThisFqdn
    }
    Write-LogMsg -Text '$ServerFqdns = Find-ServerFqdn' -Suffix " # for $ParentCount Parents" -Expand $Cmd, $Cache @Log @LogMap
    $ServerFqdns = Find-ServerFqdn @Cmd @Cache

    $ProgressUpdate = @{
        CurrentOperation = 'Query each FQDN to pre-populate caches, avoiding redundant ADSI and CIM queries'
        PercentComplete  = 25
        Status           = '25% (step 6 of 20) Initialize-Cache'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        Fqdn = $ServerFqdns
    }
    $FqdnCount = $ServerFqdns.Count
    Write-LogMsg -Text 'Initialize-Cache' -Suffix " # for $FqdnCount Server FQDNs" -Expand $Cmd, $Threads, $LogThis, $Fqdn, $Cache @Log @LogMap
    Initialize-Cache @Cmd @Cache @LogThis @Fqdn @Threads

    # The resolved name will include the domain name (or local computer name for local accounts)
    $ProgressUpdate = @{
        CurrentOperation = 'Resolve each identity reference to its SID and NTAccount name'
        PercentComplete  = 30
        Status           = '30% (step 7 of 20) Resolve-AccessControlList'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        InheritanceFlagResolved = $InheritanceFlagResolved
    }
    $AclCount = $PermissionCache['AclByPath'].Value.Keys.Count
    Write-LogMsg -Text 'Resolve-AccessControlList' -Suffix " # for $AclCount ACLs" -Expand $Threads, $Fqdn, $LogThis, $Cache, $Cmd @Log @LogMap
    Resolve-AccessControlList @Cmd @Cache @LogThis @Fqdn @Threads

    $ProgressUpdate = @{
        CurrentOperation = 'Get the current domain'
        PercentComplete  = 35
        Status           = '35% (step 8 of 20) Get-CurrentDomain'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        ThisHostname = $ThisHostname
        ThisFqdn     = $ThisFqdn
        WhoAmI       = $WhoAmI
    }
    Write-LogMsg -Text '$CurrentDomain = Get-CurrentDomain' -Expand $Cmd, $Cache @Log @LogMap
    $CurrentDomain = Get-CurrentDomain @Cmd @Cache

    $ProgressUpdate = @{
        CurrentOperation = 'Use ADSI to get details about each resolved identity reference'
        PercentComplete  = 40
        Status           = '40% (step 9 of 20) Get-PermissionPrincipal'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        CurrentDomain  = $CurrentDomain
        NoGroupMembers = $NoMembers
    }
    $AceCount = $PermissionCache['AceByGuid'].Value.Keys.Count
    $IdCount = $PermissionCache['AceGuidById'].Value.Keys.Count
    Write-LogMsg -Text 'Get-PermissionPrincipal' -Suffix " # for $IdCount Identity References" -Expand $Cmd, $Threads, $LogThis, $Fqdn, $Cache @Log @LogMap
    Get-PermissionPrincipal @Cmd @Cache @LogThis @Fqdn @Threads

    $ProgressUpdate = @{
        CurrentOperation = 'Join access rules with their associated accounts'
        PercentComplete  = 45
        Status           = '45% (step 10 of 20) Expand-Permission'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        Children = $Items
        GroupBy  = $GroupBy
        SplitBy  = $SplitBy
    }
    Write-LogMsg -Text "`$Permissions = Expand-Permission" -Suffix " # for $AceCount ACEs in $AclCount ACLs" -Expand $Cmd, $LogThis, $Cache @Log @LogMap
    $Permissions = Expand-Permission @Cmd @Cache @LogThis

    $ProgressUpdate = @{
        CurrentOperation = 'Hide domain names and include/exclude accounts as specified'
        PercentComplete  = 50
        Status           = '50% (step 11 of 20) Select-UniqueAccountPermission'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        ExcludeAccount = $ExcludeAccount
        IgnoreDomain   = $IgnoreDomain
        IncludeAccount = $IncludeAccount
    }
    $PrincipalCount = $PermissionCache['PrincipalByID'].Value.Keys.Count
    Write-LogMsg -Text 'Select-PermissionPrincipal' -Suffix " # for $PrincipalCount Security Principals" -Expand $Cmd, $LogThis, $Cache @Log @LogMap
    Select-PermissionPrincipal @Cmd @Cache @LogThis

    $ProgressUpdate = @{
        CurrentOperation = 'Analyze the permissions against established best practices'
        PercentComplete  = 55
        Status           = '55% (step 12 of 20) Invoke-PermissionAnalyzer'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        AllowDisabledInheritance = $Items
        AccountConvention        = $AccountConvention
    }
    Write-LogMsg -Text 'Invoke-PermissionAnalyzer' -Expand $Cmd, $Cache @Log @LogMap
    $BestPracticeEval = Invoke-PermissionAnalyzer @Cmd @Cache

    $ProgressUpdate = @{
        CurrentOperation = 'Format the permissions'
        PercentComplete  = 60
        Status           = '60 % (step 13 of 20) Format-Permission'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        Analysis     = $BestPracticeEval
        FileFormat   = $FileFormat
        GroupBy      = $GroupBy
        IgnoreDomain = $IgnoreDomain
        OutputFormat = $OutputFormat
        Permission   = $Permissions
    }
    Write-LogMsg -Text '$FormattedPermissions = Format-Permission' -Expand $Cmd, $Cache @Log @LogMap
    $FormattedPermissions = Format-Permission @Cmd @Cache

    $ProgressUpdate = @{
        CurrentOperation = 'Export the report files'
        PercentComplete  = 65
        Status           = '65 % (step 14 of 20) Out-PermissionFile'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{

        # Objects as they progressed through the data pipeline
        BestPracticeEval = $BestPracticeEval; FormattedPermission = $FormattedPermissions ; Permission = $Permissions ; TargetPath = $TargetPath

        # Parameters
        Detail = $Detail ; ExcludeAccount = $ExcludeAccount ; ExcludeClass = $ExcludeClass ; FileFormat = $FileFormat ;
        GroupBy = $GroupBy ; IgnoreDomain = $IgnoreDomain ; OutputDir = $OutputDir ; OutputFormat = $OutputFormat ;
        NoMembers = $NoMembers ; RecurseDepth = $RecurseDepth ; SplitBy = $SplitBy ; Title = $Title ;

        # Cached variables in memory
        LogFileList = $TranscriptFile, $LogFile ; LogParams = $Log ; StopWatch = $StopWatch
        ReportInstanceId = $ReportInstanceId ; WhoAmI = $WhoAmI ; ThisFqdn = $ThisFqdn

        # Measurements taken
        TargetCount = $TargetCount ; ParentCount = $ParentCount ; ChildCount = $ChildCount ; FqdnCount = $FqdnCount ;
        AclCount = $AclCount ; AceCount = $AceCount ; IdCount = $IdCount ; PrincipalCount = $PrincipalCount ; ItemCount = $ItemCount

    }
    $ExpandKeyMap = $LogMap['ExpandKeyMap']
    $ExpandKeyMap['StopWatch'] = '$StopWatch'
    Write-LogMsg -Text 'Out-PermissionFile' -Suffix " # for $IdCount Access Control Entries" -Expand $Cmd, $Cache -ExpandKeyMap $ExpandKeyMap @Log
    $ReportFile = Out-PermissionFile @Cmd @Cache

    $ProgressUpdate = @{
        CurrentOperation = 'Open the HTML report file (if the -Interactive switch was used)'
        PercentComplete  = 70
        Status           = '70 % (step 15 of 20) Invoke-Item'
    }
    Write-Progress @Progress @ProgressUpdate
    if ($Interactive -and $ReportFile) {
        Write-LogMsg -Text "Invoke-Item -Path '$ReportFile'" @Log @LogEmptyMap
        Invoke-Item -Path $ReportFile
    }

    $ProgressUpdate = @{
        CurrentOperation = 'Send the results to a PRTG Custom XML Push sensor for tracking'
        PercentComplete  = 75
        Status           = '75 % (step 16 of 20) Send-PrtgXmlSensorOutput'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        XmlOutput    = $XMLOutput
        PrtgProbe    = $PrtgProbe
        PrtgProtocol = $PrtgProtocol
        PrtgPort     = $PrtgPort
        PrtgToken    = $PrtgToken
    }
    Write-LogMsg -Text 'Send-PrtgXmlSensorOutput' -Expand $Cmd @Log @LogEmptyMap
    Send-PrtgXmlSensorOutput @Cmd

    $ProgressUpdate = @{
        CurrentOperation = 'Output the result to the pipeline'
        PercentComplete  = 80
        Status           = '80 % (step 17 of 20) Out-Permission'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        FormattedPermission = $FormattedPermissions
        GroupBy             = $GroupBy
        OutputFormat        = $OutputFormat
    }
    Write-LogMsg -Text 'Out-Permission' -Expand $Cmd -ExpandKeyMap @{ FormattedPermission = '$FormattedPermissions' } @Log
    Out-Permission @Cmd

    $ProgressUpdate = @{
        CurrentOperation = 'Cleanup CIM sessions'
        PercentComplete  = 85
        Status           = '85 % (step 18 of 20) Remove-CachedCimSession'
    }
    Write-Progress @Progress @ProgressUpdate
    Write-LogMsg -Text 'Remove-CachedCimSession -CimCache $CimCache' @Log @LogEmptyMap
    Remove-CachedCimSession -CimCache $CimCache

    $ProgressUpdate = @{
        CurrentOperation = 'Export the buffered log messages to a CSV file'
        PercentComplete  = 90
        Status           = '95 % (step 19 of 20) Export-LogCsv'
    }
    Write-Progress @Progress @ProgressUpdate
    $Cmd = @{
        Buffer       = $LogBuffer
        LogFile      = $LogFile
        ThisHostname = $ThisHostname
        WhoAmI       = $WhoAmI
    }
    Write-LogMsg -Text 'Export-LogCsv' -Expand $Cmd -ExpandKeyMap @{ Buffer = '[ref]$LogBuffer' } @Log
    Export-LogCsv @Cmd

    Stop-Transcript  *>$null
    Write-Progress @Progress -Completed

}

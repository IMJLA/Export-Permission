<#PSScriptInfo

.VERSION 0.0.262

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
new psdfs version

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
    [System.String] XML output formatted for a Custom XML Sensor in Paessler PRTG Network Monitor
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

    Generate reports on the NTFS permissions for ? Invalid/fail param validation?
.EXAMPLE
    Export-Permission.ps1 -TargetPath '\\computer.ad.contoso.com\'

    This is an edge case that is not currently supported

    The target path is the root of a server

    Generate reports on the NTFS permissions for ? Invalid/fail param validation?
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

param (

    <#
    Path to the NTFS folder whose permissions to export

    Currently supports NTFS folders
    TODO: support same targets as Get-Acl (AD, Registry, StorageSubSystem)
    #>
    #
    [Parameter(ValueFromPipeline)]
    [ValidateScript({ Test-Path $_ })]
    [System.IO.DirectoryInfo[]]$TargetPath,

    # Regular expressions matching names of security principals to exclude from the HTML report
    [string[]]$ExcludeAccount = 'SYSTEM',

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
    Valid group names that are allowed to appear in ACEs

    Specify as a ScriptBlock meant for the FilterScript parameter of Where-Object

    By default, this is a ScriptBlock that always evaluates to $true so it doesn't evaluate any naming convention compliance

    In the ScriptBlock, use string comparisons on the Name property

    e.g. {$_.Name -like 'CONTOSO\Group1*' -or $_.Name -eq 'CONTOSO\Group23'}

    The naming format that will be used for the groups is CONTOSO\Group1

      where CONTOSO is the NetBIOS name of the domain, and Group1 is the samAccountName of the group
    #>
    [scriptblock]$GroupNameRule = { $true },

    # Number of asynchronous threads to use
    [uint16]$ThreadCount = (Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum,

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
        none    generate 1 file with all permissions
        target  generate 1 file per target
        item    generate 1 file per item
        account generate 1 file per account
        all     generate 1 file per target and 1 file per item and 1 file per account and 1 file with all permissions.
    #>
    [ValidateSet('none', 'all', 'target', 'item', 'account')]
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

    if ($NoProgress) {
        $ProgressPreference = 'Ignore'
    }

    # Create a splat of the constant Write-Progress parameters for script readability
    $Progress = @{
        Activity = 'Export-Permission'
        Id       = 0
    }

    Write-Progress -Status '0% (step 1 of 20)' -CurrentOperation 'Initializing' -PercentComplete 0 @Progress

    #----------------[ Functions ]------------------

    # This is where the function definitions will be inserted in the portable version of this script

    #----------------[ Logging ]----------------

    # Start a timer to measure progress and performance
    $StopWatch = [System.Diagnostics.Stopwatch]::new()
    $null = $StopWatch.Start()

    # Generate a unique ID for this run of the script
    $ReportInstanceId = [guid]::NewGuid().ToString()

    # Create a folder to store logs
    $OutputDir = New-DatedSubfolder -Root $OutputDir -Suffix "_$ReportInstanceId"

    <# Start the PowerShell transcript
       PowerShell cannot redirect the Success stream of Start-Transcript to the Information stream
       But it can redirect it to $null, and then send the Transcript file path to Write-Information
    #>
    $TranscriptFile = "$OutputDir\PowerShellTranscript.log"
    Start-Transcript $TranscriptFile *>$null
    Write-Information $TranscriptFile

    #----------------[ Declarations ]----------------

    $LogFile = "$OutputDir\Export-Permission.log"
    $DirectoryEntryCache = [hashtable]::Synchronized(@{})
    $DomainsBySID = [hashtable]::Synchronized(@{})
    $DomainsByNetbios = [hashtable]::Synchronized(@{})
    $DomainsByFqdn = [hashtable]::Synchronized(@{})
    $LogCache = [hashtable]::Synchronized(@{})
    $CimCache = [hashtable]::Synchronized(@{})
    $AclByPath = [hashtable]::Synchronized(@{}) # Initialize a cache of access control lists keyed by their paths
    $AceByGUID = [hashtable]::Synchronized(@{}) # Initialize a cache of access control entries keyed by GUID generated in Resolve-ACE
    $AceGuidByID = [hashtable]::Synchronized(@{}) # Initialize a cache of access control entry GUIDs keyed by their resolved identities
    $AceGuidByPath = [hashtable]::Synchronized(@{}) # Initialize a cache of access control entry GUIDs keyed by their paths
    $PrincipalByID = [hashtable]::Synchronized(@{}) # Initialize a cache of ADSI security principals keyed by their resolved NTAccount caption
    $UniquePrincipals = [hashtable]::Synchronized(@{})
    $UniquePrincipalsByResolvedID = [hashtable]::Synchronized(@{})
    $Parents = [hashtable]::Synchronized(@{})

    # Get the hostname of the computer running the script
    $ThisHostname = HOSTNAME.EXE

    # Get the NTAccount caption of the user running the script, with the correct capitalization
    $WhoAmI = Get-CurrentWhoAmI -LogMsgCache $LogCache -ThisHostName $ThisHostname

    # Create a splat of the ThreadCount parameter to pass to various functions for script readability
    $Threads = @{
        ThreadCount = $ThreadCount
    }

    # Create a splat of log-related parameters to pass to various functions for script readability
    $LogThis = @{
        ThisHostname = $ThisHostname
        LogMsgCache  = $LogCache
        WhoAmI       = $WhoAmI
    }

    # Create a splat of constant Write-LogMsg parameters for script readability
    $Log = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogCache
        WhoAmI       = $WhoAmI
    }

    # These events already happened but we will log them now that we have the correct capitalization of the user
    Write-LogMsg @Log -Text '$LogCache = [hashtable]::Synchronized(@{}) # This command was already run but is now being logged'
    Write-LogMsg @Log -Text '$ThisHostname = HOSTNAME.EXE # This command was already run but is now being logged'
    Write-LogMsg @Log -Text "`$WhoAmI = Get-CurrentWhoAmI -LogMsgCache `$LogCache -ThisHostName $ThisHostname # This command was already run but is now being logged"

    # Get the FQDN of the computer running the script
    Write-LogMsg @Log -Text "`$ThisFqdn = ConvertTo-DnsFqdn -ComputerName '$ThisHostName'"
    $ThisFqdn = ConvertTo-DnsFqdn -ComputerName $ThisHostName @LogThis

    # Create a splat of caching-related parameters to pass to various functions for script readability
    $CacheParams = @{
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByFqdn       = $DomainsByFqdn
        DomainsByNetbios    = $DomainsByNetbios
        DomainsBySid        = $DomainsBySid
        ThisFqdn            = $ThisFqdn
        ThreadCount         = $ThreadCount
    }

    Write-LogMsg @Log -Text '$TrustedDomains = Get-TrustedDomain'
    $TrustedDomains = Get-TrustedDomain @LogThis

    # Add a key to the splat of log-related parameters where the value is the parent progress bar ID to pass to various functions for progress bar nesting
    $LogThis['ProgressParentId'] = 0

    $FqdnParams = @{
        Known    = $TrustedDomains.DomainFqdn
        ThisFqdn = $ThisFqdn
    }

}

process {

    #----------------[ Main Execution ]---------------

    Write-Progress -Status '5% (step 2 of 20) Resolve-PermissionTarget' -CurrentOperation 'Resolve target paths to network paths such as UNC paths (including all DFS folder targets)' -PercentComplete 5 @Progress
    Write-LogMsg @Log -Text "Resolve-PermissionTarget -TargetPath @('$($TargetPath -join "',")') -Output `$Parents -CimCache `$CimCache @LogThis"
    Resolve-PermissionTarget -TargetPath $TargetPath -Output $Parents -CimCache $CimCache @LogThis

}

end {

    Write-Progress -Status '10% (step 3 of 20) Expand-PermissionTarget' -CurrentOperation 'Expand parent paths into the paths of their children' -PercentComplete 10 @Progress
    Write-LogMsg @Log -Text "Expand-PermissionTarget -TargetPath @('$($Parents.Values -join "',")') -RecurseDepth $RecurseDepth @Threads @LogThis"
    $Items = Expand-PermissionTarget -TargetPath $Parents -RecurseDepth $RecurseDepth @Threads @LogThis

    Write-Progress -Status '15% (step 4 of 20) Get-AccessControlList' -CurrentOperation 'Get the ACL of each path' -PercentComplete 15 @Progress
    Write-LogMsg @Log -Text "`$Permissions = Get-AccessControlList -TargetPath `$Items -AclByPath `$AclByPath @Threads @LogThis"
    Get-AccessControlList -TargetPath $Items -Output $AclByPath @Threads @LogThis

    Write-Progress -Status '20% (step 5 of 20) Find-ServerFqdn' -CurrentOperation 'Get the FQDN of this computer, each trusted domain, and each server in the paths' -PercentComplete 20 @Progress
    Write-LogMsg @Log -Text "`$ServerFqdns = Find-ServerFqdn -Known @('$($FqdnParams['Known'] -join "',")') -ThisFqdn '$ThisFqdn' -TargetPath `$Items @FqdnParams @LogThis"
    $ServerFqdns = Find-ServerFqdn -TargetPath $Items @FqdnParams @LogThis

    Write-Progress -Status '25% (step 6 of 20) Initialize-Cache' -CurrentOperation 'Query each FQDN to pre-populate caches, avoiding redundant ADSI and CIM queries' -PercentComplete 25 @Progress
    Write-LogMsg @Log -Text "Initialize-Cache -ServerFqdns @('$($ServerFqdns -join "',")') @CacheParams @LogThis"
    Initialize-Cache -Fqdn $ServerFqdns -CimCache $CimCache @CacheParams @LogThis

    # The resolved name will include the domain name (or local computer name for local accounts)
    Write-Progress -Status '30% (step 7 of 20) Resolve-AccessControlList' -CurrentOperation 'Resolve each identity reference to its SID and NTAccount name' -PercentComplete 30 @Progress
    Write-LogMsg @Log -Text 'Resolve-AccessControlList -Permission $Permissions -ACEsByResolvedID $ACEsByResolvedID -ACLsByPath $AclByPath -ACEsByGUID $AceByGUID -AceGUIDsByPath $AceGuidByPath -AceGUIDsByResolvedID $AceGuidByID -CimCache $CimCache -InheritanceFlagResolved $InheritanceFlagResolved @CacheParams @LogThis'
    Resolve-AccessControlList -ACLsByPath $AclByPath -ACEsByGUID $AceByGUID -AceGUIDsByPath $AceGuidByPath -AceGUIDsByResolvedID $AceGuidByID -CimCache $CimCache -InheritanceFlagResolved $InheritanceFlagResolved @CacheParams @LogThis

    Write-Progress -Status '35% (step 8 of 20) Get-CurrentDomain' -CurrentOperation 'Get the current domain' -PercentComplete 35 @Progress
    Write-LogMsg @Log -Text "Get-CurrentDomain"
    $CurrentDomain = Get-CurrentDomain

    Write-Progress -Status '40% (step 9 of 20) Get-PermissionPrincipal' -CurrentOperation 'Use ADSI to get details about each resolved identity reference' -PercentComplete 40 @Progress
    Write-LogMsg @Log -Text "Get-PermissionPrincipal -ACEsByResolvedID `$ACEsByResolvedID -PrincipalsByResolvedID `$PrincipalByID -NoGroupMembers:`$$NoMembers -CurrentDomain $CurrentDomain -CimCache `$CimCache @CacheParams @LogThis"
    Get-PermissionPrincipal -ACEsByResolvedID $AceGuidByID -PrincipalsByResolvedID $PrincipalByID -NoGroupMembers:$NoMembers -CurrentDomain $CurrentDomain -CimCache $CimCache @CacheParams @LogThis

    ####Write-Progress -Status '45% (step 10 of 20) Select-UniqueAccountPermission' -CurrentOperation 'Hide domain names we do not want on the report' -PercentComplete 45 @Progress
    ####Write-LogMsg @Log -Text "`$UniqueAccountPermissions = Select-UniqueAccountPermission -AccountPermission `$Accounts -IgnoreDomain @('$($IgnoreDomain -join "',")')"
    ####Select-UniquePrincipal -IgnoreDomain $IgnoreDomain -ExcludeAccount $ExcludeAccount -PrincipalsByResolvedID $PrincipalByID -UniquePrincipal $UniquePrincipals -UniquePrincipalsByResolvedID $UniquePrincipalsByResolvedID

    Write-Progress -Status '55% (step 12 of 20) Expand-Permission' -CurrentOperation 'Join access rules with their associated accounts' -PercentComplete 55 @Progress
    Write-LogMsg @Log -Text "`$Permissions = Expand-Permission -SplitBy $SplitBy -GroupBy $GroupBy -AceGuidByPath $AceGuidByPath -AceGUIDsByResolvedID $AceGuidByID -ACEsByGUID $AceByGUID -PrincipalsByResolvedID $PrincipalByID -ACLsByPath $AclByPath @LogThis"
    $Permissions = Expand-Permission -TargetPath $Parents -Children $Items -SplitBy $SplitBy -GroupBy $GroupBy -AceGuidByPath $AceGuidByPath -AceGUIDsByResolvedID $AceGuidByID -ACEsByGUID $AceByGUID -PrincipalsByResolvedID $PrincipalByID -ACLsByPath $AclByPath @LogThis

    Write-Progress -Status '65% (step 14 of 20) Format-Permission' -CurrentOperation 'Format the permissions' -PercentComplete 65 @Progress
    Write-LogMsg @Log -Text "`$FormattedPermissions = Format-Permission -Permission `$Permissions -FileFormat `$FileFormat -OutputFormat `$OutputFormat"
    $FormattedPermissions = Format-Permission -Permission $Permissions -FileFormat $FileFormat -OutputFormat $OutputFormat -GroupBy $GroupBy

    Write-Progress -Status '70 % (step 15 of 20) Out-PermissionReport' -CurrentOperation 'Export the HTML report' -PercentComplete 70 @Progress
    Write-LogMsg @Log -Text 'Out-PermissionReport @ExportFolderPermissionHtml'
    $OutPermissionReport = @{

        # Objects as they progressed through the data pipeline
        TargetPath = $TargetPath ; Parent = $Parents ; ACLsByPath = $AclByPath ; ACEsByGUID = $AceByGUID ; PrincipalsByResolvedID = $PrincipalByID ;
        Permission = $Permissions ; FormattedPermission = $FormattedPermissions ; BestPracticeIssue = $BestPracticeIssues ;

        # Parameters
        Detail = $Detail ; ExcludeAccount = $ExcludeAccount ; ExcludeClass = $ExcludeClass ; IgnoreDomain = $IgnoreDomain ; NoMembers = $NoMembers ;
        RecurseDepth = $RecurseDepth ; Title = $Title ; FileFormat = $FileFormat ; OutputFormat = $OutputFormat ; GroupBy = $GroupBy ; OutputDir = $OutputDir ;

        # Cached variables in memory
        LogFileList = $TranscriptFile, $LogFile ; LogParams = $Log ; StopWatch = $StopWatch
        ReportInstanceId = $ReportInstanceId ; WhoAmI = $WhoAmI ; ThisFqdn = $ThisFqdn

    }
    $ReportFile = Out-PermissionReport @OutPermissionReport
    Write-Progress @Progress -Completed



















    <#
    # Send the XML to a PRTG Custom XML Push sensor for tracking
    $PrtgParams = @{
        XmlOutput    = $XMLOutput
        PrtgProbe    = $PrtgProbe
        PrtgProtocol = $PrtgProtocol
        PrtgPort     = $PrtgPort
        PrtgToken    = $PrtgToken
    }
    Write-LogMsg @Log -Text "Send-PrtgXmlSensorOutput @PrtgParams"
    Send-PrtgXmlSensorOutput @PrtgParams
    #>

    # Open the HTML report file (useful only interactively)
    if ($Interactive) {
        Write-LogMsg @Log -Text "Invoke-Item '$ReportFile'"
        Invoke-Item $ReportFile
    }

    # Output the full path of the log file to the Information stream
    Write-Information $LogFile

    # Save the log file to disk
    $LogCache.Values | Sort-Object -Property Timestamp |
    Export-Csv -Delimiter "`t" -NoTypeInformation -LiteralPath $LogFile

    # Remove any CIM Sessions
    Remove-CachedCimSession -CimCache $CimCache

    Stop-Transcript  *>$null

    Write-Progress @Progress -Completed

    switch ($OutputFormat) {
        'PassThru' {
            $TypeData = @{
                TypeName                  = 'Permission.PassThruPermission'
                DefaultDisplayPropertySet = 'Folder', 'Account', 'Access'
                ErrorAction               = 'SilentlyContinue'
            }
            Update-TypeData @TypeData
            return $FolderPermissions
        }
        'GroupByFolder' {
            Update-TypeData -MemberName Folder -Value { $This.Name } -TypeName 'Permission.FolderPermission' -MemberType ScriptProperty -ErrorAction SilentlyContinue
            Update-TypeData -MemberName Access -TypeName 'Permission.FolderPermission' -MemberType ScriptProperty -ErrorAction SilentlyContinue -Value {
                $Access = ForEach ($Permission in $This.Access) {
                    [pscustomobject]@{
                        Account = $Permission.Account
                        Access  = $Permission.Access
                    }
                }
                $Access
            }
            Update-TypeData -DefaultDisplayPropertySet ('Path', 'Access') -TypeName 'Permission.FolderPermission' -ErrorAction SilentlyContinue
            return $GroupedPermissions
        }
        'PrtgXml' {
            # Output the XML so the script can be directly used as a PRTG sensor
            # Caution: This use may be a problem for a PRTG probe because of how long the script can run on large folders/domains
            # Recommendation: Specify the appropriate parameters to run this as a PRTG push sensor instead
            return $XMLOutput
        }
        'GroupByAccount' {
            Update-TypeData -MemberName Account -Value { $This.Name } -TypeName 'Permission.AccountPermission' -MemberType ScriptProperty -ErrorAction SilentlyContinue
            Update-TypeData -MemberName Access -TypeName 'Permission.AccountPermission' -MemberType ScriptProperty -ErrorAction SilentlyContinue -Value {
                $Access = ForEach ($Permission in $This.Group) {
                    [pscustomobject]@{
                        Folder = $Permission.Folder
                        Access = $Permission.Access
                    }
                }
                $Access
            }
            Update-TypeData -DefaultDisplayPropertySet ('Account', 'Access') -TypeName 'Permission.AccountPermission' -ErrorAction SilentlyContinue

            #Group-Permission -InputObject $FolderPermissions -Property Account |
            #Sort-Object -Property Name
            return
        }
        Default { return }
    }

}

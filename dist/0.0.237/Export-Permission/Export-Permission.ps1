<#PSScriptInfo

.VERSION 0.0.237

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
bugfix fake directory entry noteproperties getting dropped with get-member

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

    # Path to the NTFS folder whose permissions to export
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

    # Generate a report with only HTML and CSS but no JavaScript
    [switch]$NoJavaScript,

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
    Type of output returned to the output stream
    #>
    [ValidateSet('PassThru', 'GroupByAccount', 'GroupByFolder', 'PrtgXml', 'Silent')]
    [string]$OutputMode = 'PassThru',

    [ValidateSet('none', 'all', 'item', 'account')] # none will generate a single file.  item will generate a file per item.  account will generate a file per account.  all will generate 1 file per item and 1 file per account.
    [string[]]$SplitBy = 'item', # optionally split files by... temporarily all during dev, later change to none

    [ValidateSet('none', 'item', 'account')]
    [string]$GroupBy = 'item',

    [ValidateSet('none', 'all', 'csv', 'xml', 'json', 'html', 'prtgxml')]
    [string[]]$Format = 'all', # temporarily all  during dev, later change to html

    # 0 is all, -1 is highest, otherwise 1,2,3,etc. for each available level.  Temporarily 0 during dev.,
    [int]$DetailLevel = 0,

    # String translations indexed by value in the [System.Security.AccessControl.InheritanceFlags] enum
    # Parameter default value is on a single line as a workaround to a PlatyPS bug
    # TODO: Move to i18n
    [string[]]$InheritanceFlagResolved = @('this folder but not subfolders', 'this folder and subfolders', 'this folder and files, but not subfolders', 'this folder, subfolders, and files')

)

begin {

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

    $CsvFilePath1 = "$OutputDir\1-AccessControlList.csv"
    $CsvFilePath2 = "$OutputDir\2-AccessControlListWithResolvedIdentityReferences.csv"
    $CsvFilePath3 = "$OutputDir\3-AccessControlListWithADSISecurityPrincipals.csv"
    $XmlFile = "$OutputDir\4-PrtgResult.xml"
    $ReportFile = "$OutputDir\PermissionsReport.htm"
    $LogFile = "$OutputDir\Export-Permission.log"
    $DirectoryEntryCache = [hashtable]::Synchronized(@{})
    $DomainsBySID = [hashtable]::Synchronized(@{})
    $DomainsByNetbios = [hashtable]::Synchronized(@{})
    $DomainsByFqdn = [hashtable]::Synchronized(@{})
    $LogCache = [hashtable]::Synchronized(@{})
    $CimCache = [hashtable]::Synchronized(@{})
    $ACLsByPath = [hashtable]::Synchronized(@{})
    $ACEsByGUID = [hashtable]::Synchronized(@{}) # Initialize a cache of access control entries keyed by GUID generated in Resolve-ACE
    $AceGUIDsByResolvedID = [hashtable]::Synchronized(@{}) # Initialize a cache of access control entry GUIDs keyed by their resolved identities
    $AceGUIDsByPath = [hashtable]::Synchronized(@{}) # Initialize a cache of access control entry GUIDs keyed by their paths
    $PrincipalsByResolvedID = [hashtable]::Synchronized(@{}) # Initialize a cache of ADSI security principals keyed by their resolved NTAccount caption
    $UniquePrincipals = [hashtable]::Synchronized(@{})
    $UniquePrincipalsByResolvedID = [hashtable]::Synchronized(@{})

    # Get the hostname of the computer running the script
    $ThisHostname = HOSTNAME.EXE

    # Get the NTAccount caption of the user running the script, with the correct capitalization
    $WhoAmI = Get-CurrentWhoAmI -LogMsgCache $LogCache -ThisHostName $ThisHostname

    # Create a splat of the parent progress bar ID to pass to various functions for script readability
    $ProgressParent = @{
        ProgressParentId = 0
    }

    # Create a splat of the ThreadCount parameter to pass to various functions for script readability
    $Threads = @{
        ThreadCount = $ThreadCount
    }

    # Create a splat of log-related parameters to pass to various functions for script readability
    $LoggingParams = @{
        ThisHostname = $ThisHostname
        LogMsgCache  = $LogCache
        WhoAmI       = $WhoAmI
    }

    # Create a splat of constant Write-LogMsg parameters for script readability
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogCache
        WhoAmI       = $WhoAmI
    }

    # These events already happened but we will log them now that we have the correct capitalization of the user
    Write-LogMsg @LogParams -Text '$ACLsByPath = [hashtable]::Synchronized(@{})'
    Write-LogMsg @LogParams -Text 'HOSTNAME.EXE # This command was already run but is now being logged'
    Write-LogMsg @LogParams -Text 'Get-CurrentWhoAmI # This command was already run but is now being logged'

    # Get the FQDN of the computer running the script
    Write-LogMsg @LogParams -Text "ConvertTo-DnsFqdn -ComputerName '$ThisHostName'"
    $ThisFqdn = ConvertTo-DnsFqdn -ComputerName $ThisHostName @LoggingParams

    # Create a splat of caching-related parameters to pass to various functions for script readability
    $CacheParams = @{
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByFqdn       = $DomainsByFqdn
        DomainsByNetbios    = $DomainsByNetbios
        DomainsBySid        = $DomainsBySid
        ThisFqdn            = $ThisFqdn
        ThreadCount         = $ThreadCount
    }

    Write-LogMsg @LogParams -Text "Get-ReportDescription -RecurseDepth $RecurseDepth"
    $ReportDescription = Get-ReportDescription -RecurseDepth $RecurseDepth

    Write-LogMsg @LogParams -Text "Get-FolderTableHeader -RecurseDepth $RecurseDepth"
    $FolderTableHeader = Get-FolderTableHeader -RecurseDepth $RecurseDepth

    Write-LogMsg @LogParams -Text "Get-TrustedDomain"
    $TrustedDomains = Get-TrustedDomain @LoggingParams

}

process {

    #----------------[ Main Execution ]---------------

    Write-Progress -Status '5% (step 2 of 20) Resolve-PermissionTarget' -CurrentOperation 'Resolve target paths to UNC paths (including all DFS folder targets)' -PercentComplete 5 @Progress
    Write-LogMsg @LogParams -Text "Resolve-PermissionTarget -TargetPath @('$($TargetPath -join "',")') -ACLsByPath `$ACLsByPath"
    Resolve-PermissionTarget -TargetPath $TargetPath -ACLsByPath $ACLsByPath -CimCache $CimCache @LoggingParams

}

end {

    Write-Progress -Status '10% (step 3 of 20) Expand-PermissionTarget' -CurrentOperation 'Expand UNC paths into the paths of their subfolders' -PercentComplete 10 @Progress
    Write-LogMsg @LogParams -Text "Expand-PermissionTarget -ACLsByPath `$ACLsByPath -RecurseDepth $RecurseDepth"
    $Children = Expand-PermissionTarget -ACLsByPath $ACLsByPath -RecurseDepth $RecurseDepth @Threads @ProgressParent @LoggingParams

    Write-Progress -Status '15% (step 4 of 20) Get-FolderAccessList' -CurrentOperation 'Get the ACL of each path' -PercentComplete 15 @Progress
    # Convert ACLsByPath.Keys to a new array of strings so that when it is modified by adding subfolder ACLs it doesn't cause an error while Get-FolderAccessList is still enumerating it
    # TODO: Implement ConcurrentDictionary which should implement auto-locking and make enumeration thread-safe
    $Parents = [string[]]$ACLsByPath.Keys
    Write-LogMsg @LogParams -Text "`$Permissions = Get-FolderAcl -Folder @('$($Parents -join "','")') -Subfolder @('$($Children -join "','")') -ACLsByPath `$ACLsByPath @Threads @ProgressParent @LoggingParams"
    Get-FolderAcl -Folder $Parents -Subfolder $Children -ACLsByPath $ACLsByPath @Threads @ProgressParent @LoggingParams

    #Write-Progress -Status '20% (step 5 of 20) Export-RawPermissionCsv' -CurrentOperation 'Save a CSV report of the raw permissions' -PercentComplete 20 @Progress
    #Write-LogMsg @LogParams -Text "Export-RawPermissionCsv -Permission `$Permissions -LiteralPath '$CsvFilePath1'"
    #Export-RawPermissionCsv -Permission $Permissions -LiteralPath $CsvFilePath1 @ProgressParent @LoggingParams

    Write-Progress -Status '25% (step 6 of 20) Get-UniqueServerFqdn' -CurrentOperation 'Get the FQDN of the current computer, each trusted domain, and each server in the paths' -PercentComplete 25 @Progress
    $FqdnParams = @{
        Known    = $TrustedDomains.DomainFqdn
        FilePath = $Parents
        ThisFqdn = $ThisFqdn
    }
    Write-LogMsg @LogParams -Text "`$ServerFqdns = Get-UniqueServerFqdn -Known @('$($FqdnParams['Known'] -join "',")') -FilePath @('$($Parents -join "',")') -ThisFqdn '$ThisFqdn'"
    $ServerFqdns = Get-UniqueServerFqdn @FqdnParams @LoggingParams @ProgressParent

    Write-Progress -Status '30% (step 7 of 20) Initialize-Cache' -CurrentOperation 'Query each FQDN to pre-populate caches, avoiding redundant ADSI and CIM queries' -PercentComplete 30 @Progress
    Write-LogMsg @LogParams -Text "Initialize-Cache -ServerFqdns @('$($ServerFqdns -join "',")')"
    Initialize-Cache -Fqdn $ServerFqdns -CimCache $CimCache @ProgressParent @LoggingParams @CacheParams

    # The resolved name will include the domain name (or local computer name for local accounts)
    Write-Progress -Status '35% (step 8 of 20) Resolve-AccessControlList' -CurrentOperation 'Resolve each identity reference to its SID and NTAccount name' -PercentComplete 35 @Progress
    Write-LogMsg @LogParams -Text 'Resolve-AccessControlList -Permission $Permissions -ACEsByResolvedID $ACEsByResolvedID -ACLsByPath $ACLsByPath -ACEsByGUID $ACEsByGUID -AceGUIDsByPath $AceGUIDsByPath -AceGUIDsByResolvedID $AceGUIDsByResolvedID -CimCache $CimCache -InheritanceFlagResolved $InheritanceFlagResolved @LoggingParams @CacheParams @ProgressParent'
    Resolve-AccessControlList -ACLsByPath $ACLsByPath -ACEsByGUID $ACEsByGUID -AceGUIDsByPath $AceGUIDsByPath -AceGUIDsByResolvedID $AceGUIDsByResolvedID -CimCache $CimCache -InheritanceFlagResolved $InheritanceFlagResolved @LoggingParams @CacheParams @ProgressParent

    #Write-Progress -Status '40% (step 9 of 20) Export-ResolvedPermissionCsv' -CurrentOperation 'Save a CSV report of the resolved identity references' -PercentComplete 40 @Progress
    #Write-LogMsg @LogParams -Text "Export-ResolvedPermissionCsv -Permission `$Permissions -LiteralPath '$CsvFilePath2'"
    #Export-ResolvedPermissionCsv @LoggingParams -Permission $PermissionsWithResolvedIdentities -LiteralPath $CsvFilePath2 @ProgressParent

    Write-Progress -Status '45% (step 10 of 20) Get-CurrentDomain' -CurrentOperation 'Get the current domain' -PercentComplete 45 @Progress
    Write-LogMsg @LogParams -Text "Get-CurrentDomain"
    $CurrentDomain = Get-CurrentDomain

    Write-Progress -Status '50% (step 11 of 20) Get-PermissionPrincipal' -CurrentOperation 'Use ADSI to get details about each resolved identity reference' -PercentComplete 50 @Progress
    Write-LogMsg @LogParams -Text "Get-PermissionPrincipal -ACEsByResolvedID `$ACEsByResolvedID -PrincipalsByResolvedID `$PrincipalsByResolvedID -NoGroupMembers:`$$NoMembers"
    Get-PermissionPrincipal -ACEsByResolvedID $AceGUIDsByResolvedID -PrincipalsByResolvedID $PrincipalsByResolvedID -NoGroupMembers:$NoMembers -CurrentDomain $CurrentDomain -CimCache $CimCache @LoggingParams @CacheParams @ProgressParent

    ###Write-Progress -Status '55% (step 12 of 20) Format-PermissionAccount' -CurrentOperation 'Expand the ADSI security principals into their group members' -PercentComplete 55 @Progress
    ###Write-LogMsg @LogParams -Text "`$FormattedSecurityPrincipals = Expand-PermissionPrincipal -SecurityPrincipal `$SecurityPrincipals @Threads"
    ###$FormattedSecurityPrincipals = Expand-PermissionPrincipal -PrincipalsByResolvedID $PrincipalsByResolvedID @Threads @LoggingParams @ProgressParent

    ###Write-Progress -Status '60% (step 13 of 20) Expand-AcctPermission' -CurrentOperation 'Expand the security principals back into their permissions (one per ACE per principal)' -PercentComplete 60 @Progress
    ###Write-LogMsg @LogParams -Text "`$ExpandedAccountPermissions = Expand-AcctPermission -SecurityPrincipal `$FormattedSecurityPrincipals @Threads"
    ###$ExpandedAccountPermissions = Expand-AcctPermission -SecurityPrincipal $FormattedSecurityPrincipals @Threads @LoggingParams @ProgressParent

    #ToDo: Expand DirectoryEntry objects in the DirectoryEntry and Members properties
    #Write-Progress -Status '65% (step 14 of 20) Export-Csv' -CurrentOperation 'Save a CSV report of the expanded account permissions' -PercentComplete 65 @Progress
    #Write-LogMsg @LogParams -Text "`$ExpandedAccountPermissions | Export-Csv -NoTypeInformation -LiteralPath '$CsvFilePath3'"
    #$ExpandedAccountPermissions | Export-Csv -NoTypeInformation -LiteralPath $CsvFilePath3
    #Write-Information $CsvFilePath3

    ###Write-Progress -Status '70% (step 15 of 20) Group-Object' -CurrentOperation 'Group the permissions by account for domain name hiding' -PercentComplete 70 @Progress
    ###Write-LogMsg @LogParams -Text "`$Accounts = `$ExpandedAccountPermissions | Group-Object -Property User"
    ###$Accounts = $ExpandedAccountPermissions | Group-Object -Property user

    ####Write-Progress -Status '75% (step 16 of 20) Select-UniqueAccountPermission' -CurrentOperation 'Hide domain names we do not want on the report' -PercentComplete 75 @Progress
    ####Write-LogMsg @LogParams -Text "`$UniqueAccountPermissions = Select-UniqueAccountPermission -AccountPermission `$Accounts -IgnoreDomain @('$($IgnoreDomain -join "',")')"
    ####Select-UniquePrincipal -IgnoreDomain $IgnoreDomain -ExcludeAccount $ExcludeAccount -PrincipalsByResolvedID $PrincipalsByResolvedID -UniquePrincipal $UniquePrincipals -UniquePrincipalsByResolvedID $UniquePrincipalsByResolvedID

    $HowToSplit = foreach ($Split in $SplitBy) {
        if ($Split -eq 'none') {
            $Split
            break
        } elseif ($Split -eq 'all') {
            @('item', 'account')
            break
        } else {
            $Split
        }
    }

    ForEach ($Split in $HowToSplit) {
        switch ($Split) {
            'account' {
                # Group reference GUIDs by the name of their associated account.
                $AccountPermissionReferences = ForEach ($ID in $PrincipalsByResolvedID.Keys) {
                    #Format-SecurityPrincipal -ResolvedID $ID -PrincipalsByResolvedID $PrincipalsByResolvedID -AceGUIDsByResolvedID $AceGUIDsByResolvedID -ACEsByGUID $ACEsByGUID
                    $ACEGuidsForThisID = $AceGUIDsByResolvedID[$ID]

                    $ItemPaths = @{}
                    ForEach ($Guid in $ACEGuidsForThisID) {

                        $Ace = $ACEsByGUID[$Guid]

                        $CacheResult = $ItemPaths[$Ace.Path]
                        if (-not $CacheResult) {
                            $CacheResult = [System.Collections.Generic.List[guid]]::new()
                        }
                        $null = $CacheResult.Add($Guid)
                        $ItemPaths[$Ace.Path] = $CacheResult

                    }

                    $ItemPermissionsForThisAccount = ForEach ($Item in $ItemPaths.Keys) {

                        [PSCustomObject]@{
                            Path     = $Item
                            AceGUIDs = $ItemPaths[$Item]
                        }

                    }

                    [PSCustomObject]@{
                        Account = $ID
                        Access  = $ItemPermissionsForThisAccount
                    }

                }

                # Expand reference GUIDs into their associated Access Control Entries and Security Principals.
                $AccountPermissions = ForEach ($Acct in $AccountPermissionReferences) {
                    $Access = ForEach ($PermissionRef in $Acct.Access) {
                        [PSCustomObject]@{
                            Path   = $PermissionRef.Path
                            Access = $ACEsByGUID[$PermissionRef.AceGUIDs]
                        }
                    }
                    [PSCustomObject]@{
                        Account = $PrincipalsByResolvedID[$Acct.Account]
                        Access  = $Access
                    }
                }
            }
            'item' {

                [string[]]$SortedPaths = $AceGUIDsByPath.Keys | Sort-Object
                $ShortestPath = $SortedPaths[0]

                # Group reference GUIDs by the path to their associated item.
                $ItemPermissionReferences = ForEach ($ItemPath in $SortedPaths) {

                    $ACEGuidsForThisItem = $AceGUIDsByPath[$ItemPath]
                    $Acl = $ACLsByPath[$ItemPath]

                    # Find-ResolvedIDsWithItemAccess
                    $IDsWithAccess = @{}
                    ForEach ($Guid in $ACEGuidsForThisItem) {

                        $Ace = $ACEsByGUID[$Guid]

                        $CacheResult = $IDsWithAccess[$Ace.IdentityReferenceResolved]
                        if (-not $CacheResult) {
                            $CacheResult = [System.Collections.Generic.List[guid]]::new()
                        }
                        $null = $CacheResult.Add($Guid)
                        $IDsWithAccess[$Ace.IdentityReferenceResolved] = $CacheResult

                        ForEach ($Member in $PrincipalsByResolvedID[$Ace.IdentityReferenceResolved].Members) {

                            $CacheResult = $IDsWithAccess[$Member]
                            if (-not $CacheResult) {
                                $CacheResult = [System.Collections.Generic.List[guid]]::new()
                            }
                            $null = $CacheResult.Add($Guid)
                            $IDsWithAccess[$Member] = $CacheResult

                        }
                    }

                    $AccountPermissionsForThisItem = ForEach ($ID in ($IDsWithAccess.Keys | Sort-Object)) {

                        [PSCustomObject]@{
                            Account  = $ID
                            AceGUIDs = $IDsWithAccess[$ID]
                        }

                    }

                    [PSCustomObject]@{
                        Item   = $Acl
                        Access = $AccountPermissionsForThisItem
                    }

                }

                # Expand reference GUIDs into their associated Access Control Entries.
                $ItemPermissions = ForEach ($Item in $ItemPermissionReferences) {

                    $Access = ForEach ($PermissionRef in $Item.Access) {

                        [PSCustomObject]@{
                            Account = $PrincipalsByResolvedID[$PermissionRef.Account]
                            Access  = $ACEsByGUID[$PermissionRef.AceGUIDs]
                        }

                    }

                    [PSCustomObject]@{
                        Item   = $Item.Item
                        Access = $Access
                    }

                }

            }
            default {

                $ACEsByGUID.Values # 'none'

            }
        }
    }

    ##Write-Progress -Status '80% (step 17 of 20) Format-FolderPermission' -CurrentOperation 'Format, group, and sort the permissions by folder for the report' -PercentComplete 80 @Progress
    ##Write-LogMsg @LogParams -Text "Format-FolderPermission -UserPermission `$UniqueAccountPermissions | Group Folder | Sort Name"
    ##$FolderPermissions = Format-FolderPermission -UserPermission $UniqueAccountPermissions @ProgressParent @LogParams
    ##$GroupedPermissions = Group-Permission -InputObject $FolderPermissions -Property Folder |
    ##Sort-Object -Property Name

    # The first version uses no JavaScript so it can be rendered by e-mail clients
    # The second version is JavaScript-dependent and will not work in e-mail clients
    Write-Progress -Status '85% (step 18 of 20) Export-FolderPermissionHtml' -CurrentOperation 'Export the HTML report' -PercentComplete 85 @Progress
    $ExportFolderPermissionHtml = @{ ItemPermissions = $ItemPermissions ; ExcludeAccount = $ExcludeAccount ; ExcludeClass = $ExcludeClass ; IgnoreDomain = $IgnoreDomain ;
        TargetPath = $TargetPath ; LogParams = $LogParams ; ReportDescription = $ReportDescription ; FolderTableHeader = $FolderTableHeader ; NoGroupMembers = $NoMembers ;
        ReportFileList = $CsvFilePath1, $CsvFilePath2, $CsvFilePath3, $XmlFile; ReportFile = $ReportFile ; LogFileList = $TranscriptFile, $LogFile ; OutputDir = $OutputDir ;
        ReportInstanceId = $ReportInstanceId ; WhoAmI = $WhoAmI ; ThisFqdn = $ThisFqdn ; StopWatch = $StopWatch ;
        Subfolders = $Children ; ResolvedFolderTargets = $ACLsByPath.Keys ; Title = $Title; NoJavaScript = $NoJavaScript; PrincipalsByResolvedID = $PrincipalsByResolvedID; ShortestPath = $ShortestPath
    }
    Write-LogMsg @LogParams -Text 'Export-FolderPermissionHtml @ExportFolderPermissionHtml'
    Export-FolderPermissionHtml @ExportFolderPermissionHtml

    # ToDo: Users with ownership
    $NtfsIssueParams = @{
        FolderPermissions = $GroupedPermissions
        UserPermissions   = $Accounts
        GroupNameRule     = $GroupNameRule
        TodaysHostname    = $ThisHostname
        WhoAmI            = $WhoAmI
        LogMsgCache       = $LogCache
    }
    Write-Progress -Status '90% (step 19 of 20) New-NtfsAclIssueReport' -CurrentOperation 'Identify common issues with permissions' -PercentComplete 90 @Progress
    Write-LogMsg @LogParams -Text 'New-NtfsAclIssueReport @NtfsIssueParams'
    $NtfsIssues = New-NtfsAclIssueReport @NtfsIssueParams

    Write-Progress -Status '95% (step 20 of 20) Output results' -CurrentOperation 'Output results' -PercentComplete 95 @Progress

    # Format the issues as a custom XML sensor for Paessler PRTG Network Monitor
    Write-LogMsg @LogParams -Text "Get-PrtgXmlSensorOutput -NtfsIssues `$NtfsIssues"
    $XMLOutput = Get-PrtgXmlSensorOutput -NtfsIssues $NtfsIssues

    # Output the full path of the XML file (result of the custom XML sensor for Paessler PRTG Network Monitor) to the Information stream
    Write-Information $XmlFile

    # Save the XML file to disk
    $null = Set-Content -LiteralPath $XmlFile -Value $XMLOutput

    # Send the XML to a PRTG Custom XML Push sensor for tracking
    $PrtgParams = @{
        XmlOutput    = $XMLOutput
        PrtgProbe    = $PrtgProbe
        PrtgProtocol = $PrtgProtocol
        PrtgPort     = $PrtgPort
        PrtgToken    = $PrtgToken
    }
    Write-LogMsg @LogParams -Text "Send-PrtgXmlSensorOutput @PrtgParams"
    Send-PrtgXmlSensorOutput @PrtgParams

    # Open the HTML report file (useful only interactively)
    if ($Interactive) {
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
    switch ($OutputMode) {
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

            Group-Permission -InputObject $FolderPermissions -Property Account |
            Sort-Object -Property Name
            return
        }
        Default { return }
    }

}

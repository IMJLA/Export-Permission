<#PSScriptInfo

.VERSION 0.0.157

.GUID fd2d03cf-4d29-4843-bb1c-0fba86b0220a

.AUTHOR Jeremy La Camera

.COMPANYNAME Jeremy La Camera

.COPYRIGHT (c) Jeremy La Camera. All rights reserved.

.TAGS adsi ldap winnt ntfs acl

.LICENSEURI https://github.com/IMJLA/Export-Permission/blob/main/LICENSE

.PROJECTURI https://github.com/IMJLA/Export-Permission

.ICONURI

.EXTERNALMODULEDEPENDENCIES Adsi,SimplePrtg,PsNtfs,PsLogMessage,PsRunspace,PsDfs,PsBootstrapCss,Permission 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
closed issue 27

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
    Benefits:
    - Presents complex nested permissions and group memberships in a report that is easy to read
    - Provides additional information about each account such as Name, Department, Title
    - Multithreaded with caching for fast results
    - Works as a scheduled task
    - Works as a custom sensor script for Paessler PRTG Network Monitor (Push sensor recommended due to execution time)

    Supports these scenarios:
    - local folder paths (resolved to UNC paths using the administrative shares, so the computer name is shown in the reports)
    - UNC folder paths
    - DFS folder paths (resolves them to their UNC folder targets, and reports permissions on each folder target)
    - Active Directory domain trusts, and unresolved SIDs for deleted accounts

    Does not support these scenarios:
    - Mapped network drives (ToDo enhancement; for now use UNC paths)
    - ACL Owners or Groups (ToDo enhancement; for now only the DACL is reported)
    - File permissions (ToDo enhancement; for now only folder permissions are reported)
    - Share permissions (ToDo enhancement; for now only NTFS permissions are reported)

    Behavior:
    - Gets all permissions for the target folder
    - Gets non-inherited permissions for subfolders (if specified)
    - Exports the permissions to a .csv file
    - Uses ADSI to get information about the accounts and groups listed in the permissions
    - Exports information about the accounts and groups to a .csv file
    - Uses ADSI to recursively retrieve group members
        - The entire chain of group memberships is not retrieved (for performance reasons)
        - This means nested group members are retrieved, but nested groups themselves are not
    - Exports information about all accounts with access to a .csv file
    - Exports information about all accounts with access to a report generated as a .html file
    - Outputs an XML-formatted list of common misconfigurations for use in Paessler PRTG Network Monitor as a custom XML sensor
.INPUTS
    [System.IO.DirectoryInfo[]] TargetPath parameter

    Strings can be passed to this parameter and will be re-cast as DirectoryInfo objects.
.OUTPUTS
    [System.String] XML PRTG sensor output
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

    The RegEx escape character is \ so that is why the regular expression needed for the parameter is 'BUILTIN\\Administrator'
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
    Export-Permission.ps1 -TargetPath C:\Test -ExcludeEmptyGroups

    Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

    Exclude empty groups from the HTML report (leaving accounts only)
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
    [System.IO.DirectoryInfo[]]$TargetPath = 'C:\Test',

    # Regular expressions matching names of security principals to exclude from the HTML report
    [string[]]$ExcludeAccount,

    # Exclude empty groups from the HTML report
    [switch]$ExcludeEmptyGroups,

    <#
    Domain(s) to ignore (they will be removed from the username)

    Intended when a user has matching SamAccountNames in multiple domains but you only want them to appear once on the report.

    Can also be used to remove all domains simply for brevity in the report.
    #>
    [string[]]$IgnoreDomain,

    # Path to the folder to save the logs and reports generated by this script
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
    [string]$Title = "Permissions Report",

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

    # Number of asynchronous threads to use
    [uint16]$ThreadCount = 4,

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
    [uint16]$PrtgSensorPort,

    <#
    If all four of the PRTG parameters are specified,

    the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
    #>
    [string]$PrtgSensorToken

)

begin {

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
    $Win32AccountsBySID = [hashtable]::Synchronized(@{})
    $Win32AccountsByCaption = [hashtable]::Synchronized(@{})
    $DomainsBySID = [hashtable]::Synchronized(@{})
    $DomainsByNetbios = [hashtable]::Synchronized(@{})
    $DomainsByFqdn = [hashtable]::Synchronized(@{})
    $LogMsgCache = [hashtable]::Synchronized(@{})
    $Permissions = $null
    $FolderTargets = $null
    $SecurityPrincipals = $null
    $FormattedSecurityPrincipals = $null
    $UniqueAccountPermissions = $null
    $FolderPermissions = $null

    # Get the hostname of the computer running the script
    $ThisHostname = HOSTNAME.EXE

    # Get the NTAccount caption of the user running the script
    $WhoAmI = whoami.exe

    # Prepare the cache of log-related variables to pass to various functions
    $LoggingParams = @{
        ThisHostname = $ThisHostname
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    # Fix the capitalization in the all-lowercase output from whoami.exe
    $WhoAmI = Get-CurrentWhoAmI @LoggingParams

    # Update the cache with the corrected capitalization
    $LoggingParams['WhoAmI'] = $WhoAmI

    # Create an additional cache specifically for Write-LogMsg
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    # These 3 events already happened but we will log them now that we have the correct capitalization of the user
    Write-LogMsg @LogParams -Text "& HOSTNAME.EXE"
    Write-LogMsg @LogParams -Text "& whoami.exe"
    Write-LogMsg @LogParams -Text "Get-CurrentWhoAmI"

    Write-LogMsg @LogParams -Text "ConvertTo-DnsFqdn"
    $ThisFqdn = ConvertTo-DnsFqdn -ComputerName $ThisHostName @LoggingParams

    Write-LogMsg @LogParams -Text "Get-ReportDescription -LevelsOfSubfolders $SubfolderLevels"
    $ReportDescription = Get-ReportDescription -LevelsOfSubfolders $SubfolderLevels

    Write-LogMsg @LogParams -Text "Get-FolderTableHeader -LevelsOfSubfolders $SubfolderLevels"
    $FolderTableHeader = Get-FolderTableHeader -LevelsOfSubfolders $SubfolderLevels

    Write-LogMsg @LogParams -Text "Get-TrustedDomain"
    $TrustedDomains = Get-TrustedDomain @LoggingParams

}

process {

    #----------------[ Main Execution ]---------------

    ForEach ($ThisTargetPath in $TargetPath) {

        Write-LogMsg @LogParams -Text "Get-FolderTarget -FolderPath '$ThisTargetPath'"
        $FolderTargets = Get-FolderTarget -FolderPath $ThisTargetPath
        Write-LogMsg @LogParams -Text "Get-FolderAccessList -FolderTargets @('$($FolderTargets -join "',")') -LevelsOfSubfolders $SubfolderLevels"
        $Permissions = Get-FolderAccessList -FolderTargets $FolderTargets -LevelsOfSubfolders $SubfolderLevels @LoggingParams

        # Save a CSV of the raw NTFS ACEs, showing non-inherited ACEs only except for the root folder $TargetPath
        $CsvFilePath = "$LogDir\1-AccessControlEntries.csv"

        $Permissions |
        Select-Object -Property @{
            Label      = 'Path'
            Expression = { $_.SourceAccessList.Path }
        }, IdentityReference, AccessControlType, FileSystemRights, IsInherited, PropagationFlags, InheritanceFlags |
        Export-Csv -NoTypeInformation -LiteralPath $CsvFilePath

        Write-Information $CsvFilePath

        # This prevents threads that start near the same time from finding the cache empty and attempting costly operations to populate it
        # This prevents repetitive queries to the same directory servers

        # Identify server names from the item paths
        $UniqueServerNames = [System.Collections.Generic.List[[string]]]::new()
        $null = $UniqueServerNames.Add($ThisFqdn)

        $Permissions.SourceAccessList.Path |
        ForEach-Object {
            $null = $UniqueServerNames.Add((Find-ServerNameInPath -LiteralPath $_))
        }

        # Add the discovered domains to our list of known ADSI server name
        $TrustedDomains |
        ForEach-Object {
            $null = $UniqueServerNames.Add($_.DomainFqdn)
        }

        # Deduplicate our list of known ADSI server names
        $UniqueServerNames = $UniqueServerNames |
        Sort-Object -Unique

        # Populate six caches:
        #   Three caches of known ADSI directory servers
        #     The first cache is keyed on domain SID (e.g. S-1-5-2)
        #     The second cache is keyed on domain FQDN (e.g. ad.contoso.com)
        #     The first cache is keyed on domain NetBIOS name (e.g. CONTOSO)
        #   Two caches of known Win32_Account instances
        #     The first cache is keyed on SID (e.g. S-1-5-2)
        #     The second cache is keyed on the Caption (NT Account name e.g. CONTOSO\user1)
        #   Also populate a cache of DirectoryEntry objects for any domains that have them
        if ($ThreadCount -eq 1) {
            $GetAdsiServerParams = @{
                Win32AccountsBySID     = $Win32AccountsBySID
                Win32AccountsByCaption = $Win32AccountsByCaption
                DirectoryEntryCache    = $DirectoryEntryCache
                DomainsByFqdn          = $DomainsByFqdn
                DomainsByNetbios       = $DomainsByNetbios
                DomainsBySid           = $DomainsBySid
                ThisHostName           = $ThisHostName
                ThisFqdn               = $ThisFqdn
                WhoAmI                 = $WhoAmI
                LogMsgCache            = $LogMsgCache
            }

            $UniqueServerNames |
            ForEach-Object {
                Write-LogMsg @LogParams -Text "Get-AdsiServer -Fqdn '$_'"
                $null = Get-AdsiServer @GetAdsiServerParams -Fqdn $_
            }

        } else {
            $GetAdsiServerParams = @{
                Command        = 'Get-AdsiServer'
                InputObject    = $UniqueServerNames
                InputParameter = 'Fqdn'
                TodaysHostname = $ThisHostname
                WhoAmI         = $WhoAmI
                LogMsgCache    = $LogMsgCache
                Timeout        = 600
                AddParam       = @{
                    Win32AccountsBySID     = $Win32AccountsBySID
                    Win32AccountsByCaption = $Win32AccountsByCaption
                    DirectoryEntryCache    = $DirectoryEntryCache
                    DomainsByFqdn          = $DomainsByFqdn
                    DomainsByNetbios       = $DomainsByNetbios
                    DomainsBySid           = $DomainsBySid
                    ThisHostName           = $ThisHostName
                    ThisFqdn               = $ThisFqdn
                    WhoAmI                 = $WhoAmI
                    LogMsgCache            = $LogMsgCache
                }
            }
            Write-LogMsg @LogParams -Text "Split-Thread -Command 'Get-AdsiServer' -InputParameter AdsiServer -InputObject @('$($UniqueServerNames -join "',")')"
            $null = Split-Thread @GetAdsiServerParams
        }

        # Resolve the IdentityReference in each Access Control Entry (e.g. CONTOSO\user1, or a SID) to their associated SIDs/Names
        # The resolved name will include the domain name (or local computer name for local accounts)
        if ($ThreadCount -eq 1) {
            $ResolveAceParams = @{
                DirectoryEntryCache    = $DirectoryEntryCache
                Win32AccountsBySID     = $Win32AccountsBySID
                Win32AccountsByCaption = $Win32AccountsByCaption
                DomainsBySID           = $DomainsBySID
                DomainsByNetbios       = $DomainsByNetbios
                DomainsByFqdn          = $DomainsByFqdn
                ThisHostName           = $ThisHostName
                ThisFqdn               = $ThisFqdn
                WhoAmI                 = $WhoAmI
                LogMsgCache            = $LogMsgCache
            }

            $PermissionsWithResolvedIdentityReferences = $Permissions |
            ForEach-Object {
                $ResolveAceParams['InputObject'] = $_
                Write-LogMsg @LogParams -Text "Resolve-Ace -InputObject $($_.IdentityReference)"
                Resolve-Ace3 @ResolveAceParams
            }

        } else {
            $ResolveAceParams = @{
                Command              = 'Resolve-Ace3'
                InputObject          = $Permissions
                InputParameter       = 'InputObject'
                ObjectStringProperty = 'IdentityReference'
                TodaysHostname       = $ThisHostname
                #DebugOutputStream    = 'Debug'
                WhoAmI               = $WhoAmI
                LogMsgCache          = $LogMsgCache
                AddParam             = @{
                    DirectoryEntryCache    = $DirectoryEntryCache
                    Win32AccountsBySID     = $Win32AccountsBySID
                    Win32AccountsByCaption = $Win32AccountsByCaption
                    DomainsBySID           = $DomainsBySID
                    DomainsByNetbios       = $DomainsByNetbios
                    DomainsByFqdn          = $DomainsByFqdn
                    ThisHostName           = $ThisHostName
                    ThisFqdn               = $ThisFqdn
                    WhoAmI                 = $WhoAmI
                    LogMsgCache            = $LogMsgCache
                }
            }
            Write-LogMsg @LogParams -Text "Split-Thread -Command 'Resolve-Ace' -InputParameter InputObject -InputObject `$Permissions -ObjectStringProperty 'IdentityReference' -DebugOutputStream 'Debug'"
            $PermissionsWithResolvedIdentityReferences = Split-Thread @ResolveAceParams
        }

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
        if ($ThreadCount -eq 1) {
            $ExpandIdentityReferenceParams = @{
                DirectoryEntryCache    = $DirectoryEntryCache
                IdentityReferenceCache = $IdentityReferenceCache
                DomainsBySID           = $DomainsBySID
                DomainsByNetbios       = $DomainsByNetbios
                DomainsByFqdn          = $DomainsByFqdn
                ThisHostName           = $ThisHostName
                ThisFqdn               = $ThisFqdn
                WhoAmI                 = $WhoAmI
                LogMsgCache            = $LogMsgCache
            }
            if ($NoGroupMembers) {
                $ExpandIdentityReferenceParams['NoGroupMembers'] = $true
            }
            $SecurityPrincipals = $GroupedIdentities |
            ForEach-Object {
                $ExpandIdentityReferenceParams['AccessControlEntry'] = $_
                Write-LogMsg @LogParams -Text "Expand-IdentityReference -AccessControlEntry $($_.Name)"
                Expand-IdentityReference @ExpandIdentityReferenceParams
            }

        } else {
            $ExpandIdentityReferenceParams = @{
                Command              = 'Expand-IdentityReference'
                InputObject          = $GroupedIdentities
                InputParameter       = 'AccessControlEntry'
                TodaysHostname       = $ThisHostname
                WhoAmI               = $WhoAmI
                LogMsgCache          = $LogMsgCache
                AddParam             = @{
                    DirectoryEntryCache    = $DirectoryEntryCache
                    IdentityReferenceCache = $IdentityReferenceCache
                    DomainsBySID           = $DomainsBySID
                    DomainsByNetbios       = $DomainsByNetbios
                    DomainsByFqdn          = $DomainsByFqdn
                    ThisHostName           = $ThisHostName
                    ThisFqdn               = $ThisFqdn
                    WhoAmI                 = $WhoAmI
                    LogMsgCache            = $LogMsgCache
                }
                ObjectStringProperty = 'Name'
            }
            if ($NoGroupMembers) {
                $ExpandIdentityReferenceParams['AddSwitch'] = 'NoGroupMembers'
            }
            Write-LogMsg @LogParams -Text "Split-Thread -Command 'Expand-IdentityReference' -InputParameter 'AccessControlEntry' -InputObject `$GroupedIdentities"
            $SecurityPrincipals = Split-Thread @ExpandIdentityReferenceParams
        }

        # Format Security Principals (distinguish group members from users directly listed in the NTFS DACLs)
        if ($ThreadCount -eq 1) {

            $FormattedSecurityPrincipals = $SecurityPrincipals |
            ForEach-Object {
                Write-LogMsg @LogParams -Text "Format-SecurityPrincipal -SecurityPrincipal $($_.Name)"
                Format-SecurityPrincipal -SecurityPrincipal $_
            }

        } else {
            $FormatSecurityPrincipalParams = @{
                Command              = 'Format-SecurityPrincipal'
                InputObject          = $SecurityPrincipals
                InputParameter       = 'SecurityPrincipal'
                Timeout              = 1200
                ObjectStringProperty = 'Name'
                TodaysHostname       = $ThisHostname
                WhoAmI               = $WhoAmI
                LogMsgCache          = $LogMsgCache
            }
            Write-LogMsg @LogParams -Text "Split-Thread -Command 'Format-SecurityPrincipal' -InputParameter 'SecurityPrincipal' -InputObject `$SecurityPrincipals -ObjectStringProperty 'Name'"
            $FormattedSecurityPrincipals = Split-Thread @FormatSecurityPrincipalParams
        }

        # Expand the collection of security principals from Format-SecurityPrincipal
        # back into a collection of access control entries (one per ACE per principal)
        if ($ThreadCount -eq 1) {

            $ExpandedAccountPermissions = $FormattedSecurityPrincipals |
            ForEach-Object {
                Write-LogMsg @LogParams -Text "Expand-AccountPermission -AccountPermission $($_.Name)"
                Expand-AccountPermission -AccountPermission $_
            }

        } else {
            $ExpandAccountPermissionParams = @{
                Command              = 'Expand-AccountPermission'
                InputObject          = $FormattedSecurityPrincipals
                InputParameter       = 'AccountPermission'
                TodaysHostname       = $ThisHostname
                ObjectStringProperty = 'Name'
                Timeout              = 1200
                AddParam             = @{
                    WhoAmI      = $WhoAmI
                    LogMsgCache = $LogMsgCache
                }
            }
            Write-LogMsg @LogParams -Text "Split-Thread -Command 'Expand-AccountPermission' -InputParameter 'AccountPermission' -InputObject `$FormattedSecurityPrincipals -ObjectStringProperty 'Name'"
            $ExpandedAccountPermissions = Split-Thread @ExpandAccountPermissionParams
        }

        # Save a CSV report of the expanded account permissions
        #ToDo: Expand DirectoryEntry objects in the DirectoryEntry and Members properties
        $CsvFilePath = "$LogDir\3-AccessControlEntriesWithResolvedAndExpandedIdentityReferences.csv"

        Write-LogMsg @LogParams -Text "`$ExpandedAccountPermissions |"
        Write-LogMsg @LogParams -Text "`Select-Object -Property @{ Label = 'SourceAclPath'; Expression = { `$_.ACESourceAccessList.Path } }, * |"
        Write-LogMsg @LogParams -Text "Export-Csv -NoTypeInformation -LiteralPath '$CsvFilePath'"

        $ExpandedAccountPermissions |
        Export-Csv -NoTypeInformation -LiteralPath $CsvFilePath

        Write-Information $CsvFilePath

        #$Accounts = $FormattedSecurityPrincipals |
        $Accounts = $ExpandedAccountPermissions |
        Group-Object -Property User

        # Filter out domain names we do not want on the report
        # This can be done when the domain is always the same and doesn't need to be displayed
        # This can also be done to ensure accounts only appear once on the report if they exist in multiple domains
        Write-LogMsg @LogParams -Text "`$UniqueAccountPermissions = Select-UniqueAccountPermission -AccountPermission `$Accounts -IgnoreDomain @('$($IgnoreDomain -join "',")')"
        $UniqueAccountPermissions = Select-UniqueAccountPermission -AccountPermission $Accounts -IgnoreDomain $IgnoreDomain

        # Group the account permissions back into folder permissions for the report
        Write-LogMsg @LogParams -Text "Format-FolderPermission -UserPermission `$UniqueAccountPermissions | Group Folder | Sort Name"

        $FolderPermissions = Format-FolderPermission -UserPermission $UniqueAccountPermissions |
        Group-Object -Property Folder |
        Sort-Object -Property Name

        # Convert the folder list to an HTML table
        Write-LogMsg @LogParams -Text "Select-FolderTableProperty -InputObject `$FolderPermissions | ConvertTo-Html -Fragment | New-BootstrapTable"

        $HtmlTableOfFolders = Select-FolderTableProperty -InputObject $FolderPermissions |
        ConvertTo-Html -Fragment |
        New-BootstrapTable

        # Convert the folder permissions to an HTML table
        $GetFolderPermissionsBlock = @{
            FolderPermissions  = $FolderPermissions
            ExcludeAccount     = $ExcludeAccount
            ExcludeEmptyGroups = $ExcludeEmptyGroups
            IgnoreDomain       = $IgnoreDomain
        }
        Write-LogMsg @LogParams -Text "Get-FolderPermissionsBlock @GetFolderPermissionsBlock"
        $HtmlFolderPermissions = Get-FolderPermissionsBlock @GetFolderPermissionsBlock

        ##Commented the two lines below because actually keeping semicolons means it copy/pastes better into Excel
        ### Convert-ToHtml will not expand in-line HTML
        ### So replace the placeholders (semicolons) with HTML line breaks now, after Convert-ToHtml has already run
        ##$HtmlFolderPermissions = $HtmlFolderPermissions -replace ' ; ','<br>'

        Write-LogMsg @LogParams -Text "New-BootstrapAlert -Class Dark -Text '$ThisTargetPath'"
        $ReportDescription = "$(New-BootstrapAlert -Class Dark -Text $ThisTargetPath) $ReportDescription"
        Write-LogMsg @LogParams -Text "Get-HtmlFolderList -FolderTableHeader `$FolderTableHeader -HtmlTableOfFolders `$HtmlTableOfFolders"
        $FolderList = Get-HtmlFolderList -FolderTableHeader $FolderTableHeader -HtmlTableOfFolders $HtmlTableOfFolders
        Write-LogMsg @LogParams -Text "Get-HtmlBody -FolderList `$FolderList -HtmlFolderPermissions `$HtmlFolderPermissions"
        [string]$Body = Get-HtmlBody -FolderList $FolderList -HtmlFolderPermissions $HtmlFolderPermissions

        $ReportParameters = @{
            Title       = $Title
            Description = $ReportDescription
            Body        = $Body
        }
        Write-LogMsg @LogParams -Text "New-BootstrapReport @ReportParameters"
        $Report = New-BootstrapReport @ReportParameters

        # Save the Html report
        $ReportFile = "$LogDir\FolderPermissionsReport.html"
        $null = Set-Content -LiteralPath $ReportFile -Value $Report

        # Output the name of the report file to the Information stream
        Write-Information $ReportFile

        # Report common issues with NTFS permissions (formatted as XML for PRTG)
        # ToDo: Users with ownership
        $NtfsIssueParams = @{
            FolderPermissions     = $FolderPermissions
            UserPermissions       = $Accounts
            GroupNamingConvention = $GroupNamingConvention
        }
        Write-LogMsg @LogParams -Text "New-NtfsAclIssueReport @NtfsIssueParams"
        $NtfsIssues = New-NtfsAclIssueReport @NtfsIssueParams

        # Format the information as a custom XML sensor for Paessler PRTG Network Monitor
        Write-LogMsg @LogParams -Text "Get-PrtgXmlSensorOutput -NtfsIssues `$NtfsIssues"
        $XMLOutput = Get-PrtgXmlSensorOutput -NtfsIssues $NtfsIssues

        # Save the result of the custom XML sensor for Paessler PRTG Network Monitor
        $XmlFile = "$LogDir\PrtgSensorResult.xml"
        $null = Set-Content -LiteralPath $XmlFile -Value $XMLOutput

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
        Write-LogMsg @LogParams -Text "Send-PrtgXmlSensorOutput @PrtgSensorParams"
        Send-PrtgXmlSensorOutput @PrtgSensorParams

        # Open the HTML report file (useful only interactively)
        if ($OpenReportAtEnd) {
            Invoke-Item $ReportFile
        }

    }

}

end {

    $LogFile = "$LogDir\Export-Permission.log"

    $LogMsgCache.Values |
    Sort-Object -Property Timestamp |
    Export-Csv -Delimiter "`t" -NoTypeInformation -LiteralPath $LogFile

    Stop-Transcript  *>$null

    # Output the XML so the script can be directly used as a PRTG sensor
    # Caution: This use may be a problem for a PRTG probe because of how long the script can run on large folders/domains
    # Recommendation: Specify the appropriate parameters to run this as a PRTG push sensor instead
    return $XMLOutput

}

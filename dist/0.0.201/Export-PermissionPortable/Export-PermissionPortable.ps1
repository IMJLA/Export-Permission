<#PSScriptInfo

.VERSION 0.0.201

.GUID c7308309-badf-44ea-8717-28e5f5beffd5

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
psakefile bugfix (needed to filter out ProgressAction common param)

.PRIVATEDATA

#> 


















<#
.SYNOPSIS
    Portable version of Export-Permission with all ScriptModule dependencies rolled up into this single .ps1 file

    Create CSV, HTML, and XML reports of permissions

.DESCRIPTION
    Benefits:
    - Presents complex nested permissions and group memberships in a report that is easy to read
    - Provides additional information about each account such as Name, Department, Title
    - Multithreaded with caching for fast results
    - Works as a scheduled task
    - Works as a custom sensor script for Paessler PRTG Network Monitor (Push sensor recommended due to execution time)

    Supports these scenarios:
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

    Intended when a user has matching SamAccountNames in multiple domains but you only want them to appear once on the report.

    Can also be used to remove all domains simply for brevity in the report.
    #>
    [string[]]$IgnoreDomain = 'CONTOSO',

    # Path to the folder to save the logs and reports generated by this script
    [string]$OutputDir = "$env:AppData\Export-Permission",

    <#
    Do not get group members (only report the groups themselves)

    Note: By default, the -ExcludeClass parameter will exclude groups from the report.
      If using -NoGroupMembers, you most likely want to modify the value of -ExcludeClass.
      Remove the 'group' class from ExcludeClass in order to see groups on the report.
    #>
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
    [string]$PrtgToken

)

begin {

    #----------------[ Functions ]------------------

# Definition of Module 'Adsi' Version '4.0.7' is below

class FakeDirectoryEntry {

    <#
    Used in place of a DirectoryEntry for certain WinNT security principals that do not have objects in the directory
    The WinNT provider only throws an error if you try to retrieve certain accounts/identities
    #>

    [string]$Name
    [string]$Parent
    [string]$Path
    [type]$SchemaEntry
    [byte[]]$objectSid
    [string]$Description
    [hashtable]$Properties
    [string]$SchemaClassName

    FakeDirectoryEntry (
        [string]$DirectoryPath
    ) {

        $LastSlashIndex = $DirectoryPath.LastIndexOf('/')
        $StartIndex = $LastSlashIndex + 1
        $This.Name = $DirectoryPath.Substring($StartIndex, $DirectoryPath.Length - $StartIndex)
        $This.Parent = $DirectoryPath.Substring(0, $LastSlashIndex)
        $This.Path = $DirectoryPath
        $This.SchemaEntry = [System.DirectoryServices.DirectoryEntry]
        switch -regex ($DirectoryPath) {

            'CREATOR OWNER$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-3-0'
                $This.Description = 'A SID to be replaced by the SID of the user who creates a new object. This SID is used in inheritable ACEs.'
                $This.Properties = @{
                    Name        = $This.Name
                    Description = $This.Description
                    objectSid   = $This.objectSid
                }
                $This.SchemaClassName = 'user'
            }
            'SYSTEM$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-18'
                $This.Description = 'By default, the SYSTEM account is granted Full Control permissions to all files on an NTFS volume'
                $This.Properties = @{
                    Name        = $This.Name
                    Description = $This.Description
                    objectSid   = $This.objectSid
                }
                $This.SchemaClassName = 'user'
            }
            'INTERACTIVE$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-4'
                $This.Description = 'Users who log on for interactive operation. This is a group identifier added to the token of a process when it was logged on interactively.'
                $This.Properties = @{
                    Name        = $This.Name
                    Description = $This.Description
                    objectSid   = $This.objectSid
                }
                $This.SchemaClassName = 'group'
            }
            'Authenticated Users$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-11'
                $This.Description = 'Any user who accesses the system through a sign-in process has the Authenticated Users identity.'
                $This.Properties = @{
                    Name        = $This.Name
                    Description = $This.Description
                    objectSid   = $This.objectSid
                }
                $This.SchemaClassName = 'group'
            }
            'TrustedInstaller$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-11'
                $This.Description = 'Most of the operating system files are owned by the TrustedInstaller security identifier (SID)'
                $This.Properties = @{
                    Name        = $This.Name
                    Description = $This.Description
                    objectSid   = $This.objectSid
                }
                $This.SchemaClassName = 'user'
            }
        }
    }

    [void]RefreshCache([string[]]$Nonsense) {}
    [void]Invoke([string]$Nonsense) {}

}
function Add-DomainFqdnToLdapPath {
    <#
        .SYNOPSIS
        Add a domain FQDN to an LDAP directory path as the server address so the new path can be used for remote queries
        .DESCRIPTION
        Uses RegEx to:
            - Match the Domain Components from the Distinguished Name in the LDAP directory path
            - Convert the Domain Components to an FQDN
            - Insert them into the directory path as the server address
        .INPUTS
        [System.String]$DirectoryPath
        .OUTPUTS
        [System.String] Complete LDAP directory path including server address
        .EXAMPLE
        Add-DomainFqdnToLdapPath -DirectoryPath 'LDAP://CN=user1,OU=UsersOU,DC=ad,DC=contoso,DC=com'
        LDAP://ad.contoso.com/CN=user1,OU=UsersOU,DC=ad,DC=contoso,DC=com

        Add the domain FQDN to a single LDAP directory path
    #>
    [OutputType([System.String])]
    param (

        # Incomplete LDAP directory path containing a distinguishedName but lacking a server address
        [Parameter(ValueFromPipeline)]
        [string[]]$DirectoryPath,

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {

        <#
        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }
        #>

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $PathRegEx = '(?<Path>LDAP:\/\/[^\/]*)'
        $DomainRegEx = '(?i)DC=\w{1,}?\b'

    }
    process {

        ForEach ($ThisPath in $DirectoryPath) {

            if ($ThisPath -match $PathRegEx) {

                $RegExMatches = $null
                $RegExMatches = [regex]::Matches($ThisPath, $DomainRegEx)

                if ($RegExMatches) {
                    $DomainDN = $null
                    $DomainFqdn = $null

                    $RegExMatches = $RegExMatches |
                    ForEach-Object { $_.Value }

                    $DomainDN = $RegExMatches -join ','
                    $DomainFqdn = ConvertTo-Fqdn -DistinguishedName $DomainDN -ThisFqdn $ThisFqdn @LoggingParams
                    if ($ThisPath -match "LDAP:\/\/$DomainFqdn\/") {
                        #Write-LogMsg @LogParams -Text " # Domain FQDN already found in the directory path: '$ThisPath'"
                        $ThisPath
                    } else {
                        $ThisPath -replace 'LDAP:\/\/', "LDAP://$DomainFqdn/"
                    }
                } else {
                    #Write-LogMsg @LogParams -Text " # Domain DN not found in the directory path: '$ThisPath'"
                    $ThisPath
                }
            } else {
                #Write-LogMsg @LogParams -Text " # Not an expected directory path: '$ThisPath'"
                $ThisPath
            }
        }
    }
}
function Add-SidInfo {
    <#
        .SYNOPSIS
        Add some useful properties to a DirectoryEntry object for easier access
        .DESCRIPTION
        Add SidString, Domain, and SamAccountName NoteProperties to a DirectoryEntry
        .INPUTS
        [System.DirectoryServices.DirectoryEntry] or a [PSCustomObject] imitation. InputObject parameter.  Must contain the objectSid property.
        .OUTPUTS
        [System.DirectoryServices.DirectoryEntry] or a [PSCustomObject] imitation. Whatever was input, but with three extra properties added now.
        .EXAMPLE
        [System.DirectoryServices.DirectoryEntry]::new('WinNT://localhost/Administrator') | Add-SidInfo
        distinguishedName :
        Path              : WinNT://localhost/Administrator

        The output object's default format is not modified so with default formatting it appears identical to the original.
        Upon closer inspection it now has SidString, Domain, and SamAccountName properties.
    #>
    [OutputType([System.DirectoryServices.DirectoryEntry[]], [PSCustomObject[]])]
    param (

        # Expecting a [System.DirectoryServices.DirectoryEntry] from the LDAP or WinNT providers, or a [PSCustomObject] imitation from Get-DirectoryEntry.
        # Must contain the objectSid property
        [Parameter(ValueFromPipeline)]
        $InputObject,

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

    }

    process {

        ForEach ($Object in $InputObject) {

            $SID = $null
            $SamAccountName = $null
            $DomainObject = $null

            if ($null -eq $Object) {
                continue
            } elseif ($Object.objectSid.Value ) {
                # With WinNT directory entries for the root (WinNT://localhost), objectSid is a method rather than a property
                # So we need to filter out those instances here to avoid this error:
                # The following exception occurred while retrieving the string representation for method "objectSid":
                # "Object reference not set to an instance of an object."
                if ( $Object.objectSid.Value.GetType().FullName -ne 'System.Management.Automation.PSMethod' ) {
                    [string]$SID = [System.Security.Principal.SecurityIdentifier]::new([byte[]]$Object.objectSid.Value, 0)
                }
            } elseif ($Object.objectSid) {
                # With WinNT directory entries for the root (WinNT://localhost), objectSid is a method rather than a property
                # So we need to filter out those instances here to avoid this error:
                # The following exception occurred while retrieving the string representation for method "objectSid":
                # "Object reference not set to an instance of an object."
                if ($Object.objectSid.GetType().FullName -ne 'System.Management.Automation.PSMethod') {
                    [string]$SID = [System.Security.Principal.SecurityIdentifier]::new([byte[]]$Object.objectSid, 0)
                }
            } elseif ($Object.Properties) {
                if ($Object.Properties['objectSid'].Value) {
                    [string]$SID = [System.Security.Principal.SecurityIdentifier]::new([byte[]]$Object.Properties['objectSid'].Value, 0)
                } elseif ($Object.Properties['objectSid']) {
                    [string]$SID = [System.Security.Principal.SecurityIdentifier]::new([byte[]]($Object.Properties['objectSid'] | ForEach-Object { $_ }), 0)
                }
                if ($Object.Properties['samaccountname']) {
                    $SamAccountName = $Object.Properties['samaccountname']
                } else {
                    #DirectoryEntries from the WinNT provider for local accounts do not have a samaccountname attribute so we use name instead
                    $SamAccountName = $Object.Properties['name']
                }
            } elseif ($Object.objectSid) {
                [string]$SID = [System.Security.Principal.SecurityIdentifier]::new([byte[]]$Object.objectSid, 0)
            }

            if ($Object.Domain.Sid) {
                #if ($Object.Domain.GetType().FullName -ne 'System.Management.Automation.PSMethod') {
                # This would only have come from Add-SidInfo in the first place
                # This means it was added with Add-Member in Get-DirectoryEntry for the root of the computer's directory
                if ($null -eq $SID) {
                    [string]$SID = $Object.Domain.Sid
                }
                $DomainObject = $Object.Domain
                #}
            }
            if (-not $DomainObject) {
                # The SID of the domain is the SID of the user minus the last block of numbers
                $DomainSid = $SID.Substring(0, $Sid.LastIndexOf("-"))

                # Lookup other information about the domain using its SID as the key
                $DomainObject = $DomainsBySid[$DomainSid]
            }

            #Write-LogMsg @LogParams -Text "$SamAccountName`t$SID"

            Add-Member -InputObject $Object -PassThru -Force @{
                SidString      = $SID
                Domain         = $DomainObject
                SamAccountName = $SamAccountName
            }
        }
    }
}
function ConvertFrom-DirectoryEntry {
    <#
    .SYNOPSIS
    Convert a DirectoryEntry to a PSCustomObject
    .DESCRIPTION
    Recursively convert every property into a string, or a PSCustomObject (whose properties are all strings, or more PSCustomObjects)
    This obfuscates the troublesome PropertyCollection and PropertyValueCollection and Hashtable aspects of working with ADSI
    .NOTES
    # TODO: There is a faster way than Select-Object, just need to dig into the default formatting of DirectoryEntry to see how to get those properties
    #>

    param (
        [Parameter(
            Position = 0,
            ValueFromPipeline
        )]
        [System.DirectoryServices.DirectoryEntry[]]$DirectoryEntry
    )

    process {
        ForEach ($ThisDirectoryEntry in $DirectoryEntry) {
            $ObjectWithProperties = $ThisDirectoryEntry |
            Select-Object -Property *

            $ObjectNoteProperties = $ObjectWithProperties |
            Get-Member -MemberType Property, CodeProperty, ScriptProperty, NoteProperty

            $ThisObject = @{}
            ForEach ($ThisObjProperty in $ObjectNoteProperties) {
                $ThisObject = ConvertTo-SimpleProperty -InputObject $ObjectWithProperties -Property $ThisObjProperty.Name -PropertyDictionary $ThisObject
            }

            [PSCustomObject]$ThisObject
        }
    }
}
function ConvertFrom-PropertyValueCollectionToString {
    <#
        .SYNOPSIS
        Convert a PropertyValueCollection to a string
        .DESCRIPTION
        Useful when working with System.DirectoryServices and some other namespaces
        .INPUTS
        None. Pipeline input is not accepted.
        .OUTPUTS
        [System.String]
        .EXAMPLE
        $DirectoryEntry = [adsi]("WinNT://$(hostname)")
        $DirectoryEntry.Properties.Keys |
        ForEach-Object {
            ConvertFrom-PropertyValueCollectionToString -PropertyValueCollection $DirectoryEntry.Properties[$_]
        }

        For each property in a DirectoryEntry, convert its corresponding PropertyValueCollection to a string
    #>
    param (
        [System.DirectoryServices.PropertyValueCollection]$PropertyValueCollection
    )
    $SubType = & { $PropertyValueCollection.Value.GetType().FullName } 2>$null
    switch ($SubType) {
        'System.Byte[]' { ConvertTo-DecStringRepresentation -ByteArray $PropertyValueCollection.Value }
        default { "$($PropertyValueCollection.Value)" }
    }
}
function ConvertFrom-ResultPropertyValueCollectionToString {
    <#
        .SYNOPSIS
        Convert a ResultPropertyValueCollection to a string
        .DESCRIPTION
        Useful when working with System.DirectoryServices and some other namespaces
        .INPUTS
        None. Pipeline input is not accepted.
        .OUTPUTS
        [System.String]
        .EXAMPLE
        $DirectoryEntry = [adsi]("WinNT://$(hostname)")
        $DirectoryEntry.Properties.Keys |
        ForEach-Object {
            ConvertFrom-PropertyValueCollectionToString -PropertyValueCollection $DirectoryEntry.Properties[$_]
        }

        For each property in a DirectoryEntry, convert its corresponding PropertyValueCollection to a string
    #>
    param (
        [System.DirectoryServices.ResultPropertyValueCollection]$ResultPropertyValueCollection
    )
    $SubType = & { $ResultPropertyValueCollection.Value.GetType().FullName } 2>$null
    switch ($SubType) {
        'System.Byte[]' { ConvertTo-DecStringRepresentation -ByteArray $ResultPropertyValueCollection.Value }
        default { "$($ResultPropertyValueCollection.Value)" }
    }
}
function ConvertFrom-SearchResult {
    <#
    .SYNOPSIS
    Convert a SearchResult to a PSCustomObject
    .DESCRIPTION
    Recursively convert every property into a string, or a PSCustomObject (whose properties are all strings, or more PSCustomObjects)
    This obfuscates the troublesome ResultPropertyCollection and ResultPropertyValueCollection and Hashtable aspects of working with ADSI searches
    .NOTES
    # TODO: There is a faster way than Select-Object, just need to dig into the default formatting of SearchResult to see how to get those properties
    #>

    param (
        [Parameter(
            Position = 0,
            ValueFromPipeline
        )]
        [System.DirectoryServices.SearchResult[]]$SearchResult
    )

    process {
        ForEach ($ThisSearchResult in $SearchResult) {
            $ObjectWithProperties = $ThisSearchResult |
            Select-Object -Property *

            $ObjectNoteProperties = $ObjectWithProperties |
            Get-Member -MemberType Property, CodeProperty, ScriptProperty, NoteProperty

            $ThisObject = @{}

            # Enumerate the keys of the ResultPropertyCollection
            ForEach ($ThisProperty in $ThisSearchResult.Properties.Keys) {
                $ThisObject = ConvertTo-SimpleProperty -InputObject $ThisSearchResult.Properties -Property $ThisProperty -PropertyDictionary $ThisObject
            }

            # We will allow any existing properties to override members of the ResultPropertyCollection
            ForEach ($ThisObjProperty in $ObjectNoteProperties) {
                $ThisObject = ConvertTo-SimpleProperty -InputObject $ObjectWithProperties -Property $ThisObjProperty.Name -PropertyDictionary $ThisObject
            }

            [PSCustomObject]$ThisObject
        }
    }
}
function ConvertFrom-SidString {
    #[OutputType([System.Security.Principal.NTAccount])]
    param (
        [string]$SID
    )
    #[System.Security.Principal.SecurityIdentifier]::new($SID)
    # Only works if SID is in the current domain...otherwise SID not found
    Get-DirectoryEntry -DirectoryPath "LDAP://<SID=$SID>"
}
function ConvertTo-DecStringRepresentation {
    <#
        .SYNOPSIS
        Convert a byte array to a string representation of its decimal format
        .DESCRIPTION
        Uses the custom format operator -f to format each byte as a string decimal representation
        .INPUTS
        [System.Byte[]]$ByteArray
        .OUTPUTS
        [System.String] Array of strings representing the byte array's decimal values
        .EXAMPLE
        ConvertTo-DecStringRepresentation -ByteArray $Bytes

        Convert the binary SID $Bytes to a decimal string representation
    #>
    [OutputType([System.String])]
    param (
        # Byte array.  Often the binary format of an objectSid or LoginHours
        [byte[]]$ByteArray
    )

    $ByteArray |
    ForEach-Object {
        '{0}' -f $_
    }
}
function ConvertTo-DistinguishedName {
    <#
        .SYNOPSIS
        Convert a domain NetBIOS name to its distinguishedName
        .DESCRIPTION
        https://docs.microsoft.com/en-us/windows/win32/api/iads/nn-iads-iadsnametranslate
        .INPUTS
        [System.String]$Domain
        .OUTPUTS
        [System.String] distinguishedName of the domain
        .EXAMPLE
        ConvertTo-DistinguishedName -Domain 'CONTOSO'
        DC=ad,DC=contoso,DC=com

        Resolve the NetBIOS domain 'CONTOSO' to its distinguishedName 'DC=ad,DC=contoso,DC=com'
    #>
    [OutputType([System.String])]
    param (

        # NetBIOS name of the domain
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'NetBIOS')]
        [string[]]$Domain,

        [Parameter(ParameterSetName = 'NetBIOS')]
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # NetBIOS name of the domain
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'FQDN')]
        [string[]]$DomainFQDN,

        # Type of initialization to be performed
        # Will be translated to the corresponding integer for use as the lnSetType parameter of the IADsNameTranslate::Init method (iads.h)
        # https://docs.microsoft.com/en-us/windows/win32/api/iads/ne-iads-ads_name_inittype_enum
        [string]$InitType = 'ADS_NAME_INITTYPE_GC',

        # Format of the name of the directory object that will be used for the input
        # Will be translated to the corresponding integer for use as the lnSetType parameter of the IADsNameTranslate::Set method (iads.h)
        # https://docs.microsoft.com/en-us/windows/win32/api/iads/ne-iads-ads_name_type_enum
        [string]$InputType = 'ADS_NAME_TYPE_NT4',

        # Format of the name of the directory object that will be used for the output
        # Will be translated to the corresponding integer for use as the lnSetType parameter of the IADsNameTranslate::Get method (iads.h)
        # https://docs.microsoft.com/en-us/windows/win32/api/iads/ne-iads-ads_name_type_enum
        [string]$OutputType = 'ADS_NAME_TYPE_1779',

        <#
        AdsiProvider (WinNT or LDAP) of the servers associated with the provided FQDNs or NetBIOS names

        This parameter can be used to reduce calls to Find-AdsiProvider

        Useful when that has been done already but the DomainsByFqdn and DomainsByNetbios caches have not been updated yet
        #>
        [string]$AdsiProvider,

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        # Declare constants for these Windows enums
        # We need to because PowerShell makes it hard to directly use the Win32 API and read the enum definition
        # Use hashtables instead of enums since this use case is so simple
        $ADS_NAME_INITTYPE_dict = @{
            ADS_NAME_INITTYPE_DOMAIN = 1 #Initializes a NameTranslate object by setting the domain that the object binds to.
            ADS_NAME_INITTYPE_SERVER = 2 #Initializes a NameTranslate object by setting the server that the object binds to.
            ADS_NAME_INITTYPE_GC     = 3 #Initializes a NameTranslate object by locating the global catalog that the object binds to.
        }
        $ADS_NAME_TYPE_dict = @{
            ADS_NAME_TYPE_1779                    = 1 #Name format as specified in RFC 1779. For example, "CN=Jeff Smith,CN=users,DC=Fabrikam,DC=com".
            ADS_NAME_TYPE_CANONICAL               = 2 #Canonical name format. For example, "Fabrikam.com/Users/Jeff Smith".
            ADS_NAME_TYPE_NT4                     = 3 #Account name format used in Windows. For example, "Fabrikam\JeffSmith".
            ADS_NAME_TYPE_DISPLAY                 = 4 #Display name format. For example, "Jeff Smith".
            ADS_NAME_TYPE_DOMAIN_SIMPLE           = 5 #Simple domain name format. For example, "JeffSmith@Fabrikam.com".
            ADS_NAME_TYPE_ENTERPRISE_SIMPLE       = 6 #Simple enterprise name format. For example, "JeffSmith@Fabrikam.com".
            ADS_NAME_TYPE_GUID                    = 7 #Global Unique Identifier format. For example, "{95ee9fff-3436-11d1-b2b0-d15ae3ac8436}".
            ADS_NAME_TYPE_UNKNOWN                 = 8 #Unknown name type. The system will estimate the format. This element is a meaningful option only with the IADsNameTranslate.Set or the IADsNameTranslate.SetEx method, but not with the IADsNameTranslate.Get or IADsNameTranslate.GetEx method.
            ADS_NAME_TYPE_USER_PRINCIPAL_NAME     = 9 #User principal name format. For example, "JeffSmith@Fabrikam.com".
            ADS_NAME_TYPE_CANONICAL_EX            = 10 #Extended canonical name format. For example, "Fabrikam.com/Users Jeff Smith".
            ADS_NAME_TYPE_SERVICE_PRINCIPAL_NAME  = 11 #Service principal name format. For example, "www/www.fabrikam.com@fabrikam.com".
            ADS_NAME_TYPE_SID_OR_SID_HISTORY_NAME = 12 #A SID string, as defined in the Security Descriptor Definition Language (SDDL), for either the SID of the current object or one from the object SID history. For example, "O:AOG:DAD:(A;;RPWPCCDCLCSWRCWDWOGA;;;S-1-0-0)"
        }
        $ChosenInitType = $ADS_NAME_INITTYPE_dict[$InitType]
        $ChosenInputType = $ADS_NAME_TYPE_dict[$InputType]
        $ChosenOutputType = $ADS_NAME_TYPE_dict[$OutputType]

    }
    process {
        ForEach ($ThisDomain in $Domain) {
            $DomainCacheResult = $DomainsByNetbios[$ThisDomain]
            if ($DomainCacheResult) {
                Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$ThisDomain'"
                #ConvertTo-DistinguishedName -DomainFQDN $DomainCacheResult.Dns -AdsiProvider $DomainCacheResult.AdsiProvider
                $DomainCacheResult.DistinguishedName
            } else {
                Write-LogMsg @LogParams -Text " # Domain NetBIOS cache miss for '$ThisDomain'. Available keys: $($DomainsByNetBios.Keys -join ',')"
                Write-LogMsg @LogParams -Text "`$IADsNameTranslateComObject = New-Object -comObject 'NameTranslate' # For '$ThisDomain'"
                $IADsNameTranslateComObject = New-Object -comObject "NameTranslate"
                Write-LogMsg @LogParams -Text "`$IADsNameTranslateInterface = `$IADsNameTranslateComObject.GetType() # For '$ThisDomain'"
                $IADsNameTranslateInterface = $IADsNameTranslateComObject.GetType()
                Write-LogMsg @LogParams -Text "`$null = `$IADsNameTranslateInterface.InvokeMember('Init', 'InvokeMethod', `$Null, `$IADsNameTranslateComObject, ($ChosenInitType, `$Null)) # For '$ThisDomain'"
                $null = $IADsNameTranslateInterface.InvokeMember("Init", "InvokeMethod", $Null, $IADsNameTranslateComObject, ($ChosenInitType, $Null))

                # For a non-domain-joined system there is no DistinguishedName for the domain
                # Suppress errors when calling these next 2 methods
                #     Exception calling "InvokeMember" with "5" argument(s): "Name translation: Could not find the name or insufficient right to see name. (Exception from HRESULT: 0x80072116)"
                Write-LogMsg @LogParams -Text "`$null = `$IADsNameTranslateInterface.InvokeMember('Set', 'InvokeMethod', `$Null, `$IADsNameTranslateComObject, ($ChosenInputType, '$ThisDomain\')) # For '$ThisDomain'"
                $null = { $IADsNameTranslateInterface.InvokeMember("Set", "InvokeMethod", $Null, $IADsNameTranslateComObject, ($ChosenInputType, "$ThisDomain\")) } 2>$null
                #     Exception calling "InvokeMember" with "5" argument(s): "Unspecified error (Exception from HRESULT: 0x80004005 (E_FAIL))"
                Write-LogMsg @LogParams -Text "`$IADsNameTranslateInterface.InvokeMember('Get', 'InvokeMethod', `$Null, `$IADsNameTranslateComObject, $ChosenOutputType) # For '$ThisDomain'"
                $null = { $null = { $IADsNameTranslateInterface.InvokeMember("Get", "InvokeMethod", $Null, $IADsNameTranslateComObject, $ChosenOutputType) } 2>$null } 2>$null
            }
        }
        ForEach ($ThisDomain in $DomainFQDN) {
            $DomainCacheResult = $DomainsByFqdn[$ThisDomain]
            if ($DomainCacheResult) {
                Write-LogMsg @LogParams -Text " # Domain FQDN cache hit for '$ThisDomain'"
                $DomainCacheResult.DistinguishedName
            } else {
                Write-LogMsg @LogParams -Text " # Domain FQDN cache miss for '$ThisDomain'"

                if (-not $PSBoundParameters.ContainsKey('AdsiProvider')) {
                    $AdsiProvider = Find-AdsiProvider -AdsiServer $ThisDomain @LoggingParams
                }

                if ($AdsiProvider -ne 'WinNT') {
                    "dc=$($ThisDomain -replace '\.',',dc=')"
                }
            }
        }
    }
}
function ConvertTo-DomainNetBIOS {
    param (
        [string]$DomainFQDN,

        [string]$AdsiProvider,

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    $LoggingParams = @{
        ThisHostname = $ThisHostname
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    $DomainCacheResult = $DomainsByFqdn[$DomainFQDN]
    if ($DomainCacheResult) {
        Write-LogMsg @LogParams -Text " # Domain FQDN cache hit for '$DomainFQDN'"
        return $DomainCacheResult.Netbios
    }

    Write-LogMsg @LogParams -Text " # Domain FQDN cache miss for '$DomainFQDN'"

    if ($AdsiProvider -eq 'LDAP') {
        $RootDSE = Get-DirectoryEntry -DirectoryPath "LDAP://$DomainFQDN/rootDSE" -DirectoryEntryCache $DirectoryEntryCache -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid @LoggingParams
        Write-LogMsg @LogParams -Text "`$RootDSE.InvokeGet('defaultNamingContext')"
        $DomainDistinguishedName = $RootDSE.InvokeGet("defaultNamingContext")
        Write-LogMsg @LogParams -Text "`$RootDSE.InvokeGet('configurationNamingContext')"
        $ConfigurationDN = $rootDSE.InvokeGet("configurationNamingContext")
        $partitions = Get-DirectoryEntry -DirectoryPath "LDAP://$DomainFQDN/cn=partitions,$ConfigurationDN" -DirectoryEntryCache $DirectoryEntryCache -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid @LoggingParams

        ForEach ($Child In $Partitions.Children) {
            If ($Child.nCName -contains $DomainDistinguishedName) {
                return $Child.nETBIOSName
            }
        }
    } else {
        $LengthOfNetBIOSName = $DomainFQDN.IndexOf('.')
        if ($LengthOfNetBIOSName -eq -1) {
            $DomainFQDN
        } else {
            $DomainFQDN.Substring(0, $LengthOfNetBIOSName)
        }
    }

}
function ConvertTo-DomainSidString {
    param (

        # Domain DNS name to convert to the domain's SID
        [Parameter(Mandatory)]
        [string]$DomainDnsName,

        <#
        Hashtable containing cached directory entries so they don't have to be retrieved from the directory again

        Uses a thread-safe hashtable by default
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        AdsiProvider (WinNT or LDAP) of the servers associated with the provided FQDNs or NetBIOS names

        This parameter can be used to reduce calls to Find-AdsiProvider

        Useful when that has been done already but the DomainsByFqdn and DomainsByNetbios caches have not been updated yet
        #>
        [string]$AdsiProvider,

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    $LoggingParams = @{
        ThisHostname = $ThisHostname
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }


    $CacheResult = $DomainsByFqdn[$DomainDnsName]
    if ($CacheResult) {
        Write-LogMsg @LogParams -Text " # Domain FQDN cache hit for '$DomainDnsName'"
        return $CacheResult.Sid
    }
    Write-LogMsg @LogParams -Text " # Domain FQDN cache miss for '$DomainDnsName'"

    if (
        -not $AdsiProvider -or
        $AdsiProvider -eq 'LDAP'
    ) {
        $DomainDirectoryEntry = Get-DirectoryEntry -DirectoryPath "LDAP://$DomainDnsName" -DirectoryEntryCache $DirectoryEntryCache -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid @LoggingParams
        try {
            $null = $DomainDirectoryEntry.RefreshCache('objectSid')
        } catch {
            Write-Debug "$(Get-Date -Format s)`t$ThisHostname`tConvertTo-DomainSidString`t # LDAP connection failed to '$DomainDnsName' - $($_.Exception.Message)"
            Write-LogMsg @LogParams -Text "Find-LocalAdsiServerSid -ComputerName '$DomainDnsName'"
            $DomainSid = Find-LocalAdsiServerSid -ComputerName $DomainDnsName-ThisFqdn $ThisFqdn @LoggingParams
            return $DomainSid
        }
    } else {
        Write-LogMsg @LogParams -Text "Find-LocalAdsiServerSid -ComputerName '$DomainDnsName'"
        $DomainSid = Find-LocalAdsiServerSid -ComputerName $DomainDnsName -ThisFqdn $ThisFqdn @LoggingParams
        return $DomainSid
    }

    $DomainSid = $null

    if ($DomainDirectoryEntry.Properties) {
        $objectSIDProperty = $DomainDirectoryEntry.Properties['objectSid']
        if ($objectSIDProperty.Value) {
            $SidByteArray = [byte[]]$objectSIDProperty.Value
        } else {
            $SidByteArray = [byte[]]$objectSIDProperty
        }
    } else {
        $SidByteArray = [byte[]]$DomainDirectoryEntry.objectSid
    }

    Write-Debug "  $(Get-Date -Format s)`t$ThisHostname`tConvertTo-DomainSidString`t[System.Security.Principal.SecurityIdentifier]::new([byte[]]@($($SidByteArray -join ',')), 0).ToString()"
    $DomainSid = [System.Security.Principal.SecurityIdentifier]::new($SidByteArray, 0).ToString()

    if ($DomainSid) {
        return $DomainSid
    } else {
        Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tConvertTo-DomainSidString`t # LDAP Domain: '$DomainDnsName' has an invalid SID - $($_.Exception.Message)"
    }

}
function ConvertTo-Fqdn {
    <#
        .SYNOPSIS
        Convert a domain distinguishedName name or NetBIOS name to its FQDN
        .DESCRIPTION
        For the DistinguishedName parameter, uses PowerShell's -replace operator to perform the conversion
        For the NetBIOS parameter, uses ConvertTo-DistinguishedName to convert from NetBIOS to distinguishedName, then recursively calls this function to get the FQDN
        .INPUTS
        [System.String]$DistinguishedName
        .OUTPUTS
        [System.String] FQDN version of the distinguishedName
        .EXAMPLE
        ConvertTo-Fqdn -DistinguishedName 'DC=ad,DC=contoso,DC=com'
        ad.contoso.com

        Convert the domain distinguishedName 'DC=ad,DC=contoso,DC=com' to its FQDN format 'ad.contoso.com'
    #>
    [OutputType([System.String])]
    param (
        # distinguishedName of the domain
        [Parameter(
            ParameterSetName = 'DistinguishedName',
            ValueFromPipeline
        )]
        [string[]]$DistinguishedName,

        # NetBIOS name of the domain
        [Parameter(
            ParameterSetName = 'NetBIOS',
            ValueFromPipeline
        )]
        [string[]]$NetBIOS,

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

    }
    process {
        ForEach ($DN in $DistinguishedName) {
            $DN -replace ',DC=', '.' -replace 'DC=', ''
        }

        ForEach ($ThisNetBios in $NetBIOS) {
            $DomainObject = $DomainsByNetbios[$DomainNetBIOS]

            if (
                -not $DomainObject -and
                -not [string]::IsNullOrEmpty($DomainNetBIOS)
            ) {
                Write-LogMsg @LogParams -Text " # Domain NetBIOS cache miss for '$DomainNetBIOS'"
                $DomainObject = Get-AdsiServer -Netbios $DomainNetBIOS -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                $DomainsByNetbios[$DomainNetBIOS] = $DomainObject
            }

            $DomainObject.Dns
        }
    }
}
function ConvertTo-HexStringRepresentation {
    <#
        .SYNOPSIS
        Convert a SID from byte array format to a string representation of its hexadecimal format
        .DESCRIPTION
        Uses the custom format operator -f to format each byte as a string hex representation
        .INPUTS
        [System.Byte[]]$SIDByteArray
        .OUTPUTS
        [System.String] SID as an array of strings representing the byte array's hexadecimal values
        .EXAMPLE
        ConvertTo-HexStringRepresentation -SIDByteArray $Bytes

        Convert the binary SID $Bytes to a hexadecimal string representation
    #>
    [OutputType([System.String[]])]
    param (
        # SID
        [byte[]]$SIDByteArray
    )

    $SIDHexString = $SIDByteArray |
    ForEach-Object {
        '{0:X}' -f $_
    }
    return $SIDHexString
}
function ConvertTo-HexStringRepresentationForLDAPFilterString {
    <#
        .SYNOPSIS
        Convert a SID from byte array format to a string representation of its hexadecimal format, properly formatted for an LDAP filter string
        .DESCRIPTION
        Uses the custom format operator -f to format each byte as a string hex representation
        .INPUTS
        [System.Byte[]]$SIDByteArray
        .OUTPUTS
        [System.String] SID as an array of strings representing the byte array's hexadecimal values
        .EXAMPLE
        ConvertTo-HexStringRepresentationForLDAPFilterString -SIDByteArray $Bytes

        Convert the binary SID $Bytes to a hexadecimal string representation, formatted for use in an LDAP filter string
    #>
    [OutputType([System.String])]
    param (
        # SID to convert to a hex string
        [byte[]]$SIDByteArray
    )
    $Hexes = $SIDByteArray |
    ForEach-Object {
        '{0:X}' -f $_
    } |
    ForEach-Object {
        if ($_.Length -eq 2) {
            $_
        } else {
            "0$_"
        }
    }
    "\$($Hexes -join '\')"
}
function ConvertTo-SidByteArray {
    <#
        .SYNOPSIS
        Convert a SID from a string to binary format (byte array)
        .DESCRIPTION
        Uses the GetBinaryForm method of the [System.Security.Principal.SecurityIdentifier] class
        .INPUTS
        [System.String]$SidString
        .OUTPUTS
        [System.Byte] SID a a byte array
        .EXAMPLE
        ConvertTo-SidByteArray -SidString $SID

        Convert the SID string to a byte array
    #>
    [OutputType([System.Byte[]])]
    param (
        # SID to convert to binary
        [Parameter(ValueFromPipeline)]
        [string[]]$SidString
    )
    process {
        ForEach ($ThisSID in $SidString) {
            $SID = [System.Security.Principal.SecurityIdentifier]::new($ThisSID)
            [byte[]]$Bytes = [byte[]]::new($SID.BinaryLength)
            $SID.GetBinaryForm($Bytes, 0)
            $Bytes
        }
    }
}
function Expand-AdsiGroupMember {
    <#
        .SYNOPSIS
        Use the LDAP provider to add information about group members to a DirectoryEntry of a group for easier access
        .DESCRIPTION
        Recursively retrieves group members and detailed information about them
        Specifically gets the SID, and resolves foreign security principals to their DirectoryEntry from the trusted domain
        .INPUTS
        [System.DirectoryServices.DirectoryEntry]$DirectoryEntry
        .OUTPUTS
        [System.DirectoryServices.DirectoryEntry] Returned with member info added now (if the DirectoryEntry is a group).
        .EXAMPLE
        [System.DirectoryServices.DirectoryEntry]::new('WinNT://localhost/Administrators') | Get-AdsiGroupMember | Expand-AdsiGroupMember

        Need to fix example and add notes
    #>
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param (

        # Expecting a DirectoryEntry from the LDAP or WinNT providers, or a PSObject imitation from Get-DirectoryEntry
        [parameter(ValueFromPipeline)]
        $DirectoryEntry,

        # Properties of the group members to retrieve
        [string[]]$PropertiesToLoad = (@('Department', 'description', 'distinguishedName', 'grouptype', 'managedby', 'member', 'name', 'objectClass', 'objectSid', 'operatingSystem', 'primaryGroupToken', 'samAccountName', 'Title')),

        # Cache of known Win32_Account instances keyed by domain and SID
        [hashtable]$Win32AccountsBySID = ([hashtable]::Synchronized(@{})),

        # Cache of known Win32_Account instances keyed by domain (e.g. CONTOSO) and Caption (NTAccount name e.g. CONTOSO\User1)
        [hashtable]$Win32AccountsByCaption = ([hashtable]::Synchronized(@{})),

        <#
        Hashtable containing cached directory entries so they don't need to be retrieved from the directory again

        Uses a thread-safe hashtable by default
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid,

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        # The DomainsBySID cache must be populated with trusted domains in order to translate foreign security principals
        if ( $DomainsBySid.Keys.Count -lt 1 ) {
            Write-LogMsg @LogParams -Text "# No valid DomainsBySid cache found"
            $DomainsBySid = ([hashtable]::Synchronized(@{}))

            $GetAdsiServerParams = @{
                Win32AccountsBySID     = $Win32AccountsBySID
                Win32AccountsByCaption = $Win32AccountsByCaption
                DirectoryEntryCache    = $DirectoryEntryCache
                DomainsByNetbios       = $DomainsByNetbios
                DomainsBySid           = $DomainsBySid
                DomainsByFqdn          = $DomainsByFqdn
                ThisFqdn               = $ThisFqdn
            }

            Get-TrustedDomain |
            ForEach-Object {
                Write-LogMsg @LogParams -Text "Get-AdsiServer -Fqdn $($_.DomainFqdn)"
                $null = Get-AdsiServer -Fqdn $_.DomainFqdn @GetAdsiServerParams @LoggingParams
            }
        } else {
            Write-LogMsg @LogParams -Text "# Valid DomainsBySid cache found"
        }

        $CacheParams = @{
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByNetbios    = $DomainsByNetbios
            DomainsBySid        = $DomainsBySid
        }

        $i = 0
    }

    process {

        ForEach ($Entry in $DirectoryEntry) {

            $i++

            #$status = ("$(Get-Date -Format s)`t$ThisHostname`tExpand-AdsiGroupMember`tStatus: Using ADSI to get info on group member $i`: " + $Entry.Name)
            #Write-LogMsg @LogParams -Text "$status"

            $Principal = $null

            if ($Entry.objectClass -contains 'foreignSecurityPrincipal') {

                if ($Entry.distinguishedName.Value -match '(?>^CN=)(?<SID>[^,]*)') {

                    [string]$SID = $Matches.SID

                    #The SID of the domain is the SID of the user minus the last block of numbers
                    $DomainSid = $SID.Substring(0, $Sid.LastIndexOf("-"))
                    $Domain = $DomainsBySid[$DomainSid]

                    $Principal = Get-DirectoryEntry -DirectoryPath "LDAP://$($Domain.Dns)/<SID=$SID>" @CacheParams @LogginParams

                    try {
                        $null = $Principal.RefreshCache($PropertiesToLoad)
                    } catch {
                        #$Success = $false
                        $Principal = $Entry
                        Write-LogMsg @LogParams -Text " # SID '$SID' could not be retrieved from domain '$Domain'"
                    }

                    # Recursively enumerate group members
                    if ($Principal.properties['objectClass'].Value -contains 'group') {
                        Write-LogMsg @LogParams -Text "'$($Principal.properties['name'])' is a group in '$Domain'"
                        $AdsiGroupWithMembers = Get-AdsiGroupMember -Group $Principal -DomainsByFqdn $DomainsByFqdn -ThisFqdn $ThisFqdn @CacheParams @LoggingParams
                        $Principal = Expand-AdsiGroupMember -DirectoryEntry $AdsiGroupWithMembers.FullMembers -DomainsByFqdn $DomainsByFqdn -ThisFqdn $ThisFqdn -ThisHostName $ThisHostName @CacheParams

                    }

                }

            } else {
                $Principal = $Entry
            }

            Add-SidInfo -InputObject $Principal -DomainsBySid $DomainsBySid @LoggingParams

        }
    }

}
function Expand-IdentityReference {
    <#
        .SYNOPSIS
        Use ADSI to collect more information about the IdentityReference in NTFS Access Control Entries
        .DESCRIPTION
        Recursively retrieves group members and detailed information about them
        Use caching to reduce duplicate directory queries
        .INPUTS
        [System.Object]$AccessControlEntry
        .OUTPUTS
        [System.Object] The input object is returned with additional properties added:
            DirectoryEntry
            DomainDn
            DomainNetBIOS
            ObjectType
            Members (if the DirectoryEntry is a group).

        .EXAMPLE
        (Get-Acl).Access |
        Resolve-IdentityReference |
        Group-Object -Property IdentityReferenceResolved |
        Expand-IdentityReference

        Incomplete example but it shows the chain of functions to generate the expected input for this
    #>
    [OutputType([System.Object])]
    param (

        # The NTFS AccessControlEntry object(s), grouped by their IdentityReference property
        # TODO: Use System.Security.Principal.NTAccount instead
        [Parameter(ValueFromPipeline)]
        [System.Object[]]$AccessControlEntry,

        # Do not get group members
        [switch]$NoGroupMembers,

        # Thread-safe hashtable to use for caching directory entries and avoiding duplicate directory queries
        [hashtable]$IdentityReferenceCache = ([hashtable]::Synchronized(@{})),

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        #Write-LogMsg @LogParams -Text "$(($AccessControlEntry | Measure).Count) unique IdentityReferences found in the $(($AccessControlEntry | Measure).Count) ACEs"

        # Get the SID of the current domain
        $CurrentDomain = (Get-CurrentDomain)

        # Convert the objectSID attribute (byte array) to a security descriptor string formatted according to SDDL syntax (Security Descriptor Definition Language)
        [string]$CurrentDomainSID = & { [System.Security.Principal.SecurityIdentifier]::new([byte[]]$CurrentDomain.objectSid.Value, 0) } 2>$null

        #$i = 0

    }

    process {

        ForEach ($ThisIdentity in $AccessControlEntry) {

            if (-not $ThisIdentity) {
                continue
            }

            $ThisIdentityGroup = $ThisIdentity.Group

            #$i++
            #Calculate the completion percentage, and format it to show 0 decimal places
            #$percentage = "{0:N0}" -f (($i / ($AccessControlEntry.Count)) * 100)

            #Display the progress bar
            #$status = $percentage + "% - Using ADSI to get info on NTFS IdentityReference $i of " + $AccessControlEntry.Count + ": " + $ThisIdentity.Name
            #Write-LogMsg @LogParams -Text "Status: $status"

            #Write-Progress -Activity ("Unique IdentityReferences: " + $AccessControlEntry.Count) -Status $status -PercentComplete $percentage

            if ($null -eq $IdentityReferenceCache[$ThisIdentity.Name]) {

                Write-LogMsg @LogParams -Text " # IdentityReferenceCache miss for '$($ThisIdentity.Name)'"

                $DomainDN = $null
                $DirectoryEntry = $null
                $Members = $null

                $GetDirectoryEntryParams = @{
                    DirectoryEntryCache = $DirectoryEntryCache
                    DomainsByNetbios    = $DomainsByNetbios
                    ThisHostname        = $ThisHostname
                    LogMsgCache         = $LogMsgCache
                    WhoAmI              = $WhoAmI
                }
                $SearchDirectoryParams = @{
                    DirectoryEntryCache = $DirectoryEntryCache
                    DomainsByNetbios    = $DomainsByNetbios
                    ThisHostname        = $ThisHostname
                    LogMsgCache         = $LogMsgCache
                    WhoAmI              = $WhoAmI
                }

                $StartingIdentityName = $ThisIdentity.Name
                $split = $StartingIdentityName.Split('\')
                $domainNetbiosString = $split[0]
                $name = $split[1]

                if (
                    $null -ne $name -and
                    @($ThisIdentity.Group.AdsiProvider)[0] -eq 'LDAP'
                ) {
                    Write-LogMsg @LogParams -Text " # '$StartingIdentityName' is a domain security principal"

                    $DomainNetbiosCacheResult = $DomainsByNetbios[$domainNetbiosString]
                    if ($DomainNetbiosCacheResult) {
                        Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$domainNetbiosString' for '$StartingIdentityName'"
                        $DomainDn = $DomainNetbiosCacheResult.DistinguishedName
                        $SearchDirectoryParams['DirectoryPath'] = "LDAP://$($DomainNetbiosCacheResult.Dns)/$DomainDn"
                    } else {
                        Write-LogMsg @LogParams -Text " # Domain NetBIOS cache miss for '$domainNetbiosString' for '$StartingIdentityName'"
                        if ( -not [string]::IsNullOrEmpty($domainNetbiosString) ) {
                            $DomainDn = ConvertTo-DistinguishedName -Domain $domainNetbiosString -DomainsByNetbios $DomainsByNetbios @LoggingParams
                        }
                        $SearchDirectoryParams['DirectoryPath'] = Add-DomainFqdnToLdapPath -DirectoryPath "LDAP://$domainNetbiosString" -ThisFqdn $ThisFqdn @LogParams
                    }

                    # Search the domain for the principal
                    $SearchDirectoryParams['Filter'] = "(samaccountname=$Name)"
                    $SearchDirectoryParams['PropertiesToLoad'] = @(
                        'objectClass',
                        'objectSid',
                        'samAccountName',
                        'distinguishedName',
                        'name',
                        'grouptype',
                        'description',
                        'managedby',
                        'member',
                        'Department',
                        'Title',
                        'primaryGroupToken'
                    )
                    try {
                        $DirectoryEntry = Search-Directory @SearchDirectoryParams
                    } catch {
                        Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tExpand-IdentityReference`t # '$StartingIdentityName' could not be resolved against its directory"
                        Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tExpand-IdentityReference`t # $($_.Exception.Message) for '$StartingIdentityName"
                    }

                } elseif (
                    $StartingIdentityName.Substring(0, $StartingIdentityName.LastIndexOf('-') + 1) -eq $CurrentDomainSID
                    #((($StartingIdentityName -split '-') | Select-Object -SkipLast 1) -join '-') -eq $CurrentDomainSID
                ) {
                    Write-LogMsg @LogParams -Text " # '$StartingIdentityName' is an unresolved SID from the current domain"

                    # Get the distinguishedName and netBIOSName of the current domain.  This also determines whether the domain is online.
                    $DomainDN = $CurrentDomain.distinguishedName.Value
                    $DomainFQDN = ConvertTo-Fqdn -DistinguishedName $DomainDN -ThisFqdn $ThisFqdn @LoggingParams

                    $SearchDirectoryParams['DirectoryPath'] = "LDAP://$DomainFQDN/cn=partitions,cn=configuration,$DomainDn"
                    $SearchDirectoryParams['Filter'] = "(&(objectcategory=crossref)(dnsroot=$DomainFQDN)(netbiosname=*))"
                    $SearchDirectoryParams['PropertiesToLoad'] = 'netbiosname'

                    $DomainCrossReference = Search-Directory @SearchDirectoryParams
                    if ($DomainCrossReference.Properties ) {
                        Write-LogMsg @LogParams -Text " # The domain '$DomainFQDN' is online for '$StartingIdentityName'"
                        [string]$domainNetbiosString = $DomainCrossReference.Properties['netbiosname']
                        # TODO: The domain is online, so let's see if any domain trusts have issues?  Determine if SID is foreign security principal?
                        # TODO: What if the foreign security principal exists but the corresponding domain trust is down?  Don't want to recommend deletion of the ACE in that case.
                    }
                    $SidObject = [System.Security.Principal.SecurityIdentifier]::new($StartingIdentityName)
                    $SidBytes = [byte[]]::new($SidObject.BinaryLength)
                    $null = $SidObject.GetBinaryForm($SidBytes, 0)
                    $ObjectSid = ConvertTo-HexStringRepresentationForLDAPFilterString -SIDByteArray $SidBytes
                    $SearchDirectoryParams['DirectoryPath'] = "LDAP://$DomainFQDN/$DomainDn"
                    $SearchDirectoryParams['Filter'] = "(objectsid=$ObjectSid)"
                    $SearchDirectoryParams['PropertiesToLoad'] = @(
                        'objectClass',
                        'objectSid',
                        'samAccountName',
                        'distinguishedName',
                        'name',
                        'grouptype',
                        'description',
                        'managedby',
                        'member',
                        'Department',
                        'Title',
                        'primaryGroupToken'
                    )
                    try {
                        $DirectoryEntry = Search-Directory @SearchDirectoryParams
                    } catch {
                        Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tExpand-IdentityReference`t # '$StartingIdentityName' could not be resolved against its directory"
                        Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tExpand-IdentityReference`t # $($_.Exception.Message) for '$StartingIdentityName'"
                    }


                } else {

                    Write-LogMsg @LogParams -Text " # '$StartingIdentityName' is a local security principal or unresolved SID"

                    if ($null -eq $name) { $name = $StartingIdentityName }

                    if ($name -like "S-1-*") {
                        Write-LogMsg @LogParams -Text "$($StartingIdentityName) is an unresolved SID"

                        # The SID of the domain is the SID of the user minus the last block of numbers
                        $DomainSid = $name.Substring(0, $name.LastIndexOf("-"))

                        # Determine if SID belongs to current domain
                        if ($DomainSid -eq $CurrentDomainSID) {
                            Write-LogMsg @LogParams -Text "$($StartingIdentityName) belongs to the current domain.  Could be a deleted user.  ?possibly a foreign security principal corresponding to an offline trusted domain or deleted user in the trusted domain?"
                        } else {
                            Write-LogMsg @LogParams -Text "$($StartingIdentityName) does not belong to the current domain. Could be a local security principal or belong to an unresolvable domain."
                        }

                        # Lookup other information about the domain using its SID as the key
                        $DomainObject = $DomainsBySID[$DomainSid]
                        if ($DomainObject) {
                            $GetDirectoryEntryParams['DirectoryPath'] = "WinNT://$($DomainObject.Dns)/Users,group"
                            $domainNetbiosString = $DomainObject.Netbios
                        } else {
                            $GetDirectoryEntryParams['DirectoryPath'] = "WinNT://$domainNetbiosString/Users,group"
                        }

                        try {
                            $UsersGroup = Get-DirectoryEntry @GetDirectoryEntryParams
                        } catch {
                            Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tExpand-IdentityReference`tCould not get '$($GetDirectoryEntryParams['DirectoryPath'])' using PSRemoting"
                            Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tExpand-IdentityReference`t$_"
                        }
                        $MembersOfUsersGroup = Get-WinNTGroupMember -DirectoryEntry $UsersGroup -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams

                        $DirectoryEntry = $MembersOfUsersGroup |
                        Where-Object -FilterScript { ($name -eq [System.Security.Principal.SecurityIdentifier]::new([byte[]]$_.Properties['objectSid'].Value, 0)) }

                        if ($DirectoryEntry.Name) {
                            $AccountName = $DirectoryEntry.Name
                        } else {
                            if ($DirectoryEntry.Properties) {
                                if ($DirectoryEntry.Properties['name'].Value) {
                                    $AccountName = $DirectoryEntry.Properties['name'].Value
                                } else {
                                    $AccountName = $DirectoryEntry.Properties['name']
                                }
                            }
                        }

                        $ThisIdentity = [pscustomobject]@{
                            Count = $(($ThisIdentityGroup | Measure-Object).Count)
                            Name  = "$domainNetbiosString\" + $AccountName
                            Group = $ThisIdentityGroup
                            # Unclear why this was filtered so I have removed it to see what happens
                            #Group = $ThisIdentityGroup | Where-Object -FilterScript { ($_.SourceAccessList.Path -split '\\')[2] -eq $domainNetbiosString } # Should be already Resolved to a UNC path so it reflects the server name
                        }

                    } else {
                        Write-LogMsg @LogParams -Text " # '$StartingIdentityName' is a local security principal"
                        $DomainNetbiosCacheResult = $DomainsByNetbios[$domainNetbiosString]
                        if ($DomainNetbiosCacheResult) {
                            $GetDirectoryEntryParams['DirectoryPath'] = "WinNT://$($DomainNetbiosCacheResult.Dns)/$name"
                        } else {
                            $GetDirectoryEntryParams['DirectoryPath'] = "WinNT://$domainNetbiosString/$name"
                        }
                        try {
                            $GetDirectoryEntryParams['PropertiesToLoad'] = @(
                                'members',
                                'objectClass',
                                'objectSid',
                                'samAccountName',
                                'distinguishedName',
                                'name',
                                'grouptype',
                                'description',
                                'managedby',
                                'member',
                                'Department',
                                'Title',
                                'primaryGroupToken'
                            )
                            $DirectoryEntry = Get-DirectoryEntry @GetDirectoryEntryParams
                        } catch {
                            Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tExpand-IdentityReference`t$($GetDirectoryEntryParams['DirectoryPath']) could not be resolved for '$StartingIdentityName'"
                        }
                    }
                }

                $ObjectType = $null
                if ($null -ne $DirectoryEntry) {

                    if (
                        $DirectoryEntry.Properties['objectClass'] -contains 'group' -or
                        $DirectoryEntry.SchemaClassName -eq 'group'
                    ) {
                        $ObjectType = 'Group'
                    } else {
                        $ObjectType = 'User'
                    }

                    if ($NoGroupMembers -eq $false) {

                        if (
                            # WinNT DirectoryEntries do not contain an objectClass property
                            # If this property exists it is an LDAP DirectoryEntry rather than WinNT
                            $DirectoryEntry.Properties['objectClass'] -contains 'group'
                        ) {
                            # Retrieve the members of groups from the LDAP provider
                            Write-LogMsg @LogParams -Text " # '$($DirectoryEntry.Path)' is an LDAP security principal for '$StartingIdentityName'"
                            $Members = (Get-AdsiGroupMember -Group $DirectoryEntry -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams).FullMembers
                        } else {
                            # Retrieve the members of groups from the WinNT provider
                            Write-LogMsg @LogParams -Text " # '$($DirectoryEntry.Path)' is a WinNT security principal for '$StartingIdentityName'"
                            if ( $DirectoryEntry.SchemaClassName -eq 'group') {
                                Write-LogMsg @LogParams -Text " # '$($DirectoryEntry.Path)' is a WinNT group for '$StartingIdentityName'"
                                $Members = Get-WinNTGroupMember -DirectoryEntry $DirectoryEntry -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                            }
                        }

                        # (Get-AdsiGroupMember).FullMembers or Get-WinNTGroupMember could return an array with null members so we must verify that is not true
                        if ($Members) {
                            $Members |
                            ForEach-Object {

                                if ($_.Domain) {

                                    Add-Member -InputObject $_ -Force -NotePropertyMembers @{
                                        Group = $ThisIdentityGroup
                                    }

                                } else {

                                    Add-Member -InputObject $_ -Force -NotePropertyMembers @{
                                        Group  = $ThisIdentityGroup
                                        Domain = [pscustomobject]@{
                                            Dns     = $domainNetbiosString
                                            Netbios = $domainNetbiosString
                                            Sid     = ($name -split '-') | Select-Object -Last 1
                                        }
                                    }

                                }
                            }
                        }

                        Write-LogMsg @LogParams -Text " # $($DirectoryEntry.Path) has $(($Members | Measure-Object).Count) members for '$StartingIdentityName'"

                    }
                } else {
                    Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tExpand-IdentityReference`t # '$StartingIdentityName' could not be matched to a DirectoryEntry"
                }

                Add-Member -InputObject $ThisIdentity -Force -NotePropertyMembers @{
                    DomainDn       = $DomainDn
                    DomainNetbios  = $DomainNetBiosString
                    ObjectType     = $ObjectType
                    DirectoryEntry = $DirectoryEntry
                    Members        = $Members
                }
                $IdentityReferenceCache[$StartingIdentityName] = $ThisIdentity

            } else {
                Write-LogMsg @LogParams -Text " # IdentityReferenceCache hit for '$($ThisIdentity.Name)'"
                $null = $IdentityReferenceCache[$ThisIdentity.Name].Group.Add($ThisIdentityGroup)
                $ThisIdentity = $IdentityReferenceCache[$ThisIdentity.Name]
            }

            $ThisIdentity

        }

    }

}
function Expand-WinNTGroupMember {
    <#
        .SYNOPSIS
        Use the LDAP provider to add information about group members to a DirectoryEntry of a group for easier access
        .DESCRIPTION
        Recursively retrieves group members and detailed information about them
        .INPUTS
        [System.DirectoryServices.DirectoryEntry]$DirectoryEntry
        .OUTPUTS
        [System.DirectoryServices.DirectoryEntry] Returned with member info added now (if the DirectoryEntry is a group).
        .EXAMPLE
        [System.DirectoryServices.DirectoryEntry]::new('WinNT://localhost/Administrators') | Get-WinNTGroupMember | Expand-WinNTGroupMember

        Need to fix example and add notes
    #>
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param (

        # Expecting a DirectoryEntry from the WinNT provider, or a PSObject imitation from Get-DirectoryEntry
        [Parameter(ValueFromPipeline)]
        $DirectoryEntry,

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

    }
    process {
        ForEach ($ThisEntry in $DirectoryEntry) {

            if (!($ThisEntry.Properties)) {
                Write-Warning "'$ThisEntry' has no properties"
            } elseif ($ThisEntry.Properties['objectClass'] -contains 'group') {

                Write-LogMsg @LogParams -Text "'$($ThisEntry.Path)' is an ADSI group"
                $AdsiGroup = Get-AdsiGroup -DirectoryEntryCache $DirectoryEntryCache -DirectoryPath $ThisEntry.Path -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                Add-SidInfo -InputObject $AdsiGroup.FullMembers -DomainsBySid $DomainsBySid @LoggingParams

            } else {

                if ($ThisEntry.SchemaClassName -eq 'group') {
                    Write-LogMsg @LogParams -Text "'$($ThisEntry.Path)' is a WinNT group"

                    if ($ThisEntry.GetType().FullName -eq 'System.Collections.Hashtable') {
                        Write-LogMsg @LogParams -Text "$($ThisEntry.Path)' is a special group with no direct memberships"
                        Add-SidInfo -InputObject $ThisEntry -DomainsBySid $DomainsBySid @LoggingParams
                    } else {
                        Get-WinNTGroupMember -DirectoryEntry $ThisEntry -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                    }

                } else {
                    Write-LogMsg @LogParams -Text "$($ThisEntry.Path)' is a user account"
                    Add-SidInfo -InputObject $ThisEntry -DomainsBySid $DomainsBySid @LoggingParams
                }

            }

        }
    }
}
function Find-AdsiProvider {
    <#
        .SYNOPSIS
        Determine whether a directory server is an LDAP or a WinNT server
        .DESCRIPTION
        Uses the ADSI provider to attempt to query the server using LDAP first, then WinNT second
        .INPUTS
        [System.String] AdsiServer parameter.
        .OUTPUTS
        [System.String] Possible return values are:
            None
            LDAP
            WinNT
        .EXAMPLE
        Find-AdsiProvider -AdsiServer localhost

        Find the ADSI provider of the local computer
        .EXAMPLE
        Find-AdsiProvider -AdsiServer 'ad.contoso.com'

        Find the ADSI provider of the AD domain 'ad.contoso.com'
    #>
    [OutputType([System.String])]

    param (

        # IP address or hostname of the directory server whose ADSI provider type to determine
        [Parameter(ValueFromPipeline)]
        [string[]]$AdsiServer,

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

    }
    process {
        ForEach ($ThisServer in $AdsiServer) {
            $AdsiProvider = $null
            $AdsiPath = "LDAP://$ThisServer"
            Write-LogMsg @LogParams -Text "[System.DirectoryServices.DirectoryEntry]::Exists('$AdsiPath')"
            try {
                $null = [System.DirectoryServices.DirectoryEntry]::Exists($AdsiPath)
                $AdsiProvider = 'LDAP'
            } catch { Write-LogMsg @LogParams -Text " # $ThisServer did not respond to LDAP" }
            if (!$AdsiProvider) {
                $AdsiPath = "WinNT://$ThisServer"
                Write-LogMsg @LogParams -Text "[System.DirectoryServices.DirectoryEntry]::Exists('$AdsiPath')"
                try {
                    $null = [System.DirectoryServices.DirectoryEntry]::Exists($AdsiPath)
                    $AdsiProvider = 'WinNT'
                } catch {
                    Write-LogMsg @LogParams -Text " # $ThisServer did not respond to WinNT"
                }
            }
            if (!$AdsiProvider) {
                $AdsiProvider = 'none'
            }
        }
        $AdsiProvider
    }
}
function Find-LocalAdsiServerSid {
    param (
        [string]$ComputerName,

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    $LoggingParams = @{
        ThisHostname = $ThisHostname
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    Write-LogMsg @LogParams -Text "Get-Win32UserAccount -ComputerName '$ComputerName'"
    $Win32UserAccounts = Get-Win32UserAccount -ComputerName $ComputerName -ThisFqdn $ThisFqdn @LoggingParams
    if (-not $Win32UserAccounts) {
        return
    }
    [string]$LocalAccountSID = @($Win32UserAccounts.SID)[0]
    return $LocalAccountSID.Substring(0, $LocalAccountSID.LastIndexOf("-"))
}
function Get-AdsiGroup {
    <#
        .SYNOPSIS
        Get the directory entries for a group and its members using ADSI
        .DESCRIPTION
        Uses the ADSI components to search a directory for a group, then get its members
        Both the WinNT and LDAP providers are supported
        .INPUTS
        None. Pipeline input is not accepted.
        .OUTPUTS
        [System.DirectoryServices.DirectoryEntry] for each group memeber
        .EXAMPLE
        Get-AdsiGroup -DirectoryPath 'WinNT://WORKGROUP/localhost' -GroupName Administrators

        Get members of the local Administrators group
        .EXAMPLE
        Get-AdsiGroup -GroupName Administrators

        On a domain-joined computer, this will get members of the domain's Administrators group
        On a workgroup computer, this will get members of the local Administrators group
    #>
    [OutputType([System.DirectoryServices.DirectoryEntry])]

    param (

        <#
        Path to the directory object to retrieve
        Defaults to the root of the current domain
        #>
        [string]$DirectoryPath = (([System.DirectoryServices.DirectorySearcher]::new()).SearchRoot.Path),

        # Name (CN or Common Name) of the group to retrieve
        [string]$GroupName,

        # Properties of the group members to retrieve
        [string[]]$PropertiesToLoad = (@('Department', 'description', 'distinguishedName', 'grouptype', 'managedby', 'member', 'name', 'objectClass', 'objectSid', 'operatingSystem', 'primaryGroupToken', 'samAccountName', 'Title')),

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    $GroupParams = @{
        DirectoryPath       = $DirectoryPath
        PropertiesToLoad    = $PropertiesToLoad
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByFqdn       = $DomainsByFqdn
        DomainsByNetbios    = $DomainsByNetbios
        DomainsBySid        = $DomainsBySid
        ThisHostname        = $ThisHostname
        LogMsgCache         = $LogMsgCache
        WhoAmI              = $WhoAmI
    }
    $GroupMemberParams = @{
        PropertiesToLoad    = $PropertiesToLoad
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByFqdn       = $DomainsByFqdn
        DomainsByNetbios    = $DomainsByNetbios
        DomainsBySid        = $DomainsBySid
        ThisHostName        = $ThisHostName
        ThisFqdn            = $ThisFqdn
        LogMsgCache         = $LogMsgCache
        WhoAmI              = $WhoAmI
    }

    switch -Regex ($DirectoryPath) {
        '^WinNT' {
            $GroupParams['DirectoryPath'] = "$DirectoryPath/$GroupName"
            $GroupMemberParams['DirectoryEntry'] = Get-DirectoryEntry @GroupParams
            $FullMembers = Get-WinNTGroupMember @GroupMemberParams
        }
        '^$' {
            # This is expected for a workgroup computer
            $GroupParams['DirectoryPath'] = "WinNT://localhost/$GroupName"
            $GroupMemberParams['DirectoryEntry'] = Get-DirectoryEntry @GroupParams
            $FullMembers = Get-WinNTGroupMember @GroupMemberParams
        }
        default {
            if ($GroupName) {
                $GroupParams['Filter'] = "(&(objectClass=group)(cn=$GroupName))"
            } else {
                $GroupParams['Filter'] = "(objectClass=group)"
            }
            $GroupMemberParams['Group'] = Search-Directory @GroupParams
            $FullMembers = Get-AdsiGroupMember @GroupMemberParams
        }
    }

    $FullMembers

}
function Get-AdsiGroupMember {
    <#
        .SYNOPSIS
        Get members of a group from the LDAP provider
        .DESCRIPTION
        Use ADSI to get members of a group from the LDAP provider
        Return the group's DirectoryEntry plus a FullMembers property containing the member DirectoryEntries
        .INPUTS
        [System.DirectoryServices.DirectoryEntry]$DirectoryEntry
        .OUTPUTS
        [System.DirectoryServices.DirectoryEntry] plus a FullMembers property
        .EXAMPLE
        [System.DirectoryServices.DirectoryEntry]::new('LDAP://ad.contoso.com/CN=Administrators,CN=BuiltIn,DC=ad,DC=contoso,DC=com') | Get-AdsiGroupMember

        Get members of the domain Administrators group
    #>
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param (

        # Directory entry of the LDAP group whose members to get
        [Parameter(ValueFromPipeline)]
        $Group,

        # Properties of the group members to find in the directory
        [string[]]$PropertiesToLoad,

        # Cache of known Win32_Account instances keyed by domain and SID
        [hashtable]$Win32AccountsBySID = ([hashtable]::Synchronized(@{})),

        # Cache of known Win32_Account instances keyed by domain (e.g. CONTOSO) and Caption (NTAccount name e.g. CONTOSO\User1)
        [hashtable]$Win32AccountsByCaption = ([hashtable]::Synchronized(@{})),

        <#
        Hashtable containing cached directory entries so they don't have to be retrieved from the directory again
        Uses a thread-safe hashtable by default
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages,

        <#
        Perform a non-recursive search of the memberOf attribute

        Otherwise the search will be recursive by default
        #>
        [switch]$NoRecurse,

        <#
        Search the primaryGroupId attribute only

        Ignore the memberOf attribute
        #>
        [switch]$PrimaryGroupOnly

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $PathRegEx = '(?<Path>LDAP:\/\/[^\/]*)'
        $DomainRegEx = '(?i)DC=\w{1,}?\b'

        $PropertiesToLoad += 'primaryGroupToken', 'objectSid', 'objectClass'

        $PropertiesToLoad = $PropertiesToLoad |
        Sort-Object -Unique

        $SearchParameters = @{
            PropertiesToLoad    = $PropertiesToLoad
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByNetbios    = $DomainsByNetbios
        }

        $CacheParams = @{
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByNetbios    = $DomainsByNetbios
            DomainsBySid        = $DomainsBySid
        }

    }
    process {

        foreach ($ThisGroup in $Group) {

            if (-not $ThisGroup.Properties['primaryGroupToken']) {
                $ThisGroup.RefreshCache('primaryGroupToken')
            }

            # The memberOf attribute does not reflect a user's Primary Group membership so the primaryGroupId attribute must be searched
            $primaryGroupIdFilter = "(primaryGroupId=$($ThisGroup.Properties['primaryGroupToken']))"

            if ($PrimaryGroupOnly) {
                $SearchParameters['Filter'] = $primaryGroupIdFilter
            } else {

                if ($NoRecurse) {
                    # Non-recursive search of the memberOf attribute
                    $MemberOfFilter = "(memberOf=$($ThisGroup.Properties['distinguishedname']))"
                } else {
                    # Recursive search of the memberOf attribute
                    $MemberOfFilter = "(memberOf:1.2.840.113556.1.4.1941:=$($ThisGroup.Properties['distinguishedname']))"
                }

                $SearchParameters['Filter'] = "(|$MemberOfFilter$primaryGroupIdFilter)"
            }

            if ($ThisGroup.Path -match $PathRegEx) {

                $SearchParameters['DirectoryPath'] = Add-DomainFqdnToLdapPath -DirectoryPath $Matches.Path -ThisFqdn $ThisFqdn @LoggingParams

                if ($ThisGroup.Path -match $DomainRegEx) {
                    $Domain = ([regex]::Matches($ThisGroup.Path, $DomainRegEx) | ForEach-Object { $_.Value }) -join ','
                    $SearchParameters['DirectoryPath'] = Add-DomainFqdnToLdapPath -DirectoryPath "LDAP://$Domain" -ThisFqdn $ThisFqdn @LoggingParams
                } else {
                    $SearchParameters['DirectoryPath'] = Add-DomainFqdnToLdapPath -DirectoryPath $ThisGroup.Path -ThisFqdn $ThisFqdn @LoggingParams
                }

            } else {
                $SearchParameters['DirectoryPath'] = Add-DomainFqdnToLdapPath -DirectoryPath $ThisGroup.Path -ThisFqdn $ThisFqdn @LoggingParams
            }

            Write-LogMsg @LogParams -Text "Search-Directory -DirectoryPath '$($SearchParameters['DirectoryPath'])' -Filter '$($SearchParameters['Filter'])'"

            $GroupMemberSearch = Search-Directory @SearchParameters
            Write-LogMsg @LogParams -Text " # '$($GroupMemberSearch.Count)' results for Search-Directory -DirectoryPath '$($SearchParameters['DirectoryPath'])' -Filter '$($SearchParameters['Filter'])'"

            if ($GroupMemberSearch.Count -gt 0) {
                $CurrentADGroupMembers = [System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]]::new()

                $MembersThatAreGroups = $GroupMemberSearch |
                Where-Object -FilterScript { $_.Properties['objectClass'] -contains 'group' }

                if ($MembersThatAreGroups.Count -gt 0) {
                    $FilterBuilder = [System.Text.StringBuilder]::new("(|")

                    $MembersThatAreGroups |
                    ForEach-Object {
                        $null = $FilterBuilder.Append("(primaryGroupId=$($_.Properties['primaryGroupToken'])))")
                    }

                    $null = $FilterBuilder.Append(")")
                    $PrimaryGroupFilter = $FilterBuilder.ToString()
                    $SearchParameters['Filter'] = $PrimaryGroupFilter
                    Write-LogMsg @LogParams -Text "Search-Directory -DirectoryPath '$($SearchParameters['DirectoryPath'])' -Filter '$($SearchParameters['Filter'])'"
                    $PrimaryGroupMembers = Search-Directory @SearchParameters

                    $PrimaryGroupMembers |
                    ForEach-Object {
                        $FQDNPath = Add-DomainFqdnToLdapPath -DirectoryPath $_.Path -ThisFqdn $ThisFqdn @LoggingParams
                        $DirectoryEntry = $null
                        Write-LogMsg @LogParams -Text "Get-DirectoryEntry -DirectoryPath '$FQDNPath'"
                        $DirectoryEntry = Get-DirectoryEntry -DirectoryPath $FQDNPath -PropertiesToLoad $PropertiesToLoad @CacheParams @LoggingParams
                        if ($DirectoryEntry) {
                            $null = $CurrentADGroupMembers.Add($DirectoryEntry)
                        }
                    }
                }

                $GroupMemberSearch |
                ForEach-Object {
                    $FQDNPath = Add-DomainFqdnToLdapPath -DirectoryPath $_.Path -ThisFqdn $ThisFqdn @LoggingParams
                    $DirectoryEntry = $null
                    Write-LogMsg @LogParams -Text "Get-DirectoryEntry -DirectoryPath '$FQDNPath'"
                    $DirectoryEntry = Get-DirectoryEntry -DirectoryPath $FQDNPath -PropertiesToLoad $PropertiesToLoad @CacheParams @LoggingParams
                    if ($DirectoryEntry) {
                        $null = $CurrentADGroupMembers.Add($DirectoryEntry)
                    }
                }

            } else {
                $CurrentADGroupMembers = $null
            }

            Write-LogMsg @LogParams -Text "$($ThisGroup.Properties.name) has $(($CurrentADGroupMembers | Measure-Object).Count) members"

            $ProcessedGroupMembers = Expand-AdsiGroupMember -DirectoryEntry $CurrentADGroupMembers -Win32AccountsBySID $Win32AccountsBySID -Win32AccountsByCaption $Win32AccountsByCaption -DomainsByFqdn $DomainsByFqdn -ThisFqdn $ThisFqdn @CacheParams @LoggingParams

            Add-Member -InputObject $ThisGroup -MemberType NoteProperty -Name FullMembers -Value $ProcessedGroupMembers -Force -PassThru

        }
    }
}
function Get-AdsiServer {
    <#
        .SYNOPSIS
        Get information about a directory server including the ADSI provider it hosts and its well-known SIDs
        .DESCRIPTION
        Uses the ADSI provider to query the server using LDAP first, then WinNT upon failure
        Uses WinRM to query the CIM class Win32_SystemAccount for well-known SIDs
        .INPUTS
        [System.String]$Fqdn
        .OUTPUTS
        [PSCustomObject] with AdsiProvider and WellKnownSIDs properties
        .EXAMPLE
        Get-AdsiServer -Fqdn localhost

        Find the ADSI provider of the local computer
        .EXAMPLE
        Get-AdsiServer -Fqdn 'ad.contoso.com'

        Find the ADSI provider of the AD domain 'ad.contoso.com'
    #>
    [OutputType([System.String])]

    param (

        # IP address or hostname of the directory server whose ADSI provider type to determine
        [Parameter(ValueFromPipeline)]
        [string[]]$Fqdn,

        # NetBIOS name of the ADSI server whose information to determine
        [string[]]$Netbios,

        # Cache of known Win32_Account instances keyed by domain and SID
        [hashtable]$Win32AccountsBySID = ([hashtable]::Synchronized(@{})),

        # Cache of known Win32_Account instances keyed by domain (e.g. CONTOSO) and Caption (NTAccount name e.g. CONTOSO\User1)
        [hashtable]$Win32AccountsByCaption = ([hashtable]::Synchronized(@{})),

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName,AdsiProvider,Win32Accounts properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $CacheParams = @{
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByFqdn       = $DomainsByFqdn
            DomainsByNetbios    = $DomainsByNetbios
            DomainsBySid        = $DomainsBySid
        }

    }
    process {
        ForEach ($DomainFqdn in $Fqdn) {
            $OutputObject = $DomainsByFqdn[$DomainFqdn]
            if ($OutputObject) {
                Write-LogMsg @LogParams -Text " # Domain FQDN cache hit for '$DomainFqdn'"
                $OutputObject
                continue
            }
            Write-LogMsg @LogParams -Text " # Domain FQDN cache miss for '$DomainFqdn'"

            Write-LogMsg @LogParams -Text "Find-AdsiProvider -AdsiServer '$DomainFqdn'"
            $AdsiProvider = Find-AdsiProvider -AdsiServer $DomainFqdn @LoggingParams
            $CacheParams['AdsiProvider'] = $AdsiProvider

            Write-LogMsg @LogParams -Text "ConvertTo-DistinguishedName -AdsiProvider '$AdsiProvider' -DomainFQDN '$DomainFqdn'"
            $DomainDn = ConvertTo-DistinguishedName -DomainFQDN $DomainFqdn -AdsiProvider $AdsiProvider @LoggingParams

            Write-LogMsg @LogParams -Text "ConvertTo-DomainSidString -AdsiProvider '$AdsiProvider' -DomainDnsName '$DomainFqdn'"
            $DomainSid = ConvertTo-DomainSidString -DomainDnsName $DomainFqdn -ThisFqdn $ThisFqdn @CacheParams @LoggingParams

            Write-LogMsg @LogParams -Text "ConvertTo-DomainNetBIOS -AdsiProvider '$AdsiProvider' -DomainFQDN '$DomainFqdn'"
            $DomainNetBIOS = ConvertTo-DomainNetBIOS -DomainFQDN $DomainFqdn @CacheParams @LoggingParams

            Write-LogMsg @LogParams -Text "Get-Win32Account -AdsiProvider '$AdsiProvider' -ComputerName '$DomainFqdn' -ThisFqdn '$ThisFqdn'"
            $Win32Accounts = Get-Win32Account -ComputerName $DomainFqdn -ThisFqdn $ThisFqdn -AdsiProvider $AdsiProvider -Win32AccountsBySID $Win32AccountsBySID -ErrorAction SilentlyContinue @LoggingParams

            ForEach ($Acct in $Win32Accounts) {
                $Win32AccountsBySID["$($Acct.Domain)\$($Acct.SID)"] = $Acct
                $Win32AccountsByCaption[$Acct.Caption] = $Acct
            }

            $OutputObject = [PSCustomObject]@{
                DistinguishedName = $DomainDn
                Dns               = $DomainFqdn
                Sid               = $DomainSid
                Netbios           = $DomainNetBIOS
                AdsiProvider      = $AdsiProvider
                Win32Accounts     = $Win32Accounts
            }
            $DomainsBySid[$OutputObject.Sid] = $OutputObject
            $DomainsByNetbios[$OutputObject.Netbios] = $OutputObject
            $DomainsByFqdn[$DomainFqdn] = $OutputObject
            $OutputObject
        }

        ForEach ($DomainNetbios in $Netbios) {
            $OutputObject = $DomainsByNetbios[$DomainNetbios]
            if ($OutputObject) {
                Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$DomainNetbios'"
                $OutputObject
                continue
            }
            Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$DomainNetbios'"

            Write-LogMsg @LogParams -Text "New-AdsiServerCimSession -ComputerName '$DomainNetBIOS'"
            $CimSession = New-AdsiServerCimSession -ComputerName $DomainNetBIOS -ThisFqdn $ThisFqdn @LoggingParams

            Write-LogMsg @LogParams -Text "Find-AdsiProvider -AdsiServer '$DomainDnsName' # for '$DomainNetbios'"
            $AdsiProvider = Find-AdsiProvider -AdsiServer $DomainDnsName @LoggingParams
            $CacheParams['AdsiProvider'] = $AdsiProvider

            Write-LogMsg @LogParams -Text "ConvertTo-DistinguishedName -Domain '$DomainNetBIOS'"
            $DomainDn = ConvertTo-DistinguishedName -Domain $DomainNetBIOS -DomainsByNetbios $DomainsByNetbios @LoggingParams

            if ($DomainDn) {
                Write-LogMsg @LogParams -Text "ConvertTo-Fqdn -DistinguishedName '$DomainDn' # for '$DomainNetbios'"
                $DomainDnsName = ConvertTo-Fqdn -DistinguishedName $DomainDn -ThisFqdn $ThisFqdn @LoggingParams
            } else {
                $ParentDomainDnsName = Get-ParentDomainDnsName -DomainsByNetbios $DomainNetBIOS -CimSession $CimSession -ThisFqdn $ThisFqdn @LoggingParams
                $DomainDnsName = "$DomainNetBIOS.$ParentDomainDnsName"
            }

            Write-LogMsg @LogParams -Text "ConvertTo-DomainSidString -DomainDnsName '$DomainFqdn' -AdsiProvider '$AdsiProvider' -ThisFqdn '$ThisFqdn' # for '$DomainNetbios'"
            $DomainSid = ConvertTo-DomainSidString -DomainDnsName $DomainDnsName -ThisFqdn $ThisFqdn @CacheParams @LoggingParams

            Write-LogMsg @LogParams -Text "Get-Win32Account -ComputerName '$DomainDnsName' -AdsiProvider '$AdsiProvider' -ThisFqdn '$ThisFqdn' # for '$DomainNetbios'"
            $Win32Accounts = Get-Win32Account -ComputerName $DomainDnsName -ThisFqdn $ThisFqdn -AdsiProvider $AdsiProvider -Win32AccountsBySID $Win32AccountsBySID -CimSession $CimSession -ErrorAction SilentlyContinue @LoggingParams

            Remove-CimSession -CimSession $CimSession

            ForEach ($Acct in $Win32Accounts) {
                $Win32AccountsBySID["$($Acct.Domain)\$($Acct.SID)"] = $Acct
                $Win32AccountsByCaption[$Acct.Caption] = $Acct
            }

            $OutputObject = [PSCustomObject]@{
                DistinguishedName = $DomainDn
                Dns               = $DomainDnsName
                Sid               = $DomainSid
                Netbios           = $DomainNetBIOS
                AdsiProvider      = $AdsiProvider
                Win32Accounts     = $Win32Accounts
            }
            $DomainsBySid[$OutputObject.Sid] = $OutputObject
            $DomainsByNetbios[$OutputObject.Netbios] = $OutputObject
            $DomainsByFqdn[$OutputObject.Dns] = $OutputObject
            $OutputObject
        }
    }
}
function Get-CurrentDomain {
    <#
        .SYNOPSIS
        Use ADSI to get the current domain
        .DESCRIPTION
        Works only on domain-joined systems, otherwise returns nothing
        .INPUTS
        None. Pipeline input is not accepted.
        .OUTPUTS
        [System.DirectoryServices.DirectoryEntry] The current domain

        .EXAMPLE
        Get-CurrentDomain

        Get the domain of the current computer
    #>
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    $Obj = [adsi]::new()
    try { $null = $Obj.RefreshCache('objectSid') } catch {
        # Assume local computer/workgroup, use CIM rather than ADSI
        # TODO: Make this more efficient.  CIM Sessions, pass in hostname via param, etc.
        $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        $AdminAccount = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount = 'True' AND SID LIKE 'S-1-5-21-%-500'"
        $Obj = [PSCustomObject]@{
            ObjectSid         = [PSCustomObject]@{
                Value = $AdminAccount.Sid.Substring(0, $AdminAccount.Sid.LastIndexOf('-')) | ConvertTo-SidByteArray
            }
            DistinguishedName = [PSCustomObject]@{
                Value = "DC=$(& HOSTNAME.EXE)"
            }
        }
    }
    return $Obj
}
function Get-DirectoryEntry {
    <#
        .SYNOPSIS
        Use Active Directory Service Interfaces to retrieve an object from a directory
        .DESCRIPTION
        Retrieve a directory entry using either the WinNT or LDAP provider for ADSI
        .INPUTS
        None. Pipeline input is not accepted.
        .OUTPUTS
        [System.DirectoryServices.DirectoryEntry] where possible
        [PSCustomObject] for security principals with no directory entry
        .EXAMPLE
        Get-DirectoryEntry
        distinguishedName : {DC=ad,DC=contoso,DC=com}
        Path              : LDAP://DC=ad,DC=contoso,DC=com

        As the current user on a domain-joined computer, bind to the current domain and retrieve the DirectoryEntry for the root of the domain
        .EXAMPLE
        Get-DirectoryEntry
        distinguishedName :
        Path              : WinNT://ComputerName

        As the current user on a workgroup computer, bind to the local system and retrieve the DirectoryEntry for the root of the directory
    #>
    [OutputType([System.DirectoryServices.DirectoryEntry], [PSCustomObject])]
    [CmdletBinding()]
    param (

        <#
        Path to the directory object to retrieve
        Defaults to the root of the current domain
        #>
        [string]$DirectoryPath = (([System.DirectoryServices.DirectorySearcher]::new()).SearchRoot.Path),

        <#
        Credentials to use to bind to the directory
        Defaults to the credentials of the current user
        #>
        [pscredential]$Credential,

        # Properties of the target object to retrieve
        [string[]]$PropertiesToLoad,

        <#
        Hashtable containing cached directory entries so they don't have to be retrieved from the directory again
        Uses a thread-safe hashtable by default
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    $LoggingParams = @{
        ThisHostname = $ThisHostname
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    $DirectoryEntry = $null
    if ($null -eq $DirectoryEntryCache[$DirectoryPath]) {
        switch -regex ($DirectoryPath) {
            <#
            The WinNT provider only throws an error if you try to retrieve certain accounts/identities
            We will create own dummy objects instead of performing the query
            #>
            '^WinNT:\/\/.*\/CREATOR OWNER$' {
                $DirectoryEntry = [FakeDirectoryEntry]::new($DirectoryPath)
            }
            '^WinNT:\/\/.*\/SYSTEM$' {
                $DirectoryEntry = [FakeDirectoryEntry]::new($DirectoryPath)
            }
            '^WinNT:\/\/.*\/INTERACTIVE$' {
                $DirectoryEntry = [FakeDirectoryEntry]::new($DirectoryPath)
            }
            '^WinNT:\/\/.*\/Authenticated Users$' {
                $DirectoryEntry = [FakeDirectoryEntry]::new($DirectoryPath)
            }
            '^WinNT:\/\/.*\/TrustedInstaller$' {
                $DirectoryEntry = [FakeDirectoryEntry]::new($DirectoryPath)
            }
            # Workgroup computers do not return a DirectoryEntry with a SearchRoot Path so this ends up being an empty string
            # This is also invoked when DirectoryPath is null for any reason
            # We will return a WinNT object representing the local computer's WinNT directory
            '^$' {
                Write-LogMsg @LogParams -Text "$ThisHostname does not appear to be domain-joined since the SearchRoot Path is empty. Defaulting to WinNT provider for localhost instead."
                $Workgroup = (Get-CimInstance -ClassName Win32_ComputerSystem).Workgroup
                $DirectoryPath = "WinNT://$Workgroup/$ThisHostname"
                Write-LogMsg @LogParams -Text "[System.DirectoryServices.DirectoryEntry]::new('$DirectoryPath')"
                if ($Credential) {
                    $DirectoryEntry = [System.DirectoryServices.DirectoryEntry]::new($DirectoryPath, $($Credential.UserName), $($Credential.GetNetworkCredential().password))
                } else {
                    $DirectoryEntry = [System.DirectoryServices.DirectoryEntry]::new($DirectoryPath)
                }

                $SampleUser = @($DirectoryEntry.PSBase.Children |
                    Where-Object -FilterScript { $_.schemaclassname -eq 'user' })[0] |
                Add-SidInfo -DomainsBySid $DomainsBySid @LoggingParams

                $DirectoryEntry |
                Add-Member -MemberType NoteProperty -Name 'Domain' -Value $SampleUser.Domain -Force

            }
            # Otherwise the DirectoryPath is an LDAP path or a WinNT path (treated the same at this stage)
            default {

                Write-LogMsg @LogParams -Text "[System.DirectoryServices.DirectoryEntry]::new('$DirectoryPath')"
                if ($Credential) {
                    $DirectoryEntry = [System.DirectoryServices.DirectoryEntry]::new($DirectoryPath, $($Credential.UserName), $($Credential.GetNetworkCredential().password))
                } else {
                    $DirectoryEntry = [System.DirectoryServices.DirectoryEntry]::new($DirectoryPath)
                }

            }

        }

        $DirectoryEntryCache[$DirectoryPath] = $DirectoryEntry
    } else {
        #Write-LogMsg @LogParams -Text "DirectoryEntryCache hit for '$DirectoryPath'"
        $DirectoryEntry = $DirectoryEntryCache[$DirectoryPath]
    }

    if ($PropertiesToLoad) {
        try {
            # If the $DirectoryPath was invalid, this line will return an error
            $null = $DirectoryEntry.RefreshCache($PropertiesToLoad)

        } catch {
            Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tGet-DirectoryEntry`t'$DirectoryPath' could not be retrieved."

            # Ensure that the error message appears on 1 line
            # Use .Trim() to remove leading and trailing whitespace
            # Use -replace to remove an errant line break in the following specific error I encountered: The following exception occurred while retrieving member "RefreshCache": "The group name could not be found.`r`n"
            Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tGet-DirectoryEntry`t'$($_.Exception.Message.Trim() -replace '\s"',' "')"
            return
        }
    }
    return $DirectoryEntry

}
function Get-ParentDomainDnsName {
    param (

        # NetBIOS name of the domain whose parent domain DNS to return
        [string]$DomainNetbios,

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages,

        # Existing CIM session to the computer (to avoid creating redundant CIM sessions)
        [CimSession]$CimSession
    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    if (-not $CimSession) {
        Write-LogMsg @LogParams -Text "New-AdsiServerCimSession -ComputerName '$DomainNetbios'"
        $CimSession = New-AdsiServerCimSession -ComputerName $DomainNetbios -ThisFqdn $ThisFqdn @LoggingParams
        $RemoveCimSession = $true
    }

    Write-LogMsg @LogParams -Text "(Get-CimInstance -CimSession `$CimSession -ClassName CIM_ComputerSystem).domain # for '$DomainNetbios'"
    $ParentDomainDnsName = (Get-CimInstance -CimSession $CimSession -ClassName CIM_ComputerSystem).domain

    if ($ParentDomainDnsName -eq 'WORKGROUP' -or $null -eq $ParentDomainDnsName) {
        # For workgroup computers there is no parent domain DNS (workgroups operate on NetBIOS)
        # There could also be unexpeted scenarios where the parent domain DNS is null
        # In all of these cases, we will use the primary DNS search suffix (that is where the OS would attempt to register DNS records for the computer)
        Write-LogMsg @LogParams -Text "(Get-DnsClientGlobalSetting -CimSession `$CimSession).SuffixSearchList[0] # for '$DomainNetbios'"
        $ParentDomainDnsName = (Get-DnsClientGlobalSetting -CimSession $CimSession).SuffixSearchList[0]
    }

    if ($RemoveCimSession) {
        Remove-CimSession -CimSession $CimSession
    }

    return $ParentDomainDnsName
}
function Get-TrustedDomain {
    <#
        .SYNOPSIS
        Returns a dictionary of trusted domains by the current computer
        .DESCRIPTION
        Works only on domain-joined systems
        Use nltest to get the domain trust relationships for the domain of the current computer
        Use ADSI's LDAP provider to get each trusted domain's DNS name, NETBIOS name, and SID
        For each trusted domain the key is the domain's SID, or its NETBIOS name if the -KeyByNetbios switch parameter was used
        For each trusted domain the value contains the details retrieved with ADSI
        .INPUTS
        None. Pipeline input is not accepted.
        .OUTPUTS
        [PSCustomObject] One object per trusted domain, each with a DomainFqdn property and a DomainNetbios property

        .EXAMPLE
        Get-TrustedDomain

        Get the trusted domains of the current computer
        .NOTES
    #>
    [OutputType([PSCustomObject])]
    param (

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        $ThisHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    # Redirect the error stream to null, errors are expected on non-domain-joined systems
    Write-LogMsg @LogParams -Text "$('& nltest /domain_trusts 2> $null')"
    #$nltestresults = & nltest /domain_trusts 2> $null
    $nltestresults = & nltest /domain_trusts 2>&1

    #$NlTestRegEx = '[\d]*: .*'
    $RegExForEachTrust = '(?<index>[\d]*): (?<netbios>\S*) (?<dns>\S*).*'
    ForEach ($Result in $nltestresults) {
        if ($Result.GetType() -eq [string]) {
            if ($Result -match $RegExForEachTrust) {
                [PSCustomObject]@{
                    DomainFqdn    = $Matches.dns
                    DomainNetbios = $Matches.netbios
                }
            }
        }
    }
}
function Get-Win32Account {
    <#
        .SYNOPSIS
        Use CIM to get well-known SIDs
        .DESCRIPTION
        Use WinRM to query the CIM namespace root/cimv2 for instances of the Win32_Account class
        .INPUTS
        [System.String]$ComputerName
        .OUTPUTS
        [Microsoft.Management.Infrastructure.CimInstance] for each instance of the Win32_Account class in the root/cimv2 namespace
        .EXAMPLE
        Get-Win32Account

        Get the well-known SIDs on the current computer
        .EXAMPLE
        Get-Win32Account -CimServerName 'server123'

        Get the well-known SIDs on the remote computer 'server123'
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    param (

        # Name or address of the computer whose Win32_Account instances to return
        [Parameter(ValueFromPipeline)]
        [string[]]$ComputerName,

        # Cache of known Win32_Account instances keyed by domain and SID
        [hashtable]$Win32AccountsBySID = ([hashtable]::Synchronized(@{})),

        # Cache of known Win32_Account instances keyed by domain (e.g. CONTOSO) and Caption (NTAccount name e.g. CONTOSO\User1)
        [hashtable]$Win32AccountsByCaption = ([hashtable]::Synchronized(@{})),

        # Cache of known directory servers to reduce duplicate queries
        [hashtable]$AdsiServersByDns = [hashtable]::Synchronized(@{}),

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        <#
        AdsiProvider (WinNT or LDAP) of the servers associated with the provided FQDNs or NetBIOS names

        This parameter can be used to reduce calls to Find-AdsiProvider

        Useful when that has been done already but the DomainsByFqdn and DomainsByNetbios caches have not been updated yet
        #>
        [string]$AdsiProvider,

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages,

        # Existing CIM session to the computer (to avoid creating redundant CIM sessions)
        [CimSession]$CimSession

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $AdsiServersWhoseWin32AccountsExistInCache = $Win32AccountsBySID.Keys |
        ForEach-Object { ($_ -split '\\')[0] } |
        Sort-Object -Unique
    }
    process {
        ForEach ($ThisServer in $ComputerName) {
            if (
                $ThisServer -eq 'localhost' -or
                $ThisServer -eq '127.0.0.1' -or
                [string]::IsNullOrEmpty($ThisServer)
            ) {
                $ThisServer = $ThisHostName
            }
            if (-not $PSBoundParameters.ContainsKey('AdsiProvider')) {
                $AdsiProvider = Find-AdsiProvider -AdsiServer $ThisServer @LoggingParams
            }
            # Return matching objects from the cache if possible rather than performing a CIM query
            # The cache is based on the Caption of the Win32 accounts which conatins only NetBios names
            if ($AdsiServersWhoseWin32AccountsExistInCache -contains $ThisServer) {
                $Win32AccountsBySID.Keys |
                ForEach-Object {
                    if ($_ -like "$ThisServer\*") {
                        $Win32AccountsBySID[$_]
                    }
                }
            } else {

                if (-not $CimSession) {
                    Write-LogMsg @LogParams -Text "New-AdsiServerCimSession -ComputerName '$ThisServer'"
                    $CimSession = New-AdsiServerCimSession -ComputerName $ThisServer -ThisFqdn $ThisFqdn @LoggingParams
                    $RemoveCimSession = $true
                }

                Write-LogMsg @LogParams -Text "Get-CimInstance -ClassName Win32_Account -CimSession `$CimSession # For '$ThisServer'"
                Get-CimInstance -ClassName Win32_Account -CimSession $CimSession

                if ($RemoveCimSession) {
                    Remove-CimSession -CimSession $CimSession
                }

            }
        }
    }
}
function Get-Win32UserAccount {
    param (
        [string]$ComputerName,

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages
    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    if (
        $ComputerName -eq $ThisHostname -or
        $ComputerName -eq "$ThisHostname." -or
        $ComputerName -eq $ThisFqdn
    ) {
        Write-LogMsg @LogParams -Text "Get-CimInstance -Query `"SELECT SID FROM Win32_UserAccount WHERE LocalAccount = 'True'`""
        Get-CimInstance -Query "SELECT SID FROM Win32_UserAccount WHERE LocalAccount = 'True'"
    } else {
        Write-LogMsg @LogParams -Text "Get-CimInstance -ComputerName $ComputerName -Query `"SELECT SID FROM Win32_UserAccount WHERE LocalAccount = 'True'`""
        # If an Active Directory domain is targeted there are no local accounts and CIM connectivity is not expected
        # Suppress errors and return nothing in that case
        Get-CimInstance -ComputerName $ComputerName -Query "SELECT SID FROM Win32_UserAccount WHERE LocalAccount = 'True'" -ErrorAction SilentlyContinue
    }
}
function Get-WinNTGroupMember {
    <#
        .SYNOPSIS
        Get members of a group from the WinNT provider
        .DESCRIPTION
        Get members of a group from the WinNT provider
        Convert them from COM objects into usable DirectoryEntry objects
        .INPUTS
        [System.DirectoryServices.DirectoryEntry]$DirectoryEntry
        .OUTPUTS
        [System.DirectoryServices.DirectoryEntry] for each group member
        .EXAMPLE
        [System.DirectoryServices.DirectoryEntry]::new('WinNT://localhost/Administrators') | Get-WinNTGroupMember

        Get members of the local Administrators group
    #>
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param (

        # DirectoryEntry [System.DirectoryServices.DirectoryEntry] of the WinNT group whose members to get
        [Parameter(ValueFromPipeline)]
        $DirectoryEntry,

        # Properties of the group members to find in the directory
        [string[]]$PropertiesToLoad,

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $PropertiesToLoad += 'Department',
        'description',
        'distinguishedName',
        'grouptype',
        'managedby',
        'member',
        'name',
        'objectClass',
        'objectSid',
        'operatingSystem',
        'primaryGroupToken',
        'samAccountName',
        'Title'

        $PropertiesToLoad = $PropertiesToLoad |
        Sort-Object -Unique

    }
    process {
        ForEach ($ThisDirEntry in $DirectoryEntry) {
            $SourceDomain = $ThisDirEntry.Path | Split-Path -Parent | Split-Path -Leaf
            # Retrieve the members of local groups
            if ($null -ne $ThisDirEntry.Properties['groupType'] -or $ThisDirEntry.schemaclassname -eq 'group') {
                # Assembly: System.DirectoryServices.dll
                # Namespace: System.DirectoryServices
                # DirectoryEntry.Invoke(String, Object[]) Method
                # Calls a method on the native Active Directory Domain Services object
                # https://docs.microsoft.com/en-us/dotnet/api/system.directoryservices.directoryentry.invoke?view=dotnet-plat-ext-6.0

                # I am using it to call the IADsGroup::Members method
                # The IADsGroup programming interface is part of the iads.h header
                # The iads.h header is part of the ADSI component of the Win32 API
                # The IADsGroup::Members method retrieves a collection of the immediate members of the group.
                # The collection does not include the members of other groups that are nested within the group.
                # The default implementation of this method uses LsaLookupSids to query name information for the group members.
                # LsaLookupSids has a maximum limitation of 20480 SIDs it can convert, therefore that limitation also applies to this method.
                # Returns a pointer to an IADsMembers interface pointer that receives the collection of group members. The caller must release this interface when it is no longer required.
                # https://docs.microsoft.com/en-us/windows/win32/api/iads/nf-iads-iadsgroup-members
                # The IADsMembers::Members method would use the same provider but I have chosen not to implement that here
                # Recursion through nested groups can be handled outside of Get-WinNTGroupMember for now
                # Maybe that could be a feature in the future
                # https://docs.microsoft.com/en-us/windows/win32/adsi/adsi-object-model-for-winnt-providers?redirectedfrom=MSDN
                $DirectoryMembers = & { $ThisDirEntry.Invoke('Members') } 2>$null
                Write-LogMsg @LogParams -Text " # '$($ThisDirEntry.Path)' has $(($DirectoryMembers | Measure-Object).Count) members # For $($ThisDirEntry.Path)"
                $MembersToGet = @{
                    'WinNTMembers' = @()
                }
                $MemberParams = @{
                    DirectoryEntryCache = $DirectoryEntryCache
                    PropertiesToLoad    = $PropertiesToLoad
                    DomainsByNetbios    = $DomainsByNetbios
                    LogMsgCache         = $LogMsgCache
                    WhoAmI              = $WhoAmI
                }
                ForEach ($DirectoryMember in $DirectoryMembers) {
                    # The IADsGroup::Members method returns ComObjects
                    # But proper .Net objects are much easier to work with
                    # So we will convert the ComObjects into DirectoryEntry objects
                    $DirectoryPath = Invoke-ComObject -ComObject $DirectoryMember -Property 'ADsPath'
                    $MemberDomainDn = $null
                    if ($DirectoryPath -match 'WinNT:\/\/(?<Domain>[^\/]*)\/(?<Acct>.*$)') {
                        Write-LogMsg @LogParams -Text " # '$DirectoryPath' has a domain of '$($Matches.Domain)' and an account name of '$($Matches.Acct)'"
                        $MemberName = $Matches.Acct
                        $MemberDomainNetbios = $Matches.Domain

                        $DomainCacheResult = $DomainsByNetbios[$MemberDomainNetbios]
                        if ($DomainCacheResult) {
                            Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$MemberDomainNetBios'"
                            if ( "WinNT:\\$MemberDomainNetbios" -ne $SourceDomain ) {
                                $MemberDomainDn = $DomainCacheResult.DistinguishedName
                            }
                        } else {
                            Write-LogMsg @LogParams -Text " # Domain NetBIOS cache miss for '$MemberDomainNetBios'. Available keys: $($DomainsByNetBios.Keys -join ',')"
                        }
                        if ($DirectoryPath -match 'WinNT:\/\/(?<Domain>[^\/]*)\/(?<Middle>[^\/]*)\/(?<Acct>.*$)') {
                            Write-LogMsg @LogParams -Text " # '$DirectoryPath' is named '$($Matches.Acct)' and is on ADSI server '$($Matches.Middle)' joined to the domain '$($Matches.Domain)'"
                            if ($Matches.Middle -eq ($ThisDirEntry.Path | Split-Path -Parent | Split-Path -Leaf)) {
                                $MemberDomainDn = $null
                            }
                        }
                    } else {
                        Write-LogMsg @LogParams -Text " # '$DirectoryPath' does not match 'WinNT:\/\/(?<Domain>[^\/]*)\/(?<Acct>.*$)'"
                    }

                    # LDAP directories have a distinguishedName
                    if ($MemberDomainDn) {
                        # LDAP directories support searching
                        # Combine all members' samAccountNames into a single search per directory distinguishedName
                        # Use a hashtable with the directory path as the key and a string as the definition
                        # The string is a partial LDAP filter, just the segments of the LDAP filter for each samAccountName
                        Write-LogMsg @LogParams -Text " # '$MemberName' is a domain security principal"
                        $MembersToGet["LDAP://$MemberDomainDn"] += "(samaccountname=$MemberName)"
                        ##$MemberParams['DirectoryPath'] = "LDAP://$MemberDomainDn"
                        ##$MemberParams['Filter'] = "(samaccountname=$MemberName)"
                        ##$MemberDirectoryEntry = Search-Directory @MemberParams
                    } else {
                        # WinNT directories do not support searching so we will retrieve each member individually
                        # Use a hashtable with 'WinNTMembers' as the key and an array of WinNT directory paths as the value
                        Write-LogMsg @LogParams -Text " # '$DirectoryPath' is a local security principal"
                        $MembersToGet['WinNTMembers'] += $DirectoryPath
                        ##$MemberDirectoryEntry = Get-DirectoryEntry @MemberParams
                    }

                    ##Expand-WinNTGroupMember -DirectoryEntry $MemberDirectoryEntry -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams

                }

                # Get and Expand the directory entries for the WinNT group members
                $MembersToGet['WinNTMembers'] |
                ForEach-Object {
                    $MemberParams['DirectoryPath'] = $_
                    Write-LogMsg @LogParams -Text "Get-DirectoryEntry -DirectoryPath '$DirectoryPath'"
                    $MemberDirectoryEntry = Get-DirectoryEntry @MemberParams
                    Expand-WinNTGroupMember -DirectoryEntry $MemberDirectoryEntry -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                }

                # Remove the WinNTMembers key from the hashtable so the only remaining keys are distinguishedName(s) of LDAP directories
                $MembersToGet.Remove('WinNTMembers')

                # Get and Expand the directory entries for the LDAP group members
                $MembersToGet.Keys |
                ForEach-Object {
                    $MemberParams['DirectoryPath'] = $_
                    $MemberParams['Filter'] = "(|$($MembersToGet[$_]))"
                    $MemberDirectoryEntries = Search-Directory @MemberParams
                    Expand-WinNTGroupMember -DirectoryEntry $MemberDirectoryEntries -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                }
            } else {
                Write-LogMsg @LogParams -Text " # '$($ThisDirEntry.Path)' is not a group"
            }
        }
    }

}
function Invoke-ComObject {
    <#
        .SYNOPSIS
        Invoke a member method of a ComObject [__ComObject]
        .DESCRIPTION
        Use the InvokeMember method to invoke the InvokeMethod or GetProperty or SetProperty methods
        By default, invokes the GetProperty method for the specified Property
        If the Value parameter is specified, invokes the SetProperty method for the specified Property
        If the Method switch is specified, invokes the InvokeMethod method
        .INPUTS
        None. Pipeline input is not accepted.
        .OUTPUTS
        The output of the invoked method is returned directly
        .EXAMPLE
        $ComObject = [System.DirectoryServices.DirectoryEntry]::new('WinNT://localhost/Administrators').Invoke('Members') | Select -First 1
        Invoke-ComObject -ComObject $ComObject -Property AdsPath

        Get the first member of the local Administrators group on the current computer
        Then use Invoke-ComObject to invoke the GetProperty method and return the value of the AdsPath property
    #>
    param (

        # The ComObject whose member method to invoke
        [Parameter(Mandatory)]
        $ComObject,

        # The property to use with the invoked method
        [Parameter(Mandatory)]
        [String]$Property,

        # The value to set with the SetProperty method, or the name of the method to run with the InvokeMethod method
        $Value,

        # Use the InvokeMethod method of the ComObject
        [Switch]$Method

    )
    <#
    # Don't remember what this is for
    If ($ComObject -IsNot "__ComObject") {
        If (!$ComInvoke) {
            $Global:ComInvoke = @{}
        }
        If (!$ComInvoke.$ComObject) {
            $ComInvoke.$ComObject = New-Object -ComObject $ComObject
        }
        $ComObject = $ComInvoke.$ComObject
    }
    #>
    If ($Method) {
        $Invoke = "InvokeMethod"
    } ElseIf ($MyInvocation.BoundParameters.ContainsKey("Value")) {
        $Invoke = "SetProperty"
    } Else {
        $Invoke = "GetProperty"
    }
    [__ComObject].InvokeMember($Property, $Invoke, $Null, $ComObject, $Value)
}
function New-AdsiServerCimSession {
    param (

        # Name of the computer to start a CIM session on
        [string]$ComputerName,

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages
    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }


    if (
        $ComputerName -eq $ThisHostName -or
        $ComputerName -eq 'localhost' -or
        $ComputerName -eq '127.0.0.1' -or
        $ComputerName -eq $ThisFqdn -or
        [string]::IsNullOrEmpty($ComputerName)
    ) {
        Write-LogMsg @LogParams -Text "`$CimSession = New-CimSession # for '$ComputerName'"
        New-CimSession
    } else {
        Write-LogMsg @LogParams -Text "`$CimSession = New-CimSession -ComputerName '$ComputerName'"
        New-CimSession -ComputerName $ComputerName
    }

}
function Resolve-Ace {
    <#
        .SYNOPSIS
        Use ADSI to lookup info about IdentityReferences from Authorization Rule Collections that came from Discretionary Access Control Lists
        .DESCRIPTION
        Based on the IdentityReference proprety of each Access Control Entry:
        Resolve SID to NT account name and vise-versa
        Resolve well-known SIDs
        Resolve generic defaults like 'NT AUTHORITY' and 'BUILTIN' to the applicable computer or domain name
        Add these properties (IdentityReferenceSID,IdentityReferenceName,IdentityReferenceResolved) to the object and return it
        .INPUTS
        [System.Security.AccessControl.AuthorizationRuleCollection]$InputObject
        .OUTPUTS
        [PSCustomObject] Original object plus IdentityReferenceSID,IdentityReferenceName,IdentityReferenceResolved, and AdsiProvider properties
        .EXAMPLE
        Get-Acl |
        Expand-Acl |
        Resolve-Ace

        Use Get-Acl from the Microsoft.PowerShell.Security module as the source of the access list
        This works in either Windows Powershell or in Powershell
        Get-Acl does not support long paths (>256 characters)
        That was why I originally used the .Net Framework method
        .EXAMPLE
        Get-FolderAce -LiteralPath C:\Test -IncludeInherited |
        Resolve-Ace
        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        $Sections = [System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner
        $FileSecurity = [System.Security.AccessControl.FileSecurity]::new($DirectoryInfo,$Sections)
        $IncludeExplicitRules = $true
        $IncludeInheritedRules = $true
        $AccountType = [System.Security.Principal.SecurityIdentifier]
        $FileSecurity.GetAccessRules($IncludeExplicitRules,$IncludeInheritedRules,$AccountType) |
        Resolve-Ace

        This uses .Net Core as the source of the access list
        It uses the GetAccessRules method on the [System.Security.AccessControl.FileSecurity] class
        The targetType parameter of the method is used to specify that the accounts in the ACL are returned as SIDs
        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        $Sections = [System.Security.AccessControl.AccessControlSections]::Access -bor
        [System.Security.AccessControl.AccessControlSections]::Owner -bor
        [System.Security.AccessControl.AccessControlSections]::Group
        $DirectorySecurity = [System.Security.AccessControl.DirectorySecurity]::new($DirectoryInfo,$Sections)
        $IncludeExplicitRules = $true
        $IncludeInheritedRules = $true
        $AccountType = [System.Security.Principal.NTAccount]
        $FileSecurity.GetAccessRules($IncludeExplicitRules,$IncludeInheritedRules,$AccountType) |
        Resolve-Ace

        This uses .Net Core as the source of the access list
        It uses the GetAccessRules method on the [System.Security.AccessControl.FileSecurity] class
        The targetType parameter of the method is used to specify that the accounts in the ACL are returned as NT account names (DOMAIN\User)
        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        [System.Security.AccessControl.DirectorySecurity]$DirectorySecurity = $DirectoryInfo.GetAccessControl('Access')
        [System.Security.AccessControl.AuthorizationRuleCollection]$AuthRules = $DirectorySecurity.Access
        $AuthRules | Resolve-Ace

        Use the .Net Framework (or legacy .Net Core up to 2.2) as the source of the access list
        Only works in Windows PowerShell
        Those versions of .Net had a GetAccessControl method on the [System.IO.DirectoryInfo] class
        This method is removed in modern versions of .Net Core

        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        $Sections = [System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner
        $FileSecurity = [System.IO.FileSystemAclExtensions]::GetAccessControl($DirectoryInfo,$Sections)

        The [System.IO.FileSystemAclExtensions] class is a Windows-specific implementation
        It provides no known benefit over the cross-platform equivalent [System.Security.AccessControl.FileSecurity]

        .NOTES
        Dependencies:
            Get-DirectoryEntry
            Add-SidInfo
            Get-TrustedDomain
            Find-AdsiProvider

        if ($FolderPath.Length -gt 255) {
            $FolderPath = "\\?\$FolderPath"
        }
    #>
    [OutputType([PSCustomObject])]
    param (

        # Authorization Rule Collection of Access Control Entries from Discretionary Access Control Lists
        [Parameter(
            ValueFromPipeline
        )]
        [PSObject[]]$InputObject,

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        [hashtable]$Win32AccountsBySID = ([hashtable]::Synchronized(@{})),

        [hashtable]$Win32AccountsByCaption = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

    }

    process {

        $ACEPropertyNames = (Get-Member -InputObject $InputObject[0] -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
        ForEach ($ThisACE in $InputObject) {

            $IdentityReference = $ThisACE.IdentityReference.ToString()

            if ([string]::IsNullOrEmpty($IdentityReference)) {
                continue
            }

            $ThisServerDns = $null
            $DomainNetBios = $null

            # Remove the PsProvider prefix from the path string
            if (-not [string]::IsNullOrEmpty($ThisACE.SourceAccessList.Path)) {
                $LiteralPath = $ThisACE.SourceAccessList.Path -replace [regex]::escape("$($ThisACE.SourceAccessList.PsProvider)::"), ''
            } else {
                $LiteralPath = $LiteralPath -replace [regex]::escape("$($ThisACE.SourceAccessList.PsProvider)::"), ''
            }

            switch -Wildcard ($IdentityReference) {
                "S-1-*" {
                    # IdentityReference is a SID (Revision 1)
                    Write-LogMsg @LogParams -Text "'$IdentityReference'.LastIndexOf('-')"
                    $IndexOfLastHyphen = $IdentityReference.LastIndexOf("-")
                    Write-LogMsg @LogParams -Text "'$IdentityReference'.Substring(0, $IndexOfLastHyphen)"
                    $DomainSid = $IdentityReference.Substring(0, $IndexOfLastHyphen)
                    if ($DomainSid) {
                        $DomainCacheResult = $DomainsBySID[$DomainSid]
                        if ($DomainCacheResult) {
                            Write-LogMsg @LogParams -Text " # Domain SID cache hit for '$DomainSid' for '$IdentityReference'"
                            $ThisServerDns = $DomainCacheResult.Dns
                            $DomainNetBios = $DomainCacheResult.Netbios
                        } else {
                            Write-LogMsg @LogParams -Text " # Domain SID cache miss for '$DomainSid' for '$IdentityReference'"
                        }
                    }
                }
                "NT SERVICE\*" {
                    $ThisServerDns = Find-ServerNameInPath -LiteralPath $LiteralPath
                }
                "BUILTIN\*" {
                    $ThisServerDns = Find-ServerNameInPath -LiteralPath $LiteralPath
                }
                "NT AUTHORITY\*" {
                    $ThisServerDns = Find-ServerNameInPath -LiteralPath $LiteralPath
                }
                default {
                    $DomainNetBios = ($IdentityReference -split '\\')[0]
                    if ($DomainNetBios) {
                        $ThisServerDns = $DomainsByNetbios[$DomainNetBios].Dns #Doesn't work for BUILTIN, etc.
                    }
                    if (-not $ThisServerDns) {
                        $ThisServerDn = ConvertTo-DistinguishedName -Domain $DomainNetBios -DomainsByNetbios $DomainsByNetbios @LoggingParams
                        $ThisServerDns = ConvertTo-Fqdn -DistinguishedName $ThisServerDn -ThisFqdn $ThisFqdn @LoggingParams
                    }
                }
            }

            if (-not $ThisServerDns) {
                # Bug: I think this will report incorrectly for a remote domain not in the cache (trust broken or something)
                $ThisServerDns = Find-ServerNameInPath -LiteralPath $LiteralPath
            }
            Write-LogMsg @LogParams -Text " # Domain FQDN is '$ThisServerDns' for '$IdentityReference'"

            $GetAdsiServerParams = @{
                Fqdn                   = $ThisServerDns
                Win32AccountsBySID     = $Win32AccountsBySID
                Win32AccountsByCaption = $Win32AccountsByCaption
                DirectoryEntryCache    = $DirectoryEntryCache
                DomainsByFqdn          = $DomainsByFqdn
                DomainsByNetbios       = $DomainsByNetbios
                DomainsBySid           = $DomainsBySid
                ThisHostName           = $ThisHostName
                ThisFqdn               = $ThisFqdn
                LogMsgCache            = $LogMsgCache
                WhoAmI                 = $WhoAmI
            }
            $AdsiServer = Get-AdsiServer @GetAdsiServerParams
            Write-LogMsg @LogParams -Text " # ADSI server is '$($AdsiServer.AdsiProvider)://$($AdsiServer.Dns)' for '$IdentityReference'"

            if ([string]$DomainNetBios -eq '') {
                $DomainNetBios = $AdsiServer.Netbios
            }

            Write-LogMsg @LogParams -Text " # Domain NetBIOS is '$DomainNetBios' for '$IdentityReference'"

            <#
            $AdsiProvider = $null
            if (-not $DomainNetBios) {
                $DomainCacheResult = $DomainsByFqdn[$ThisServerDns]
                if ($DomainCacheResult) {
                    Write-LogMsg @LogParams -Text " # Domain FQDN cache hit for '$ThisServerDns'"
                    $DomainNetBios = $DomainCacheResult.Netbios
                    $AdsiProvider = $DomainCacheResult.AdsiProvider
                } else {
                    Write-LogMsg @LogParams -Text " # Domain FQDN cache miss for '$ThisServerDns'"
                }
            }

            if (-not $DomainNetBios) {
                if (-not $AdsiProvider) {
                    $AdsiProvider = Find-AdsiProvider -AdsiServer $ThisServerDns
                }
                $DomainNetBios = ConvertTo-DomainNetBIOS -DomainFQDN $ThisServerDns -AdsiProvider $AdsiProvider -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid
            }
            #>

            $ResolveIdentityReferenceParams = @{
                IdentityReference      = $IdentityReference
                AdsiServer             = $AdsiServer
                Win32AccountsBySID     = $Win32AccountsBySID
                Win32AccountsByCaption = $Win32AccountsByCaption
                DirectoryEntryCache    = $DirectoryEntryCache
                DomainsBySID           = $DomainsBySID
                DomainsByNetbios       = $DomainsByNetbios
                DomainsByFqdn          = $DomainsByFqdn
                ThisHostName           = $ThisHostName
                ThisFqdn               = $ThisFqdn
                LogMsgCache            = $LogMsgCache
                WhoAmI                 = $WhoAmI
            }
            Write-LogMsg @LogParams -Text "Resolve-IdentityReference -IdentityReference '$IdentityReference'..."
            $ResolvedIdentityReference = Resolve-IdentityReference @ResolveIdentityReferenceParams

            # not sure if I should add a param to offer DNS instead of NetBIOS

            $ObjectProperties = @{
                AdsiProvider              = $AdsiServer.AdsiProvider
                AdsiServer                = $AdsiServer.Dns
                IdentityReferenceSID      = $ResolvedIdentityReference.SIDString
                IdentityReferenceName     = $ResolvedIdentityReference.IdentityReferenceUnresolved
                IdentityReferenceResolved = $ResolvedIdentityReference.IdentityReferenceNetBios
            }
            ForEach ($ThisProperty in $ACEPropertyNames) {
                $ObjectProperties[$ThisProperty] = $ThisACE.$ThisProperty
            }
            [PSCustomObject]$ObjectProperties

        }

    }

}
function Resolve-Ace3 {
    <#
        .SYNOPSIS
        Use ADSI to lookup info about IdentityReferences from Authorization Rule Collections that came from Discretionary Access Control Lists
        .DESCRIPTION
        Based on the IdentityReference proprety of each Access Control Entry:
        Resolve SID to NT account name and vise-versa
        Resolve well-known SIDs
        Resolve generic defaults like 'NT AUTHORITY' and 'BUILTIN' to the applicable computer or domain name
        Add these properties (IdentityReferenceSID,IdentityReferenceName,IdentityReferenceResolved) to the object and return it
        .INPUTS
        [System.Security.AccessControl.AuthorizationRuleCollection]$InputObject
        .OUTPUTS
        [PSCustomObject] Original object plus IdentityReferenceSID,IdentityReferenceName,IdentityReferenceResolved, and AdsiProvider properties
        .EXAMPLE
        Get-Acl |
        Expand-Acl |
        Resolve-Ace

        Use Get-Acl from the Microsoft.PowerShell.Security module as the source of the access list
        This works in either Windows Powershell or in Powershell
        Get-Acl does not support long paths (>256 characters)
        That was why I originally used the .Net Framework method
        .EXAMPLE
        Get-FolderAce -LiteralPath C:\Test -IncludeInherited |
        Resolve-Ace
        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        $Sections = [System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner
        $FileSecurity = [System.Security.AccessControl.FileSecurity]::new($DirectoryInfo,$Sections)
        $IncludeExplicitRules = $true
        $IncludeInheritedRules = $true
        $AccountType = [System.Security.Principal.SecurityIdentifier]
        $FileSecurity.GetAccessRules($IncludeExplicitRules,$IncludeInheritedRules,$AccountType) |
        Resolve-Ace

        This uses .Net Core as the source of the access list
        It uses the GetAccessRules method on the [System.Security.AccessControl.FileSecurity] class
        The targetType parameter of the method is used to specify that the accounts in the ACL are returned as SIDs
        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        $Sections = [System.Security.AccessControl.AccessControlSections]::Access -bor
        [System.Security.AccessControl.AccessControlSections]::Owner -bor
        [System.Security.AccessControl.AccessControlSections]::Group
        $DirectorySecurity = [System.Security.AccessControl.DirectorySecurity]::new($DirectoryInfo,$Sections)
        $IncludeExplicitRules = $true
        $IncludeInheritedRules = $true
        $AccountType = [System.Security.Principal.NTAccount]
        $FileSecurity.GetAccessRules($IncludeExplicitRules,$IncludeInheritedRules,$AccountType) |
        Resolve-Ace

        This uses .Net Core as the source of the access list
        It uses the GetAccessRules method on the [System.Security.AccessControl.FileSecurity] class
        The targetType parameter of the method is used to specify that the accounts in the ACL are returned as NT account names (DOMAIN\User)
        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        [System.Security.AccessControl.DirectorySecurity]$DirectorySecurity = $DirectoryInfo.GetAccessControl('Access')
        [System.Security.AccessControl.AuthorizationRuleCollection]$AuthRules = $DirectorySecurity.Access
        $AuthRules | Resolve-Ace

        Use the .Net Framework (or legacy .Net Core up to 2.2) as the source of the access list
        Only works in Windows PowerShell
        Those versions of .Net had a GetAccessControl method on the [System.IO.DirectoryInfo] class
        This method is removed in modern versions of .Net Core

        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        $Sections = [System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner
        $FileSecurity = [System.IO.FileSystemAclExtensions]::GetAccessControl($DirectoryInfo,$Sections)

        The [System.IO.FileSystemAclExtensions] class is a Windows-specific implementation
        It provides no known benefit over the cross-platform equivalent [System.Security.AccessControl.FileSecurity]

        .NOTES
        Dependencies:
            Get-DirectoryEntry
            Add-SidInfo
            Get-TrustedDomain
            Find-AdsiProvider

        if ($FolderPath.Length -gt 255) {
            $FolderPath = "\\?\$FolderPath"
        }
    #>
    [OutputType([PSCustomObject])]
    param (

        # Authorization Rule Collection of Access Control Entries from Discretionary Access Control Lists
        [Parameter(
            ValueFromPipeline
        )]
        [PSObject[]]$InputObject,

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        [hashtable]$Win32AccountsBySID = ([hashtable]::Synchronized(@{})),

        [hashtable]$Win32AccountsByCaption = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }

    }

    process {

        $ACEPropertyNames = (Get-Member -InputObject $InputObject[0] -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
        ForEach ($ThisACE in $InputObject) {

            $IdentityReference = $ThisACE.IdentityReference.ToString()

            if ([string]::IsNullOrEmpty($IdentityReference)) {
                continue
            }

            $ThisServerDns = $null
            $DomainNetBios = $null

            # Remove the PsProvider prefix from the path string
            if (-not [string]::IsNullOrEmpty($ThisACE.SourceAccessList.Path)) {
                $LiteralPath = $ThisACE.SourceAccessList.Path -replace [regex]::escape("$($ThisACE.SourceAccessList.PsProvider)::"), ''
            } else {
                $LiteralPath = $LiteralPath -replace [regex]::escape("$($ThisACE.SourceAccessList.PsProvider)::"), ''
            }

            switch -Wildcard ($IdentityReference) {
                "S-1-*" {
                    # IdentityReference is a SID (Revision 1)
                    Write-LogMsg @LogParams -Text "'$IdentityReference'.LastIndexOf('-')"
                    $IndexOfLastHyphen = $IdentityReference.LastIndexOf("-")
                    Write-LogMsg @LogParams -Text "'$IdentityReference'.Substring(0, $IndexOfLastHyphen)"
                    $DomainSid = $IdentityReference.Substring(0, $IndexOfLastHyphen)
                    if ($DomainSid) {
                        $DomainCacheResult = $DomainsBySID[$DomainSid]
                        if ($DomainCacheResult) {
                            Write-LogMsg @LogParams -Text " # Domain SID cache hit for '$DomainSid' for '$IdentityReference'"
                            $ThisServerDns = $DomainCacheResult.Dns
                            $DomainNetBios = $DomainCacheResult.Netbios
                        } else {
                            Write-LogMsg @LogParams -Text " # Domain SID cache miss for '$DomainSid' for '$IdentityReference'"
                        }
                    }
                }
                "NT SERVICE\*" {
                    $ThisServerDns = Find-ServerNameInPath -LiteralPath $LiteralPath
                }
                "BUILTIN\*" {
                    $ThisServerDns = Find-ServerNameInPath -LiteralPath $LiteralPath
                }
                "NT AUTHORITY\*" {
                    $ThisServerDns = Find-ServerNameInPath -LiteralPath $LiteralPath
                }
                default {
                    $DomainNetBios = ($IdentityReference -split '\\')[0]
                    if ($DomainNetBios) {
                        $ThisServerDns = $DomainsByNetbios[$DomainNetBios].Dns #Doesn't work for BUILTIN, etc.
                    }
                    if (-not $ThisServerDns) {
                        $ThisServerDn = ConvertTo-DistinguishedName -Domain $DomainNetBios -DomainsByNetbios $DomainsByNetbios @LoggingParams
                        $ThisServerDns = ConvertTo-Fqdn -DistinguishedName $ThisServerDn -ThisFqdn $ThisFqdn @LoggingParams
                    }
                }
            }

            if (-not $ThisServerDns) {
                # Bug: I think this will report incorrectly for a remote domain not in the cache (trust broken or something)
                $ThisServerDns = Find-ServerNameInPath -LiteralPath $LiteralPath
            }
            Write-LogMsg @LogParams -Text " # Domain FQDN is '$ThisServerDns' for '$IdentityReference'"

            $GetAdsiServerParams = @{
                Fqdn                   = $ThisServerDns
                Win32AccountsBySID     = $Win32AccountsBySID
                Win32AccountsByCaption = $Win32AccountsByCaption
                DirectoryEntryCache    = $DirectoryEntryCache
                DomainsByFqdn          = $DomainsByFqdn
                DomainsByNetbios       = $DomainsByNetbios
                DomainsBySid           = $DomainsBySid
                ThisHostName           = $ThisHostName
                ThisFqdn               = $ThisFqdn
                LogMsgCache            = $LogMsgCache
                WhoAmI                 = $WhoAmI
            }
            $AdsiServer = Get-AdsiServer @GetAdsiServerParams
            Write-LogMsg @LogParams -Text " # ADSI server is '$($AdsiServer.AdsiProvider)://$($AdsiServer.Dns)' for '$IdentityReference'"

            if ([string]$DomainNetBios -eq '') {
                $DomainNetBios = $AdsiServer.Netbios
            }

            Write-LogMsg @LogParams -Text " # Domain NetBIOS is '$DomainNetBios' for '$IdentityReference'"

            <#
            $AdsiProvider = $null
            if (-not $DomainNetBios) {
                $DomainCacheResult = $DomainsByFqdn[$ThisServerDns]
                if ($DomainCacheResult) {
                    Write-LogMsg @LogParams -Text " # Domain FQDN cache hit for '$ThisServerDns'"
                    $DomainNetBios = $DomainCacheResult.Netbios
                    $AdsiProvider = $DomainCacheResult.AdsiProvider
                } else {
                    Write-LogMsg @LogParams -Text " # Domain FQDN cache miss for '$ThisServerDns'"
                }
            }

            if (-not $DomainNetBios) {
                if (-not $AdsiProvider) {
                    $AdsiProvider = Find-AdsiProvider -AdsiServer $ThisServerDns
                }
                $DomainNetBios = ConvertTo-DomainNetBIOS -DomainFQDN $ThisServerDns -AdsiProvider $AdsiProvider -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid
            }
            #>

            $ResolveIdentityReferenceParams = @{
                IdentityReference      = $IdentityReference
                AdsiServer             = $AdsiServer
                Win32AccountsBySID     = $Win32AccountsBySID
                Win32AccountsByCaption = $Win32AccountsByCaption
                DirectoryEntryCache    = $DirectoryEntryCache
                DomainsBySID           = $DomainsBySID
                DomainsByNetbios       = $DomainsByNetbios
                DomainsByFqdn          = $DomainsByFqdn
                ThisHostName           = $ThisHostName
                ThisFqdn               = $ThisFqdn
                LogMsgCache            = $LogMsgCache
                WhoAmI                 = $WhoAmI
            }
            Write-LogMsg @LogParams -Text "Resolve-IdentityReference -IdentityReference '$IdentityReference'..."
            $ResolvedIdentityReference = Resolve-IdentityReference @ResolveIdentityReferenceParams

            # not sure if I should add a param to offer DNS instead of NetBIOS

            $ObjectProperties = @{
                AdsiProvider              = $AdsiServer.AdsiProvider
                AdsiServer                = $AdsiServer.Dns
                IdentityReferenceSID      = $ResolvedIdentityReference.SIDString
                IdentityReferenceName     = $ResolvedIdentityReference.IdentityReferenceUnresolved
                IdentityReferenceResolved = $ResolvedIdentityReference.IdentityReferenceNetBios
            }
            ForEach ($ThisProperty in $ACEPropertyNames) {
                $ObjectProperties[$ThisProperty] = $ThisACE.$ThisProperty
            }
            [PSCustomObject]$ObjectProperties

        }

    }

}

function Resolve-Ace4 {
    <#
        .SYNOPSIS
        Use ADSI to lookup info about IdentityReferences from Authorization Rule Collections that came from Discretionary Access Control Lists
        .DESCRIPTION
        Based on the IdentityReference proprety of each Access Control Entry:
        Resolve SID to NT account name and vise-versa
        Resolve well-known SIDs
        Resolve generic defaults like 'NT AUTHORITY' and 'BUILTIN' to the applicable computer or domain name
        Add these properties (IdentityReferenceSID,IdentityReferenceName,IdentityReferenceResolved) to the object and return it
        .INPUTS
        [System.Security.AccessControl.AuthorizationRuleCollection]$InputObject
        .OUTPUTS
        [PSCustomObject] Original object plus IdentityReferenceSID,IdentityReferenceName,IdentityReferenceResolved, and AdsiProvider properties
        .EXAMPLE
        Get-Acl |
        Expand-Acl |
        Resolve-Ace

        Use Get-Acl from the Microsoft.PowerShell.Security module as the source of the access list
        This works in either Windows Powershell or in Powershell
        Get-Acl does not support long paths (>256 characters)
        That was why I originally used the .Net Framework method
        .EXAMPLE
        Get-FolderAce -LiteralPath C:\Test -IncludeInherited |
        Resolve-Ace
        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        $Sections = [System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner
        $FileSecurity = [System.Security.AccessControl.FileSecurity]::new($DirectoryInfo,$Sections)
        $IncludeExplicitRules = $true
        $IncludeInheritedRules = $true
        $AccountType = [System.Security.Principal.SecurityIdentifier]
        $FileSecurity.GetAccessRules($IncludeExplicitRules,$IncludeInheritedRules,$AccountType) |
        Resolve-Ace

        This uses .Net Core as the source of the access list
        It uses the GetAccessRules method on the [System.Security.AccessControl.FileSecurity] class
        The targetType parameter of the method is used to specify that the accounts in the ACL are returned as SIDs
        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        $Sections = [System.Security.AccessControl.AccessControlSections]::Access -bor
        [System.Security.AccessControl.AccessControlSections]::Owner -bor
        [System.Security.AccessControl.AccessControlSections]::Group
        $DirectorySecurity = [System.Security.AccessControl.DirectorySecurity]::new($DirectoryInfo,$Sections)
        $IncludeExplicitRules = $true
        $IncludeInheritedRules = $true
        $AccountType = [System.Security.Principal.NTAccount]
        $FileSecurity.GetAccessRules($IncludeExplicitRules,$IncludeInheritedRules,$AccountType) |
        Resolve-Ace

        This uses .Net Core as the source of the access list
        It uses the GetAccessRules method on the [System.Security.AccessControl.FileSecurity] class
        The targetType parameter of the method is used to specify that the accounts in the ACL are returned as NT account names (DOMAIN\User)
        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        [System.Security.AccessControl.DirectorySecurity]$DirectorySecurity = $DirectoryInfo.GetAccessControl('Access')
        [System.Security.AccessControl.AuthorizationRuleCollection]$AuthRules = $DirectorySecurity.Access
        $AuthRules | Resolve-Ace

        Use the .Net Framework (or legacy .Net Core up to 2.2) as the source of the access list
        Only works in Windows PowerShell
        Those versions of .Net had a GetAccessControl method on the [System.IO.DirectoryInfo] class
        This method is removed in modern versions of .Net Core

        .EXAMPLE
        [System.String]$FolderPath = 'C:\Test'
        [System.IO.DirectoryInfo]$DirectoryInfo = Get-Item -LiteralPath $FolderPath
        $Sections = [System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner
        $FileSecurity = [System.IO.FileSystemAclExtensions]::GetAccessControl($DirectoryInfo,$Sections)

        The [System.IO.FileSystemAclExtensions] class is a Windows-specific implementation
        It provides no known benefit over the cross-platform equivalent [System.Security.AccessControl.FileSecurity]

        .NOTES
        Dependencies:
            Get-DirectoryEntry
            Add-SidInfo
            Get-TrustedDomain
            Find-AdsiProvider

        if ($FolderPath.Length -gt 255) {
            $FolderPath = "\\?\$FolderPath"
        }
    #>
    [OutputType([PSCustomObject])]
    param (

        # Authorization Rule Collection of Access Control Entries from Discretionary Access Control Lists
        [Parameter(
            ValueFromPipeline
        )]
        [PSObject[]]$InputObject,

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        [hashtable]$Win32AccountsBySID = ([hashtable]::Synchronized(@{})),

        [hashtable]$Win32AccountsByCaption = ([hashtable]::Synchronized(@{})),

        [hashtable]$DomainsBySID = ([hashtable]::Synchronized(@{})),

        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{}))

    )
    return $InputObject
}

function Resolve-IdentityReference {
    <#
        .SYNOPSIS
        Use ADSI to lookup info about IdentityReferences from Access Control Entries that came from Discretionary Access Control Lists
        .DESCRIPTION
        Based on the IdentityReference proprety of each Access Control Entry:
        Resolve SID to NT account name and vise-versa
        Resolve well-known SIDs
        Resolve generic defaults like 'NT AUTHORITY' and 'BUILTIN' to the applicable computer or domain name
        .INPUTS
        None. Pipeline input is not accepted.
        .OUTPUTS
        [PSCustomObject] with UnresolvedIdentityReference and SIDString properties (each strings)
        .EXAMPLE
        Resolve-IdentityReference -IdentityReference 'BUILTIN\Administrator' -AdsiServer (Get-AdsiServer 'localhost')

        Get information about the local Administrator account
    #>
    [OutputType([PSCustomObject])]
    param (
        # IdentityReference from an Access Control Entry
        # Expecting either a SID (S-1-5-18) or an NT account name (CONTOSO\User)
        [Parameter(Mandatory)]
        [string]$IdentityReference,

        # Object from Get-AdsiServer representing the directory server and its attributes
        [PSObject]$AdsiServer,

        <#
        Dictionary to cache directory entries to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        [hashtable]$Win32AccountsBySID = ([hashtable]::Synchronized(@{})),

        [hashtable]$Win32AccountsByCaption = ([hashtable]::Synchronized(@{})),

        <#
        Dictionary to cache known servers to avoid redundant lookups

        Defaults to an empty thread-safe hashtable
        #>
        [hashtable]$AdsiServersByDns = [hashtable]::Synchronized(@{}),

        # Hashtable with known domain NetBIOS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain SIDs as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),

        # Hashtable with known domain DNS names as keys and objects with Dns,NetBIOS,SID,DistinguishedName properties as values
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    $LoggingParams = @{
        ThisHostname = $ThisHostname
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    # Populate the caches of known domains if they are currently empty (not sure if this is required so commenting it out for now)
    #if (($DomainsByFqdn.Keys.Count + $DomainsByNetBios.Keys.Count + $DomainsBySid.Keys.Count) -lt 1) {
    #    $null = Get-TrustedDomainInfo -DirectoryEntryCache $DirectoryEntryCache -DomainsBySID $DomainsBySid -DomainsByNetbios $DomainsByNetbios -DomainsByFqdn $DomainsByFqdn
    #}

    # Populate the caches of known domains if they are currently empty (not sure if this is required so commenting it out for now)
    #if (($DomainsByFqdn.Keys.Count + $DomainsByNetBios.Keys.Count + $DomainsBySid.Keys.Count) -lt 1) {
    #    $null = Get-TrustedDomainInfo -DirectoryEntryCache $DirectoryEntryCache -DomainsBySID $DomainsBySid -DomainsByNetbios $DomainsByNetbios -DomainsByFqdn $DomainsByFqdn
    #}

    $ServerNetBIOS = $AdsiServer.Netbios
    $split = $IdentityReference.Split('\')
    $DomainNetBIOS = $split[0]
    $DomainNetBIOS = $ServerNetBIOS
    $Name = $split[1]

    # Many Well-Known SIDs cannot be translated with the Translate method
    # Instead we have used CIM to collect information on instances of the Win32_Account class from the AdsiServer
    # This has been done by Get-AdsiServer and it updated the Win32AccountsBySID and Win32AccountsByCaption caches
    # Search the caches now
    $CacheResult = $Win32AccountsBySID["$ServerNetBIOS\$IdentityReference"]
    if ($CacheResult) {
        #IdentityReference is a SID, and has been cached from this server
        Write-LogMsg @LogParams -Text " # Win32_Account SID cache hit for '$ServerNetBIOS\$IdentityReference'"
        return [PSCustomObject]@{
            IdentityReferenceOriginal   = $IdentityReference
            # IdentityReferenceNameUnresolved below is not available, the Win32_Account instances in the cache are already resolved to the NetBios domain names
            IdentityReferenceUnresolved = $null # Could parse SID to get this?
            SIDString                   = $CacheResult.SID
            IdentityReferenceNetBios    = $CacheResult.Caption -replace "^$ThisHostname\\", "$ThisHostname\" # required for ps 5.1 support
            # PS 7 more efficient IdentityReferenceNetBios    = $CacheResult.Caption.Replace("$ThisHostname\","$ThisHostname\",[System.StringComparison]::CurrentCultureIgnoreCase)
            IdentityReferenceDns        = "$($AdsiServer.Dns)\$($CacheResult.Name)"
        }
    } else {
        Write-LogMsg @LogParams -Text " # Win32_Account SID cache miss for '$ServerNetBIOS\$IdentityReference'"
    }
    if ($Name) {
        # Win32_Account provides a NetBIOS-resolved IdentityReference
        # NT Authority\SYSTEM would be SERVER123\SYSTEM as a Win32_Account on a server with hostname server123
        # This could also match on a domain account since those can be returned as Win32_Account, not sure if that will be a bug or what
        $CacheResult = $Win32AccountsByCaption["$ServerNetBIOS\$Name"]
        if ($CacheResult) {
            # IdentityReference is an NT Account Name, and has been cached from this server
            Write-LogMsg @LogParams -Text " # Win32_Account caption cache hit for '$ServerNetBIOS\$ServerNetBIOS\$Name'"
            if ($ServerNetBIOS -eq $CacheResult.Domain) {
                $DomainDns = $AdsiServer.Dns
            }
            if (-not $DomainDns) {
                $DomainCacheResult = $DomainsByNetbios[$CacheResult.Domain]
                if ($DomainCacheResult) {
                    $DomainDns = $DomainCacheResult.Dns
                }
            }
            if (-not $DomainDns) {
                $DomainDns = ConvertTo-Fqdn -NetBIOS $DomainNetBIOS -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                $DomainDn = $DomainsByNetbios[$DomainNetBIOS].DistinguishedName
            }

            return [PSCustomObject]@{
                IdentityReferenceOriginal   = $IdentityReference
                # IdentityReferenceNameUnresolved below is not available, the Win32_Account instances in the cache are already resolved to the NetBios domain names
                IdentityReferenceUnresolved = $IdentityReference
                SIDString                   = $CacheResult.SID
                IdentityReferenceNetBios    = $CacheResult.Caption -replace "^$ThisHostname\\", "$ThisHostname\" # required for ps 5.1 support
                # PS 7 more efficient IdentityReferenceNetBios    = $CacheResult.Caption.Replace("$ThisHostname\","$ThisHostname\",[System.StringComparison]::CurrentCultureIgnoreCase)
                IdentityReferenceDns        = "$DomainDns\$($CacheResult.Name)"
            }
        } else {
            Write-LogMsg @LogParams -Text " # Win32_Account caption cache miss for '$ServerNetBIOS\$ServerNetBIOS\$Name'"
        }
    }
    $CacheResult = $Win32AccountsByCaption["$ServerNetBIOS\$IdentityReference"]
    if ($CacheResult) {
        # IdentityReference is an NT Account Name without a \, and has been cached from this server
        Write-LogMsg @LogParams -Text " # Win32_Account caption cache hit for '$ServerNetBIOS\$IdentityReference'"
        return [PSCustomObject]@{
            IdentityReferenceOriginal   = $IdentityReference
            # IdentityReferenceNameUnresolved below is not available, the Win32_Account instances in the cache are already resolved to the NetBios domain names
            IdentityReferenceUnresolved = $null
            SIDString                   = $CacheResult.SID
            IdentityReferenceNetBios    = $CacheResult.Caption -replace "^$ThisHostname\\", "$ThisHostname\" # required for ps 5.1 support
            # PS 7 more efficient IdentityReferenceNetBios    = $CacheResult.Caption.Replace("$ThisHostname\","$ThisHostname\",[System.StringComparison]::CurrentCultureIgnoreCase)
            IdentityReferenceDns        = "$($AdsiServer.Dns)\$($CacheResult.Name)"
        }
    } else {
        Write-LogMsg @LogParams -Text " # Win32_Account caption cache miss for '$ServerNetBIOS\$IdentityReference'"
    }

    switch -Wildcard ($IdentityReference) {
        "S-1-*" {
            # IdentityReference is a Revision 1 SID
            <#
            Use the SecurityIdentifier.Translate() method to translate the SID to an NT Account name
                This .Net method makes it impossible to redirect the error stream directly
                Wrapping it in a scriptblock (which is then executed with &) fixes the problem
                I don't understand exactly why
                The scriptblock will evaluate null if the SID cannot be translated, and the error stream redirection supresses the error
            #>
            Write-LogMsg @LogParams -Text "[System.Security.Principal.SecurityIdentifier]::new('$IdentityReference').Translate([System.Security.Principal.NTAccount])"
            $SecurityIdentifier = [System.Security.Principal.SecurityIdentifier]::new($IdentityReference)
            $UnresolvedIdentityReference = & { $SecurityIdentifier.Translate([System.Security.Principal.NTAccount]).Value } 2>$null

            # The SID of the domain is everything up to (but not including) the last hyphen
            $DomainSid = $IdentityReference.Substring(0, $IdentityReference.LastIndexOf("-"))

            # Search the cache of domains, first by SID, then by NetBIOS name
            $DomainCacheResult = $DomainsBySID[$DomainSid]
            if (-not $DomainCacheResult) {
                $split = $UnresolvedIdentityReference -split '\\'
                $DomainCacheResult = $DomainsByNetbios[$split[0]]
                Write-LogMsg @LogParams -Text " # Domain SID cache miss for '$DomainSid'"
            } else {
                Write-LogMsg @LogParams -Text " # Domain SID cache hit for '$DomainSid'"
            }
            if ($DomainCacheResult) {
                $DomainNetBIOS = $DomainCacheResult.Netbios
                $DomainDns = $DomainCacheResult.Dns
            } else {
                Write-LogMsg @LogParams -Text " # Domain SID '$DomainSid' is unknown."
                $DomainNetBIOS = $split[0]
                Write-LogMsg @LogParams -Text " # Translated NTAccount name for '$IdentityReference' is '$UnresolvedIdentityReference'"
                $DomainDns = ConvertTo-Fqdn -NetBIOS $DomainNetBIOS -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
            }
            $AdsiServer = Get-AdsiServer -Fqdn $DomainDns -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams

            if ( -not $UnresolvedIdentityReference ) {
                $Resolved = [PSCustomObject]@{
                    IdentityReferenceOriginal   = $IdentityReference
                    IdentityReferenceUnresolved = $IdentityReference
                    SIDString                   = $IdentityReference
                    IdentityReferenceNetBios    = $CacheResult.Caption -replace "^$ThisHostname\\", "$ThisHostname\" # required for ps 5.1 support
                    # PS 7 more efficient IdentityReferenceNetBios    = $CacheResult.Caption.Replace("$ThisHostname\","$ThisHostname\",[System.StringComparison]::CurrentCultureIgnoreCase)
                    IdentityReferenceDns        = "$DomainDns\$IdentityReference"
                }
            } else {
                # Recursively call this function to resolve the new IdentityReference we have
                $ResolveIdentityReferenceParams = @{
                    IdentityReference      = $UnresolvedIdentityReference
                    AdsiServer             = $AdsiServer
                    Win32AccountsBySID     = $Win32AccountsBySID
                    Win32AccountsByCaption = $Win32AccountsByCaption
                    AdsiServersByDns       = $AdsiServersByDns
                    DirectoryEntryCache    = $DirectoryEntryCache
                    DomainsBySID           = $DomainsBySID
                    DomainsByNetbios       = $DomainsByNetbios
                    DomainsByFqdn          = $DomainsByFqdn
                    ThisHostName           = $ThisHostName
                    ThisFqdn               = $ThisFqdn
                    LogMsgCache            = $LogMsgCache
                    WhoAmI                 = $WhoAmI
                }
                $Resolved = Resolve-IdentityReference @ResolveIdentityReferenceParams
            }

            return $Resolved

        }
        "NT SERVICE\*" {
            # Some of them are services (yes services can have SIDs, notably this includes TrustedInstaller but it is also common with SQL)
            if ($ServerNetBIOS -eq $ThisHostName) {
                Write-LogMsg @LogParams -Text "sc.exe showsid $Name"
                [string[]]$ScResult = & sc.exe showsid $Name
            } else {
                Write-LogMsg @LogParams -Text "Invoke-Command -ComputerName $ServerNetBIOS -ScriptBlock { & sc.exe showsid `$args[0] } -ArgumentList $Name"
                [string[]]$ScResult = Invoke-Command -ComputerName $ServerNetBIOS -ScriptBlock { & sc.exe showsid $args[0] } -ArgumentList $Name
            }
            $ScResultProps = @{}

            $ScResult |
            ForEach-Object {
                $Prop, $Value = ($_ -split ':').Trim()
                $ScResultProps[$Prop] = $Value
            }

            $SIDString = $ScResultProps['SERVICE SID']
            $Caption = $IdentityReference -replace 'NT SERVICE', $ServerNetBIOS -replace "^$ThisHostname\\", "$ThisHostname\"

            $DomainCacheResult = $DomainsByNetbios[$ServerNetBIOS]
            if ($DomainCacheResult) {
                $DomainDns = $DomainCacheResult.Dns
            }
            if (-not $DomainDns) {
                $DomainDns = ConvertTo-Fqdn -NetBIOS $ServerNetBIOS -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
            }

            # Update the caches
            $Win32Acct = [PSCustomObject]@{
                SID     = $SIDString
                Caption = $Caption
                Domain  = $ServerNetBIOS
                Name    = $Name
            }
            $Win32AccountsByCaption[$Caption] = $Win32Acct
            $Win32AccountsBySID["$ServerNetBIOS\$SIDString"] = $Win32Acct

            return [PSCustomObject]@{
                IdentityReferenceOriginal   = $IdentityReference
                IdentityReferenceUnresolved = $IdentityReference
                SIDString                   = $SIDString
                IdentityReferenceNetBios    = $Caption
                IdentityReferenceDns        = "$DomainDns\$Name"
            }
        }
        "BUILTIN\*" {
            # Some built-in groups such as BUILTIN\Users and BUILTIN\Administrators are not in the CIM class or translatable with the NTAccount.Translate() method
            # But they may have real DirectoryEntry objects
            # Try to find the DirectoryEntry object locally on the server
            $DirectoryPath = "$($AdsiServer.AdsiProvider)`://$ServerNetBIOS/$Name"
            $DirectoryEntry = Get-DirectoryEntry -DirectoryPath $DirectoryPath -DirectoryEntryCache $DirectoryEntryCache -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -DomainsBySid $DomainsBySid @LoggingParams
            $SIDString = (Add-SidInfo -InputObject $DirectoryEntry -DomainsBySid $DomainsBySid @LoggingParams).SidString
            $Caption = $IdentityReference -replace 'BUILTIN', $ServerNetBIOS -replace "^$ThisHostname\\", "$ThisHostname\"
            $DomainDns = $AdsiServer.Dns

            # Update the caches
            $Win32Acct = [PSCustomObject]@{
                SID     = $SIDString
                Caption = $Caption
                Domain  = $ServerNetBIOS
                Name    = $Name
            }
            $Win32AccountsByCaption[$Caption] = $Win32Acct
            $Win32AccountsBySID["$ServerNetBIOS\$SIDString"] = $Win32Acct

            return [PSCustomObject]@{
                IdentityReferenceOriginal   = $IdentityReference
                IdentityReferenceUnresolved = $IdentityReference
                SIDString                   = $SIDString
                IdentityReferenceNetBios    = $Caption
                IdentityReferenceDns        = "$DomainDns\$Name"
            }
        }
    }

    # The IdentityReference is an NTAccount
    # Resolve NTAccount to SID
    # Start by determining the domain

    if (-not [string]::IsNullOrEmpty($DomainNetBIOS)) {
        $DomainNetBIOSCacheResult = $DomainsByNetbios[$DomainNetBIOS]
        if (-not $DomainNetBIOSCacheResult) {
            Write-LogMsg @LogParams -Text " # Domain NetBIOS cache miss for '$($DomainNetBIOS)'."
            $DomainNetBIOSCacheResult = Get-AdsiServer -Netbios $DomainNetBIOS -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
            $DomainsByNetbios[$DomainNetBIOS] = $DomainNetBIOSCacheResult

        } else {
            Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$($DomainNetBIOS)'."
        }

        $DomainDn = $DomainNetBIOSCacheResult.DistinguishedName
        $DomainDns = $DomainNetBIOSCacheResult.Dns

        # Try to resolve the account against the server the Access Control Entry came from (which may or may not be the directory server for the account)
        Write-LogMsg @LogParams -Text "[System.Security.Principal.NTAccount]::new('$ServerNetBIOS', '$Name').Translate([System.Security.Principal.SecurityIdentifier])"
        $NTAccount = [System.Security.Principal.NTAccount]::new($ServerNetBIOS, $Name)
        $SIDString = & { $NTAccount.Translate([System.Security.Principal.SecurityIdentifier]) } 2>$null

        if (-not $SIDString) {
            # Try to resolve the account against the domain indicated in its NT Account Name (which may or may not be the correct ADSI server for the account, it won't be if it's NT AUTHORITY\SYSTEM for example)
            Write-LogMsg @LogParams -Text "[System.Security.Principal.NTAccount]::new('$DomainNetBIOS', '$Name')"
            $NTAccount = [System.Security.Principal.NTAccount]::new($DomainNetBIOS, $Name)
            Write-LogMsg @LogParams -Text "[System.Security.Principal.NTAccount]::new('$DomainNetBIOS', '$Name').Translate([System.Security.Principal.SecurityIdentifier])"
            $SIDString = & { $NTAccount.Translate([System.Security.Principal.SecurityIdentifier]) } 2>$null
        } else {
            $DomainNetBIOS = $ServerNetBIOS
        }

        if (-not $SIDString) {
            # Try to resolve the account against the domain indicated in its NT Account Name
            # Add this domain to our list of known domains
            try {
                $SearchPath = Add-DomainFqdnToLdapPath -DirectoryPath "LDAP://$DomainDn" -ThisFqdn $ThisFqdn @LogParams
                $DirectoryEntry = Search-Directory -DirectoryEntryCache $DirectoryEntryCache -DirectoryPath $SearchPath -Filter "(samaccountname=$Name)" -PropertiesToLoad @('objectClass', 'distinguishedName', 'name', 'grouptype', 'description', 'managedby', 'member', 'objectClass', 'Department', 'Title') -DomainsByNetbios $DomainsByNetbios
                $SIDString = (Add-SidInfo -InputObject $DirectoryEntry -DomainsBySid $DomainsBySid @LoggingParams).SidString
            } catch {
                Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tResolve-IdentityReference`t$($StartingIdentityName) could not be resolved against its directory"
                Write-Warning "$(Get-Date -Format s)`t$ThisHostname`tResolve-IdentityReference`t$($_.Exception.Message)"
            }
        }

        if (-not $SIDString) {

            # Try to find the DirectoryEntry object directly on the server
            $DirectoryPath = "$($AdsiServer.AdsiProvider)`://$ServerNetBIOS/$Name"
            $DirectoryEntry = Get-DirectoryEntry -DirectoryPath $DirectoryPath -DirectoryEntryCache $DirectoryEntryCache -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -DomainsBySid $DomainsBySid @LoggingParams
            $SIDString = (Add-SidInfo -InputObject $DirectoryEntry -DomainsBySid $DomainsBySid @LoggingParams).SidString

        }

        if ($SIDString) {
            $DomainNetBIOS = $ServerNetBIOS
        }

        # This covers unresolved SIDs for deleted accounts, broken domain trusts, etc.
        if ( '' -eq "$Name" ) {
            $Name = $IdentityReference
            Write-LogMsg @LogParams -Text " # An identity reference girl has no name ($Name)"
        } else {
            Write-LogMsg @LogParams -Text " # '$IdentityReference' is named '$Name'"
        }

        return [PSCustomObject]@{
            IdentityReferenceOriginal   = $IdentityReference
            IdentityReferenceUnresolved = $IdentityReference
            SIDString                   = $SIDString
            IdentityReferenceNetBios    = "$DomainNetBios\$Name" -replace "^$ThisHostname\\", "$ThisHostname\"
            IdentityReferenceDns        = "$DomainDns\$Name"
        }

    }
}
function Search-Directory {
    <#
        .SYNOPSIS
        Use Active Directory Service Interfaces to search an LDAP directory
        .DESCRIPTION
        Find directory entries using the LDAP provider for ADSI (the WinNT provider does not support searching)
        Provides a wrapper around the [System.DirectoryServices.DirectorySearcher] class
        .INPUTS
        None. Pipeline input is not accepted.
        .OUTPUTS
        [System.DirectoryServices.DirectoryEntry]
        .EXAMPLE
        Search-Directory -Filter ''

        As the current user on a domain-joined computer, bind to the current domain and search for all directory entries matching the LDAP filter
    #>
    param (

        <#
        Path to the directory object to retrieve
        Defaults to the root of the current domain
        #>
        [string]$DirectoryPath = (([adsisearcher]'').SearchRoot.Path),

        # Filter for the LDAP search
        [string]$Filter,

        # Number of records per page of results
        [int]$PageSize = 1000,

        # Additional properties to return
        [string[]]$PropertiesToLoad,

        # Credentials to use
        [pscredential]$Credential,

        # Scope of the search
        [string]$SearchScope = 'subtree',

        <#
        Hashtable containing cached directory entries so they don't have to be retrieved from the directory again
        Uses a thread-safe hashtable by default
        #>
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),

        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    $DirectoryEntryParameters = @{
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByNetbios    = $DomainsByNetbios
        ThisHostname        = $ThisHostname
        LogMsgCache         = $LogMsgCache
        WhoAmI              = $WhoAmI
    }

    if ($Credential) {
        $DirectoryEntryParameters['Credential'] = $Credential
    }

    if (($null -eq $DirectoryPath -or '' -eq $DirectoryPath)) {
        $Workgroup = (Get-CimInstance -ClassName Win32_ComputerSystem).Workgroup
        $DirectoryPath = "WinNT://$Workgroup/$ThisHostname"
    }
    $DirectoryEntryParameters['DirectoryPath'] = $DirectoryPath

    $DirectoryEntry = Get-DirectoryEntry @DirectoryEntryParameters

    Write-LogMsg @LogParams -Text "`$DirectorySearcher = [System.DirectoryServices.DirectorySearcher]::new(([System.DirectoryServices.DirectoryEntry]::new('$DirectoryPath')))"
    $DirectorySearcher = [System.DirectoryServices.DirectorySearcher]::new($DirectoryEntry)

    if ($Filter) {
        Write-LogMsg @LogParams -Text "`$DirectorySearcher.Filter = '$Filter'"
        $DirectorySearcher.Filter = $Filter
    }

    Write-LogMsg @LogParams -Text "`$DirectorySearcher.PageSize = '$PageSize'"
    $DirectorySearcher.PageSize = $PageSize
    Write-LogMsg @LogParams -Text "`$DirectorySearcher.SearchScope = '$SearchScope'"
    $DirectorySearcher.SearchScope = $SearchScope

    ForEach ($Property in $PropertiesToLoad) {
        Write-LogMsg @LogParams -Text "`$DirectorySearcher.PropertiesToLoad.Add('$Property')"
        $null = $DirectorySearcher.PropertiesToLoad.Add($Property)
    }

    Write-LogMsg @LogParams -Text "`$DirectorySearcher.FindAll()"
    $SearchResultCollection = $DirectorySearcher.FindAll()
    # TODO: Fix this.  Problems in integration testing trying to use the objects later if I dispose them here now.
    # Error: Cannot access a disposed object.
    #$null = $DirectorySearcher.Dispose()
    #$null = $DirectoryEntry.Dispose()
    $Output = [System.DirectoryServices.SearchResult[]]::new($SearchResultCollection.Count)
    $SearchResultCollection.CopyTo($Output, 0)
    #$null = $SearchResultCollection.Dispose()
    return $Output

}
<#
# Add any custom C# classes as usable (exported) types
$CSharpFiles = Get-ChildItem -Path "$PSScriptRoot\*.cs"
ForEach ($ThisFile in $CSharpFiles) {
    Add-Type -Path $ThisFile.FullName -ErrorAction Stop
}
#>

# Definition of Module 'SimplePrtg' Version '1.0.13' is below

function Format-PrtgXmlResult {

    <#
        .SYNOPSIS
        Generate an XML result for a single channel to include in the result for a PRTG custom XML sensor
        .DESCRIPTION
        Generate a <result>...</result> XML channel for a PRTG custom XML sensor
        .INPUTS
        [System.String]$Channel
        .OUTPUTS
        [System.String] A single XML channel to include in the output for a PRTG XML sensor
        .EXAMPLE
        New-PrtgXmlResult -Channel 'Channel123' -Value 'Value123' -CustomUnit 'Miles Per Hour'
        <result>
        <channel>Channel123</channel>
        <value>Value123</value>
        <unit>Custom</unit>
        <customUnit>Miles Per Hour</customUnit>
        <showchart>0</showchart>
        </result>

        Generate XML output for a PRTG sensor that will put it in an OK state
    #>

    param (

        # PRTG sensor channel of the result
        [parameter(Mandatory)]
        [string]$Channel,

        # Value to return
        [parameter(Mandatory)]
        [string]$Value,

        # Reccomend leaving this as 'Custom' but see PRTG docs for other options
        [string]$Unit = 'Custom',

        # Custom unit label to apply to the value
        [string]$CustomUnit,

        # Show the channel on charts in PRTG
        [int]$ShowChart = 0,

        # If the value goes above this the channel will be in an alarm state in PRTG
        [string]$MaxError,

        # If the value goes below this the channel will be in an alarm state in PRTG
        [string]$MinError,

        # If the value goes above this the channel will be in a warning state in PRTG
        [string]$MaxWarn,

        # If the value goes below this the channel will be in a warning state in PRTG
        [string]$MinWarn,

        # Force the channel into a warning state in PRTG
        [switch]$Warning

    )

    $Xml = [System.Collections.Generic.List[string]]::new()

    $null = $Xml.Add('<result>')
    $null = $Xml.Add("  <channel>$Channel</channel>")
    $null = $Xml.Add("  <value>$Value</value>")
    $null = $Xml.Add("  <unit>$Unit</unit>")
    $null = $Xml.Add("  <showchart>$ShowChart</showchart>")

    if ($CustomUnit) {
        $null = $Xml.Add("  <customUnit>$CustomUnit</customUnit>")
    }

    if ($MaxError -or $MinError -or $MaxWarn -or $MinWarn) {

        $null = $Xml.Add("  <limitmode>1</limitmode>")

        if ($MaxError) {
            $null = $Xml.Add("  <limitmaxerror>$MaxError</limitmaxerror>")
        }

        if ($MinError) {
            $null = $Xml.Add("  <limitminerror>$MinError</limitminerror>")
        }

        if ($MaxWarn) {
            $null = $Xml.Add("  <limitmaxwarn>$MaxWarn</limitmaxwarn>")
        }

        if ($MinWarn) {
            $null = $Xml.Add("  <limitminwarn>$MinWarn</limitminwarn>")
        }

    }

    if ($Warning) {
        $null = $Xml.Add('  <Warning>1</Warning>')
    } else {
        $null = $Xml.Add('  <Warning>0</Warning>')
    }

    $null = $Xml.Add('</result>')
    $Xml

}

function Format-PrtgXmlSensorOutput {
    <#
        .SYNOPSIS
        Assemble the complete output for a PRTG XML sensor
        .DESCRIPTION
        Combine multiple channels into a single PRTG XML sensor result
        .INPUTS
        [System.String]$PrtgXmlResult
        .OUTPUTS
        [System.String] Complete XML output for a PRTG custom XML sensor
        .EXAMPLE
        @"
        <result>
        <channel>Channel123</channel>
        <value>Value123</value>
        <unit>Custom</unit>
        <customUnit>Miles Per Hour</customUnit>
        <showchart>$ShowChart</showchart>
        </result>
        @" |
        New-PrtgXmlSensorOutput

        Generate XML output for a PRTG sensor that will put it in an OK state
        .EXAMPLE
        @"
        <result>
        <channel>Channel123</channel>
        <value>Value123</value>
        <unit>Custom</unit>
        <customUnit>Miles Per Hour</customUnit>
        <showchart>0</showchart>
        </result>
        @" |
        New-PrtgXmlSensorOutput -IssueDetected

        Generate XML output for a PRTG sensor that will put it in an alarm state
    #>

    param (

        # Valid XML for a PRTG result for a single channel
        # Can be created by Format-PrtgXmlResult
        [Parameter(ValueFromPipeline)]
        [string[]]$PrtgXmlResult,

        # Force the PRTG sensor into an alarm state
        [switch]$IssueDetected

    )

    begin {
        $Strings = [System.Collections.Generic.List[string]]::new()
        $null = $Strings.add("<prtg>")
    }
    process {
        foreach ($XmlResult in $PrtgXmlResult) {
            $null = $Strings.add($XmlResult)
        }
    }
    end {
        if ($IssueDetected) {
            $null = $Strings.add("<text>Issue detected, see sensor channels for details</text>")
        } else {
            $null = $Strings.add("<text>OK</text>")
        }
        $null = $Strings.add("</prtg>")
        $Strings
    }
}
function Send-PrtgXmlSensorOutput {

    <#
        .SYNOPSIS
        Wrapper for Invoke-WebRequest to make it easy to push results to PRTG XML push sensors
        .DESCRIPTION
        Use HTTP post to post results to PRTG XML push sensors
        .INPUTS
        [System.String]$XmlOutput
        .OUTPUTS
        Passes through the output of Invoke-WebRequest
        .EXAMPLE
        New-PrtgXmlSensorOutput ... |
        Send-PrtgXmlSensorOutput -PrtgProtocol 'https' -PrtgProbe 'server1' -PrtgPort 443 -PrtgToken 'e3edd633-3018-4d8a-91b6-d2635b42b85b'

        Post sensor output to PRTG push sensor e3edd633-3018-4d8a-91b6-d2635b42b85b on server1 using HTTPS on TCP port 443
    #>

    param(

        # Valid XML for a PRTG custom XML sensor
        # Can be created by Format-PrtgXmlSensorOutput
        [string]$XmlOutput,

        # If all four of the PRTG parameters are specified, then the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
        [string]$PrtgProbe,

        # If all four of the PRTG parameters are specified, then the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
        [string]$PrtgProtocol,

        # If all four of the PRTG parameters are specified, then the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
        [int]$PrtgPort,

        # If all four of the PRTG parameters are specified, then the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor
        [string]$PrtgToken
    )

    $ResultToPost = @{
        Body            = $XMLOutput
        ContentType     = 'application/xml'
        Method          = 'Post'
        Uri             = "$PrtgProtocol`://$PrtgProbe`:$PrtgPort/$PrtgToken"
        UseBasicParsing = $true
    }

    if ($PrtgToken) {
        Write-Verbose "URI: $PrtgProtocol`://$PrtgProbe`:$PrtgPort/$PrtgToken"

        Invoke-WebRequest @ResultToPost
    }

}
<#
# Add any custom C# classes as usable (exported) types
$CSharpFiles = Get-ChildItem -Path "$PSScriptRoot\*.cs"
ForEach ($ThisFile in $CSharpFiles) {
    Add-Type -Path $ThisFile.FullName -ErrorAction Stop
}
#>

# Definition of Module 'PsNtfs' Version '2.0.79' is below

function GetDirectories {
    param (
        [Parameter(Mandatory)]
        [string]$TargetPath,

        [string]$SearchPattern = '*',

        [System.IO.SearchOption]$SearchOption = [System.IO.SearchOption]::AllDirectories
    )
    Write-Debug "  $(Get-Date -Format s)`t$(hostname)`tGetDirectories`t[System.IO.Directory]::GetDirectories('$TargetPath','$SearchPattern',[System.IO.SearchOption]::$SearchOption)"
    try {
        [System.IO.Directory]::GetDirectories($TargetPath, $SearchPattern, $SearchOption)
    } catch {
        Write-Warning "$(Get-Date -Format s)`t$(hostname)`tGetDirectories`t$($_.Exception.Message)"
    }
}
function ConvertTo-SimpleProperty {
    param (
        $InputObject,

        [string]$Property,

        [hashtable]$PropertyDictionary = @{},

        [string]$Prefix
    )

    $Value = $InputObject.$Property

    [string]$Type = $null
    if ($Value) {
        # Ensure the GetType method exists to avoid this error:
        # The following exception occurred while retrieving member "GetType": "Not implemented"
        if (Get-Member -InputObject $Value -Name GetType) {
            [string]$Type = $Value.GetType().FullName
        }
        else {
            # The only scenario we've encountered where the GetType() method does not exist is DirectoryEntry objects from the WinNT provider
            # Force the type to 'System.DirectoryServices.DirectoryEntry'
            [string]$Type = 'System.DirectoryServices.DirectoryEntry'
        }
    }

    switch ($Type) {
        'System.DirectoryServices.DirectoryEntry' {
            $PropertyDictionary["$Prefix$Property"] = ConvertFrom-DirectoryEntry -DirectoryEntry $Value
        }
        'System.DirectoryServices.PropertyCollection' {
            $ThisObject = @{}
            <#
            This error was happening when:
                A DirectoryEntry has a SchemaEntry property
                which is a DirectoryEntry
                which has a Properties property
                which is a System.DirectoryServices.PropertyCollection
                but throws the following error to the Success stream (not the error stream, so it is hard to catch):
                    PS C:\Users\Test> $ThisDirectoryEntry.Properties
                    format-default : The entry properties cannot be enumerated. Consider using the entry schema to determine what properties are available.
                        + CategoryInfo          : NotSpecified: (:) [format-default], NotSupportedException
                        + FullyQualifiedErrorId : System.NotSupportedException,Microsoft.PowerShell.Commands.FormatDefaultCommand
            To catch the error we will redirect the Success Stream to the Error Stream
            Then if the Exception type matches, we will use the continue keyword to break out of the current switch statement
            #>
            $KeyCount = $Value.Keys.$KeyCount
            if (-not $KeyCount -gt 0) {
                continue
            }

            ForEach ($ThisProperty in $Value.Keys) {
                $ThisPropertyString = ConvertFrom-PropertyValueCollectionToString -PropertyValueCollection $Value[$ThisProperty]
                $ThisObject[$ThisProperty] = $ThisPropertyString

                # This copies the properties up to the top level.
                # Want to remove this later
                # The nested pscustomobject accomplishes the goal of removing hashtables and PropertyValueCollections and PropertyCollections
                # But I may have existing functionality expecting these properties so I am not yet ready to remove this
                # When I am, I should move this code into a ConvertFrom-PropertyCollection function in the Adsi module
                $PropertyDictionary["$Prefix$ThisProperty"] = $ThisPropertyString

            }
            $PropertyDictionary["$Prefix$Property"] = [PSCustomObject]$ThisObject
            continue
        }
        'System.DirectoryServices.PropertyValueCollection' {
            $PropertyDictionary["$Prefix$Property"] = ConvertFrom-PropertyValueCollectionToString -PropertyValueCollection $Value
            continue
        }
        'System.Object[]' {
            $PropertyDictionary["$Prefix$Property"] = $Value
            continue
        }
        'System.Object' {
            $PropertyDictionary["$Prefix$Property"] = $Value
            continue
        }
        'System.DirectoryServices.SearchResult' {
            $PropertyDictionary["$Prefix$Property"] = ConvertFrom-SearchResult -SearchResult $Value
            continue
        }
        'System.DirectoryServices.ResultPropertyCollection' {
            $ThisObject = @{}

            ForEach ($ThisProperty in $Value.Keys) {
                $ThisPropertyString = ConvertFrom-ResultPropertyValueCollectionToString -ResultPropertyValueCollection $Value[$ThisProperty]
                $ThisObject[$ThisProperty] = $ThisPropertyString

                # This copies the properties up to the top level.
                # Want to remove this later
                # The nested pscustomobject accomplishes the goal of removing hashtables and PropertyValueCollections and PropertyCollections
                # But I may have existing functionality expecting these properties so I am not yet ready to remove this
                # When I am, I should move this code into a ConvertFrom-PropertyCollection function in the Adsi module
                $PropertyDictionary["$Prefix$ThisProperty"] = $ThisPropertyString

            }
            $PropertyDictionary["$Prefix$Property"] = [PSCustomObject]$ThisObject
            continue
        }
        'System.DirectoryServices.ResultPropertyValueCollection' {
            $PropertyDictionary["$Prefix$Property"] = ConvertFrom-ResultPropertyValueCollectionToString -ResultPropertyValueCollection $Value
            continue
        }
        'System.Management.Automation.PSCustomObject' {
            $PropertyDictionary["$Prefix$Property"] = $Value
            continue
        }
        'System.Collections.Hashtable' {
            $PropertyDictionary["$Prefix$Property"] = [PSCustomObject]$Value
            continue
        }
        'System.Byte[]' {
            $PropertyDictionary["$Prefix$Property"] = ConvertTo-DecStringRepresentation -ByteArray $Value
        }
        default {
            <#
                By default we will just let most types get cast as a string
                Includes but not limited to:
                    $null (because GetType is not implemented)
                    System.String
                    System.Boolean
            #>
            $PropertyDictionary["$Prefix$Property"] = "$Value"
            continue
        }
    }

    return $PropertyDictionary
}
function Expand-AccountPermission {
    <#
        .SYNOPSIS
        Expand an object representing a security principal and into a collection of objects respresenting the access control entries for that principal
        .DESCRIPTION
        Expand an object from Format-SecurityPrincipal (one object per principal, containing nested access entries) into flat objects (one per access entry per account)
        .INPUTS
        [pscustomobject]$AccountPermission
        .OUTPUTS
        [pscustomobject] One object per access control entry per account
        .EXAMPLE
        (Get-Acl).Access |
        Group-Object -Property IdentityReference |
        Expand-IdentityReference |
        Format-SecurityPrincipal |
        Expand-AccountPermission

        Incomplete example but it shows the chain of functions to generate the expected input for this
    #>
    param (
        # Object that was output from Format-SecurityPrincipal
        $AccountPermission,

        # Properties to exclude from the output because they cause problems or are unnecessary/redundant/undesirable
        # All properties listed on a single line to workaround a bug in PlatyPS when building MAML help
        # (error is 'Invalid yaml: expected simple key-value pairs')
        # Caused by multi-line default parameter values in the markdown
        [string[]]$PropertiesToExclude = @('NativeObject', 'NtfsAccessControlEntries', 'Group')
    )
    ForEach ($Account in $AccountPermission) {

        $Props = @{}

        $AccountNoteProperties = $Account |
        Get-Member -MemberType Property, CodeProperty, ScriptProperty, NoteProperty |
        Where-Object -Property Name -NotIn $PropertiesToExclude

        ForEach ($ThisProperty in $AccountNoteProperties) {
            if ($null -eq $Props[$ThisProperty.Name]) {
                $Props = ConvertTo-SimpleProperty -InputObject $Account -Property $ThisProperty.Name -PropertyDictionary $Props
            }
        }

        ForEach ($ACE in $Account.NtfsAccessControlEntries) {

            $ACENoteProperties = $ACE |
            Get-Member -MemberType Property, CodeProperty, ScriptProperty, NoteProperty

            ForEach ($ThisProperty in $ACENoteProperties) {
                $Props = ConvertTo-SimpleProperty -InputObject $ACE -Property $ThisProperty.Name -PropertyDictionary $Props -Prefix "ACE"
            }

            $Props['SourceAclPath'] = $ACE.SourceAccessList.Path

            [pscustomobject]$Props

        }
    }
}
function Expand-Acl {
    <#
        .SYNOPSIS
        Expand an Access Control List into its constituent Access Control Entries
        .DESCRIPTION
        Enumerate the members of the Access property of the $InputObject parameter (which is an AuthorizationRuleCollection or similar)
        Append the original ACL to each member as a SourceAccessList property
        Then return each member
        .INPUTS
        [PSObject]$InputObject
        Expected:
        [System.Security.AccessControl.DirectorySecurity]$InputObject from Get-Acl
        or
        [System.Security.AccessControl.FileSecurity]$InputObject from Get-Acl
        .OUTPUTS
        [PSCustomObject]
        .EXAMPLE
        Get-Acl |
        Expand-Acl

        Use Get-Acl from the Microsoft.PowerShell.Security module as the source of the access list
        This works in either Windows Powershell or in Powershell
        Get-Acl does not support long paths (>256 characters)
        That was why I originally used the .Net Framework method
    #>
    param (

        # Access Control List whose Access Control Entries to return
        # Expects [System.Security.AccessControl.FileSecurity] objects from Get-Acl or otherwise
        # Expects [System.Security.AccessControl.DirectorySecurity] objects from Get-Acl or otherwise
        # Accepts any [PSObject] as long as it has an 'Access' property that contains a collection
        [Parameter(
            ValueFromPipeline
        )]
        [PSObject]$InputObject

    )

    process {

        ForEach ($ThisInputObject in $InputObject) {

            $ObjectProperties = @{
                SourceAccessList = $ThisInputObject
            }
            $AllACEs = $ThisInputObject.Access
            $AceProperties = (Get-Member -InputObject $AllACEs[0] -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
            ForEach ($ThisACE in $AllACEs) {
                ForEach ($ThisProperty in $AceProperties) {
                    $ObjectProperties["$Prefix$ThisProperty"] = $ThisACE.$ThisProperty
                }
                [PSCustomObject]$ObjectProperties
            }

        }

    }

}
function Find-ServerNameInPath {
    <#
        .SYNOPSIS
        Parse a literal path to find its server
        .DESCRIPTION
        Currently only supports local file paths or UNC paths
        .INPUTS
        None. Pipeline input is not accepted.
        .OUTPUTS
        [System.String] representing the name of the server that was extracted from the path
        .EXAMPLE
        Find-ServerNameInPath -LiteralPath 'C:\Test'

        Return the hostname of the local computer because a local filepath was used
        .EXAMPLE
        Find-ServerNameInPath -LiteralPath '\\server123\Test\'

        Return server123 because a UNC path for a folder shared on server123 was used
    #>
    [OutputType([System.String])]
    param (
        [string]$LiteralPath
    )
    if ($LiteralPath -match '[A-Za-z]\:\\' -or $null -eq $LiteralPath -or '' -eq $LiteralPath) {
        # For local file paths, the "server" is the local computer.  Assume the same for null paths.
        hostname
    }
    else {
        # Otherwise it must be a UNC path, so the server is the first non-empty string between backwhacks (\)
        $ThisServer = @($LiteralPath -split '\\' |
            Where-Object -FilterScript { $_ -ne '' })[0]

        $ThisServer -replace '\?', (hostname)
    }

}
function Format-FolderPermission {

    Param (

        # Expects ACEs grouped using Group-Object
        $UserPermission,

        # Ignore these FileSystemRights
        [string[]]$FileSystemRightsToIgnore = @('Synchronize'),

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    begin {
        $i = 0

        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Verbose'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }
    }
    process {

        ForEach ($ThisUser in $UserPermission) {

            $i++
            #Calculate the completion percentage, and format it to show 0 decimal places
            $percentage = "{0:N0}" -f (($i / ($UserPermission.Count)) * 100)

            #Update the log with the current status
            [string]$statusMsg = "Status: $percentage% - Processing user permission $i of " + $UserPermission.Count + ": " + $ThisUser.Name
            Write-LogMsg @LogParams -Text $statusMsg

            #Display the progress bar
            $status = "$(Get-Date -Format s)`t$ThisHostName`tFormat-FolderPermission`t$statusMsg"
            Write-Progress -Activity ("Total Users: " + $UserPermission.Count) -Status $status -PercentComplete $percentage

            if ($ThisUser.Group.DirectoryEntry.Properties) {
                if (
                    (
                        $ThisUser.Group.DirectoryEntry |
                        ForEach-Object {
                            if ($null -ne $_) {
                                $_.GetType().FullName 2>$null
                            }
                        }
                    ) -contains 'System.Management.Automation.PSCustomObject'
                ) {
                    $Names = $ThisUser.Group.DirectoryEntry.Properties.Name
                    $Depts = $ThisUser.Group.DirectoryEntry.Properties.Department
                    $Titles = $ThisUser.Group.DirectoryEntry.Properties.Title
                }
                else {
                    $Names = $ThisUser.Group.DirectoryEntry |
                    ForEach-Object {
                        if ($_.Properties) {
                            $_.Properties['name']
                        }
                    }

                    $Depts = $ThisUser.Group.DirectoryEntry |
                    ForEach-Object {
                        if ($_.Properties) {
                            $_.Properties['department']
                        }
                    }

                    $Titles = $ThisUser.Group.DirectoryEntry |
                    ForEach-Object {
                        if ($_.Properties) {
                            $_.Properties['title']
                        }
                    }

                    if ($ThisUser.Group.DirectoryEntry.Properties['objectclass'] -contains 'group' -or
                        "$($ThisUser.Group.DirectoryEntry.Properties['groupType'])" -ne ''
                    ) {
                        $SchemaClassName = 'group'
                    }
                    else {
                        $SchemaClassName = 'user'
                    }
                }
                $Name = @($Names)[0]
                $Dept = @($Depts)[0]
                $Title = @($Titles)[0]
            }
            else {
                $Name = @($ThisUser.Group.name)[0]
                $Dept = @($ThisUser.Group.department)[0]
                $Title = @($ThisUser.Group.title)[0]

                if ($ThisUser.Group.Properties) {
                    if (
                        $ThisUser.Group.Properties['objectclass'] -contains 'group' -or
                        "$($ThisUser.Group.Properties['groupType'])" -ne ''
                    ) {
                        $SchemaClassName = 'group'
                    }
                    else {
                        $SchemaClassName = 'user'
                    }
                }
                else {
                    if ($ThisUser.Group.DirectoryEntry.SchemaClassName) {
                        $SchemaClassName = @($ThisUser.Group.DirectoryEntry.SchemaClassName)[0]
                    }
                    else {
                        $SchemaClassName = @($ThisUser.Group.SchemaClassName)[0]
                    }
                }
            }
            if ("$Name" -eq '') {
                $Name = $ThisUser.Name
            }

            ForEach ($ThisACE in $ThisUser.Group) {

                switch ($ThisACE.ACEInheritanceFlags) {
                    'ContainerInherit, ObjectInherit' { $Scope = 'this folder, subfolders, and files' }
                    'ContainerInherit' { $Scope = 'this folder and subfolders' }
                    'ObjectInherit' { $Scope = 'this folder and files, but not subfolders' }
                    default { $Scope = 'this folder but not subfolders' }
                }

                if ($null -eq $ThisUser.Group.IdentityReference) {
                    $IdentityReference = $null
                }
                else {
                    $IdentityReference = $ThisACE.ACEIdentityReferenceResolved
                }

                $FileSystemRights = $ThisACE.ACEFileSystemRights
                ForEach ($Ignore in $FileSystemRightsToIgnore) {
                    $FileSystemRights = $FileSystemRights -replace ", $Ignore\Z", '' -replace "$Ignore,", ''
                }

                [pscustomobject]@{
                    Folder                   = $ThisACE.ACESourceAccessList.Path
                    FolderInheritanceEnabled = !($ThisACE.ACESourceAccessList.AreAccessRulesProtected)
                    Access                   = "$($ThisACE.ACEAccessControlType) $FileSystemRights $Scope"
                    Account                  = $ThisUser.Name
                    Name                     = $Name
                    Department               = $Dept
                    Title                    = $Title
                    IdentityReference        = $IdentityReference
                    AccessControlEntry       = $ThisACE
                    SchemaClassName          = $SchemaClassName
                }

            }

        }

    }

    end {
        Write-Progress -Activity ("Total User Permissions: " + $UserPermission.Count) -Completed
    }

}
function Format-SecurityPrincipal {

    # Format Security Principals (distinguish group members from principals directly listed in the NTFS DACLs)
    # The IdentityReference property will be null for any principals directly listed in the NTFS DACLs

    param (

        # Security Principals received from Expand-IdentityReference in the Adsi module
        $SecurityPrincipal

    )

    ForEach ($ThisPrincipal in $SecurityPrincipal) {

        # Format and output the security principal
        $ThisPrincipal |
        Select-Object -ExcludeProperty Name -Property @{
            Label      = 'User'
            Expression = {
                $ThisPrincipalAccount = $null
                if ($_.Properties) {
                    $ThisPrincipalAccount = $_.Properties['sAmAccountName']
                }
                if ("$ThisPrincipalAccount" -eq '') {
                    $_.Name
                }
                else {
                    $ThisPrincipalAccount
                }
            }
        },
        @{
            Label      = 'IdentityReference'
            Expression = { $null }
        },
        @{
            Label      = 'NtfsAccessControlEntries'
            Expression = { $_.Group }
        },
        @{
            Label      = 'Name'
            Expression = {
                $ThisName = $null
                if ($_.DirectoryEntry.Properties) {
                    $ThisName = $_.DirectoryEntry.Properties['name']
                }
                if ("$ThisName" -eq '') {
                    $_.Name -replace [regex]::Escape("$($_.DomainNetBios)\"), ''
                }
                else {
                    $ThisName
                }
            }
        },
        *

        # Format and output its members if it is a group
        $ThisPrincipal.Members |
        Select-Object -Property @{
            Label      = 'User'
            Expression = {
                $ThisPrincipalAccount = $null
                if ($_.Properties) {
                    $ThisPrincipalAccount = $_.Properties['sAmAccountName']
                    if ("$ThisPrincipalAccount" -eq '') {
                        $ThisPrincipalAccount = $_.Properties['Name']
                    }
                }

                if ("$ThisPrincipalAccount" -eq '') {
                    # This code should never execute
                    # but if we are somehow not dealing with a DirectoryEntry,
                    # it will not have sAmAcountName or Name properties
                    # However it may have a direct Name attribute on the PSObject itself
                    # We will attempt that as a last resort in hopes of avoiding a null Account name
                    $ThisPrincipalAccount = $_.Name
                }
                "$($_.Domain.Netbios)\$ThisPrincipalAccount"
            }
        },
        @{
            Label      = 'IdentityReference'
            Expression = {
                @($ThisPrincipal.Group.IdentityReferenceResolved)[0]
            }
        },
        @{
            Label      = 'NtfsAccessControlEntries'
            Expression = { $ThisPrincipal.Group }
        },
        @{
            Label      = 'ObjectType'
            Expression = { $_.SchemaClassName }
        },
        *

    }

}
function Get-DirectorySecurity {
    <#
    .SYNOPSIS
    Alternative to Get-Acl designed to be as lightweight and flexible as possible
        Lightweight: Does not return the Path property like Get-Acl does
        Flexible how?  Was it long paths?  DFS?  Can't remember what didn't work with Get-Acl
    TEMP NOTE: Get-DirectorySecurity combined with Get-FileSystemAccessRule is basically what Get-FolderACE does
    .DESCRIPTION
    Returns an object for each access control entry instead of a single object for the ACL
    Excludes inherited permissions by default but allows them to be included with the -IncludeInherited switch parameter
    .INPUTS
    None. Pipeline input is not accepted.
    .OUTPUTS
    [PSCustomObject]
    .NOTES
    Currently only supports Directories but could easily be copied to support files, or Registry or AD providers
    #>

    param(

        # Path to the directory whose permissions to get
        [string]$LiteralPath,

        # Include all sections except Audit because it requires admin rights if run on the local system and we want to avoid that requirement
        [System.Security.AccessControl.AccessControlSections]$Sections = (
            [System.Security.AccessControl.AccessControlSections]::Access -bor
            [System.Security.AccessControl.AccessControlSections]::Owner -bor
            [System.Security.AccessControl.AccessControlSections]::Group)

    )

    [System.Security.AccessControl.DirectorySecurity]::new(
        $LiteralPath,
        $Sections
    )

}
function Get-FileSystemAccessRule {
    <#
    .SYNOPSIS
    Alternative to Get-Acl designed to be as lightweight and flexible as possible
    TEMP NOTE: Get-DirectorySecurity combined with Get-FileSystemAccessRule is basically what Get-FolderACE does
    .DESCRIPTION
    Returns an object for each access control entry instead of a single object for the ACL
    Excludes inherited permissions by default but allows them to be included with the -IncludeInherited switch parameter
    .INPUTS
    None. Pipeline input is not accepted.
    .OUTPUTS
    [PSCustomObject]
    .NOTES
    Currently only supports Directories but could easily be copied to support files, or Registry or AD providers
    #>

    param(

        # Discretionary Access List whose FileSystemAccessRules to return
        [System.Security.AccessControl.DirectorySecurity]$DirectorySecurity,

        # Include inherited Access Control Entries in the results
        [Switch]$IncludeInherited,

        # Include non-inherited Access Control Entries in the results
        [bool]$IncludeExplicitRules = $true,

        # Type of IdentityReference to return in each ACE
        [System.Type]$AccountType = [System.Security.Principal.SecurityIdentifier],

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Hashtable of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    $AccessRules = $DirectorySecurity.GetAccessRules($IncludeExplicitRules, $IncludeInherited, $AccountType)
    if ($AccessRules.Count -lt 1) {
        Write-LogMsg @LogParams -Text "# Found no matching access rules for '$LiteralPath'"
        return
    }

    $ACEPropertyNames = (Get-Member -InputObject $AccessRules[0] -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
    ForEach ($ThisAccessRule in $AccessRules) {
        $ACEProperties = @{
            SourceAccessList = $SourceAccessList
            Source           = 'Discretionary Access List'
        }
        ForEach ($ThisProperty in $ACEPropertyNames) {
            $ACEProperties[$ThisProperty] = $ThisAccessRule.$ThisProperty
        }
        [PSCustomObject]$ACEProperties
    }

    <#
    The creator of a folder is the Owner
    Unless S-1-3-4 (Owner Rights) is in the DACL, the Owner is implicitly granted two standard access rights defined in WinNT.h of the Win32 API:
      READ_CONTROL: The right to read the information in the object's security descriptor, not including the information in the system access control list (SACL).
      WRITE_DAC: The right to modify the discretionary access control list (DACL) in the object's security descriptor.
    Output an object for the Owner as well to represent that they have Full Control
    #>
    [PSCustomObject]@{
        SourceAccessList  = $SourceAccessList
        Source            = 'Ownership'
        IsInherited       = $false
        IdentityReference = $DirectorySecurity.Owner -replace '^O:', ''
        FileSystemRights  = [System.Security.AccessControl.FileSystemRights]::FullControl
        InheritanceFlags  = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        PropagationFlags  = [System.Security.AccessControl.PropagationFlags]::None
        AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
    }

}
function Get-FolderAce {
    <#
    .SYNOPSIS
    Alternative to Get-Acl designed to be as lightweight and flexible as possible
        Lightweight: Does not return the Path property like Get-Acl does
        Flexible how?  Was it long paths?  DFS?  Can't remember what didn't work with Get-Acl
    .DESCRIPTION
    Returns an object for each access control entry instead of a single object for the ACL
    Excludes inherited permissions by default but allows them to be included with the -IncludeInherited switch parameter
    .INPUTS
    None. Pipeline input is not accepted.
    .OUTPUTS
    [PSCustomObject]
    .NOTES
    Currently only supports Directories but could easily be copied to support files, or Registry or AD providers
    #>

    param(

        # Path to the directory whose permissions to get
        [string]$LiteralPath,

        # Include inherited Access Control Entries in the results
        [Switch]$IncludeInherited,

        # Include all sections except Audit because it requires admin rights if run on the local system and we want to avoid that requirement
        [System.Security.AccessControl.AccessControlSections]$Sections = (
            [System.Security.AccessControl.AccessControlSections]::Access -bor
            [System.Security.AccessControl.AccessControlSections]::Owner -bor
            [System.Security.AccessControl.AccessControlSections]::Group),

        # Include non-inherited Access Control Entries in the results
        [bool]$IncludeExplicitRules = $true,

        # Type of IdentityReference to return in each ACE
        [System.Type]$AccountType = [System.Security.Principal.SecurityIdentifier],

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Thread-safe cache of items and their owners
        [System.Collections.Concurrent.ConcurrentDictionary[String, PSCustomObject]]$OwnerCache = [System.Collections.Concurrent.ConcurrentDictionary[String, PSCustomObject]]::new()

    )

    # Use the same timestamp twice for efficiency through reduced calls to Get-Date, and for easy matching of the corresponding log entries
    $Timestamp = Get-Date -Format 'yyyy-MM-ddThh:mm:ss.ffff'

    Write-Debug "  $Timestamp`t$TodaysHostname`t$WhoAmI`t$($MyInvocation.ScriptLineNumber)`tGet-FolderAce`t$($MyInvocation.ScriptLineNumber)`tDebug`t[System.Security.AccessControl.DirectorySecurity]::new('$LiteralPath', '$Sections')"
    $DirectorySecurity = & { [System.Security.AccessControl.DirectorySecurity]::new(
            $LiteralPath,
            $Sections
        )
    } 2>$null

    if ($null -eq $DirectorySecurity) {
        Write-Warning "$Timestamp`t$TodaysHostname`t$WhoAmI`t$($MyInvocation.ScriptLineNumber)`tGet-FolderAce`t$($MyInvocation.ScriptLineNumber)`tDebug`t# Found no ACL for '$LiteralPath'" -Type Warning @LogParams
        return
    }

    <#
    Get-Acl would have already populated the Path property on the Access List, but [System.Security.AccessControl.DirectorySecurity] has a null Path property instead
    Creating new PSCustomObjects with all the original properties then manually setting the Path is faster than using Add-Member
    #>
    $AclProperties = @{}
    ForEach (
        $ThisProperty in
        (Get-Member -InputObject $DirectorySecurity -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
    ) {
        $AclProperties[$ThisProperty] = $DirectorySecurity.$ThisProperty
    }
    $AclProperties['Path'] = $LiteralPath

    <#
    The creator of a folder is the Owner
    Unless S-1-3-4 (Owner Rights) is in the DACL, the Owner is implicitly granted two standard access rights defined in WinNT.h of the Win32 API:
      READ_CONTROL: The right to read the information in the object's security descriptor, not including the information in the system access control list (SACL).
      WRITE_DAC: The right to modify the discretionary access control list (DACL) in the object's security descriptor.

    Previously the .Owner property was already populated with the NTAccount name of the Owner,
    but for some reason this stopped being true and now I have to call the GetOwner method.
    This at least lets us specify the AccountType to match what is used when calling the GetAccessRules method.
    #>
    $AclProperties['Owner'] = $DirectorySecurity.GetOwner($AccountType).Value

    $SourceAccessList = [PSCustomObject]$AclProperties

    # Update the OwnerCache with the Source Access List, so that Get-OwnerAce can output an object for the Owner to represent that they have Full Control
    $OwnerCache[$LiteralPath] = $SourceAccessList

    # Use the same timestamp twice for efficiency through reduced calls to Get-Date, and for easy matching of the corresponding log entries
    $Timestamp = Get-Date -Format 'yyyy-MM-ddThh:mm:ss.ffff'
    Write-Debug "  $Timestamp`t$TodaysHostname`t$WhoAmI`t$($MyInvocation.InvocationName)`tGet-FolderAce`t$($MyInvocation.ScriptLineNumber)`tDebug`t[System.Security.AccessControl.DirectorySecurity]::new('$LiteralPath', '$Sections').GetAccessRules(`$$IncludeExplicitRules, `$$IncludeInherited, [$AccountType])"
    $AccessRules = $DirectorySecurity.GetAccessRules($IncludeExplicitRules, $IncludeInherited, $AccountType)
    if ($AccessRules.Count -lt 1) {
        Write-Debug "  $Timestamp`t$TodaysHostname`t$WhoAmI`t$($($MyInvocation.ScriptLineNumber))`tGet-FolderAce`t$($MyInvocation.ScriptLineNumber)`tDebug`t# Found no matching access rules for '$LiteralPath'"
        return
    }

    $ACEPropertyNames = (Get-Member -InputObject $AccessRules[0] -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
    ForEach ($ThisAccessRule in $AccessRules) {
        $ACEProperties = @{
            SourceAccessList = $SourceAccessList
            Source           = 'Discretionary Access Control List'
        }
        ForEach ($ThisProperty in $ACEPropertyNames) {
            $ACEProperties[$ThisProperty] = $ThisAccessRule.$ThisProperty
        }
        [PSCustomObject]$ACEProperties
    }

}
function Get-OwnerAce {

    param (

        # Path to the parent item whose owners to export
        [string]$Item,

        # Thread-safe cache of items and their owners
        [System.Collections.Concurrent.ConcurrentDictionary[String, PSCustomObject]]$OwnerCache = [System.Collections.Concurrent.ConcurrentDictionary[String, PSCustomObject]]::new()

    )

    # ToDo - Confirm the logic for selecting this to make sure it accurately represents NTFS ownership behavior, then replace this comment with that confirmation and an explanation
    $InheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit

    $SourceAccessList = $OwnerCache[$Item]
    $ThisParent = $Item.Substring(0, [math]::Max($Item.LastIndexOf('\'), 0)) # ToDo - This method of finding the parent path is faster than Split-Path -Parent but it has a dependency on a folder path not containing a trailing \ which is not currently what I am seeing in my simple test but should be supported in the future (possibly default)
    if ($SourceAccessList.Owner -ne $OwnerCache[$ThisParent].Owner) {
        [PSCustomObject]@{
            SourceAccessList  = $SourceAccessList
            IdentityReference = $SourceAccessList.Owner
            AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
            FileSystemRights  = [System.Security.AccessControl.FileSystemRights]::FullControl
            InheritanceFlags  = $InheritanceFlags
            IsInherited       = $false
            PropagationFlags  = [System.Security.AccessControl.PropagationFlags]::None
            Source            = 'Ownership'
        }

    }

}
function Get-Subfolder {

    # Use the fastest available method to enumerate subfolders

    [CmdletBinding()]
    param (

        # Parent folder whose subfolders to enumerate
        [string]$TargetPath,

        <#
        How many levels of subfolder to enumerate
            Set to 0 to ignore all subfolders
            Set to -1 (default) to recurse infinitely
            Set to any whole number to enumerate that many levels
        #>
        [int]$FolderRecursionDepth = -1
    )

    if ($FolderRecursionDepth -eq -1) {
        $DepthString = '∞'
    } else {
        $DepthString = $FolderRecursionDepth
    }
    Write-Progress -Activity ("Retrieving subfolders...") -Status ("Enumerating all subfolders of '$TargetPath' to a depth of $DepthString levels of recursion") -PercentComplete 50
    if ($Host.Version.Major -gt 2) {
        switch ($FolderRecursionDepth) {
            -1 {
                GetDirectories -TargetPath $TargetPath -SearchOption ([System.IO.SearchOption]::AllDirectories)
            }
            0 {}
            1 {
                GetDirectories -TargetPath $TargetPath -SearchOption ([System.IO.SearchOption]::TopDirectoryOnly)
            }
            Default {
                $FolderRecursionDepth = $FolderRecursionDepth - 1
                Write-Debug "  $(Get-Date -Format s)`t$(hostname)`tGet-Subfolder`tGet-ChildItem '$TargetPath' -Force -Name -Recurse -Attributes Directory -Depth $FolderRecursionDepth"
                (Get-ChildItem $TargetPath -Force -Recurse -Attributes Directory -Depth $FolderRecursionDepth).FullName
            }
        }
    } else {
        Write-Debug "  $(Get-Date -Format s)`t$(hostname)`tGet-Subfolder`tGet-ChildItem '$TargetPath' -Recurse"
        Get-ChildItem $TargetPath -Recurse | Where-Object -FilterScript { $_.PSIsContainer } | ForEach-Object { $_.FullName }
    }
    Write-Progress -Activity ("Retrieving subfolders...") -Completed
}
function Get-Win32MappedLogicalDisk {
    param (
        [string]$ComputerName,

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        <#
        FQDN of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages
    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    if (
        $ComputerName -eq $ThisHostname -or
        $ComputerName -eq "$ThisHostname." -or
        $ComputerName -eq $ThisFqdn
    ) {
        Write-LogMsg @LogParams -Text "Get-CimInstance -ClassName Win32_MappedLogicalDisk"
        Get-CimInstance -ClassName Win32_MappedLogicalDisk
    }
    else {
        Write-LogMsg @LogParams -Text "Get-CimInstance -ComputerName $ComputerName -ClassName Win32_MappedLogicalDisk"
        # If an Active Directory domain is targeted there are no local accounts and CIM connectivity is not expected
        # Suppress errors and return nothing in that case
        Get-CimInstance -ComputerName $ComputerName -ClassName Win32_MappedLogicalDisk -ErrorAction SilentlyContinue
    }
}
function New-NtfsAclIssueReport {

    param (

        $FolderPermissions,

        $UserPermissions,

        <#
        If specified, all groups that have NTFS access to the target folder/subfolders will be evaluated for compliance with this naming convention
        The naming format that will be used for the users is CONTOSO\User1 where CONTOSO is the NetBIOS name of the domain, and User1 is the samAccountName of the user
        By default, this is a scriptblock that always evaluates to $true so it doesn't evaluate any naming convention compliance
        #>
        [scriptblock]$GroupNameRule = { $true },

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages
    )

    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Verbose'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }

    $IssuesDetected = $false

    # List of folders with broken inheritance (recommend moving to higher level to avoid breaking inheritance.  Deny entries are a less desirable alternative)
    $FoldersWithBrokenInheritance = $FolderPermissions |
    Select-Object -Skip 1 |
    Where-Object -FilterScript {
        @($_.Group.FolderInheritanceEnabled)[0] -eq $false -and
                (($_.Name -replace ([regex]::Escape($TargetPath)), '' -split '\\') | Measure-Object).Count -ne 2
    }
    $Count = ($FoldersWithBrokenInheritance | Measure-Object).Count
    if ($Count -gt 0) {
        $IssuesDetected = $true
        $Txt = "folders with broken inheritance: $($FoldersWithBrokenInheritance.Name -join "`r`n")"
    }
    else {
        $Txt = 'OK'
    }
    Write-LogMsg @LogParams -Text "$Count $Txt"

    # List of ACEs for groups that do not match the specified naming convention
    # Invert the naming convention scriptblock (because we actually want to identify groups that do NOT follow the convention)
    $ViolatesNamingConvention = [scriptblock]::Create("!($GroupNameRule)")
    $NonCompliantGroups = $SecurityPrincipals |
    Where-Object -FilterScript { $_.ObjectType -contains 'Group' } |
    Where-Object -FilterScript $ViolatesNamingConvention |
    Select-Object -ExpandProperty Group |
    ForEach-Object { "$($_.IdentityReference) on '$($_.Path)'" }

    $Count = ($NonCompliantGroups | Measure-Object).Count
    if ($Count -gt 0) {
        $IssuesDetected = $true
        $Txt = "groups that don't match naming convention: $($NonCompliantGroups -join "`r`n")"
    }
    else {
        $Txt = 'OK'
    }
    Write-LogMsg @LogParams -Text "$Count $Txt"

    # ACEs for users (recommend replacing with group-based access on any folder that is not a home folder)
    $UserACEs = $UserPermissions.Group |
    Where-Object -FilterScript {
        $_.ObjectType -contains 'User' -and
        $_.ACEIdentityReference -ne 'S-1-5-18' # The 'NT AUTHORITY\SYSTEM' account is part of default Windows file permissions and is out of scope
    } |
    ForEach-Object { "$($_.User) on '$($_.SourceAclPath)'" } |
    Sort-Object -Unique
    $Count = ($UserACEs | Measure-Object).Count
    if ($Count -gt 0) {
        $IssuesDetected = $true
        $Txt = "users with ACEs: $($UserACEs -join "`r`n")"
    }
    else {
        $Txt = 'OK'
    }
    Write-LogMsg @LogParams -Text "$Count $Txt"

    # ACEs for unresolvable SIDs (recommend removing these ACEs)
    $SIDsToCleanup = $UserPermissions.Group.NtfsAccessControlEntries |
    Where-Object -FilterScript { $_.IdentityReference -match 'S-\d+-\d+-\d+-\d+-\d+\-\d+\-\d+' } |
    ForEach-Object { "$($_.IdentityReference) on '$($_.Path)'" } |
    Sort-Object -Unique
    $Count = ($SIDsToCleanup | Measure-Object).Count
    if ($Count -gt 0) {
        $IssuesDetected = $true
        $Txt = "ACEs for unresolvable SIDs: $($SIDsToCleanup -join "`r`n")"
    }
    else {
        $Txt = 'OK'
    }
    Write-LogMsg @LogParams -Text "$Count $Txt"

    # CREATOR OWNER access (recommend replacing with group-based access, or with explicit user access for a home folder.)
    $FoldersWithCreatorOwner = ($UserPermissions | ? { $_.Name -match 'CREATOR OWNER' }).Group.NtfsAccessControlEntries.Path | Sort -Unique
    $Count = ($FoldersWithCreatorOwner | Measure-Object).Count
    if ($Count -gt 0) {
        $IssuesDetected = $true
        $Txt = "folders with 'CREATOR OWNER' ACEs: $($FoldersWithCreatorOwner -join "`r`n")"
    }
    else {
        $Txt = 'OK'
    }
    Write-LogMsg @LogParams -Text "$Count $Txt"

    [PSCustomObject]@{
        IssueDetected                = $IssuesDetected
        FoldersWithBrokenInheritance = $FoldersWithBrokenInheritance
        NonCompliantGroups           = $NonCompliantGroups
        UserACEs                     = $UserACEs
        SIDsToCleanup                = $SIDsToCleanup
        FoldersWithCreatorOwner      = $FoldersWithCreatorOwner
    }

}
function Resolve-Folder {

    # Resolve the provided FolderPath to all of its associated UNC paths

    param (
        [string[]]$FolderPath
    )

    process {
        foreach ($TargetPath in $FolderPath) {

            $RegEx = '^(?<DriveLetter>\w):'
            if ($TargetPath -match $RegEx) {
                $MappedNetworkDrives = Get-Win32MappedLogicalDisk

                $MatchingNetworkDrive = $MappedNetworkDrives |
                Where-Object -FilterScript { $_.DeviceID -eq "$($Matches.DriveLetter):" }

                if ($MatchingNetworkDrive) {
                    # Resolve mapped network drives to their UNC path
                    $UNC = $MatchingNetworkDrive.ProviderName
                }
                else {
                    # Resolve local drive letters to their UNC paths using administrative shares
                    $UNC = $TargetPath -replace $RegEx, "\\$(hostname)\$($Matches.DriveLetter)$"
                }
                if ($UNC) {
                    # Replace hostname with FQDN in the path
                    $Server = $UNC.split('\')[2]
                    $FQDN = ConvertTo-DnsFqdn -ComputerName $Server
                    $UNC -replace "^\\\\$Server\\", "\\$FQDN\"
                }
            }
            else {
                ## Workaround in place: Get-NetDfsEnum -Verbose parameter is not used due to errors when it is used with the PsRunspace module for multithreading
                ## https://github.com/IMJLA/Export-Permission/issues/46
                ## https://github.com/IMJLA/PsNtfs/issues/1
                $AllDfs = Get-NetDfsEnum -FolderPath $TargetPath -ErrorAction SilentlyContinue

                if ($AllDfs) {
                    $MatchingDfsEntryPaths = $AllDfs |
                    Group-Object -Property DfsEntryPath |
                    Where-Object -FilterScript {
                        $TargetPath -match [regex]::Escape($_.Name)
                    }

                    # Filter out the DFS Namespace
                    # TODO: I know this is an inefficient n2 algorithm, but my brain is fried...plez...halp...leeloo dallas multipass
                    $RemainingDfsEntryPaths = $MatchingDfsEntryPaths |
                    Where-Object -FilterScript {
                        -not [bool]$(
                            ForEach ($ThisEntryPath in $MatchingDfsEntryPaths) {
                                if ($ThisEntryPath.Name -match "$([regex]::Escape("$($_.Name)")).+") { $true }
                            }
                        )
                    } |
                    Sort-Object -Property Name

                    $RemainingDfsEntryPaths |
                    Select-Object -Last 1 -ExpandProperty Group |
                    ForEach-Object {
                        $_.FullOriginalQueryPath -replace [regex]::Escape($_.DfsEntryPath), $_.DfsTarget
                    }
                }
                else {
                    $Server = $TargetPath.split('\')[2]
                    $FQDN = ConvertTo-DnsFqdn -ComputerName $Server
                    $TargetPath -replace "^\\\\$Server\\", "\\$FQDN\"
                }

            }
        }
    }

}
<#
# Dot source any functions
ForEach ($ThisScript in $ScriptFiles) {
    # Dot source the function
    . $($ThisScript.FullName)
}
#>

# Definition of Module 'PsLogMessage' Version '1.0.20' is below

function ConvertTo-DnsFqdn {

    # Output the results of a DNS lookup to the default DNS server for the specified

    # Wrapper for [System.Net.Dns]::GetHostByName([string]$ComputerName)

    param (

        [string]$ComputerName,

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        LogMsgCache  = $LogMsgCache
        WhoAmI       = $WhoAmI
    }
    Write-LogMsg @LogParams -Text "[System.Net.Dns]::GetHostByName('$ComputerName')"
    [System.Net.Dns]::GetHostByName($ComputerName).HostName # -replace "^$ThisHostname", "$ThisHostname" #replace does not appear to be needed, capitalization is correct from GetHostByName()

}
function Get-CurrentHostName {
    # Future function to universally retrieve hostname using various methods (in order of preference):
    # hostname.exe
    # $env:hostname
    # CIM
    # other?
}
function Get-CurrentWhoAmI {

    # Output the results of whoami.exe after editing them to correct capitalization

    # whoami.exe returns lowercase but we want to honor the correct capitalization

    # Correct capitalization is regurned from $ENV:USERNAME

    param (

        <#
        Hostname of the computer running this function.

        Can be provided as a string to avoid calls to HOSTNAME.EXE
        #>
        [string]$ThisHostName = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Dictionary of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    $WhoAmI -replace "^$ThisHostname\\", "$ThisHostname\" -replace "$ENV:USERNAME", $ENV:USERNAME
    if (-not $PSBoundParameters.ContainsKey('WhoAmI')) {
        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            LogMsgCache  = $LogMsgCache
            WhoAmI       = $WhoAmI
        }
        # Technically this exe has already been run, but it is advantageous to offer it as a parameter
        # Also, this way the log will use the correct capitalization
        Write-LogMsg @LogParams -Text "& whoami.exe"
    }
}
function New-DatedSubfolder {
    # Creates a folder structure with a folder for each year and month
    # Then it creates one timestamped folder inside the appropriate month
    # This folder is intended to be used to store output from a single execution of a script
    param (
        [parameter(Mandatory)]
        [string]$Root,

        # A suffix to append to the folder name
        [string]$Suffix
    )
    $Year = Get-Date -Format 'yyyy'
    $Month = Get-Date -Format 'MM'
    $Timestamp = (Get-Date -Format s) -replace ':', '-'

    $NewDir = "$Root\$Year\$Month\$Timestamp$Suffix"

    $null = New-Item -ItemType Directory -Path $NewDir -ErrorAction SilentlyContinue
    Write-Output $NewDir
}
function Write-LogMsg {

    <#
        .SYNOPSIS
            Prepend a prefix to a log message, write the message to an output stream, and write the message to a text file.
            Writes a message to a log file and/or PowerShell output stream
        .DESCRIPTION
            Prepends the log message with:
                a current timestamp
                the current hostname
                the current username
                the current command (function or file name)
                the current location (line number in the code)

            Tab-delimits these fields for a compromise between readability and parseability

            Adds the log message to either:
            * a hashtable (which can be thread-safe) using the timestamp as the key, which was passed to the $LogMsgCache parameter
            * a Global:$LogMessages variable which was created by the PsLogMessage module during import

            Optionally writes the message to a log file

            Optionally writes the message to a PowerShell output stream
        .INPUTS
        [System.String]$Text parameter
        .OUTPUTS
        [System.String] Resulting log line, returned if the -PassThru or -Type Output parameters were used
    #>
    [OutputType([System.String])]
    [CmdletBinding()]
    param(

        # Message to log
        [Parameter(Position = 0, ValueFromPipeline)]
        [string]$Text,

        # Output stream to send the message to
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$Type = 'Information',

        # Add a prefix to the message including the date, hostname, current user, and info about the current call stack
        [bool]$AddPrefix = $true,

        # Text file to append the log message to
        [string]$LogFile,

        # Output the message to the pipeline
        [bool]$PassThru = $false,

        # Hostname to use in the log messages and/or output object
        [string]$ThisHostname = (HOSTNAME.EXE),

        # Hostname to use in the log messages and/or output object
        [string]$WhoAmI = (whoami.EXE),

        [hashtable]$LogMsgCache = $Global:LogMessages

    )


    # This will ensure the message is not written to any PowerShell output streams or log files
    if ($Type -eq 'Silent') { return }

    $Timestamp = Get-Date -Format 'yyyy-MM-ddThh:mm:ss.ffff'
    $OutputToPipeline = $false
    $PSCallStack = Get-PSCallStack

    if ($AddPrefix) {
        # This method is faster than StringBuilder or the -join operator
        [string]$MessageToLog = "$Timestamp`t$ThisHostname`t$WhoAmI`t$($PSCallStack[1].Location)`t$($PSCallStack[1].Command)`t$($MyInvocation.ScriptLineNumber)`t$($Type)`t$($Text)"
    } else {
        [string]$MessageToLog = $Text
    }

    Switch ($Type) {

        # This will ensure the message is added to log files, but not written to any PowerShell output streams
        'Quiet' {}

        # This one is made-up to correspond with the 'success' contextual class in Bootstrap.
        'Success' { Write-Information "SUCCESS: $MessageToLog" }

        # These represent normal PowerShell output streams
        # The correct number of spaces should be added to maintain proper column alignment
        'Debug' { Write-Debug "  $MessageToLog" }
        'Verbose' { Write-Verbose $MessageToLog }
        'Host' { Write-Host "HOST:    $MessageToLog" }
        'Warning' { Write-Warning $MessageToLog }
        'Error' { Write-Error $MessageToLog }
        'Output' { $OutputToPipeline = $true }
        default { Write-Information "INFO:    $MessageToLog" }
    }

    if ('' -ne $LogFile) {
        $MessageToLog | Out-File $LogFile -Append
    }

    if ($PassThru -or $OutputToPipeline) {
        $MessageToLog
    }

    # Add a GUID to the timestamp and use it as a unique key in the hashtable of log messages
    [string]$Guid = [guid]::NewGuid()
    [string]$Key = "$Timestamp$Guid"

    $LogMsgCache[$Key] = [pscustomobject]@{
        Timestamp = $Timestamp
        Hostname  = $ThisHostname
        WhoAmI    = $WhoAmI
        Location  = $PSCallStack[1].Location
        Command   = $PSCallStack[1].Command
        Line      = $MyInvocation.ScriptLineNumber
        Type      = $Type
        Text      = $Text
    }

}
<#
# Add any custom C# classes as usable (exported) types
$CSharpFiles = Get-ChildItem -Path "$PSScriptRoot\*.cs"
ForEach ($ThisFile in $CSharpFiles) {
    Add-Type -Path $ThisFile.FullName -ErrorAction Stop
}
#>

#$Global:LogMessages = [system.collections.generic.list[pscustomobject]]::new()
$Global:LogMessages = [hashtable]::Synchronized(@{})

# Definition of Module 'PsRunspace' Version '1.0.104' is below

function Add-PsCommand {

    <#
    .Synopsis
        Add a command to a [System.Management.Automation.PowerShell] instance
    .Description
        Used by Invoke-Thread
        Uses AddScript() or AddStatement() and AddCommand() depending on the command
    .EXAMPLE
        [powershell]::Create() | Add-PsCommand -Command 'Write-Output'

        Add a command by sending a Cmdlet name to the -Command parameter
    #>

    param(

        # Powershell interface to add the Command to
        [Parameter(ValueFromPipeline = $true)]
        [powershell[]]$PowershellInterface,

        <#
        Command to add to the Powershell interface
        This can be a scriptblock object, or a string that specifies a:
            Alias
            Function (the name of the function)
            ExternalScript (the path to the .ps1 file)
            All, Application, Cmdlet, Configuration, Filter, or Script
        #>
        [Parameter(Position = 0)]
        $Command,

        # Output from Get-PsCommandInfo
        # Optional, to improve performance if it will be re-used for multiple calls of Add-PsCommand
        [pscustomobject]$CommandInfo,

        # Add Commands rather than their definitions
        [switch]$Force,

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Hashtable of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    begin {

        $LogParams = @{
            LogMsgCache  = $LogMsgCache
            ThisHostname = $TodaysHostname
            Type         = $DebugOutputStream
            WhoAmI       = $WhoAmI
        }

        $CommandInfoParams = @{
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogMsgCache       = $LogMsgCache
        }

        if ($CommandInfo -eq $null) {
            $CommandInfo = Get-PsCommandInfo @CommandInfoParams -Command $Command
        }

    }
    process {

        ForEach ($ThisPowershell in $PowershellInterface) {

            switch ($CommandInfo.CommandType) {

                'Alias' {
                    # Resolve the alias to its command and start from the beginning with that command.
                    $CommandInfo = Get-PsCommandInfo @CommandInfoParams -Command $CommandInfo.CommandInfo.Definition
                    $null = Add-PsCommand @CommandInfoParams -Command $CommandInfo.CommandInfo.Definition -CommandInfo $CommandInfo -PowershellInterface $ThisPowerShell
                }
                'Function' {

                    if ($Force) {
                        Write-LogMsg @LogParams -Text " # Adding command '$Command' of type '$($CommandInfo.CommandType)' (treating it as a command instead of a Function because -Force was used)"
                        # If the type is All, Application, Cmdlet, Configuration, Filter, or Script then run the command as-is
                        Write-LogMsg @LogParams -Text "`$PowershellInterface.AddStatement().AddCommand('$Command')"
                        $null = $ThisPowershell.AddStatement().AddCommand($Command)
                    } else {
                        # Add the definitions of the function
                        # BUG: Look at the definition of Get-Member for example, it is not in a ScriptModule so its definition is not PowerShell code
                        [string]$ThisFunction = "function $($CommandInfo.CommandInfo.Name) {`r`n$($CommandInfo.CommandInfo.Definition)`r`n}"
                        Write-LogMsg @LogParams -Text " # Adding Script (the Definition of a Function, `$CommandInfo.CommandInfo.Definition not expanded below for brevity)"
                        ##Write-LogMsg @LogParams -Text "`$PowershellInterface.AddScript('function $($CommandInfo.CommandInfo.Name) { `$CommandInfo.CommandInfo.Definition }')"
                        Write-LogMsg @LogParams -Text "`$PowershellInterface.AddScript('$ThisFunction')"
                        $null = $ThisPowershell.AddScript($ThisFunction)
                    }
                }
                'ExternalScript' {
                    Write-LogMsg @LogParams -Text " # Adding Script (the ScriptBlock of an ExternalScript, `$CommandInfo.ScriptBlock not expanded below for brevity)"
                    ##Write-LogMsg @LogParams -Text "`$PowershellInterface.AddScript(`"`$(`$CommandInfo.ScriptBlock)`") # "
                    Write-LogMsg @LogParams -Text "`$PowershellInterface.AddScript('$($CommandInfo.ScriptBlock)')"
                    $null = $ThisPowershell.AddScript($CommandInfo.ScriptBlock)
                }
                'ScriptBlock' {
                    Write-LogMsg @LogParams -Text " # Adding Script (a ScriptBlock, not expanded below for brevity)"
                    ##Write-LogMsg @LogParams -Text "`$PowershellInterface.AddScript(`"`$Command`")
                    Write-LogMsg @LogParams -Text "`$PowershellInterface.AddScript('$Command')"
                    $null = $ThisPowershell.AddScript($Command)
                }
                default {
                    Write-LogMsg @LogParams -Text " # Adding command '$Command' of type '$($CommandInfo.CommandType)'"
                    # If the type is All, Application, Cmdlet, Configuration, Filter, or Script then run the command as-is
                    Write-LogMsg @LogParams -Text "`$PowershellInterface.AddStatement().AddCommand('$Command')"
                    $null = $ThisPowershell.AddStatement().AddCommand($Command)
                }

            }
        }
    }
}
function Add-PsModule {
    <#
    .Synopsis
        Import a Module in a [System.Management.Automation.Runspaces.InitialSessionState] instance
    .Description
        Used by Add-PsCommand
        Uses ImportPSModule() or ImportPSModulesFromPath() depending on the module
    .EXAMPLE
        $InitialSessionState = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
        Add-PsModule -InitialSessionState $InitialSessionState -ModuleInfo $ModuleInfo
    #>

    param(

        # Powershell interface to add the Command to
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.InitialSessionState]$InitialSessionState,

        <#
        ModuleInfo object for the module to add to the Powershell interface
        #>
        [Parameter(
            Position = 0
        )]
        [System.Management.Automation.PSModuleInfo[]]$ModuleInfo,

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Hashtable of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    begin {

        $LogParams = @{
            LogMsgCache  = $LogMsgCache
            ThisHostname = $TodaysHostname
            Type         = $DebugOutputStream
            WhoAmI       = $WhoAmI
        }

    }

    process {

        ForEach ($ThisModule in $ModuleInfo) {

            switch ($ThisModule.ModuleType) {
                'Binary' {
                    Write-LogMsg @LogParams -Text "`$InitialSessionState.ImportPSModule('$($ThisModule.Name)')"
                    $InitialSessionState.ImportPSModule($ThisModule.Name)
                }
                'Script' {
                    $ModulePath = Split-Path -Path $ThisModule.Path -Parent
                    Write-LogMsg @LogParams -Text "`$InitialSessionState.ImportPSModulesFromPath('$ModulePath')"
                    $InitialSessionState.ImportPSModulesFromPath($ModulePath)
                }
                'Manifest' {
                    $ModulePath = Split-Path -Path $ThisModule.Path -Parent
                    Write-LogMsg @LogParams -Text "`$InitialSessionState.ImportPSModulesFromPath('$ModulePath')"
                    $InitialSessionState.ImportPSModulesFromPath($ModulePath)
                }
                default {
                    # Scriptblocks or Functions not from modules will have no module to import so ModuleInfo will be null
                }

            }

        }

    }

}
function Convert-FromPsCommandInfoToString {
    param (
        [Parameter (
            Mandatory,
            Position = 0
        )]
        [PSCustomObject[]]$CommandInfo,

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Hashtable of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )
    begin {
        $CommandInfoParams = @{
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogMsgCache       = $LogMsgCache
        }
    }

    process {
        ForEach ($ThisCmd in $CommandInfo) {

            switch ($ThisCmd.CommandType) {

                'Alias' {
                    # Resolve the alias to its command and start from the beginning with that command
                    $ThisCmd = Get-PsCommandInfo @CommandInfoParams -Command $ThisCmd.CommandInfo.Definition
                    Convert-FromPsCommandInfoToString @CommandInfoParams -CommandInfo $ThisCmd
                }
                'Function' {
                    "function $($ThisCmd.CommandInfo.Name) {`r`n$($ThisCmd.CommandInfo.Definition)`r`n}"
                }
                'ExternalScript' {
                    "$($ThisCmd.ScriptBlock)"
                    #"$($ThisCmd.CommandInfo.ScriptBlock)"
                    #"$Command"
                }
                'ScriptBlock' {
                    "$Command"
                }
                default {
                    "$Command"
                }

            }
        }
    }
}
function Expand-PsCommandInfo {

    <#
    .SYNOPSIS
        Return the original PsCommandInfo object as well as CommandInfo objects for any nested commands
    #>

    param (
        # CommandInfo object for the command whose nested command names to return
        [PSCustomObject]$PsCommandInfo,

        # Cache of already identified CommmandInfo objects
        [hashtable]$Cache = [hashtable]::Synchronized(@{}),

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Hashtable of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages
    )

    $CommandInfoParams = @{
        DebugOutputStream = $DebugOutputStream
        TodaysHostname    = $TodaysHostname
        WhoAmI            = $WhoAmI
        LogMsgCache       = $LogMsgCache
    }

    # Add the first object to the cache
    if (-not $PsCommandInfo.CommandInfo.Name) {
        $PsCommandInfo
    } else {
        $Cache[$PsCommandInfo.CommandInfo.Name] = $PsCommandInfo
    }

    # Tokenize the function definition
    $PsTokens = $null
    $TokenizerErrors = $null
    $AbstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput(
        # We need the property which contains tokenizable PowerShell
        # For a function in a ScriptModule, the definition and scriptblock properties are the same
        # For an ExternalScript, the definition is the filepath and the scriptblock is tokenizable powershell
        # This is why the Scriptblock property has been chosen
        #$PsCommandInfo.CommandInfo.Definition,
        $PsCommandInfo.CommandInfo.Scriptblock,
        [ref]$PsTokens,
        [ref]$TokenizerErrors
    )

    # Get all nested tokens
    $AllPsTokens = Expand-PsToken -InputObject $PsTokens

    # Find any other functions we also need to add
    $CommandTokens = $AllPsTokens |
    Where-Object -FilterScript {
        $_.Kind -eq 'Generic' -and
        $_.TokenFlags.HasFlag([System.Management.Automation.Language.TokenFlags]::CommandName)
    }

    # Add the definitions of those functions if available
    # TODO: Add modules if available? Not needed at this time but maybe later
    ForEach ($ThisCommandToken in $CommandTokens) {
        if (
            -not $Cache[$ThisCommandToken.Value] -and
            $ThisCommandToken.Value -notmatch '[\.\\]' # Exclude any file paths since they are not PowerShell commands with tokenizable definitions (they contain \ or .)
        ) {
            $TokenCommandInfo = Get-PsCommandInfo @CommandInfoParams -Command $ThisCommandToken.Value
            $Cache[$ThisCommandToken.Value] = $TokenCommandInfo

            # Suppress the output of the Expand-PsCommandInfo function because we will instead be using the updated cache contents
            # This way the results are already deduplicated for us by the hashtable
            $null = Expand-PsCommandInfo @CommandInfoParams -PsCommandInfo $TokenCommandInfo -Cache $Cache
        }
    }

    # Output the objects in the cache
    ForEach ($ThisKey in $Cache.Keys) {
        $Cache[$ThisKey]
    }

}
function Expand-PsToken {
    <#
    .SYNOPSIS
        Recursively get nested tokens
    .DESCRIPTION
        Recursively emits all tokens embedded in a token of type "StringExpandable"
        The original token is also emitted.
    .EXAMPLE
        $Tokens = $null
        $TokenizerErrors = $null
        $AbstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput(
          [string]$Code,
          [ref]$Tokens,
          [ref]$TokenizerErrors
      )
      $Tokens |
      Expand-PsToken

      Return all tokens nested inside the provided $Code string (not scriptblock)
    #>

    param (
        # Management.Automation.Language.StringExpandableToken or
        # Management.Automation.Language.Token
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [psobject]$InputObject
    )

    process {
        if ($InputObject.GetType().FullName -eq 'Management.Automation.Language.StringExpandableToken]') {
            ForEach ($ThisToken in $InputObject.NestedTokens) {
                if ($ThisToken) {
                    Expand-PsToken -InputObject $ThisToken
                }
            }
        }
        $InputObject
    }

}
function Get-PsCommandInfo {

    <#
    .Synopsis
        Get info about a PowerShell command

    .Description
        Used by Split-Thread, Invoke-Thread, and Add-PsCommand

       Determine whether the Command is a [System.Management.Automation.ScriptBlock] object
       If not, passes it to the Name parameter of Get-Command

    .EXAMPLE
        The following demonstrates sending a Cmdlet name to the -Command parameter
            Get-PsCommandInfo -Command 'Write-Output'
    #>

    param(
        <#
        Command to retrieve info on
        This can be a scriptblock object, or a string that specifies an:
            Alias
            Function (the name of the function)
            ExternalScript (the path to the .ps1 file)
            All, Application, Cmdlet, Configuration, Filter, or Script
        #>
        $Command,

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Hashtable of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    $LogParams = @{
        LogMsgCache  = $LogMsgCache
        ThisHostname = $TodaysHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }

    if ($Command.GetType().FullName -eq 'System.Management.Automation.ScriptBlock') {
        [string]$CommandType = 'ScriptBlock'
    } else {
        $CommandInfo = Get-Command $Command -ErrorAction SilentlyContinue
        [string]$CommandType = $CommandInfo.CommandType
        if ($CommandInfo.Source -like "*\*") {
            $ModuleInfo = Get-Module -Name $CommandInfo.Source -ListAvailable -ErrorAction SilentlyContinue
        } else {
            if ($CommandInfo.Source) {
                Write-LogMsg @LogParams -Text "Get-Module -Name '$($CommandInfo.Source)'"
                $ModuleInfo = Get-Module -Name $CommandInfo.Source -ErrorAction SilentlyContinue
            }
        }
    }

    if ($ModuleInfo.Path -like "*.ps1") {
        $ModuleInfo = $null
        $SourceModuleName = $null
    } else {
        $SourceModuleName = $CommandInfo.Source
    }

    Write-LogMsg @LogParams -Text " # $Command is a $CommandType"
    [pscustomobject]@{
        CommandInfo            = $CommandInfo
        ModuleInfo             = $ModuleInfo
        CommandType            = $CommandType
        SourceModuleDefinition = $ModuleInfo.Definition
        SourceModuleName       = $SourceModuleName
    }

}
function Open-Thread {

    <#
    .Synopsis
        Prepares each thread so it is ready to execute a command and capture the output streams

    .Description
        Used by Split-Thread

        For each InputObject an instance will be created of [System.Management.Automation.PowerShell]
        Then a series of commands will be run to enable the specified output streams (all by default)
    #>

    Param(

        # Objects to pass to the Command as an argument or parameter
        [Parameter(
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        $InputObject,

        # .Net Framework runspace pool to use for the threads
        [Parameter(
            Mandatory = $true
        )]
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool,

        <#
        Name of a property (whose value is a string) that exists on each $InputObject
        It will be used to represent the object in text form
        If left null, the object's ToString() method will be used instead.
        #>
        [string]$ObjectStringProperty,

        # PowerShell Command or Script to run against each InputObject
        [Parameter(Mandatory = $true)]
        $Command,

        # Output from Get-PsCommandInfo
        [pscustomobject[]]$CommandInfo,

        # Named parameter of the Command to pass InputObject to
        # If this is not specified, InputObject will be passed to the Command as an argument
        [string]$InputParameter = $null,

        <#
        Parameters to add to the Command
        Each parameter is a name-value pair in the hashtable:
            @{"ParameterName" = "Value"}
            @{"ParameterName" = "Value" ; "ParameterTwo" = "Value2"}
        #>
        [HashTable]$AddParam = @{},

        # Switches to add to the Command
        [string[]]$AddSwitch = @(),

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Hashtable of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    begin {

        $LogParams = @{
            LogMsgCache  = $LogMsgCache
            ThisHostname = $TodaysHostname
            Type         = $DebugOutputStream
            WhoAmI       = $WhoAmI
        }

        $CommandInfoParams = @{
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogMsgCache       = $LogMsgCache
        }

        [int64]$CurrentObjectIndex = 0
        $ThreadCount = @($InputObject).Count
        Write-LogMsg @LogParams -Text " # Received $(($CommandInfo | Measure-Object).Count) PsCommandInfos from Split-Thread for '$Command'"

        if ($CommandInfo) {

            # Begin to build the command that the script will run with all its parameters
            if (Test-Path $Command -ErrorAction SilentlyContinue) {
                # If $Command is a valid file path, dot-source it and wrap it in single quotes to handle spaces
                $CommandStringForScriptDefinition = [System.Text.StringBuilder]::new(". '$Command'")
            } else {
                $CommandStringForScriptDefinition = [System.Text.StringBuilder]::new($Command)
            }

            # Build the param block of the script. Along the way, add any necessary parameters and switches
            # Avoided using AppendJoin. It would provide slight performance and code readability but lacks support in PS 5.1
            $ScriptDefinition = [System.Text.StringBuilder]::new()
            $null = $ScriptDefinition.AppendLine('param (')
            If ([string]::IsNullOrEmpty($InputParameter)) {
                $null = $ScriptDefinition.Append("    `$PsRunspaceArgument1")
                $null = $CommandStringForScriptDefinition.Append(" `$PsRunspaceArgument1")
            } else {
                $null = $ScriptDefinition.Append("    `$$InputParameter")
                $null = $CommandStringForScriptDefinition.Append(" -$InputParameter `$$InputParameter")
            }

            ForEach ($ThisKey in $AddParam.Keys) {
                $null = $ScriptDefinition.Append(",`r`n    `$$ThisKey")
                $null = $CommandStringForScriptDefinition.Append(" -$ThisKey `$$ThisKey")
            }

            ForEach ($ThisSwitch in $AddSwitch) {
                $null = $ScriptDefinition.Append(",`r`n    [switch]`$", $ThisSwitch)
                $null = $CommandStringForScriptDefinition.Append(" -$ThisSwitch")
            }
            $null = $ScriptDefinition.AppendLine("`r`n)`r`n")

            # Define the command in the script ($Command)
            Convert-FromPsCommandInfoToString @CommandInfoParams -CommandInfo $CommandInfo |
            ForEach-Object {
                $null = $ScriptDefinition.AppendLine("`r`n$_")
            }
            $null = $ScriptDefinition.AppendLine()

            # Call the function in the script
            Write-LogMsg @LogParams -Text " # Command string is $($CommandStringForScriptDefinition.ToString())"
            $CommandStringForScriptDefinition |
            ForEach-Object {
                $null = $ScriptDefinition.AppendLine("`r`n$_")
            }
            $null = $ScriptDefinition.AppendLine()

            # Convert the script to a single string
            $ScriptString = $ScriptDefinition.ToString()

            # Remove blank lines
            # Commented out due to risk of unintended side effects: what if the code includes a here-string that requires blank lines, etc)
            #while ( $ScriptString -match '\r\n\r\n' ) {
            #    $ScriptString = $ScriptString -replace "`r`n`r`n", "`r`n"
            #}

            # Convert the script to a single scriptblock
            $ScriptBlock = [scriptblock]::Create($ScriptString)
        }

    }
    process {

        ForEach ($Object in $InputObject) {

            $CurrentObjectIndex++

            if ($ObjectStringProperty -ne '') {
                [string]$ObjectString = $Object."$ObjectStringProperty"
            } else {
                [string]$ObjectString = $Object.ToString()
            }

            Write-LogMsg @LogParams -Text "`$PowershellInterface = [powershell]::Create() # for '$Command' on '$ObjectString'"
            $PowershellInterface = [powershell]::Create()

            Write-LogMsg @LogParams -Text "`$PowershellInterface.RunspacePool = `$RunspacePool # for '$Command' on '$ObjectString'"
            $PowershellInterface.RunspacePool = $RunspacePool

            # Do I need this one?  What commands would be in there?
            Write-LogMsg @LogParams -Text "`$PowershellInterface.Commands.Clear() # for '$Command' on '$ObjectString'"
            $null = $PowershellInterface.Commands.Clear()

            if ($ScriptBlock) {
                $null = Add-PsCommand @CommandInfoParams -Command $ScriptBlock -PowershellInterface $PowershellInterface #-DebugOutputStream 'Debug'

                <#
                If:
                    the Command is a ScriptBlock (such as the content of a .ps1 file)
                    and
                    $InputParameter is null
                Then:
                    Pass $Object into the runspace as a parameter (not an argument)
                Otherwise we will:
                    Pass $Object into the runspace as an argument
                Because:
                    This allows more flexibility in the ScriptBlock
                    TODO: Need more detail here, this was a bugfix for .ps1 files but I didn't save the details (or maybe I did and forgot)
                #>
                If ([string]::IsNullOrEmpty($InputParameter)) {
                    $InputParameter = 'PsRunspaceArgument1'
                }
            } else {
                $null = Add-PsCommand @CommandInfoParams -Command $Command -CommandInfo $CommandInfo -PowershellInterface $PowershellInterface -Force
            }

            # Prepare to
            # Do this even if we end up passing it as an argument to the command inside the runspace
            ## WHY?? past self did not explain this and it's causing problems for non-script values of Command
            ## Therefore I have re-introduced AddArgument until I figure out what was wrong with it #
            If ([string]::IsNullOrEmpty($InputParameter)) {
                Write-LogMsg @LogParams -Text "`$PowershellInterface.AddArgument('$ObjectString') # for '$Command' on '$ObjectString'"
                $null = $PowershellInterface.AddArgument($Object)
                <#NormallyCommentThisForPerformanceOptimization#>$InputParameterStringForDebug = " '$ObjectString'"
            } else {
                Write-LogMsg @LogParams -Text "`$PowershellInterface.AddParameter('$InputParameter', '$ObjectString') # for '$Command' on '$ObjectString'"
                $null = $PowershellInterface.AddParameter($InputParameter, $Object)
                <#NormallyCommentThisForPerformanceOptimization#>$InputParameterStringForDebug = "-$InputParameter '$ObjectString'"
            }

            $AdditionalParameters = @()
            $AdditionalParameters = ForEach ($Key in $AddParam.Keys) {
                Write-LogMsg @LogParams -Text "`$PowershellInterface.AddParameter('$Key', '$($AddParam.$key)') # for '$Command' on '$ObjectString'"
                $null = $PowershellInterface.AddParameter($Key, $AddParam.$key)
                <#NormallyCommentThisForPerformanceOptimization#>"-$Key '$($AddParam.$key)'"
            }
            $AdditionalParametersString = $AdditionalParameters -join ' '

            $Switches = @()
            $Switches = ForEach ($Switch in $AddSwitch) {
                Write-LogMsg @LogParams -Text "`$PowershellInterface.AddParameter('$Switch') # for '$Command' on '$ObjectString'"
                $null = $PowershellInterface.AddParameter($Switch)
                <#NormallyCommentThisForPerformanceOptimization#>"-$Switch"
            }
            $SwitchParameterString = $Switches -join ' '

            $StatusString = "Invoking thread $CurrentObjectIndex`: $Command $InputParameterStringForDebug $AdditionalParametersString $SwitchParameterString"
            $Progress = @{
                Activity        = $StatusString
                PercentComplete = $CurrentObjectIndex / $ThreadCount * 100
                Status          = "$($ThreadCount - $CurrentObjectIndex) remaining"
            }
            Write-Progress @Progress

            Write-LogMsg @LogParams -Text "`$Handle = `$PowershellInterface.BeginInvoke() # for '$Command' on '$ObjectString'"
            $Handle = $PowershellInterface.BeginInvoke()

            [PSCustomObject]@{
                Handle              = $Handle
                PowerShellInterface = $PowershellInterface
                Object              = $Object
                ObjectString        = $ObjectString
                Index               = $CurrentObjectIndex
                Command             = "$Command"
            }

        }

    }

    end {

        Write-Progress -Activity $StatusString -Completed

    }
}
function Split-Thread {

    <#
    .Synopsis
        Split a command for a collection of input objects into multiple threads for asynchronous processing
    .Description
        The specified command will be run for each input object in a separate powershell instance with its own runspace
        These runspaces are part of the same runspace pool inside the same powershell.exe process
    .EXAMPLE
        The following demonstrates sending a Cmdlet name to the -Command parameter
            $InputObject | Split-Thread -Command 'Write-Output'
    .EXAMPLE
        The following demonstrates sending a scriptblock to the -Command parameter
            $InputObject | Split-Thread -Command [scriptblock]::create("Write-Output `$args[0]")
    .EXAMPLE
        The following demonstrates sending a script file path to the -Command parameter
            $InputObject | Split-Thread -Command "C:\Test-Command.ps1"
    .EXAMPLE
        The following demonstrates sending a function to the -Command parameter
            $InputObject | Split-Thread -Command 'Test-Function'
    .EXAMPLE
        The following demonstrates the -AddParam parameter

        $InputObject | Split-Thread -Command "Get-Service" -InputParameter ComputerName -AddParam @{"Name" = "BITS"}
    .EXAMPLE
        The following demonstrates the -AddSwitch parameter

        $InputObject | Split-Thread -Command "Get-Service" -AddSwitch @('RequiredServices','DependentServices')
	.EXAMPLE
		The following demonstrates the use of a threadsafe hashtable to store results
		The hastable can be accessed and updated from inside each runspace

		$ThreadsafeHashtable = [hashtable]::Synchronized(@{})
		$InputObject | Split-Thread -Command "Fake-Function" -InputParameter ComputerName -AddParam @{"ResultHashTableParameter" = $ThreadsafeHashtable}
    #>

    param (

        # PowerShell Command or Script to run against each InputObject
        [Parameter(Mandatory = $true)]
        $Command,

        # Objects to pass to the Command as an argument or parameter
        [Parameter(
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        $InputObject,

        # Named parameter of the Command to pass InputObject to
        # If this is not specified, InputObject will be passed to the Command as an argument
        $InputParameter = $null,

        # Maximum number of concurrent threads to allow
        [int]$Threads = (Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum,

        # Milliseconds to wait between cycles of the loop that checks threads for completion
        [int]$SleepTimer = 200,

        # Seconds to wait without receiving any new results before giving up and stopping all remaining threads
        [int]$Timeout = 120,

        <#
        Parameters to add to the Command
        Each parameter is a name-value pair in the hashtable:
            @{"ParameterName" = "Value"}
            @{"ParameterName" = "Value" ; "ParameterTwo" = "Value2"}
        #>
        [HashTable]$AddParam = @{},

        # Switches to add to the Command
        [string[]]$AddSwitch = @(),

        # Names of modules to import in each runspace
        [String[]]$AddModule,

        <#
        Name of a property (whose value is a string) that exists on each $InputObject and can be used to represent the object in text form
        If left null, the object's ToString() method will be used instead.
        #>
        [string]$ObjectStringProperty,

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Hashtable of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    begin {

        $LogParams = @{
            LogMsgCache  = $LogMsgCache
            ThisHostname = $TodaysHostname
            Type         = $DebugOutputStream
            WhoAmI       = $WhoAmI
        }

        Write-LogMsg @LogParams -Text "`$InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault() # for '$Command'"
        $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

        $CommandInfoParams = @{
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogMsgCache       = $LogMsgCache
        }
        $OriginalCommandInfo = Get-PsCommandInfo @CommandInfoParams -Command $Command
        Write-LogMsg @LogParams -Text " # Found 1 original PsCommandInfo for '$Command'"

        $CommandInfo = Expand-PsCommandInfo @CommandInfoParams -PsCommandInfo $OriginalCommandInfo
        Write-LogMsg @LogParams -Text " # Found $(($CommandInfo | Measure-Object).Count) nested PsCommandInfos for '$Command' ($($CommandInfo.CommandInfo.Name -join ','))"

        # Import the source module containing the specified Command in each thread

        # Prepare our collection of PowerShell modules to import in each thread
        # This will include any modules specified by name with the -AddModule parameter
        $ModulesToAdd = [System.Collections.Generic.List[System.Management.Automation.PSModuleInfo]]::new()
        ForEach ($Module in $AddModule) {
            Write-LogMsg @LogParams -Text "Get-Module -Name '$Module'"
            $ModuleObj = Get-Module -Name $Module -ErrorAction SilentlyContinue
            $null = $ModulesToAdd.Add($ModuleObj)
        }

        # This will also include any modules identified by tokenizing the -Command parameter or its definition, and recursing through all nested command tokens
        $CommandInfo.ModuleInfo |
        ForEach-Object {
            $null = $ModulesToAdd.Add($_)
        }
        $ModulesToAdd = $ModulesToAdd |
        Sort-Object -Property Name -Unique

        $CommandsToAdd = $CommandInfo |
        Where-Object -FilterScript {
            (
                -not $_.ModuleInfo.Name -or
                $ModulesToAdd.Name -notcontains $_.ModuleInfo.Name
            ) -and
            $_.CommandType -ne 'Cmdlet'
        }
        Write-LogMsg @LogParams -Text " # Found $(($CommandsToAdd | Measure-Object).Count) remaining PsCommandInfos to define for '$Command' (not in modules: $($CommandsToAdd.CommandInfo.Name -join ','))"

        if ($ModulesToAdd.Count -gt 0) {
            $null = Add-PsModule -InitialSessionState $InitialSessionState -ModuleInfo $ModulesToAdd @CommandInfoParams
        }

        # Set the preference variables for PowerShell output streams in each thread to match the current preferences
        $OutputStream = @('Debug', 'Verbose', 'Information', 'Warning', 'Error')
        ForEach ($ThisStream in $OutputStream) {
            if ($ThisStream -eq 'Error') {
                $VariableName = 'ErrorActionPreference'
            } else {
                $VariableName = "$($ThisStream)Preference"
            }
            $VariableValue = (Get-Variable -Name $VariableName).Value
            $VariableEntry = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new($VariableName, $VariableValue, '')
            $InitialSessionState.Variables.Add($VariableEntry)
        }

        Write-LogMsg @LogParams -Text "`$RunspacePool = [runspacefactory]::CreateRunspacePool(1, $Threads, `$InitialSessionState, `$Host) # for '$Command'"
        $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $Threads, $InitialSessionState, $Host)
        Write-LogMsg @LogParams -Text "`$RunspacePool.Open() # for '$Command'"
        $RunspacePool.Open()

        $Global:TimedOut = $false

        $AllInputObjects = [System.Collections.Generic.List[psobject]]::new()

    }

    process {

        # Add all the input objects from the pipeline to a single collection; allows progress bars later
        ForEach ($ThisObject in $InputObject) {
            $null = $AllInputObjects.Add($ThisObject)
        }

    }
    end {

        Write-LogMsg @LogParams -Text " # Entered end block. Sending $(($CommandsToAdd | Measure-Object).Count) PsCommandInfos to Open-Thread for '$Command'"
        $ThreadParameters = @{
            Command              = $Command
            InputParameter       = $InputParameter
            InputObject          = $AllInputObjects
            AddParam             = $AddParam
            AddSwitch            = $AddSwitch
            ObjectStringProperty = $ObjectStringProperty
            CommandInfo          = $CommandsToAdd
            RunspacePool         = $RunspacePool
            DebugOutputStream    = $DebugOutputStream
            WhoAmI               = $WhoAmI
            LogMsgCache          = $LogMsgCache
        }
        $AllThreads = Open-Thread @ThreadParameters
        Write-LogMsg @LogParams -Text " # Received $(($AllThreads | Measure-Object).Count) threads from Open-Thread for $Command"

        $ThreadParameters = @{
            Thread            = $AllThreads
            Threads           = $Threads
            SleepTimer        = $SleepTimer
            Timeout           = $Timeout
            Dispose           = $true
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogMsgCache       = $LogMsgCache
        }
        Wait-Thread @ThreadParameters
        $VerbosePreference = 'Continue'

        if ($Global:TimedOut -eq $false) {

            Write-LogMsg @LogParams -Text "[System.Management.Automation.Runspaces.RunspacePool]::Close()"
            $null = $RunspacePool.Close()
            Write-LogMsg @LogParams -Text " # [System.Management.Automation.Runspaces.RunspacePool]::Close() completed"

            Write-LogMsg @LogParams -Text "[System.Management.Automation.Runspaces.RunspacePool]::Dispose()"
            $null = $RunspacePool.Dispose()
            Write-LogMsg @LogParams -Text " # [System.Management.Automation.Runspaces.RunspacePool]::Dispose() completed"

        } else {
            # Statement-terminating error
            #$PSCmdlet.ThrowTerminatingError()

            # Script-terminating error
            throw 'Split-Thread timeout reached'
        }

        Write-Progress -Activity 'Completed' -Completed

    }

}
function Wait-Thread {

    <#
    .Synopsis
        Waits for a thread to be completed so the results can be returned, or for a timeout to be reached

    .Description
        Used by Split-Thread

    .INPUTS
        [PSCustomObject]$Thread

    .OUTPUTS
        Outputs the specified output streams from the threads
    #>

    param (

        # Threads to wait for
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        [PSCustomObject[]]$Thread,

        # Maximum number of concurrent threads that are allowed (used only for progress display)
        [int]$Threads = 20,

        # Milliseconds to wait between cycles of the loop that checks threads for completion
        [int]$SleepTimer = 200,

        # Seconds to wait without receiving any new results before giving up and stopping all remaining threads
        [int]$Timeout = 120,

        # Dispose of the thread when it is finished
        [switch]$Dispose,

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Hashtable of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    begin {

        $LogParams = @{
            LogMsgCache  = $LogMsgCache
            ThisHostname = $TodaysHostname
            Type         = $DebugOutputStream
            WhoAmI       = $WhoAmI
        }

        $StopWatch = [System.Diagnostics.Stopwatch]::new()
        $StopWatch.Start()

        $AllThreads = [System.Collections.Generic.List[PSCustomObject]]::new()

        $FirstThread = @($Thread)[0]

        $RunspacePool = $FirstThread.PowershellInterface.RunspacePool

        $CommandString = $FirstThread.Command

    }

    process {

        ForEach ($ThisThread in $Thread) {

            # If the threads do not have handles, there is nothing to wait for, so output the thread as-is.
            # Otherwise wait for the handle to indicate completion (or a timeout to be reached)
            if ($ThisThread.Handle -eq $false) {
                Write-LogMsg @LogParams -Text "`$PowerShellInterface.Streams.ClearStreams() # for '$CommandString' on '$($ThisThread.ObjectString)'"
                $null = $ThisThread.PowerShellInterface.Streams.ClearStreams()
                $ThisThread
            } else {
                $null = $AllThreads.Add($ThisThread)
            }

        }

    }

    end {

        # If the threads have handles, we can check to see if they are complete.
        While (@($AllThreads | Where-Object -FilterScript { $null -ne $_.Handle }).Count -gt 0) {

            Write-LogMsg @LogParams -Text "Start-Sleep -Milliseconds $SleepTimer # for '$CommandString'"
            Start-Sleep -Milliseconds $SleepTimer

            if ($RunspacePool) { $AvailableRunspaces = $RunspacePool.GetAvailableRunspaces() }

            $CleanedUpThreads = [System.Collections.Generic.List[PSCustomObject]]::new()
            $CompletedThreads = [System.Collections.Generic.List[PSCustomObject]]::new()
            $IncompleteThreads = [System.Collections.Generic.List[PSCustomObject]]::new()
            ForEach ($ThisThread in $AllThreads) {
                if ($null -eq $ThisThread.Handle) {
                    $null = $CleanedUpThreads.Add($ThisThread)
                }
                if ($ThisThread.Handle.IsCompleted -eq $true) {
                    $null = $CompletedThreads.Add($ThisThread)
                }
                if ($ThisThread.Handle.IsCompleted -eq $false) {
                    $null = $IncompleteThreads.Add($ThisThread)
                }
            }

            $ActiveThreadCountString = "$($Threads - $AvailableRunspaces) of $Threads are active"

            Write-LogMsg @LogParams -Text " # $ActiveThreadCountString for '$CommandString'"
            Write-LogMsg @LogParams -Text " # $($CompletedThreads.Count) completed threads for '$CommandString'"
            Write-LogMsg @LogParams -Text " # $($CleanedUpThreads.Count) cleaned up threads for '$CommandString'"
            Write-LogMsg @LogParams -Text " # $($IncompleteThreads.Count) incomplete threads for '$CommandString'"

            $RemainingString = "$($IncompleteThreads.ObjectString)"
            If ($RemainingString.Length -gt 60) {
                $RemainingString = $RemainingString.Substring(0, 60) + "..."
            }

            $Progress = @{
                Activity        = "Waiting on threads - $ActiveThreadCountString`: $CommandString"
                PercentComplete = ($($CleanedUpThreads).count) / @($Thread).Count * 100
                Status          = "$(@($IncompleteThreads).Count) remaining - $RemainingString"
            }
            Write-Progress @Progress

            ForEach ($CompletedThread in $CompletedThreads) {

                # TODO: Debug these counts, something seems off, they vary wildly with Test-Multithreading.ps1 but I would expect consistency (same number of Warnings per thread)
                Write-LogMsg @LogParams -Text " # $($CompletedThread.PowerShellInterface.Streams.Progress.Count) Progress messages for '$CommandString' on '$($CompletedThread.ObjectString)'"
                Write-LogMsg @LogParams -Text " # $($CompletedThread.PowerShellInterface.Streams.Information.Count) Information messages for '$CommandString' on '$($CompletedThread.ObjectString)'"
                Write-LogMsg @LogParams -Text " # $($CompletedThread.PowerShellInterface.Streams.Verbose.Count) Verbose messages for '$CommandString' on '$($CompletedThread.ObjectString)'"
                Write-LogMsg @LogParams -Text " # $($CompletedThread.PowerShellInterface.Streams.Debug.Count) Debug messages for '$CommandString' on '$($CompletedThread.ObjectString)'"
                Write-LogMsg @LogParams -Text " # $($CompletedThread.PowerShellInterface.Streams.Warning.Count) Warning messages for '$CommandString' on '$($CompletedThread.ObjectString)'"

                # Because $Host was used to create the RunspacePool, any output to $Host (which includes Write-Host and Write-Information and Write-Progress) has already been displayed
                #$CompletedThread.PowerShellInterface.Streams.Progress | ForEach-Object {Write-Progress "$_"}
                #$CompletedThread.PowerShellInterface.Streams.Information | ForEach-Object { Write-Information "$_" }
                #$CompletedThread.PowerShellInterface.Streams.Verbose | ForEach-Object { Write-Verbose "$_" }
                #$CompletedThread.PowerShellInterface.Streams.Debug | ForEach-Object { Write-Debug "$_" }
                #$CompletedThread.PowerShellInterface.Streams.Warning | ForEach-Object { Write-Warning "$_" }

                Write-LogMsg @LogParams -Text "`$PowerShellInterface.Streams.ClearStreams() # for '$CommandString' on '$($CompletedThread.ObjectString)'"
                $null = $CompletedThread.PowerShellInterface.Streams.ClearStreams()

                Write-LogMsg @LogParams -Text "`$PowerShellInterface.EndInvoke(`$Handle) # for '$CommandString' on '$($CompletedThread.ObjectString)'"
                $ThreadOutput = $CompletedThread.PowerShellInterface.EndInvoke($CompletedThread.Handle)

                if (@($ThreadOutput).Count -gt 0) {
                    Write-LogMsg @LogParams -Text " # Output (count of $(@($ThreadOutput).Count)) received from thread $($CompletedThread.Index): $($CompletedThread.ObjectString)"
                } else {
                    Write-LogMsg @LogParams -Text " # Null result for thread $($CompletedThread.Index) ($($CompletedThread.ObjectString))"
                }

                if ($Dispose -eq $true) {
                    $ThreadOutput
                    Write-LogMsg @LogParams -Text "`$PowerShellInterface.Dispose() # for '$CommandString' on '$($CompletedThread.ObjectString)'"
                    $null = $CompletedThread.PowerShellInterface.Dispose()
                    $CompletedThread.PowerShellInterface = $null
                    $CompletedThread.Handle = $null
                } else {
                    Write-LogMsg @LogParams -Text " # Thread $($CompletedThread.Index) is finished opening for '$CommandString' on '$($CompletedThread.ObjectString)'"
                    $CompletedThread.Handle = $null
                    $CompletedThread
                }

                $StopWatch.Reset()
                $StopWatch.Start()

            }

            If ($StopWatch.ElapsedMilliseconds / 1000 -gt $Timeout) {

                Write-Warning "  Reached Timeout of $Timeout seconds. Skipping $($IncompleteThreads.Count) remaining threads: $RemainingString"

                $Global:TimedOut = $true

                $IncompleteThreads |
                ForEach-Object {
                    $_.Handle = $null
                    [PSCustomObject]@{
                        Handle              = $null
                        PowerShellInterface = $_.PowershellInterface
                        Object              = $_.Object
                        ObjectString        = $_.ObjectString
                        Index               = $_.CurrentObjectIndex
                        Command             = $_.Command
                    }
                }
            }

        }

        $StopWatch.Stop()

        Write-LogMsg @LogParams -Text " # Finished waiting for threads"
        Write-Progress -Activity 'Completed' -Completed

    }

}
<#
# Dot source any functions
ForEach ($ThisScript in $ScriptFiles) {
    # Dot source the function
    . $($ThisScript.FullName)
}
#>
Import-Module PsLogMessage -ErrorAction SilentlyContinue

# Definition of Module 'PsDfs' Version '1.0.16' is below

Function Get-DfsNetInfo {
    # Wrapper for the NetDfsGetInfo([string]) method in the lmdfs.h header in NetApi32.dll for Distributed File Systems
    [CmdletBinding()]
    Param (

        [PSCredential]$Credentials,

        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript({
                Test-Path -LiteralPath $_ -PathType Container
            })]
        [String[]]$FolderPath

    )

    Process {

        foreach ($ThisFolderPath in $FolderPath) {

            $Split = $ThisFolderPath -split '\\'
            $ServerOrDomain = $Split[0]
            $DfsNamespace = $Split[1]
            $DfsLink = ""
            $Remainder = ""

            <#
            # Use the NetDfsGetInfo method instead as it does not filter out disabled folder targets
            # But it does not work
            #>
            #[NetApi32Dll]::NetDfsGetClientInfo($ThisFolderPath)

            #[NetApi32Dll]::NetDfsEnum($ThisFolderPath)

            [NetApi32Dll]::NetDfsGetInfo($ThisFolderPath)

        }

    }

}
function Get-FileShareInfo {
    # Get the corresponding local file path for DFS folder targets (which are UNC paths)
    param (

        [Parameter(ValueFromPipeline)]
        [psobject[]]$ServerAndShare

    )

    process {

        # State 6 notes that the DFS path is online and active
        #$DFS = $DfsNetClientInfo #| Where-Object -FilterScript { $_.State -eq 6 }

        ForEach ($DFS in $ServerAndShare) {

            $SessionParams = @{
                #Credential    = $Credentials
                ComputerName  = $DFS.ServerName
                SessionOption = New-CimSessionOption -Protocol Dcom
            }
            $CimParams = @{
                CimSession = New-CimSession @SessionParams
                ClassName  = 'Win32_Share'
            }

            $ShareName = ($DFS.ShareName -split '\\')[0]
            $ShareLocalPath = Get-CimInstance @CimParams |
            Where-Object Name -EQ $ShareName
            $LocalPath = $DFS.ShareName -replace [regex]::Escape("$ShareName\"), $ShareLocalPath.Path

            $DFS | Add-Member -PassThru -NotePropertyMembers @{
                #DfsPath = $DFS.DfsPath
                FolderTarget = "$($DFS.ServerName)\$($DFS.ShareName)\$($DFS.DfsPath -replace [regex]::Escape($DFS.ShareName))"
                #DfsState = $DFS.State
                #ServerName = $DFS.ServerName
                #ShareName = $DFS.ShareName
                LocalPath    = $LocalPath
            }

        }

    }

}
Function Get-NetDfsEnum {
    # Wrapper for the NetDfsEnum([string]) method in the lmdfs.h header in NetApi32.dll for Distributed File Systems
    [CmdletBinding()]
    Param (

        [PSCredential]$Credentials,

        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript({
                Test-Path -LiteralPath $_ -PathType Container
            })]
        [String[]]$FolderPath

    )

    Process {

        foreach ($ThisFolderPath in $FolderPath) {

            $Split = $ThisFolderPath -split '\\'
            $ServerOrDomain = $Split[0]
            $DfsNamespace = $Split[1]
            $DfsLink = ""
            $Remainder = ""

            # Can't use [NetApi32Dll]::NetDfsGetInfo($ThisFolderPath) because it doesn't work if the provided path is a subfolder of a DFS folder
            # Can't use [NetApi32Dll]::NetDfsGetClientInfo($ThisFolderPath) because it does not return disabled folder targets
            # Instead need to use [NetApi32Dll]::NetDfsEnum($ThisFolderPath) then Where-Object to filter results

            [NetApi32Dll]::NetDfsEnum($ThisFolderPath)

        }

    }

}

Add-Type -ErrorAction Stop -TypeDefinition @"


using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Management.Automation;
using System.Runtime.InteropServices;

public class NetApi32Dll
{

    [DllImport("netapi32.dll", SetLastError = true)]
    private static extern int NetApiBufferFree
    (
        IntPtr buffer
    );

    [DllImport("netapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int NetDfsEnum
    (
        [MarshalAs(UnmanagedType.LPWStr)] string DfsName,
        int Level,
        int PrefMaxLen,
        out IntPtr Buffer,
        [MarshalAs(UnmanagedType.I4)] out int EntriesRead,
        [MarshalAs(UnmanagedType.I4)] ref int ResumeHandle
    );

    [DllImport("netapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int NetDfsGetClientInfo
    (
        [MarshalAs(UnmanagedType.LPWStr)] string EntryPath,
        [MarshalAs(UnmanagedType.LPWStr)] string ServerName,
        [MarshalAs(UnmanagedType.LPWStr)] string ShareName,
        int Level,
        ref IntPtr Buffer
    );

    [DllImport("netapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int NetDfsGetInfo
    (
        [MarshalAs(UnmanagedType.LPWStr)] string EntryPath,
        [MarshalAs(UnmanagedType.LPWStr)] string ServerName,
        [MarshalAs(UnmanagedType.LPWStr)] string ShareName,
        int Level,
        ref IntPtr Buffer
    );

    public struct DFS_INFO_3
    {
        [MarshalAs(UnmanagedType.LPWStr)] public string EntryPath;
        [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
        public UInt32 State;
        public UInt32 NumberOfStorages;
        public IntPtr Storages;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DFS_INFO_6
    {
        [MarshalAs(UnmanagedType.LPWStr)] public string EntryPath;
        [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
        public UInt32 State;
        public UInt64 Timeout;
        public Guid Guid;
        public UInt32 NumberOfStorages;
        public UInt64 MetadataSize;
        public UInt64 PropertyFlags;
        public IntPtr Storages;
    }

    public struct DFS_STORAGE_INFO
    {
        public Int32 State;
        [MarshalAs(UnmanagedType.LPWStr)] public string ServerName;
        [MarshalAs(UnmanagedType.LPWStr)] public string ShareName;
    }
    public struct DFS_STORAGE_INFO_1
    {
        public DFS_STORAGE_STATE State;
        [MarshalAs(UnmanagedType.LPWStr)] public string ServerName;
        [MarshalAs(UnmanagedType.LPWStr)] public string ShareName;
        public DFS_TARGET_PRIORITY TargetPriority;
    }

    public struct DFS_TARGET_PRIORITY
    {
        public DFS_TARGET_PRIORITY_CLASS TargetPriorityClass;
        public UInt16 TargetPriorityRank;
        public UInt16 Reserved;
    }

    public enum DFS_TARGET_PRIORITY_CLASS
    {
        DfsInvalidPriorityClass = -1,
        DfsSiteCostNormalPriorityClass = 0,
        DfsGlobalHighPriorityClass = 1,
        DfsSiteCostHighPriorityClass = 2,
        DfsSiteCostLowPriorityClass = 3,
        DfsGlobalLowPriorityClass = 4
    }

    public enum DFS_STORAGE_STATE
    {
        DFS_STORAGE_STATE_OFFLINE = 1,

        DFS_STORAGE_STATE_ONLINE = 2,

        DFS_STORAGE_STATE_ACTIVE = 4,

        DFS_STORAGE_STATES = 0xF,
    }

    public static List<PSObject> NetDfsEnum(string DfsName)
    {

        IntPtr buffer = new IntPtr();
        int EntriesRead = 0;
        int ResumeHere = 0;
        List<PSObject> returnList = new List<PSObject>();
        const int MAX_PREFERRED_LENGTH = 0xFFFFFFF;
        const int NERR_Success = 0;

        try
        {
            int result = NetDfsEnum(DfsName, 3, MAX_PREFERRED_LENGTH, out buffer, out EntriesRead, ref ResumeHere);

            if (result != NERR_Success)
            {
                string errorMessage = new Win32Exception(Marshal.GetLastWin32Error()).Message;

                throw (new SystemException("NetDfsEnum error. System Error Code: " + result + " - " + errorMessage));
            }
            else
            {

                for (int n = 0; n < EntriesRead; n++)
                {

                    IntPtr DfsPtr = new IntPtr(buffer.ToInt64() + n * Marshal.SizeOf(typeof(DFS_INFO_3)));
                    object dfsObject = Marshal.PtrToStructure(DfsPtr, typeof(DFS_INFO_3));
                    DFS_INFO_3 dfsInfo = (DFS_INFO_3)dfsObject;

                    for (int i = 0; i < dfsInfo.NumberOfStorages; i++)
                    {
                        IntPtr storage = new IntPtr(dfsInfo.Storages.ToInt64() + i * Marshal.SizeOf(typeof(DFS_STORAGE_INFO)));

                        DFS_STORAGE_INFO storageInfo = (DFS_STORAGE_INFO)Marshal.PtrToStructure(storage, typeof(DFS_STORAGE_INFO));

                        PSObject psObject = new PSObject();
                        psObject.Properties.Add(new PSNoteProperty("FullOriginalQueryPath", DfsName));
                        psObject.Properties.Add(new PSNoteProperty("DfsEntryPath", dfsInfo.EntryPath));
                        psObject.Properties.Add(new PSNoteProperty("DfsTarget", System.IO.Path.Combine(new string[] { @"\\", storageInfo.ServerName, storageInfo.ShareName })));
                        psObject.Properties.Add(new PSNoteProperty("DfsTargetState", storageInfo.State));
                        psObject.Properties.Add(new PSNoteProperty("TargetServerName", storageInfo.ServerName));
                        psObject.Properties.Add(new PSNoteProperty("TargetShareName", storageInfo.ShareName));

                        returnList.Add(psObject);
                    }

                }
            }
        }
        finally
        {
            NetApiBufferFree(buffer);
        }
        return returnList;
    }

    public static List<PSObject> NetDfsEnum6(string DfsName)
    {

        IntPtr buffer = new IntPtr();
        int EntriesRead = 0;
        int ResumeHere = 0;
        List<PSObject> returnList = new List<PSObject>();
        const int MAX_PREFERRED_LENGTH = 0xFFFFFFF;
        const int NERR_Success = 0;
        const int Level = 6;

        try
        {
            int result = NetDfsEnum(DfsName, Level, MAX_PREFERRED_LENGTH, out buffer, out EntriesRead, ref ResumeHere);

            if (result != NERR_Success)
            {
                string errorMessage = new Win32Exception(Marshal.GetLastWin32Error()).Message;
                string customErrorMessage = "NetDfsEnum error for '" + DfsName + "'. System Error Code: " + result + " - " + errorMessage;
                throw (new SystemException(customErrorMessage));
            }
            else
            {

                Int64 dfsStart = buffer.ToInt64();
                Type dfsType = typeof(DFS_INFO_6);
                Int64 dfsSize = Marshal.SizeOf(dfsType);

                for (int n = 0; n < EntriesRead; n++)
                {

                    IntPtr dfsPtr = new IntPtr(dfsStart + n * dfsSize);

                    object dfsObject = Marshal.PtrToStructure(dfsPtr, dfsType);
                    DFS_INFO_6 dfsInfo = (DFS_INFO_6)dfsObject;

                    //if (dfsInfo.EntryPath == DfsName) {   // skip link for namespace
                    //    continue;
                    //}

                    Int64 storagesStart = dfsInfo.Storages.ToInt64();
                    Type storageType = typeof(DFS_STORAGE_INFO_1);
                    Int64 storageSize = Marshal.SizeOf(storageType);

                    for (int i = 0; i < dfsInfo.NumberOfStorages; i++)
                    {

                        //Attempted some different properties in case they were mis-mapped the same way that NumberofStorages was
                        //Int64 StartPoint = Convert.ToInt64(dfsInfo.MetadataSize); //System.AccessViolationException
                        //Int64 StartPoint = Convert.ToInt64(dfsInfo.PropertyFlags); //System.AccessViolationException
                        //Int64 StartPoint = Convert.ToInt64(dfsInfo.Timeout); //System.AccessViolationException
                        //IntPtr storagePtr = new IntPtr(StartPoint);

                        IntPtr storagePtr = new IntPtr(storagesStart + i * storageSize);
                        object storageObject = Marshal.PtrToStructure(storagePtr, storageType); //System.NullReferenceException
                        DFS_STORAGE_INFO_1 storageInfo = (DFS_STORAGE_INFO_1)storageObject;
                        PSObject psObject = new PSObject();
                        psObject.Properties.Add(new PSNoteProperty("FullOriginalQueryPath", DfsName));
                        psObject.Properties.Add(new PSNoteProperty("DfsEntryPath", dfsInfo.EntryPath));
                        psObject.Properties.Add(new PSNoteProperty("DfsTarget", System.IO.Path.Combine(new string[] { @"", storageInfo.ServerName, storageInfo.ShareName })));
                        psObject.Properties.Add(new PSNoteProperty("DfsTargetState", storageInfo.State));
                        psObject.Properties.Add(new PSNoteProperty("TargetServerName", storageInfo.ServerName));
                        psObject.Properties.Add(new PSNoteProperty("TargetShareName", storageInfo.ShareName));

                        returnList.Add(psObject);
                    }

                }
            }
        }
        finally
        {
            NetApiBufferFree(buffer);
        }

        return returnList;
    }

    public static List<PSObject> NetDfsGetInfo(string DfsEntryPath)
    {
        IntPtr buffer = new IntPtr();
        List<PSObject> returnList = new List<PSObject>();

        try
        {
            int result = NetDfsGetInfo(DfsEntryPath, null, null, 3, ref buffer);

            if (result != 0)
            {
                throw (new SystemException("Error getting DFS information"));
            }
            else
            {
                DFS_INFO_3 dfsInfo = (DFS_INFO_3)Marshal.PtrToStructure(buffer, typeof(DFS_INFO_3));

                for (int i = 0; i < dfsInfo.NumberOfStorages; i++)
                {
                    IntPtr storage = new IntPtr(dfsInfo.Storages.ToInt64() + i * Marshal.SizeOf(typeof(DFS_STORAGE_INFO)));

                    DFS_STORAGE_INFO storageInfo = (DFS_STORAGE_INFO)Marshal.PtrToStructure(storage, typeof(DFS_STORAGE_INFO));

                    PSObject psObject = new PSObject();

                    psObject.Properties.Add(new PSNoteProperty("State", storageInfo.State));
                    psObject.Properties.Add(new PSNoteProperty("ServerName", storageInfo.ServerName));
                    psObject.Properties.Add(new PSNoteProperty("ShareName", storageInfo.ShareName));

                    returnList.Add(psObject);
                }
            }
        }
        finally
        {
            NetApiBufferFree(buffer);
        }
        return returnList;
    }

    public static List<PSObject> NetDfsGetClientInfo(string DfsPath)
    {
        IntPtr buffer = new IntPtr();
        List<PSObject> returnList = new List<PSObject>();

        try
        {
            int result = NetDfsGetClientInfo(DfsPath, null, null, 3, ref buffer);

            if (result != 0)
            {
                throw (new SystemException("Error getting DFS information"));
            }
            else
            {
                DFS_INFO_3 dfsInfo = (DFS_INFO_3)Marshal.PtrToStructure(buffer, typeof(DFS_INFO_3));

                for (int i = 0; i < dfsInfo.NumberOfStorages; i++)
                {
                    IntPtr storage = new IntPtr(dfsInfo.Storages.ToInt64() + i * Marshal.SizeOf(typeof(DFS_STORAGE_INFO)));

                    DFS_STORAGE_INFO storageInfo = (DFS_STORAGE_INFO)Marshal.PtrToStructure(storage, typeof(DFS_STORAGE_INFO));

                    PSObject psObject = new PSObject();

                    psObject.Properties.Add(new PSNoteProperty("State", storageInfo.State));
                    psObject.Properties.Add(new PSNoteProperty("ServerName", storageInfo.ServerName));
                    psObject.Properties.Add(new PSNoteProperty("ShareName", storageInfo.ShareName));

                    returnList.Add(psObject);
                }
            }
        }
        finally
        {
            NetApiBufferFree(buffer);
        }
        return returnList;
    }

}


"@

# Definition of Module 'PsBootstrapCss' Version '1.0.28' is below

function ConvertTo-BootstrapJavaScriptTable {
    param (
        [string]$Id,
        $InputObject,
        [switch]$DataFilterControl,
        [string[]]$UnsortableColumn,
        [string[]]$SearchableColumn,
        [string[]]$DropdownColumn,
        [switch]$AllColumnsSearchable,
        [string[]]$PropNames
    )

    # Convert the arrays to hashtables for faster lookups
    $UnsortableColumns = @{}
    ForEach ($Col in $UnsortableColumn) {
        $UnsortableColumns[$Col] = $null
    }
    $SearchableColumns = @{}
    ForEach ($Col in $SearchableColumn) {
        $SearchableColumns[$Col] = $null
    }
    $DropdownColumns = @{}
    ForEach ($Col in $DropdownColumn) {
        $DropdownColumns[$Col] = $null
    }

    $Stringbuilder = [System.Text.StringBuilder]::new()
    $null = $Stringbuilder.Append('<table id="')
    $null = $Stringbuilder.Append($Id)
    $null = $Stringbuilder.Append('"')
    if ($DataFilterControl) {
        $null = $Stringbuilder.Append(' data-filter-control="true"')
    }
    $null = $Stringbuilder.AppendLine('>')
    $null = $Stringbuilder.AppendLine('<thead>')
    $null = $Stringbuilder.AppendLine('<tr>')

    if (-not $PSBoundParameters.ContainsKey('PropNames')) {
        $PropNames = ($InputObject | Get-Member -MemberType noteproperty).Name
    }
    ForEach ($Prop in $PropNames) {
        $null = $Stringbuilder.Append('<th')
        if ($DataFilterControl) {
            $null = $Stringbuilder.Append(' data-field="')
            $null = $Stringbuilder.Append(($Prop -replace '\s', ''))
            $null = $Stringbuilder.Append('"')
        }
        if ($DataFilterControl) {
            if ($SearchableColumns.ContainsKey($Prop) -or $AllColumnsSearchable) {
                $null = $Stringbuilder.Append(' data-filter-control="input"')
            }
            if ($DropdownColumns.ContainsKey($Prop)) {
                $null = $Stringbuilder.Append(' data-filter-control="select"')
            }
        }
        if (-not $UnsortableColumns.ContainsKey($Prop)) {
            $null = $Stringbuilder.Append(' data-sortable="true"')
        }
        $null = $Stringbuilder.Append('>')
        $null = $Stringbuilder.Append($Prop)
        $null = $Stringbuilder.AppendLine('</th>')
    }
    $null = $Stringbuilder.AppendLine('</tr>')
    $null = $Stringbuilder.AppendLine('</thead>')
    $null = $Stringbuilder.AppendLine('</table>')
    $Stringbuilder.ToString()
}
Function ConvertTo-BootstrapListGroup {
    <#
        .SYNOPSIS
            Upgrade a boring HTML list to a fancy Bootstrap list group
        .DESCRIPTION
            Applies the Bootstrap 'list-group' CSS class to an HTML list
            Applies the Bootstrap 'list-group-item' CSS class to each list item
        .OUTPUTS
            A string wih the code for the Bootstrap list
        .EXAMPLE
            1,2,3 |
            ConvertTo-HtmlList |
            ConvertTo-BootstrapListGroup

            This example returns the following string:
            '<ul class ="list-group"><li class ="list-group-item>1</li><li class ="list-group-item>2</li><li class ="list-group-item>3</li></ul>'
    #>
    [OutputType([System.String])]
    [CmdletBinding()]
    param(
        #The HTML table to apply the Bootstrap striped table CSS class to
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$HtmlList
    )
    process {
        ForEach ($List in $HtmlList) {

            $List -replace
            '<ul>', '<ul class="list-group">' -replace
            '<ol>', '<ol class="list-group">' -replace
            '<li>', '<li class ="list-group-item">'

        }
    }
}


function ConvertTo-BootstrapTableScript {

    param (

        # ID of the table to format with the bootstrapTable() JavaScript method.
        [Parameter(Mandatory)]
        [string]$TableId,

        # Used for the columns Property
        [Parameter(Mandatory)]
        [string]$ColumnJson,

        # Used for the data Property
        [Parameter(Mandatory)]
        [string]$DataJson,

        # CSS classes to apply to the table
        [string]$Classes = 'table table-striped table-hover table-sm',

        #Name of the function to use to style the table header row
        [string]$HeaderStyle = 'headerStyle'

    )

    $null = $ResultingJavaScript = [System.Text.StringBuilder]::new()
    $null = $ResultingJavaScript.AppendLine('<script>')
    $null = $ResultingJavaScript.AppendLine('  $(function() {')
    $null = $ResultingJavaScript.Append("    `$('")
    $null = $ResultingJavaScript.Append($TableId)
    $null = $ResultingJavaScript.AppendLine("').bootstrapTable({")
    $null = $ResultingJavaScript.AppendLine("      classes: '$Classes',")
    $null = $ResultingJavaScript.AppendLine("      headerStyle: '$HeaderStyle',")
    $null = $ResultingJavaScript.AppendLine("      columns: $ColumnJson,")
    $null = $ResultingJavaScript.AppendLine("      data: $DataJson")
    $null = $ResultingJavaScript.AppendLine('    });')

    ########
    # Only one of these two blocks of 4 lines is needed, but I need to get the JavaScript working.  For now the template has these attributes hard-coded
    $null = $ResultingJavaScript.Append("    `$('")
    $null = $ResultingJavaScript.Append($TableId)
    $null = $ResultingJavaScript.Append("').attr(")
    $null = $ResultingJavaScript.AppendLine('"data-filter-control",true); //not working, but seems to result in same final element attributes so not sure why')

    $null = $ResultingJavaScript.Append("    //`$('")
    $null = $ResultingJavaScript.Append($TableId)
    $null = $ResultingJavaScript.Append("').prop(")
    $null = $ResultingJavaScript.AppendLine('"data-filter-control","true"); //does not work, and results in different final element attributes than when hard-coding the property into the HTML table')
    #
    ########

    $null = $ResultingJavaScript.AppendLine('  })')
    $null = $ResultingJavaScript.AppendLine('</script>')

    return $ResultingJavaScript.ToString()

}
function ConvertTo-HtmlList {
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true
        )]
        [string[]]$InputObject,
        [switch]$Ordered
    )
    begin {

        if ($Ordered) {
            $ListType = 'ol'
        } else {
            $ListType = 'ul'
        }

        $StringBuilder = [System.Text.StringBuilder]::new("<$ListType>")

    }
    process {
        ForEach ($ThisObject in $InputObject) {
            $null = $StringBuilder.Append("<li>$ThisObject</li>")
        }
    }
    end {
        $null = $StringBuilder.Append("</$ListType>")
        $StringBuilder.ToString()
    }
}
function Get-BootstrapTemplate {
	@"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
	<head>
		<style type="text/css">
			/*!
			 * Bootstrap v5.1.3 (https://getbootstrap.com/)
			 * Copyright 2011-2021 The Bootstrap Authors
			 * Copyright 2011-2021 Twitter, Inc.
			 * Licensed under MIT (https://github.com/twbs/bootstrap/blob/main/LICENSE)
			 */
			 :root{--bs-blue:#0d6efd;--bs-indigo:#6610f2;--bs-purple:#6f42c1;--bs-pink:#d63384;--bs-red:#dc3545;--bs-orange:#fd7e14;--bs-yellow:#ffc107;--bs-green:#198754;--bs-teal:#20c997;--bs-cyan:#0dcaf0;--bs-white:#fff;--bs-gray:#6c757d;--bs-gray-dark:#343a40;--bs-gray-100:#f8f9fa;--bs-gray-200:#e9ecef;--bs-gray-300:#dee2e6;--bs-gray-400:#ced4da;--bs-gray-500:#adb5bd;--bs-gray-600:#6c757d;--bs-gray-700:#495057;--bs-gray-800:#343a40;--bs-gray-900:#212529;--bs-primary:#0d6efd;--bs-secondary:#6c757d;--bs-success:#198754;--bs-info:#0dcaf0;--bs-warning:#ffc107;--bs-danger:#dc3545;--bs-light:#f8f9fa;--bs-dark:#212529;--bs-primary-rgb:13,110,253;--bs-secondary-rgb:108,117,125;--bs-success-rgb:25,135,84;--bs-info-rgb:13,202,240;--bs-warning-rgb:255,193,7;--bs-danger-rgb:220,53,69;--bs-light-rgb:248,249,250;--bs-dark-rgb:33,37,41;--bs-white-rgb:255,255,255;--bs-black-rgb:0,0,0;--bs-body-color-rgb:33,37,41;--bs-body-bg-rgb:255,255,255;--bs-font-sans-serif:system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,"Noto Sans","Liberation Sans",sans-serif,"Apple Color Emoji","Segoe UI Emoji","Segoe UI Symbol","Noto Color Emoji";--bs-font-monospace:SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;--bs-gradient:linear-gradient(180deg, rgba(255, 255, 255, 0.15), rgba(255, 255, 255, 0));--bs-body-font-family:var(--bs-font-sans-serif);--bs-body-font-size:1rem;--bs-body-font-weight:400;--bs-body-line-height:1.5;--bs-body-color:#212529;--bs-body-bg:#fff}*,::after,::before{box-sizing:border-box}@media (prefers-reduced-motion:no-preference){:root{scroll-behavior:smooth}}body{margin:0;font-family:var(--bs-body-font-family);font-size:var(--bs-body-font-size);font-weight:var(--bs-body-font-weight);line-height:var(--bs-body-line-height);color:var(--bs-body-color);text-align:var(--bs-body-text-align);background-color:var(--bs-body-bg);-webkit-text-size-adjust:100%;-webkit-tap-highlight-color:transparent}hr{margin:1rem 0;color:inherit;background-color:currentColor;border:0;opacity:.25}hr:not([size]){height:1px}.h1,.h2,.h3,.h4,.h5,.h6,h1,h2,h3,h4,h5,h6{margin-top:0;margin-bottom:.5rem;font-weight:500;line-height:1.2}.h1,h1{font-size:calc(1.375rem + 1.5vw)}@media (min-width:1200px){.h1,h1{font-size:2.5rem}}.h2,h2{font-size:calc(1.325rem + .9vw)}@media (min-width:1200px){.h2,h2{font-size:2rem}}.h3,h3{font-size:calc(1.3rem + .6vw)}@media (min-width:1200px){.h3,h3{font-size:1.75rem}}.h4,h4{font-size:calc(1.275rem + .3vw)}@media (min-width:1200px){.h4,h4{font-size:1.5rem}}.h5,h5{font-size:1.25rem}.h6,h6{font-size:1rem}p{margin-top:0;margin-bottom:1rem}abbr[data-bs-original-title],abbr[title]{-webkit-text-decoration:underline dotted;text-decoration:underline dotted;cursor:help;-webkit-text-decoration-skip-ink:none;text-decoration-skip-ink:none}address{margin-bottom:1rem;font-style:normal;line-height:inherit}ol,ul{padding-left:2rem}dl,ol,ul{margin-top:0;margin-bottom:1rem}ol ol,ol ul,ul ol,ul ul{margin-bottom:0}dt{font-weight:700}dd{margin-bottom:.5rem;margin-left:0}blockquote{margin:0 0 1rem}b,strong{font-weight:bolder}.small,small{font-size:.875em}.mark,mark{padding:.2em;background-color:#fcf8e3}sub,sup{position:relative;font-size:.75em;line-height:0;vertical-align:baseline}sub{bottom:-.25em}sup{top:-.5em}a{color:#0d6efd;text-decoration:underline}a:hover{color:#0a58ca}a:not([href]):not([class]),a:not([href]):not([class]):hover{color:inherit;text-decoration:none}code,kbd,pre,samp{font-family:var(--bs-font-monospace);font-size:1em;direction:ltr;unicode-bidi:bidi-override}pre{display:block;margin-top:0;margin-bottom:1rem;overflow:auto;font-size:.875em}pre code{font-size:inherit;color:inherit;word-break:normal}code{font-size:.875em;color:#d63384;word-wrap:break-word}a>code{color:inherit}kbd{padding:.2rem .4rem;font-size:.875em;color:#fff;background-color:#212529;border-radius:.2rem}kbd kbd{padding:0;font-size:1em;font-weight:700}figure{margin:0 0 1rem}img,svg{vertical-align:middle}table{caption-side:bottom;border-collapse:collapse}caption{padding-top:.5rem;padding-bottom:.5rem;color:#6c757d;text-align:left}th{text-align:inherit;text-align:-webkit-match-parent}tbody,td,tfoot,th,thead,tr{border-color:inherit;border-style:solid;border-width:0}label{display:inline-block}button{border-radius:0}button:focus:not(:focus-visible){outline:0}button,input,optgroup,select,textarea{margin:0;font-family:inherit;font-size:inherit;line-height:inherit}button,select{text-transform:none}[role=button]{cursor:pointer}select{word-wrap:normal}select:disabled{opacity:1}[list]::-webkit-calendar-picker-indicator{display:none}[type=button],[type=reset],[type=submit],button{-webkit-appearance:button}[type=button]:not(:disabled),[type=reset]:not(:disabled),[type=submit]:not(:disabled),button:not(:disabled){cursor:pointer}::-moz-focus-inner{padding:0;border-style:none}textarea{resize:vertical}fieldset{min-width:0;padding:0;margin:0;border:0}legend{float:left;width:100%;padding:0;margin-bottom:.5rem;font-size:calc(1.275rem + .3vw);line-height:inherit}@media (min-width:1200px){legend{font-size:1.5rem}}legend+*{clear:left}::-webkit-datetime-edit-day-field,::-webkit-datetime-edit-fields-wrapper,::-webkit-datetime-edit-hour-field,::-webkit-datetime-edit-minute,::-webkit-datetime-edit-month-field,::-webkit-datetime-edit-text,::-webkit-datetime-edit-year-field{padding:0}::-webkit-inner-spin-button{height:auto}[type=search]{outline-offset:-2px;-webkit-appearance:textfield}::-webkit-search-decoration{-webkit-appearance:none}::-webkit-color-swatch-wrapper{padding:0}::-webkit-file-upload-button{font:inherit}::file-selector-button{font:inherit}::-webkit-file-upload-button{font:inherit;-webkit-appearance:button}output{display:inline-block}iframe{border:0}summary{display:list-item;cursor:pointer}progress{vertical-align:baseline}[hidden]{display:none!important}.lead{font-size:1.25rem;font-weight:300}.display-1{font-size:calc(1.625rem + 4.5vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-1{font-size:5rem}}.display-2{font-size:calc(1.575rem + 3.9vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-2{font-size:4.5rem}}.display-3{font-size:calc(1.525rem + 3.3vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-3{font-size:4rem}}.display-4{font-size:calc(1.475rem + 2.7vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-4{font-size:3.5rem}}.display-5{font-size:calc(1.425rem + 2.1vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-5{font-size:3rem}}.display-6{font-size:calc(1.375rem + 1.5vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-6{font-size:2.5rem}}.list-unstyled{padding-left:0;list-style:none}.list-inline{padding-left:0;list-style:none}.list-inline-item{display:inline-block}.list-inline-item:not(:last-child){margin-right:.5rem}.initialism{font-size:.875em;text-transform:uppercase}.blockquote{margin-bottom:1rem;font-size:1.25rem}.blockquote>:last-child{margin-bottom:0}.blockquote-footer{margin-top:-1rem;margin-bottom:1rem;font-size:.875em;color:#6c757d}.blockquote-footer::before{content:"— "}.img-fluid{max-width:100%;height:auto}.img-thumbnail{padding:.25rem;background-color:#fff;border:1px solid #dee2e6;border-radius:.25rem;max-width:100%;height:auto}.figure{display:inline-block}.figure-img{margin-bottom:.5rem;line-height:1}.figure-caption{font-size:.875em;color:#6c757d}.container,.container-fluid,.container-lg,.container-md,.container-sm,.container-xl,.container-xxl{width:100%;padding-right:var(--bs-gutter-x,.75rem);padding-left:var(--bs-gutter-x,.75rem);margin-right:auto;margin-left:auto}@media (min-width:576px){.container,.container-sm{max-width:540px}}@media (min-width:768px){.container,.container-md,.container-sm{max-width:720px}}@media (min-width:992px){.container,.container-lg,.container-md,.container-sm{max-width:960px}}@media (min-width:1200px){.container,.container-lg,.container-md,.container-sm,.container-xl{max-width:1140px}}@media (min-width:1400px){.container,.container-lg,.container-md,.container-sm,.container-xl,.container-xxl{max-width:1320px}}.row{--bs-gutter-x:1.5rem;--bs-gutter-y:0;display:flex;flex-wrap:wrap;margin-top:calc(-1 * var(--bs-gutter-y));margin-right:calc(-.5 * var(--bs-gutter-x));margin-left:calc(-.5 * var(--bs-gutter-x))}.row>*{flex-shrink:0;width:100%;max-width:100%;padding-right:calc(var(--bs-gutter-x) * .5);padding-left:calc(var(--bs-gutter-x) * .5);margin-top:var(--bs-gutter-y)}.col{flex:1 0 0%}.row-cols-auto>*{flex:0 0 auto;width:auto}.row-cols-1>*{flex:0 0 auto;width:100%}.row-cols-2>*{flex:0 0 auto;width:50%}.row-cols-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-4>*{flex:0 0 auto;width:25%}.row-cols-5>*{flex:0 0 auto;width:20%}.row-cols-6>*{flex:0 0 auto;width:16.6666666667%}.col-auto{flex:0 0 auto;width:auto}.col-1{flex:0 0 auto;width:8.33333333%}.col-2{flex:0 0 auto;width:16.66666667%}.col-3{flex:0 0 auto;width:25%}.col-4{flex:0 0 auto;width:33.33333333%}.col-5{flex:0 0 auto;width:41.66666667%}.col-6{flex:0 0 auto;width:50%}.col-7{flex:0 0 auto;width:58.33333333%}.col-8{flex:0 0 auto;width:66.66666667%}.col-9{flex:0 0 auto;width:75%}.col-10{flex:0 0 auto;width:83.33333333%}.col-11{flex:0 0 auto;width:91.66666667%}.col-12{flex:0 0 auto;width:100%}.offset-1{margin-left:8.33333333%}.offset-2{margin-left:16.66666667%}.offset-3{margin-left:25%}.offset-4{margin-left:33.33333333%}.offset-5{margin-left:41.66666667%}.offset-6{margin-left:50%}.offset-7{margin-left:58.33333333%}.offset-8{margin-left:66.66666667%}.offset-9{margin-left:75%}.offset-10{margin-left:83.33333333%}.offset-11{margin-left:91.66666667%}.g-0,.gx-0{--bs-gutter-x:0}.g-0,.gy-0{--bs-gutter-y:0}.g-1,.gx-1{--bs-gutter-x:0.25rem}.g-1,.gy-1{--bs-gutter-y:0.25rem}.g-2,.gx-2{--bs-gutter-x:0.5rem}.g-2,.gy-2{--bs-gutter-y:0.5rem}.g-3,.gx-3{--bs-gutter-x:1rem}.g-3,.gy-3{--bs-gutter-y:1rem}.g-4,.gx-4{--bs-gutter-x:1.5rem}.g-4,.gy-4{--bs-gutter-y:1.5rem}.g-5,.gx-5{--bs-gutter-x:3rem}.g-5,.gy-5{--bs-gutter-y:3rem}@media (min-width:576px){.col-sm{flex:1 0 0%}.row-cols-sm-auto>*{flex:0 0 auto;width:auto}.row-cols-sm-1>*{flex:0 0 auto;width:100%}.row-cols-sm-2>*{flex:0 0 auto;width:50%}.row-cols-sm-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-sm-4>*{flex:0 0 auto;width:25%}.row-cols-sm-5>*{flex:0 0 auto;width:20%}.row-cols-sm-6>*{flex:0 0 auto;width:16.6666666667%}.col-sm-auto{flex:0 0 auto;width:auto}.col-sm-1{flex:0 0 auto;width:8.33333333%}.col-sm-2{flex:0 0 auto;width:16.66666667%}.col-sm-3{flex:0 0 auto;width:25%}.col-sm-4{flex:0 0 auto;width:33.33333333%}.col-sm-5{flex:0 0 auto;width:41.66666667%}.col-sm-6{flex:0 0 auto;width:50%}.col-sm-7{flex:0 0 auto;width:58.33333333%}.col-sm-8{flex:0 0 auto;width:66.66666667%}.col-sm-9{flex:0 0 auto;width:75%}.col-sm-10{flex:0 0 auto;width:83.33333333%}.col-sm-11{flex:0 0 auto;width:91.66666667%}.col-sm-12{flex:0 0 auto;width:100%}.offset-sm-0{margin-left:0}.offset-sm-1{margin-left:8.33333333%}.offset-sm-2{margin-left:16.66666667%}.offset-sm-3{margin-left:25%}.offset-sm-4{margin-left:33.33333333%}.offset-sm-5{margin-left:41.66666667%}.offset-sm-6{margin-left:50%}.offset-sm-7{margin-left:58.33333333%}.offset-sm-8{margin-left:66.66666667%}.offset-sm-9{margin-left:75%}.offset-sm-10{margin-left:83.33333333%}.offset-sm-11{margin-left:91.66666667%}.g-sm-0,.gx-sm-0{--bs-gutter-x:0}.g-sm-0,.gy-sm-0{--bs-gutter-y:0}.g-sm-1,.gx-sm-1{--bs-gutter-x:0.25rem}.g-sm-1,.gy-sm-1{--bs-gutter-y:0.25rem}.g-sm-2,.gx-sm-2{--bs-gutter-x:0.5rem}.g-sm-2,.gy-sm-2{--bs-gutter-y:0.5rem}.g-sm-3,.gx-sm-3{--bs-gutter-x:1rem}.g-sm-3,.gy-sm-3{--bs-gutter-y:1rem}.g-sm-4,.gx-sm-4{--bs-gutter-x:1.5rem}.g-sm-4,.gy-sm-4{--bs-gutter-y:1.5rem}.g-sm-5,.gx-sm-5{--bs-gutter-x:3rem}.g-sm-5,.gy-sm-5{--bs-gutter-y:3rem}}@media (min-width:768px){.col-md{flex:1 0 0%}.row-cols-md-auto>*{flex:0 0 auto;width:auto}.row-cols-md-1>*{flex:0 0 auto;width:100%}.row-cols-md-2>*{flex:0 0 auto;width:50%}.row-cols-md-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-md-4>*{flex:0 0 auto;width:25%}.row-cols-md-5>*{flex:0 0 auto;width:20%}.row-cols-md-6>*{flex:0 0 auto;width:16.6666666667%}.col-md-auto{flex:0 0 auto;width:auto}.col-md-1{flex:0 0 auto;width:8.33333333%}.col-md-2{flex:0 0 auto;width:16.66666667%}.col-md-3{flex:0 0 auto;width:25%}.col-md-4{flex:0 0 auto;width:33.33333333%}.col-md-5{flex:0 0 auto;width:41.66666667%}.col-md-6{flex:0 0 auto;width:50%}.col-md-7{flex:0 0 auto;width:58.33333333%}.col-md-8{flex:0 0 auto;width:66.66666667%}.col-md-9{flex:0 0 auto;width:75%}.col-md-10{flex:0 0 auto;width:83.33333333%}.col-md-11{flex:0 0 auto;width:91.66666667%}.col-md-12{flex:0 0 auto;width:100%}.offset-md-0{margin-left:0}.offset-md-1{margin-left:8.33333333%}.offset-md-2{margin-left:16.66666667%}.offset-md-3{margin-left:25%}.offset-md-4{margin-left:33.33333333%}.offset-md-5{margin-left:41.66666667%}.offset-md-6{margin-left:50%}.offset-md-7{margin-left:58.33333333%}.offset-md-8{margin-left:66.66666667%}.offset-md-9{margin-left:75%}.offset-md-10{margin-left:83.33333333%}.offset-md-11{margin-left:91.66666667%}.g-md-0,.gx-md-0{--bs-gutter-x:0}.g-md-0,.gy-md-0{--bs-gutter-y:0}.g-md-1,.gx-md-1{--bs-gutter-x:0.25rem}.g-md-1,.gy-md-1{--bs-gutter-y:0.25rem}.g-md-2,.gx-md-2{--bs-gutter-x:0.5rem}.g-md-2,.gy-md-2{--bs-gutter-y:0.5rem}.g-md-3,.gx-md-3{--bs-gutter-x:1rem}.g-md-3,.gy-md-3{--bs-gutter-y:1rem}.g-md-4,.gx-md-4{--bs-gutter-x:1.5rem}.g-md-4,.gy-md-4{--bs-gutter-y:1.5rem}.g-md-5,.gx-md-5{--bs-gutter-x:3rem}.g-md-5,.gy-md-5{--bs-gutter-y:3rem}}@media (min-width:992px){.col-lg{flex:1 0 0%}.row-cols-lg-auto>*{flex:0 0 auto;width:auto}.row-cols-lg-1>*{flex:0 0 auto;width:100%}.row-cols-lg-2>*{flex:0 0 auto;width:50%}.row-cols-lg-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-lg-4>*{flex:0 0 auto;width:25%}.row-cols-lg-5>*{flex:0 0 auto;width:20%}.row-cols-lg-6>*{flex:0 0 auto;width:16.6666666667%}.col-lg-auto{flex:0 0 auto;width:auto}.col-lg-1{flex:0 0 auto;width:8.33333333%}.col-lg-2{flex:0 0 auto;width:16.66666667%}.col-lg-3{flex:0 0 auto;width:25%}.col-lg-4{flex:0 0 auto;width:33.33333333%}.col-lg-5{flex:0 0 auto;width:41.66666667%}.col-lg-6{flex:0 0 auto;width:50%}.col-lg-7{flex:0 0 auto;width:58.33333333%}.col-lg-8{flex:0 0 auto;width:66.66666667%}.col-lg-9{flex:0 0 auto;width:75%}.col-lg-10{flex:0 0 auto;width:83.33333333%}.col-lg-11{flex:0 0 auto;width:91.66666667%}.col-lg-12{flex:0 0 auto;width:100%}.offset-lg-0{margin-left:0}.offset-lg-1{margin-left:8.33333333%}.offset-lg-2{margin-left:16.66666667%}.offset-lg-3{margin-left:25%}.offset-lg-4{margin-left:33.33333333%}.offset-lg-5{margin-left:41.66666667%}.offset-lg-6{margin-left:50%}.offset-lg-7{margin-left:58.33333333%}.offset-lg-8{margin-left:66.66666667%}.offset-lg-9{margin-left:75%}.offset-lg-10{margin-left:83.33333333%}.offset-lg-11{margin-left:91.66666667%}.g-lg-0,.gx-lg-0{--bs-gutter-x:0}.g-lg-0,.gy-lg-0{--bs-gutter-y:0}.g-lg-1,.gx-lg-1{--bs-gutter-x:0.25rem}.g-lg-1,.gy-lg-1{--bs-gutter-y:0.25rem}.g-lg-2,.gx-lg-2{--bs-gutter-x:0.5rem}.g-lg-2,.gy-lg-2{--bs-gutter-y:0.5rem}.g-lg-3,.gx-lg-3{--bs-gutter-x:1rem}.g-lg-3,.gy-lg-3{--bs-gutter-y:1rem}.g-lg-4,.gx-lg-4{--bs-gutter-x:1.5rem}.g-lg-4,.gy-lg-4{--bs-gutter-y:1.5rem}.g-lg-5,.gx-lg-5{--bs-gutter-x:3rem}.g-lg-5,.gy-lg-5{--bs-gutter-y:3rem}}@media (min-width:1200px){.col-xl{flex:1 0 0%}.row-cols-xl-auto>*{flex:0 0 auto;width:auto}.row-cols-xl-1>*{flex:0 0 auto;width:100%}.row-cols-xl-2>*{flex:0 0 auto;width:50%}.row-cols-xl-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-xl-4>*{flex:0 0 auto;width:25%}.row-cols-xl-5>*{flex:0 0 auto;width:20%}.row-cols-xl-6>*{flex:0 0 auto;width:16.6666666667%}.col-xl-auto{flex:0 0 auto;width:auto}.col-xl-1{flex:0 0 auto;width:8.33333333%}.col-xl-2{flex:0 0 auto;width:16.66666667%}.col-xl-3{flex:0 0 auto;width:25%}.col-xl-4{flex:0 0 auto;width:33.33333333%}.col-xl-5{flex:0 0 auto;width:41.66666667%}.col-xl-6{flex:0 0 auto;width:50%}.col-xl-7{flex:0 0 auto;width:58.33333333%}.col-xl-8{flex:0 0 auto;width:66.66666667%}.col-xl-9{flex:0 0 auto;width:75%}.col-xl-10{flex:0 0 auto;width:83.33333333%}.col-xl-11{flex:0 0 auto;width:91.66666667%}.col-xl-12{flex:0 0 auto;width:100%}.offset-xl-0{margin-left:0}.offset-xl-1{margin-left:8.33333333%}.offset-xl-2{margin-left:16.66666667%}.offset-xl-3{margin-left:25%}.offset-xl-4{margin-left:33.33333333%}.offset-xl-5{margin-left:41.66666667%}.offset-xl-6{margin-left:50%}.offset-xl-7{margin-left:58.33333333%}.offset-xl-8{margin-left:66.66666667%}.offset-xl-9{margin-left:75%}.offset-xl-10{margin-left:83.33333333%}.offset-xl-11{margin-left:91.66666667%}.g-xl-0,.gx-xl-0{--bs-gutter-x:0}.g-xl-0,.gy-xl-0{--bs-gutter-y:0}.g-xl-1,.gx-xl-1{--bs-gutter-x:0.25rem}.g-xl-1,.gy-xl-1{--bs-gutter-y:0.25rem}.g-xl-2,.gx-xl-2{--bs-gutter-x:0.5rem}.g-xl-2,.gy-xl-2{--bs-gutter-y:0.5rem}.g-xl-3,.gx-xl-3{--bs-gutter-x:1rem}.g-xl-3,.gy-xl-3{--bs-gutter-y:1rem}.g-xl-4,.gx-xl-4{--bs-gutter-x:1.5rem}.g-xl-4,.gy-xl-4{--bs-gutter-y:1.5rem}.g-xl-5,.gx-xl-5{--bs-gutter-x:3rem}.g-xl-5,.gy-xl-5{--bs-gutter-y:3rem}}@media (min-width:1400px){.col-xxl{flex:1 0 0%}.row-cols-xxl-auto>*{flex:0 0 auto;width:auto}.row-cols-xxl-1>*{flex:0 0 auto;width:100%}.row-cols-xxl-2>*{flex:0 0 auto;width:50%}.row-cols-xxl-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-xxl-4>*{flex:0 0 auto;width:25%}.row-cols-xxl-5>*{flex:0 0 auto;width:20%}.row-cols-xxl-6>*{flex:0 0 auto;width:16.6666666667%}.col-xxl-auto{flex:0 0 auto;width:auto}.col-xxl-1{flex:0 0 auto;width:8.33333333%}.col-xxl-2{flex:0 0 auto;width:16.66666667%}.col-xxl-3{flex:0 0 auto;width:25%}.col-xxl-4{flex:0 0 auto;width:33.33333333%}.col-xxl-5{flex:0 0 auto;width:41.66666667%}.col-xxl-6{flex:0 0 auto;width:50%}.col-xxl-7{flex:0 0 auto;width:58.33333333%}.col-xxl-8{flex:0 0 auto;width:66.66666667%}.col-xxl-9{flex:0 0 auto;width:75%}.col-xxl-10{flex:0 0 auto;width:83.33333333%}.col-xxl-11{flex:0 0 auto;width:91.66666667%}.col-xxl-12{flex:0 0 auto;width:100%}.offset-xxl-0{margin-left:0}.offset-xxl-1{margin-left:8.33333333%}.offset-xxl-2{margin-left:16.66666667%}.offset-xxl-3{margin-left:25%}.offset-xxl-4{margin-left:33.33333333%}.offset-xxl-5{margin-left:41.66666667%}.offset-xxl-6{margin-left:50%}.offset-xxl-7{margin-left:58.33333333%}.offset-xxl-8{margin-left:66.66666667%}.offset-xxl-9{margin-left:75%}.offset-xxl-10{margin-left:83.33333333%}.offset-xxl-11{margin-left:91.66666667%}.g-xxl-0,.gx-xxl-0{--bs-gutter-x:0}.g-xxl-0,.gy-xxl-0{--bs-gutter-y:0}.g-xxl-1,.gx-xxl-1{--bs-gutter-x:0.25rem}.g-xxl-1,.gy-xxl-1{--bs-gutter-y:0.25rem}.g-xxl-2,.gx-xxl-2{--bs-gutter-x:0.5rem}.g-xxl-2,.gy-xxl-2{--bs-gutter-y:0.5rem}.g-xxl-3,.gx-xxl-3{--bs-gutter-x:1rem}.g-xxl-3,.gy-xxl-3{--bs-gutter-y:1rem}.g-xxl-4,.gx-xxl-4{--bs-gutter-x:1.5rem}.g-xxl-4,.gy-xxl-4{--bs-gutter-y:1.5rem}.g-xxl-5,.gx-xxl-5{--bs-gutter-x:3rem}.g-xxl-5,.gy-xxl-5{--bs-gutter-y:3rem}}.table{--bs-table-bg:transparent;--bs-table-accent-bg:transparent;--bs-table-striped-color:#212529;--bs-table-striped-bg:rgba(0, 0, 0, 0.05);--bs-table-active-color:#212529;--bs-table-active-bg:rgba(0, 0, 0, 0.1);--bs-table-hover-color:#212529;--bs-table-hover-bg:rgba(0, 0, 0, 0.075);width:100%;margin-bottom:1rem;color:#212529;vertical-align:top;border-color:#dee2e6}.table>:not(caption)>*>*{padding:.5rem .5rem;background-color:var(--bs-table-bg);border-bottom-width:1px;box-shadow:inset 0 0 0 9999px var(--bs-table-accent-bg)}.table>tbody{vertical-align:inherit}.table>thead{vertical-align:bottom}.table>:not(:first-child){border-top:2px solid currentColor}.caption-top{caption-side:top}.table-sm>:not(caption)>*>*{padding:.25rem .25rem}.table-bordered>:not(caption)>*{border-width:1px 0}.table-bordered>:not(caption)>*>*{border-width:0 1px}.table-borderless>:not(caption)>*>*{border-bottom-width:0}.table-borderless>:not(:first-child){border-top-width:0}.table-striped>tbody>tr:nth-of-type(odd)>*{--bs-table-accent-bg:var(--bs-table-striped-bg);color:var(--bs-table-striped-color)}.table-active{--bs-table-accent-bg:var(--bs-table-active-bg);color:var(--bs-table-active-color)}.table-hover>tbody>tr:hover>*{--bs-table-accent-bg:var(--bs-table-hover-bg);color:var(--bs-table-hover-color)}.table-primary{--bs-table-bg:#cfe2ff;--bs-table-striped-bg:#c5d7f2;--bs-table-striped-color:#000;--bs-table-active-bg:#bacbe6;--bs-table-active-color:#000;--bs-table-hover-bg:#bfd1ec;--bs-table-hover-color:#000;color:#000;border-color:#bacbe6}.table-secondary{--bs-table-bg:#e2e3e5;--bs-table-striped-bg:#d7d8da;--bs-table-striped-color:#000;--bs-table-active-bg:#cbccce;--bs-table-active-color:#000;--bs-table-hover-bg:#d1d2d4;--bs-table-hover-color:#000;color:#000;border-color:#cbccce}.table-success{--bs-table-bg:#d1e7dd;--bs-table-striped-bg:#c7dbd2;--bs-table-striped-color:#000;--bs-table-active-bg:#bcd0c7;--bs-table-active-color:#000;--bs-table-hover-bg:#c1d6cc;--bs-table-hover-color:#000;color:#000;border-color:#bcd0c7}.table-info{--bs-table-bg:#cff4fc;--bs-table-striped-bg:#c5e8ef;--bs-table-striped-color:#000;--bs-table-active-bg:#badce3;--bs-table-active-color:#000;--bs-table-hover-bg:#bfe2e9;--bs-table-hover-color:#000;color:#000;border-color:#badce3}.table-warning{--bs-table-bg:#fff3cd;--bs-table-striped-bg:#f2e7c3;--bs-table-striped-color:#000;--bs-table-active-bg:#e6dbb9;--bs-table-active-color:#000;--bs-table-hover-bg:#ece1be;--bs-table-hover-color:#000;color:#000;border-color:#e6dbb9}.table-danger{--bs-table-bg:#f8d7da;--bs-table-striped-bg:#eccccf;--bs-table-striped-color:#000;--bs-table-active-bg:#dfc2c4;--bs-table-active-color:#000;--bs-table-hover-bg:#e5c7ca;--bs-table-hover-color:#000;color:#000;border-color:#dfc2c4}.table-light{--bs-table-bg:#f8f9fa;--bs-table-striped-bg:#ecedee;--bs-table-striped-color:#000;--bs-table-active-bg:#dfe0e1;--bs-table-active-color:#000;--bs-table-hover-bg:#e5e6e7;--bs-table-hover-color:#000;color:#000;border-color:#dfe0e1}.table-dark{--bs-table-bg:#212529;--bs-table-striped-bg:#2c3034;--bs-table-striped-color:#fff;--bs-table-active-bg:#373b3e;--bs-table-active-color:#fff;--bs-table-hover-bg:#323539;--bs-table-hover-color:#fff;color:#fff;border-color:#373b3e}.table-responsive{overflow-x:auto;-webkit-overflow-scrolling:touch}@media (max-width:575.98px){.table-responsive-sm{overflow-x:auto;-webkit-overflow-scrolling:touch}}@media (max-width:767.98px){.table-responsive-md{overflow-x:auto;-webkit-overflow-scrolling:touch}}@media (max-width:991.98px){.table-responsive-lg{overflow-x:auto;-webkit-overflow-scrolling:touch}}@media (max-width:1199.98px){.table-responsive-xl{overflow-x:auto;-webkit-overflow-scrolling:touch}}@media (max-width:1399.98px){.table-responsive-xxl{overflow-x:auto;-webkit-overflow-scrolling:touch}}.form-label{margin-bottom:.5rem}.col-form-label{padding-top:calc(.375rem + 1px);padding-bottom:calc(.375rem + 1px);margin-bottom:0;font-size:inherit;line-height:1.5}.col-form-label-lg{padding-top:calc(.5rem + 1px);padding-bottom:calc(.5rem + 1px);font-size:1.25rem}.col-form-label-sm{padding-top:calc(.25rem + 1px);padding-bottom:calc(.25rem + 1px);font-size:.875rem}.form-text{margin-top:.25rem;font-size:.875em;color:#6c757d}.form-control{display:block;width:100%;padding:.375rem .75rem;font-size:1rem;font-weight:400;line-height:1.5;color:#212529;background-color:#fff;background-clip:padding-box;border:1px solid #ced4da;-webkit-appearance:none;-moz-appearance:none;appearance:none;border-radius:.25rem;transition:border-color .15s ease-in-out,box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.form-control{transition:none}}.form-control[type=file]{overflow:hidden}.form-control[type=file]:not(:disabled):not([readonly]){cursor:pointer}.form-control:focus{color:#212529;background-color:#fff;border-color:#86b7fe;outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.form-control::-webkit-date-and-time-value{height:1.5em}.form-control::-moz-placeholder{color:#6c757d;opacity:1}.form-control::placeholder{color:#6c757d;opacity:1}.form-control:disabled,.form-control[readonly]{background-color:#e9ecef;opacity:1}.form-control::-webkit-file-upload-button{padding:.375rem .75rem;margin:-.375rem -.75rem;-webkit-margin-end:.75rem;margin-inline-end:.75rem;color:#212529;background-color:#e9ecef;pointer-events:none;border-color:inherit;border-style:solid;border-width:0;border-inline-end-width:1px;border-radius:0;-webkit-transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}.form-control::file-selector-button{padding:.375rem .75rem;margin:-.375rem -.75rem;-webkit-margin-end:.75rem;margin-inline-end:.75rem;color:#212529;background-color:#e9ecef;pointer-events:none;border-color:inherit;border-style:solid;border-width:0;border-inline-end-width:1px;border-radius:0;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.form-control::-webkit-file-upload-button{-webkit-transition:none;transition:none}.form-control::file-selector-button{transition:none}}.form-control:hover:not(:disabled):not([readonly])::-webkit-file-upload-button{background-color:#dde0e3}.form-control:hover:not(:disabled):not([readonly])::file-selector-button{background-color:#dde0e3}.form-control::-webkit-file-upload-button{padding:.375rem .75rem;margin:-.375rem -.75rem;-webkit-margin-end:.75rem;margin-inline-end:.75rem;color:#212529;background-color:#e9ecef;pointer-events:none;border-color:inherit;border-style:solid;border-width:0;border-inline-end-width:1px;border-radius:0;-webkit-transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.form-control::-webkit-file-upload-button{-webkit-transition:none;transition:none}}.form-control:hover:not(:disabled):not([readonly])::-webkit-file-upload-button{background-color:#dde0e3}.form-control-plaintext{display:block;width:100%;padding:.375rem 0;margin-bottom:0;line-height:1.5;color:#212529;background-color:transparent;border:solid transparent;border-width:1px 0}.form-control-plaintext.form-control-lg,.form-control-plaintext.form-control-sm{padding-right:0;padding-left:0}.form-control-sm{min-height:calc(1.5em + .5rem + 2px);padding:.25rem .5rem;font-size:.875rem;border-radius:.2rem}.form-control-sm::-webkit-file-upload-button{padding:.25rem .5rem;margin:-.25rem -.5rem;-webkit-margin-end:.5rem;margin-inline-end:.5rem}.form-control-sm::file-selector-button{padding:.25rem .5rem;margin:-.25rem -.5rem;-webkit-margin-end:.5rem;margin-inline-end:.5rem}.form-control-sm::-webkit-file-upload-button{padding:.25rem .5rem;margin:-.25rem -.5rem;-webkit-margin-end:.5rem;margin-inline-end:.5rem}.form-control-lg{min-height:calc(1.5em + 1rem + 2px);padding:.5rem 1rem;font-size:1.25rem;border-radius:.3rem}.form-control-lg::-webkit-file-upload-button{padding:.5rem 1rem;margin:-.5rem -1rem;-webkit-margin-end:1rem;margin-inline-end:1rem}.form-control-lg::file-selector-button{padding:.5rem 1rem;margin:-.5rem -1rem;-webkit-margin-end:1rem;margin-inline-end:1rem}.form-control-lg::-webkit-file-upload-button{padding:.5rem 1rem;margin:-.5rem -1rem;-webkit-margin-end:1rem;margin-inline-end:1rem}textarea.form-control{min-height:calc(1.5em + .75rem + 2px)}textarea.form-control-sm{min-height:calc(1.5em + .5rem + 2px)}textarea.form-control-lg{min-height:calc(1.5em + 1rem + 2px)}.form-control-color{width:3rem;height:auto;padding:.375rem}.form-control-color:not(:disabled):not([readonly]){cursor:pointer}.form-control-color::-moz-color-swatch{height:1.5em;border-radius:.25rem}.form-control-color::-webkit-color-swatch{height:1.5em;border-radius:.25rem}.form-select{display:block;width:100%;padding:.375rem 2.25rem .375rem .75rem;-moz-padding-start:calc(0.75rem - 3px);font-size:1rem;font-weight:400;line-height:1.5;color:#212529;background-color:#fff;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3e%3cpath fill='none' stroke='%23343a40' stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M2 5l6 6 6-6'/%3e%3c/svg%3e");background-repeat:no-repeat;background-position:right .75rem center;background-size:16px 12px;border:1px solid #ced4da;border-radius:.25rem;transition:border-color .15s ease-in-out,box-shadow .15s ease-in-out;-webkit-appearance:none;-moz-appearance:none;appearance:none}@media (prefers-reduced-motion:reduce){.form-select{transition:none}}.form-select:focus{border-color:#86b7fe;outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.form-select[multiple],.form-select[size]:not([size="1"]){padding-right:.75rem;background-image:none}.form-select:disabled{background-color:#e9ecef}.form-select:-moz-focusring{color:transparent;text-shadow:0 0 0 #212529}.form-select-sm{padding-top:.25rem;padding-bottom:.25rem;padding-left:.5rem;font-size:.875rem;border-radius:.2rem}.form-select-lg{padding-top:.5rem;padding-bottom:.5rem;padding-left:1rem;font-size:1.25rem;border-radius:.3rem}.form-check{display:block;min-height:1.5rem;padding-left:1.5em;margin-bottom:.125rem}.form-check .form-check-input{float:left;margin-left:-1.5em}.form-check-input{width:1em;height:1em;margin-top:.25em;vertical-align:top;background-color:#fff;background-repeat:no-repeat;background-position:center;background-size:contain;border:1px solid rgba(0,0,0,.25);-webkit-appearance:none;-moz-appearance:none;appearance:none;-webkit-print-color-adjust:exact;color-adjust:exact}.form-check-input[type=checkbox]{border-radius:.25em}.form-check-input[type=radio]{border-radius:50%}.form-check-input:active{filter:brightness(90%)}.form-check-input:focus{border-color:#86b7fe;outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.form-check-input:checked{background-color:#0d6efd;border-color:#0d6efd}.form-check-input:checked[type=checkbox]{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20'%3e%3cpath fill='none' stroke='%23fff' stroke-linecap='round' stroke-linejoin='round' stroke-width='3' d='M6 10l3 3l6-6'/%3e%3c/svg%3e")}.form-check-input:checked[type=radio]{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='-4 -4 8 8'%3e%3ccircle r='2' fill='%23fff'/%3e%3c/svg%3e")}.form-check-input[type=checkbox]:indeterminate{background-color:#0d6efd;border-color:#0d6efd;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20'%3e%3cpath fill='none' stroke='%23fff' stroke-linecap='round' stroke-linejoin='round' stroke-width='3' d='M6 10h8'/%3e%3c/svg%3e")}.form-check-input:disabled{pointer-events:none;filter:none;opacity:.5}.form-check-input:disabled~.form-check-label,.form-check-input[disabled]~.form-check-label{opacity:.5}.form-switch{padding-left:2.5em}.form-switch .form-check-input{width:2em;margin-left:-2.5em;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='-4 -4 8 8'%3e%3ccircle r='3' fill='rgba%280, 0, 0, 0.25%29'/%3e%3c/svg%3e");background-position:left center;border-radius:2em;transition:background-position .15s ease-in-out}@media (prefers-reduced-motion:reduce){.form-switch .form-check-input{transition:none}}.form-switch .form-check-input:focus{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='-4 -4 8 8'%3e%3ccircle r='3' fill='%2386b7fe'/%3e%3c/svg%3e")}.form-switch .form-check-input:checked{background-position:right center;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='-4 -4 8 8'%3e%3ccircle r='3' fill='%23fff'/%3e%3c/svg%3e")}.form-check-inline{display:inline-block;margin-right:1rem}.btn-check{position:absolute;clip:rect(0,0,0,0);pointer-events:none}.btn-check:disabled+.btn,.btn-check[disabled]+.btn{pointer-events:none;filter:none;opacity:.65}.form-range{width:100%;height:1.5rem;padding:0;background-color:transparent;-webkit-appearance:none;-moz-appearance:none;appearance:none}.form-range:focus{outline:0}.form-range:focus::-webkit-slider-thumb{box-shadow:0 0 0 1px #fff,0 0 0 .25rem rgba(13,110,253,.25)}.form-range:focus::-moz-range-thumb{box-shadow:0 0 0 1px #fff,0 0 0 .25rem rgba(13,110,253,.25)}.form-range::-moz-focus-outer{border:0}.form-range::-webkit-slider-thumb{width:1rem;height:1rem;margin-top:-.25rem;background-color:#0d6efd;border:0;border-radius:1rem;-webkit-transition:background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;transition:background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;-webkit-appearance:none;appearance:none}@media (prefers-reduced-motion:reduce){.form-range::-webkit-slider-thumb{-webkit-transition:none;transition:none}}.form-range::-webkit-slider-thumb:active{background-color:#b6d4fe}.form-range::-webkit-slider-runnable-track{width:100%;height:.5rem;color:transparent;cursor:pointer;background-color:#dee2e6;border-color:transparent;border-radius:1rem}.form-range::-moz-range-thumb{width:1rem;height:1rem;background-color:#0d6efd;border:0;border-radius:1rem;-moz-transition:background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;transition:background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;-moz-appearance:none;appearance:none}@media (prefers-reduced-motion:reduce){.form-range::-moz-range-thumb{-moz-transition:none;transition:none}}.form-range::-moz-range-thumb:active{background-color:#b6d4fe}.form-range::-moz-range-track{width:100%;height:.5rem;color:transparent;cursor:pointer;background-color:#dee2e6;border-color:transparent;border-radius:1rem}.form-range:disabled{pointer-events:none}.form-range:disabled::-webkit-slider-thumb{background-color:#adb5bd}.form-range:disabled::-moz-range-thumb{background-color:#adb5bd}.form-floating{position:relative}.form-floating>.form-control,.form-floating>.form-select{height:calc(3.5rem + 2px);line-height:1.25}.form-floating>label{position:absolute;top:0;left:0;height:100%;padding:1rem .75rem;pointer-events:none;border:1px solid transparent;transform-origin:0 0;transition:opacity .1s ease-in-out,transform .1s ease-in-out}@media (prefers-reduced-motion:reduce){.form-floating>label{transition:none}}.form-floating>.form-control{padding:1rem .75rem}.form-floating>.form-control::-moz-placeholder{color:transparent}.form-floating>.form-control::placeholder{color:transparent}.form-floating>.form-control:not(:-moz-placeholder-shown){padding-top:1.625rem;padding-bottom:.625rem}.form-floating>.form-control:focus,.form-floating>.form-control:not(:placeholder-shown){padding-top:1.625rem;padding-bottom:.625rem}.form-floating>.form-control:-webkit-autofill{padding-top:1.625rem;padding-bottom:.625rem}.form-floating>.form-select{padding-top:1.625rem;padding-bottom:.625rem}.form-floating>.form-control:not(:-moz-placeholder-shown)~label{opacity:.65;transform:scale(.85) translateY(-.5rem) translateX(.15rem)}.form-floating>.form-control:focus~label,.form-floating>.form-control:not(:placeholder-shown)~label,.form-floating>.form-select~label{opacity:.65;transform:scale(.85) translateY(-.5rem) translateX(.15rem)}.form-floating>.form-control:-webkit-autofill~label{opacity:.65;transform:scale(.85) translateY(-.5rem) translateX(.15rem)}.input-group{position:relative;display:flex;flex-wrap:wrap;align-items:stretch;width:100%}.input-group>.form-control,.input-group>.form-select{position:relative;flex:1 1 auto;width:1%;min-width:0}.input-group>.form-control:focus,.input-group>.form-select:focus{z-index:3}.input-group .btn{position:relative;z-index:2}.input-group .btn:focus{z-index:3}.input-group-text{display:flex;align-items:center;padding:.375rem .75rem;font-size:1rem;font-weight:400;line-height:1.5;color:#212529;text-align:center;white-space:nowrap;background-color:#e9ecef;border:1px solid #ced4da;border-radius:.25rem}.input-group-lg>.btn,.input-group-lg>.form-control,.input-group-lg>.form-select,.input-group-lg>.input-group-text{padding:.5rem 1rem;font-size:1.25rem;border-radius:.3rem}.input-group-sm>.btn,.input-group-sm>.form-control,.input-group-sm>.form-select,.input-group-sm>.input-group-text{padding:.25rem .5rem;font-size:.875rem;border-radius:.2rem}.input-group-lg>.form-select,.input-group-sm>.form-select{padding-right:3rem}.input-group:not(.has-validation)>.dropdown-toggle:nth-last-child(n+3),.input-group:not(.has-validation)>:not(:last-child):not(.dropdown-toggle):not(.dropdown-menu){border-top-right-radius:0;border-bottom-right-radius:0}.input-group.has-validation>.dropdown-toggle:nth-last-child(n+4),.input-group.has-validation>:nth-last-child(n+3):not(.dropdown-toggle):not(.dropdown-menu){border-top-right-radius:0;border-bottom-right-radius:0}.input-group>:not(:first-child):not(.dropdown-menu):not(.valid-tooltip):not(.valid-feedback):not(.invalid-tooltip):not(.invalid-feedback){margin-left:-1px;border-top-left-radius:0;border-bottom-left-radius:0}.valid-feedback{display:none;width:100%;margin-top:.25rem;font-size:.875em;color:#198754}.valid-tooltip{position:absolute;top:100%;z-index:5;display:none;max-width:100%;padding:.25rem .5rem;margin-top:.1rem;font-size:.875rem;color:#fff;background-color:rgba(25,135,84,.9);border-radius:.25rem}.is-valid~.valid-feedback,.is-valid~.valid-tooltip,.was-validated :valid~.valid-feedback,.was-validated :valid~.valid-tooltip{display:block}.form-control.is-valid,.was-validated .form-control:valid{border-color:#198754;padding-right:calc(1.5em + .75rem);background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 8 8'%3e%3cpath fill='%23198754' d='M2.3 6.73L.6 4.53c-.4-1.04.46-1.4 1.1-.8l1.1 1.4 3.4-3.8c.6-.63 1.6-.27 1.2.7l-4 4.6c-.43.5-.8.4-1.1.1z'/%3e%3c/svg%3e");background-repeat:no-repeat;background-position:right calc(.375em + .1875rem) center;background-size:calc(.75em + .375rem) calc(.75em + .375rem)}.form-control.is-valid:focus,.was-validated .form-control:valid:focus{border-color:#198754;box-shadow:0 0 0 .25rem rgba(25,135,84,.25)}.was-validated textarea.form-control:valid,textarea.form-control.is-valid{padding-right:calc(1.5em + .75rem);background-position:top calc(.375em + .1875rem) right calc(.375em + .1875rem)}.form-select.is-valid,.was-validated .form-select:valid{border-color:#198754}.form-select.is-valid:not([multiple]):not([size]),.form-select.is-valid:not([multiple])[size="1"],.was-validated .form-select:valid:not([multiple]):not([size]),.was-validated .form-select:valid:not([multiple])[size="1"]{padding-right:4.125rem;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3e%3cpath fill='none' stroke='%23343a40' stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M2 5l6 6 6-6'/%3e%3c/svg%3e"),url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 8 8'%3e%3cpath fill='%23198754' d='M2.3 6.73L.6 4.53c-.4-1.04.46-1.4 1.1-.8l1.1 1.4 3.4-3.8c.6-.63 1.6-.27 1.2.7l-4 4.6c-.43.5-.8.4-1.1.1z'/%3e%3c/svg%3e");background-position:right .75rem center,center right 2.25rem;background-size:16px 12px,calc(.75em + .375rem) calc(.75em + .375rem)}.form-select.is-valid:focus,.was-validated .form-select:valid:focus{border-color:#198754;box-shadow:0 0 0 .25rem rgba(25,135,84,.25)}.form-check-input.is-valid,.was-validated .form-check-input:valid{border-color:#198754}.form-check-input.is-valid:checked,.was-validated .form-check-input:valid:checked{background-color:#198754}.form-check-input.is-valid:focus,.was-validated .form-check-input:valid:focus{box-shadow:0 0 0 .25rem rgba(25,135,84,.25)}.form-check-input.is-valid~.form-check-label,.was-validated .form-check-input:valid~.form-check-label{color:#198754}.form-check-inline .form-check-input~.valid-feedback{margin-left:.5em}.input-group .form-control.is-valid,.input-group .form-select.is-valid,.was-validated .input-group .form-control:valid,.was-validated .input-group .form-select:valid{z-index:1}.input-group .form-control.is-valid:focus,.input-group .form-select.is-valid:focus,.was-validated .input-group .form-control:valid:focus,.was-validated .input-group .form-select:valid:focus{z-index:3}.invalid-feedback{display:none;width:100%;margin-top:.25rem;font-size:.875em;color:#dc3545}.invalid-tooltip{position:absolute;top:100%;z-index:5;display:none;max-width:100%;padding:.25rem .5rem;margin-top:.1rem;font-size:.875rem;color:#fff;background-color:rgba(220,53,69,.9);border-radius:.25rem}.is-invalid~.invalid-feedback,.is-invalid~.invalid-tooltip,.was-validated :invalid~.invalid-feedback,.was-validated :invalid~.invalid-tooltip{display:block}.form-control.is-invalid,.was-validated .form-control:invalid{border-color:#dc3545;padding-right:calc(1.5em + .75rem);background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12' width='12' height='12' fill='none' stroke='%23dc3545'%3e%3ccircle cx='6' cy='6' r='4.5'/%3e%3cpath stroke-linejoin='round' d='M5.8 3.6h.4L6 6.5z'/%3e%3ccircle cx='6' cy='8.2' r='.6' fill='%23dc3545' stroke='none'/%3e%3c/svg%3e");background-repeat:no-repeat;background-position:right calc(.375em + .1875rem) center;background-size:calc(.75em + .375rem) calc(.75em + .375rem)}.form-control.is-invalid:focus,.was-validated .form-control:invalid:focus{border-color:#dc3545;box-shadow:0 0 0 .25rem rgba(220,53,69,.25)}.was-validated textarea.form-control:invalid,textarea.form-control.is-invalid{padding-right:calc(1.5em + .75rem);background-position:top calc(.375em + .1875rem) right calc(.375em + .1875rem)}.form-select.is-invalid,.was-validated .form-select:invalid{border-color:#dc3545}.form-select.is-invalid:not([multiple]):not([size]),.form-select.is-invalid:not([multiple])[size="1"],.was-validated .form-select:invalid:not([multiple]):not([size]),.was-validated .form-select:invalid:not([multiple])[size="1"]{padding-right:4.125rem;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3e%3cpath fill='none' stroke='%23343a40' stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M2 5l6 6 6-6'/%3e%3c/svg%3e"),url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12' width='12' height='12' fill='none' stroke='%23dc3545'%3e%3ccircle cx='6' cy='6' r='4.5'/%3e%3cpath stroke-linejoin='round' d='M5.8 3.6h.4L6 6.5z'/%3e%3ccircle cx='6' cy='8.2' r='.6' fill='%23dc3545' stroke='none'/%3e%3c/svg%3e");background-position:right .75rem center,center right 2.25rem;background-size:16px 12px,calc(.75em + .375rem) calc(.75em + .375rem)}.form-select.is-invalid:focus,.was-validated .form-select:invalid:focus{border-color:#dc3545;box-shadow:0 0 0 .25rem rgba(220,53,69,.25)}.form-check-input.is-invalid,.was-validated .form-check-input:invalid{border-color:#dc3545}.form-check-input.is-invalid:checked,.was-validated .form-check-input:invalid:checked{background-color:#dc3545}.form-check-input.is-invalid:focus,.was-validated .form-check-input:invalid:focus{box-shadow:0 0 0 .25rem rgba(220,53,69,.25)}.form-check-input.is-invalid~.form-check-label,.was-validated .form-check-input:invalid~.form-check-label{color:#dc3545}.form-check-inline .form-check-input~.invalid-feedback{margin-left:.5em}.input-group .form-control.is-invalid,.input-group .form-select.is-invalid,.was-validated .input-group .form-control:invalid,.was-validated .input-group .form-select:invalid{z-index:2}.input-group .form-control.is-invalid:focus,.input-group .form-select.is-invalid:focus,.was-validated .input-group .form-control:invalid:focus,.was-validated .input-group .form-select:invalid:focus{z-index:3}.btn{display:inline-block;font-weight:400;line-height:1.5;color:#212529;text-align:center;text-decoration:none;vertical-align:middle;cursor:pointer;-webkit-user-select:none;-moz-user-select:none;user-select:none;background-color:transparent;border:1px solid transparent;padding:.375rem .75rem;font-size:1rem;border-radius:.25rem;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.btn{transition:none}}.btn:hover{color:#212529}.btn-check:focus+.btn,.btn:focus{outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.btn.disabled,.btn:disabled,fieldset:disabled .btn{pointer-events:none;opacity:.65}.btn-primary{color:#fff;background-color:#0d6efd;border-color:#0d6efd}.btn-primary:hover{color:#fff;background-color:#0b5ed7;border-color:#0a58ca}.btn-check:focus+.btn-primary,.btn-primary:focus{color:#fff;background-color:#0b5ed7;border-color:#0a58ca;box-shadow:0 0 0 .25rem rgba(49,132,253,.5)}.btn-check:active+.btn-primary,.btn-check:checked+.btn-primary,.btn-primary.active,.btn-primary:active,.show>.btn-primary.dropdown-toggle{color:#fff;background-color:#0a58ca;border-color:#0a53be}.btn-check:active+.btn-primary:focus,.btn-check:checked+.btn-primary:focus,.btn-primary.active:focus,.btn-primary:active:focus,.show>.btn-primary.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(49,132,253,.5)}.btn-primary.disabled,.btn-primary:disabled{color:#fff;background-color:#0d6efd;border-color:#0d6efd}.btn-secondary{color:#fff;background-color:#6c757d;border-color:#6c757d}.btn-secondary:hover{color:#fff;background-color:#5c636a;border-color:#565e64}.btn-check:focus+.btn-secondary,.btn-secondary:focus{color:#fff;background-color:#5c636a;border-color:#565e64;box-shadow:0 0 0 .25rem rgba(130,138,145,.5)}.btn-check:active+.btn-secondary,.btn-check:checked+.btn-secondary,.btn-secondary.active,.btn-secondary:active,.show>.btn-secondary.dropdown-toggle{color:#fff;background-color:#565e64;border-color:#51585e}.btn-check:active+.btn-secondary:focus,.btn-check:checked+.btn-secondary:focus,.btn-secondary.active:focus,.btn-secondary:active:focus,.show>.btn-secondary.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(130,138,145,.5)}.btn-secondary.disabled,.btn-secondary:disabled{color:#fff;background-color:#6c757d;border-color:#6c757d}.btn-success{color:#fff;background-color:#198754;border-color:#198754}.btn-success:hover{color:#fff;background-color:#157347;border-color:#146c43}.btn-check:focus+.btn-success,.btn-success:focus{color:#fff;background-color:#157347;border-color:#146c43;box-shadow:0 0 0 .25rem rgba(60,153,110,.5)}.btn-check:active+.btn-success,.btn-check:checked+.btn-success,.btn-success.active,.btn-success:active,.show>.btn-success.dropdown-toggle{color:#fff;background-color:#146c43;border-color:#13653f}.btn-check:active+.btn-success:focus,.btn-check:checked+.btn-success:focus,.btn-success.active:focus,.btn-success:active:focus,.show>.btn-success.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(60,153,110,.5)}.btn-success.disabled,.btn-success:disabled{color:#fff;background-color:#198754;border-color:#198754}.btn-info{color:#000;background-color:#0dcaf0;border-color:#0dcaf0}.btn-info:hover{color:#000;background-color:#31d2f2;border-color:#25cff2}.btn-check:focus+.btn-info,.btn-info:focus{color:#000;background-color:#31d2f2;border-color:#25cff2;box-shadow:0 0 0 .25rem rgba(11,172,204,.5)}.btn-check:active+.btn-info,.btn-check:checked+.btn-info,.btn-info.active,.btn-info:active,.show>.btn-info.dropdown-toggle{color:#000;background-color:#3dd5f3;border-color:#25cff2}.btn-check:active+.btn-info:focus,.btn-check:checked+.btn-info:focus,.btn-info.active:focus,.btn-info:active:focus,.show>.btn-info.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(11,172,204,.5)}.btn-info.disabled,.btn-info:disabled{color:#000;background-color:#0dcaf0;border-color:#0dcaf0}.btn-warning{color:#000;background-color:#ffc107;border-color:#ffc107}.btn-warning:hover{color:#000;background-color:#ffca2c;border-color:#ffc720}.btn-check:focus+.btn-warning,.btn-warning:focus{color:#000;background-color:#ffca2c;border-color:#ffc720;box-shadow:0 0 0 .25rem rgba(217,164,6,.5)}.btn-check:active+.btn-warning,.btn-check:checked+.btn-warning,.btn-warning.active,.btn-warning:active,.show>.btn-warning.dropdown-toggle{color:#000;background-color:#ffcd39;border-color:#ffc720}.btn-check:active+.btn-warning:focus,.btn-check:checked+.btn-warning:focus,.btn-warning.active:focus,.btn-warning:active:focus,.show>.btn-warning.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(217,164,6,.5)}.btn-warning.disabled,.btn-warning:disabled{color:#000;background-color:#ffc107;border-color:#ffc107}.btn-danger{color:#fff;background-color:#dc3545;border-color:#dc3545}.btn-danger:hover{color:#fff;background-color:#bb2d3b;border-color:#b02a37}.btn-check:focus+.btn-danger,.btn-danger:focus{color:#fff;background-color:#bb2d3b;border-color:#b02a37;box-shadow:0 0 0 .25rem rgba(225,83,97,.5)}.btn-check:active+.btn-danger,.btn-check:checked+.btn-danger,.btn-danger.active,.btn-danger:active,.show>.btn-danger.dropdown-toggle{color:#fff;background-color:#b02a37;border-color:#a52834}.btn-check:active+.btn-danger:focus,.btn-check:checked+.btn-danger:focus,.btn-danger.active:focus,.btn-danger:active:focus,.show>.btn-danger.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(225,83,97,.5)}.btn-danger.disabled,.btn-danger:disabled{color:#fff;background-color:#dc3545;border-color:#dc3545}.btn-light{color:#000;background-color:#f8f9fa;border-color:#f8f9fa}.btn-light:hover{color:#000;background-color:#f9fafb;border-color:#f9fafb}.btn-check:focus+.btn-light,.btn-light:focus{color:#000;background-color:#f9fafb;border-color:#f9fafb;box-shadow:0 0 0 .25rem rgba(211,212,213,.5)}.btn-check:active+.btn-light,.btn-check:checked+.btn-light,.btn-light.active,.btn-light:active,.show>.btn-light.dropdown-toggle{color:#000;background-color:#f9fafb;border-color:#f9fafb}.btn-check:active+.btn-light:focus,.btn-check:checked+.btn-light:focus,.btn-light.active:focus,.btn-light:active:focus,.show>.btn-light.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(211,212,213,.5)}.btn-light.disabled,.btn-light:disabled{color:#000;background-color:#f8f9fa;border-color:#f8f9fa}.btn-dark{color:#fff;background-color:#212529;border-color:#212529}.btn-dark:hover{color:#fff;background-color:#1c1f23;border-color:#1a1e21}.btn-check:focus+.btn-dark,.btn-dark:focus{color:#fff;background-color:#1c1f23;border-color:#1a1e21;box-shadow:0 0 0 .25rem rgba(66,70,73,.5)}.btn-check:active+.btn-dark,.btn-check:checked+.btn-dark,.btn-dark.active,.btn-dark:active,.show>.btn-dark.dropdown-toggle{color:#fff;background-color:#1a1e21;border-color:#191c1f}.btn-check:active+.btn-dark:focus,.btn-check:checked+.btn-dark:focus,.btn-dark.active:focus,.btn-dark:active:focus,.show>.btn-dark.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(66,70,73,.5)}.btn-dark.disabled,.btn-dark:disabled{color:#fff;background-color:#212529;border-color:#212529}.btn-outline-primary{color:#0d6efd;border-color:#0d6efd}.btn-outline-primary:hover{color:#fff;background-color:#0d6efd;border-color:#0d6efd}.btn-check:focus+.btn-outline-primary,.btn-outline-primary:focus{box-shadow:0 0 0 .25rem rgba(13,110,253,.5)}.btn-check:active+.btn-outline-primary,.btn-check:checked+.btn-outline-primary,.btn-outline-primary.active,.btn-outline-primary.dropdown-toggle.show,.btn-outline-primary:active{color:#fff;background-color:#0d6efd;border-color:#0d6efd}.btn-check:active+.btn-outline-primary:focus,.btn-check:checked+.btn-outline-primary:focus,.btn-outline-primary.active:focus,.btn-outline-primary.dropdown-toggle.show:focus,.btn-outline-primary:active:focus{box-shadow:0 0 0 .25rem rgba(13,110,253,.5)}.btn-outline-primary.disabled,.btn-outline-primary:disabled{color:#0d6efd;background-color:transparent}.btn-outline-secondary{color:#6c757d;border-color:#6c757d}.btn-outline-secondary:hover{color:#fff;background-color:#6c757d;border-color:#6c757d}.btn-check:focus+.btn-outline-secondary,.btn-outline-secondary:focus{box-shadow:0 0 0 .25rem rgba(108,117,125,.5)}.btn-check:active+.btn-outline-secondary,.btn-check:checked+.btn-outline-secondary,.btn-outline-secondary.active,.btn-outline-secondary.dropdown-toggle.show,.btn-outline-secondary:active{color:#fff;background-color:#6c757d;border-color:#6c757d}.btn-check:active+.btn-outline-secondary:focus,.btn-check:checked+.btn-outline-secondary:focus,.btn-outline-secondary.active:focus,.btn-outline-secondary.dropdown-toggle.show:focus,.btn-outline-secondary:active:focus{box-shadow:0 0 0 .25rem rgba(108,117,125,.5)}.btn-outline-secondary.disabled,.btn-outline-secondary:disabled{color:#6c757d;background-color:transparent}.btn-outline-success{color:#198754;border-color:#198754}.btn-outline-success:hover{color:#fff;background-color:#198754;border-color:#198754}.btn-check:focus+.btn-outline-success,.btn-outline-success:focus{box-shadow:0 0 0 .25rem rgba(25,135,84,.5)}.btn-check:active+.btn-outline-success,.btn-check:checked+.btn-outline-success,.btn-outline-success.active,.btn-outline-success.dropdown-toggle.show,.btn-outline-success:active{color:#fff;background-color:#198754;border-color:#198754}.btn-check:active+.btn-outline-success:focus,.btn-check:checked+.btn-outline-success:focus,.btn-outline-success.active:focus,.btn-outline-success.dropdown-toggle.show:focus,.btn-outline-success:active:focus{box-shadow:0 0 0 .25rem rgba(25,135,84,.5)}.btn-outline-success.disabled,.btn-outline-success:disabled{color:#198754;background-color:transparent}.btn-outline-info{color:#0dcaf0;border-color:#0dcaf0}.btn-outline-info:hover{color:#000;background-color:#0dcaf0;border-color:#0dcaf0}.btn-check:focus+.btn-outline-info,.btn-outline-info:focus{box-shadow:0 0 0 .25rem rgba(13,202,240,.5)}.btn-check:active+.btn-outline-info,.btn-check:checked+.btn-outline-info,.btn-outline-info.active,.btn-outline-info.dropdown-toggle.show,.btn-outline-info:active{color:#000;background-color:#0dcaf0;border-color:#0dcaf0}.btn-check:active+.btn-outline-info:focus,.btn-check:checked+.btn-outline-info:focus,.btn-outline-info.active:focus,.btn-outline-info.dropdown-toggle.show:focus,.btn-outline-info:active:focus{box-shadow:0 0 0 .25rem rgba(13,202,240,.5)}.btn-outline-info.disabled,.btn-outline-info:disabled{color:#0dcaf0;background-color:transparent}.btn-outline-warning{color:#ffc107;border-color:#ffc107}.btn-outline-warning:hover{color:#000;background-color:#ffc107;border-color:#ffc107}.btn-check:focus+.btn-outline-warning,.btn-outline-warning:focus{box-shadow:0 0 0 .25rem rgba(255,193,7,.5)}.btn-check:active+.btn-outline-warning,.btn-check:checked+.btn-outline-warning,.btn-outline-warning.active,.btn-outline-warning.dropdown-toggle.show,.btn-outline-warning:active{color:#000;background-color:#ffc107;border-color:#ffc107}.btn-check:active+.btn-outline-warning:focus,.btn-check:checked+.btn-outline-warning:focus,.btn-outline-warning.active:focus,.btn-outline-warning.dropdown-toggle.show:focus,.btn-outline-warning:active:focus{box-shadow:0 0 0 .25rem rgba(255,193,7,.5)}.btn-outline-warning.disabled,.btn-outline-warning:disabled{color:#ffc107;background-color:transparent}.btn-outline-danger{color:#dc3545;border-color:#dc3545}.btn-outline-danger:hover{color:#fff;background-color:#dc3545;border-color:#dc3545}.btn-check:focus+.btn-outline-danger,.btn-outline-danger:focus{box-shadow:0 0 0 .25rem rgba(220,53,69,.5)}.btn-check:active+.btn-outline-danger,.btn-check:checked+.btn-outline-danger,.btn-outline-danger.active,.btn-outline-danger.dropdown-toggle.show,.btn-outline-danger:active{color:#fff;background-color:#dc3545;border-color:#dc3545}.btn-check:active+.btn-outline-danger:focus,.btn-check:checked+.btn-outline-danger:focus,.btn-outline-danger.active:focus,.btn-outline-danger.dropdown-toggle.show:focus,.btn-outline-danger:active:focus{box-shadow:0 0 0 .25rem rgba(220,53,69,.5)}.btn-outline-danger.disabled,.btn-outline-danger:disabled{color:#dc3545;background-color:transparent}.btn-outline-light{color:#f8f9fa;border-color:#f8f9fa}.btn-outline-light:hover{color:#000;background-color:#f8f9fa;border-color:#f8f9fa}.btn-check:focus+.btn-outline-light,.btn-outline-light:focus{box-shadow:0 0 0 .25rem rgba(248,249,250,.5)}.btn-check:active+.btn-outline-light,.btn-check:checked+.btn-outline-light,.btn-outline-light.active,.btn-outline-light.dropdown-toggle.show,.btn-outline-light:active{color:#000;background-color:#f8f9fa;border-color:#f8f9fa}.btn-check:active+.btn-outline-light:focus,.btn-check:checked+.btn-outline-light:focus,.btn-outline-light.active:focus,.btn-outline-light.dropdown-toggle.show:focus,.btn-outline-light:active:focus{box-shadow:0 0 0 .25rem rgba(248,249,250,.5)}.btn-outline-light.disabled,.btn-outline-light:disabled{color:#f8f9fa;background-color:transparent}.btn-outline-dark{color:#212529;border-color:#212529}.btn-outline-dark:hover{color:#fff;background-color:#212529;border-color:#212529}.btn-check:focus+.btn-outline-dark,.btn-outline-dark:focus{box-shadow:0 0 0 .25rem rgba(33,37,41,.5)}.btn-check:active+.btn-outline-dark,.btn-check:checked+.btn-outline-dark,.btn-outline-dark.active,.btn-outline-dark.dropdown-toggle.show,.btn-outline-dark:active{color:#fff;background-color:#212529;border-color:#212529}.btn-check:active+.btn-outline-dark:focus,.btn-check:checked+.btn-outline-dark:focus,.btn-outline-dark.active:focus,.btn-outline-dark.dropdown-toggle.show:focus,.btn-outline-dark:active:focus{box-shadow:0 0 0 .25rem rgba(33,37,41,.5)}.btn-outline-dark.disabled,.btn-outline-dark:disabled{color:#212529;background-color:transparent}.btn-link{font-weight:400;color:#0d6efd;text-decoration:underline}.btn-link:hover{color:#0a58ca}.btn-link.disabled,.btn-link:disabled{color:#6c757d}.btn-group-lg>.btn,.btn-lg{padding:.5rem 1rem;font-size:1.25rem;border-radius:.3rem}.btn-group-sm>.btn,.btn-sm{padding:.25rem .5rem;font-size:.875rem;border-radius:.2rem}.fade{transition:opacity .15s linear}@media (prefers-reduced-motion:reduce){.fade{transition:none}}.fade:not(.show){opacity:0}.collapse:not(.show){display:none}.collapsing{height:0;overflow:hidden;transition:height .35s ease}@media (prefers-reduced-motion:reduce){.collapsing{transition:none}}.collapsing.collapse-horizontal{width:0;height:auto;transition:width .35s ease}@media (prefers-reduced-motion:reduce){.collapsing.collapse-horizontal{transition:none}}.dropdown,.dropend,.dropstart,.dropup{position:relative}.dropdown-toggle{white-space:nowrap}.dropdown-toggle::after{display:inline-block;margin-left:.255em;vertical-align:.255em;content:"";border-top:.3em solid;border-right:.3em solid transparent;border-bottom:0;border-left:.3em solid transparent}.dropdown-toggle:empty::after{margin-left:0}.dropdown-menu{position:absolute;z-index:1000;display:none;min-width:10rem;padding:.5rem 0;margin:0;font-size:1rem;color:#212529;text-align:left;list-style:none;background-color:#fff;background-clip:padding-box;border:1px solid rgba(0,0,0,.15);border-radius:.25rem}.dropdown-menu[data-bs-popper]{top:100%;left:0;margin-top:.125rem}.dropdown-menu-start{--bs-position:start}.dropdown-menu-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-end{--bs-position:end}.dropdown-menu-end[data-bs-popper]{right:0;left:auto}@media (min-width:576px){.dropdown-menu-sm-start{--bs-position:start}.dropdown-menu-sm-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-sm-end{--bs-position:end}.dropdown-menu-sm-end[data-bs-popper]{right:0;left:auto}}@media (min-width:768px){.dropdown-menu-md-start{--bs-position:start}.dropdown-menu-md-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-md-end{--bs-position:end}.dropdown-menu-md-end[data-bs-popper]{right:0;left:auto}}@media (min-width:992px){.dropdown-menu-lg-start{--bs-position:start}.dropdown-menu-lg-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-lg-end{--bs-position:end}.dropdown-menu-lg-end[data-bs-popper]{right:0;left:auto}}@media (min-width:1200px){.dropdown-menu-xl-start{--bs-position:start}.dropdown-menu-xl-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-xl-end{--bs-position:end}.dropdown-menu-xl-end[data-bs-popper]{right:0;left:auto}}@media (min-width:1400px){.dropdown-menu-xxl-start{--bs-position:start}.dropdown-menu-xxl-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-xxl-end{--bs-position:end}.dropdown-menu-xxl-end[data-bs-popper]{right:0;left:auto}}.dropup .dropdown-menu[data-bs-popper]{top:auto;bottom:100%;margin-top:0;margin-bottom:.125rem}.dropup .dropdown-toggle::after{display:inline-block;margin-left:.255em;vertical-align:.255em;content:"";border-top:0;border-right:.3em solid transparent;border-bottom:.3em solid;border-left:.3em solid transparent}.dropup .dropdown-toggle:empty::after{margin-left:0}.dropend .dropdown-menu[data-bs-popper]{top:0;right:auto;left:100%;margin-top:0;margin-left:.125rem}.dropend .dropdown-toggle::after{display:inline-block;margin-left:.255em;vertical-align:.255em;content:"";border-top:.3em solid transparent;border-right:0;border-bottom:.3em solid transparent;border-left:.3em solid}.dropend .dropdown-toggle:empty::after{margin-left:0}.dropend .dropdown-toggle::after{vertical-align:0}.dropstart .dropdown-menu[data-bs-popper]{top:0;right:100%;left:auto;margin-top:0;margin-right:.125rem}.dropstart .dropdown-toggle::after{display:inline-block;margin-left:.255em;vertical-align:.255em;content:""}.dropstart .dropdown-toggle::after{display:none}.dropstart .dropdown-toggle::before{display:inline-block;margin-right:.255em;vertical-align:.255em;content:"";border-top:.3em solid transparent;border-right:.3em solid;border-bottom:.3em solid transparent}.dropstart .dropdown-toggle:empty::after{margin-left:0}.dropstart .dropdown-toggle::before{vertical-align:0}.dropdown-divider{height:0;margin:.5rem 0;overflow:hidden;border-top:1px solid rgba(0,0,0,.15)}.dropdown-item{display:block;width:100%;padding:.25rem 1rem;clear:both;font-weight:400;color:#212529;text-align:inherit;text-decoration:none;white-space:nowrap;background-color:transparent;border:0}.dropdown-item:focus,.dropdown-item:hover{color:#1e2125;background-color:#e9ecef}.dropdown-item.active,.dropdown-item:active{color:#fff;text-decoration:none;background-color:#0d6efd}.dropdown-item.disabled,.dropdown-item:disabled{color:#adb5bd;pointer-events:none;background-color:transparent}.dropdown-menu.show{display:block}.dropdown-header{display:block;padding:.5rem 1rem;margin-bottom:0;font-size:.875rem;color:#6c757d;white-space:nowrap}.dropdown-item-text{display:block;padding:.25rem 1rem;color:#212529}.dropdown-menu-dark{color:#dee2e6;background-color:#343a40;border-color:rgba(0,0,0,.15)}.dropdown-menu-dark .dropdown-item{color:#dee2e6}.dropdown-menu-dark .dropdown-item:focus,.dropdown-menu-dark .dropdown-item:hover{color:#fff;background-color:rgba(255,255,255,.15)}.dropdown-menu-dark .dropdown-item.active,.dropdown-menu-dark .dropdown-item:active{color:#fff;background-color:#0d6efd}.dropdown-menu-dark .dropdown-item.disabled,.dropdown-menu-dark .dropdown-item:disabled{color:#adb5bd}.dropdown-menu-dark .dropdown-divider{border-color:rgba(0,0,0,.15)}.dropdown-menu-dark .dropdown-item-text{color:#dee2e6}.dropdown-menu-dark .dropdown-header{color:#adb5bd}.btn-group,.btn-group-vertical{position:relative;display:inline-flex;vertical-align:middle}.btn-group-vertical>.btn,.btn-group>.btn{position:relative;flex:1 1 auto}.btn-group-vertical>.btn-check:checked+.btn,.btn-group-vertical>.btn-check:focus+.btn,.btn-group-vertical>.btn.active,.btn-group-vertical>.btn:active,.btn-group-vertical>.btn:focus,.btn-group-vertical>.btn:hover,.btn-group>.btn-check:checked+.btn,.btn-group>.btn-check:focus+.btn,.btn-group>.btn.active,.btn-group>.btn:active,.btn-group>.btn:focus,.btn-group>.btn:hover{z-index:1}.btn-toolbar{display:flex;flex-wrap:wrap;justify-content:flex-start}.btn-toolbar .input-group{width:auto}.btn-group>.btn-group:not(:first-child),.btn-group>.btn:not(:first-child){margin-left:-1px}.btn-group>.btn-group:not(:last-child)>.btn,.btn-group>.btn:not(:last-child):not(.dropdown-toggle){border-top-right-radius:0;border-bottom-right-radius:0}.btn-group>.btn-group:not(:first-child)>.btn,.btn-group>.btn:nth-child(n+3),.btn-group>:not(.btn-check)+.btn{border-top-left-radius:0;border-bottom-left-radius:0}.dropdown-toggle-split{padding-right:.5625rem;padding-left:.5625rem}.dropdown-toggle-split::after,.dropend .dropdown-toggle-split::after,.dropup .dropdown-toggle-split::after{margin-left:0}.dropstart .dropdown-toggle-split::before{margin-right:0}.btn-group-sm>.btn+.dropdown-toggle-split,.btn-sm+.dropdown-toggle-split{padding-right:.375rem;padding-left:.375rem}.btn-group-lg>.btn+.dropdown-toggle-split,.btn-lg+.dropdown-toggle-split{padding-right:.75rem;padding-left:.75rem}.btn-group-vertical{flex-direction:column;align-items:flex-start;justify-content:center}.btn-group-vertical>.btn,.btn-group-vertical>.btn-group{width:100%}.btn-group-vertical>.btn-group:not(:first-child),.btn-group-vertical>.btn:not(:first-child){margin-top:-1px}.btn-group-vertical>.btn-group:not(:last-child)>.btn,.btn-group-vertical>.btn:not(:last-child):not(.dropdown-toggle){border-bottom-right-radius:0;border-bottom-left-radius:0}.btn-group-vertical>.btn-group:not(:first-child)>.btn,.btn-group-vertical>.btn~.btn{border-top-left-radius:0;border-top-right-radius:0}.nav{display:flex;flex-wrap:wrap;padding-left:0;margin-bottom:0;list-style:none}.nav-link{display:block;padding:.5rem 1rem;color:#0d6efd;text-decoration:none;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out}@media (prefers-reduced-motion:reduce){.nav-link{transition:none}}.nav-link:focus,.nav-link:hover{color:#0a58ca}.nav-link.disabled{color:#6c757d;pointer-events:none;cursor:default}.nav-tabs{border-bottom:1px solid #dee2e6}.nav-tabs .nav-link{margin-bottom:-1px;background:0 0;border:1px solid transparent;border-top-left-radius:.25rem;border-top-right-radius:.25rem}.nav-tabs .nav-link:focus,.nav-tabs .nav-link:hover{border-color:#e9ecef #e9ecef #dee2e6;isolation:isolate}.nav-tabs .nav-link.disabled{color:#6c757d;background-color:transparent;border-color:transparent}.nav-tabs .nav-item.show .nav-link,.nav-tabs .nav-link.active{color:#495057;background-color:#fff;border-color:#dee2e6 #dee2e6 #fff}.nav-tabs .dropdown-menu{margin-top:-1px;border-top-left-radius:0;border-top-right-radius:0}.nav-pills .nav-link{background:0 0;border:0;border-radius:.25rem}.nav-pills .nav-link.active,.nav-pills .show>.nav-link{color:#fff;background-color:#0d6efd}.nav-fill .nav-item,.nav-fill>.nav-link{flex:1 1 auto;text-align:center}.nav-justified .nav-item,.nav-justified>.nav-link{flex-basis:0;flex-grow:1;text-align:center}.nav-fill .nav-item .nav-link,.nav-justified .nav-item .nav-link{width:100%}.tab-content>.tab-pane{display:none}.tab-content>.active{display:block}.navbar{position:relative;display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;padding-top:.5rem;padding-bottom:.5rem}.navbar>.container,.navbar>.container-fluid,.navbar>.container-lg,.navbar>.container-md,.navbar>.container-sm,.navbar>.container-xl,.navbar>.container-xxl{display:flex;flex-wrap:inherit;align-items:center;justify-content:space-between}.navbar-brand{padding-top:.3125rem;padding-bottom:.3125rem;margin-right:1rem;font-size:1.25rem;text-decoration:none;white-space:nowrap}.navbar-nav{display:flex;flex-direction:column;padding-left:0;margin-bottom:0;list-style:none}.navbar-nav .nav-link{padding-right:0;padding-left:0}.navbar-nav .dropdown-menu{position:static}.navbar-text{padding-top:.5rem;padding-bottom:.5rem}.navbar-collapse{flex-basis:100%;flex-grow:1;align-items:center}.navbar-toggler{padding:.25rem .75rem;font-size:1.25rem;line-height:1;background-color:transparent;border:1px solid transparent;border-radius:.25rem;transition:box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.navbar-toggler{transition:none}}.navbar-toggler:hover{text-decoration:none}.navbar-toggler:focus{text-decoration:none;outline:0;box-shadow:0 0 0 .25rem}.navbar-toggler-icon{display:inline-block;width:1.5em;height:1.5em;vertical-align:middle;background-repeat:no-repeat;background-position:center;background-size:100%}.navbar-nav-scroll{max-height:var(--bs-scroll-height,75vh);overflow-y:auto}@media (min-width:576px){.navbar-expand-sm{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand-sm .navbar-nav{flex-direction:row}.navbar-expand-sm .navbar-nav .dropdown-menu{position:absolute}.navbar-expand-sm .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand-sm .navbar-nav-scroll{overflow:visible}.navbar-expand-sm .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand-sm .navbar-toggler{display:none}.navbar-expand-sm .offcanvas-header{display:none}.navbar-expand-sm .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand-sm .offcanvas-bottom,.navbar-expand-sm .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand-sm .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}}@media (min-width:768px){.navbar-expand-md{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand-md .navbar-nav{flex-direction:row}.navbar-expand-md .navbar-nav .dropdown-menu{position:absolute}.navbar-expand-md .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand-md .navbar-nav-scroll{overflow:visible}.navbar-expand-md .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand-md .navbar-toggler{display:none}.navbar-expand-md .offcanvas-header{display:none}.navbar-expand-md .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand-md .offcanvas-bottom,.navbar-expand-md .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand-md .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}}@media (min-width:992px){.navbar-expand-lg{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand-lg .navbar-nav{flex-direction:row}.navbar-expand-lg .navbar-nav .dropdown-menu{position:absolute}.navbar-expand-lg .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand-lg .navbar-nav-scroll{overflow:visible}.navbar-expand-lg .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand-lg .navbar-toggler{display:none}.navbar-expand-lg .offcanvas-header{display:none}.navbar-expand-lg .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand-lg .offcanvas-bottom,.navbar-expand-lg .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand-lg .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}}@media (min-width:1200px){.navbar-expand-xl{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand-xl .navbar-nav{flex-direction:row}.navbar-expand-xl .navbar-nav .dropdown-menu{position:absolute}.navbar-expand-xl .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand-xl .navbar-nav-scroll{overflow:visible}.navbar-expand-xl .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand-xl .navbar-toggler{display:none}.navbar-expand-xl .offcanvas-header{display:none}.navbar-expand-xl .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand-xl .offcanvas-bottom,.navbar-expand-xl .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand-xl .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}}@media (min-width:1400px){.navbar-expand-xxl{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand-xxl .navbar-nav{flex-direction:row}.navbar-expand-xxl .navbar-nav .dropdown-menu{position:absolute}.navbar-expand-xxl .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand-xxl .navbar-nav-scroll{overflow:visible}.navbar-expand-xxl .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand-xxl .navbar-toggler{display:none}.navbar-expand-xxl .offcanvas-header{display:none}.navbar-expand-xxl .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand-xxl .offcanvas-bottom,.navbar-expand-xxl .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand-xxl .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}}.navbar-expand{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand .navbar-nav{flex-direction:row}.navbar-expand .navbar-nav .dropdown-menu{position:absolute}.navbar-expand .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand .navbar-nav-scroll{overflow:visible}.navbar-expand .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand .navbar-toggler{display:none}.navbar-expand .offcanvas-header{display:none}.navbar-expand .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand .offcanvas-bottom,.navbar-expand .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}.navbar-light .navbar-brand{color:rgba(0,0,0,.9)}.navbar-light .navbar-brand:focus,.navbar-light .navbar-brand:hover{color:rgba(0,0,0,.9)}.navbar-light .navbar-nav .nav-link{color:rgba(0,0,0,.55)}.navbar-light .navbar-nav .nav-link:focus,.navbar-light .navbar-nav .nav-link:hover{color:rgba(0,0,0,.7)}.navbar-light .navbar-nav .nav-link.disabled{color:rgba(0,0,0,.3)}.navbar-light .navbar-nav .nav-link.active,.navbar-light .navbar-nav .show>.nav-link{color:rgba(0,0,0,.9)}.navbar-light .navbar-toggler{color:rgba(0,0,0,.55);border-color:rgba(0,0,0,.1)}.navbar-light .navbar-toggler-icon{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 30 30'%3e%3cpath stroke='rgba%280, 0, 0, 0.55%29' stroke-linecap='round' stroke-miterlimit='10' stroke-width='2' d='M4 7h22M4 15h22M4 23h22'/%3e%3c/svg%3e")}.navbar-light .navbar-text{color:rgba(0,0,0,.55)}.navbar-light .navbar-text a,.navbar-light .navbar-text a:focus,.navbar-light .navbar-text a:hover{color:rgba(0,0,0,.9)}.navbar-dark .navbar-brand{color:#fff}.navbar-dark .navbar-brand:focus,.navbar-dark .navbar-brand:hover{color:#fff}.navbar-dark .navbar-nav .nav-link{color:rgba(255,255,255,.55)}.navbar-dark .navbar-nav .nav-link:focus,.navbar-dark .navbar-nav .nav-link:hover{color:rgba(255,255,255,.75)}.navbar-dark .navbar-nav .nav-link.disabled{color:rgba(255,255,255,.25)}.navbar-dark .navbar-nav .nav-link.active,.navbar-dark .navbar-nav .show>.nav-link{color:#fff}.navbar-dark .navbar-toggler{color:rgba(255,255,255,.55);border-color:rgba(255,255,255,.1)}.navbar-dark .navbar-toggler-icon{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 30 30'%3e%3cpath stroke='rgba%28255, 255, 255, 0.55%29' stroke-linecap='round' stroke-miterlimit='10' stroke-width='2' d='M4 7h22M4 15h22M4 23h22'/%3e%3c/svg%3e")}.navbar-dark .navbar-text{color:rgba(255,255,255,.55)}.navbar-dark .navbar-text a,.navbar-dark .navbar-text a:focus,.navbar-dark .navbar-text a:hover{color:#fff}.card{position:relative;display:flex;flex-direction:column;min-width:0;word-wrap:break-word;background-color:#fff;background-clip:border-box;border:1px solid rgba(0,0,0,.125);border-radius:.25rem}.card>hr{margin-right:0;margin-left:0}.card>.list-group{border-top:inherit;border-bottom:inherit}.card>.list-group:first-child{border-top-width:0;border-top-left-radius:calc(.25rem - 1px);border-top-right-radius:calc(.25rem - 1px)}.card>.list-group:last-child{border-bottom-width:0;border-bottom-right-radius:calc(.25rem - 1px);border-bottom-left-radius:calc(.25rem - 1px)}.card>.card-header+.list-group,.card>.list-group+.card-footer{border-top:0}.card-body{flex:1 1 auto;padding:1rem 1rem}.card-title{margin-bottom:.5rem}.card-subtitle{margin-top:-.25rem;margin-bottom:0}.card-text:last-child{margin-bottom:0}.card-link+.card-link{margin-left:1rem}.card-header{padding:.5rem 1rem;margin-bottom:0;background-color:rgba(0,0,0,.03);border-bottom:1px solid rgba(0,0,0,.125)}.card-header:first-child{border-radius:calc(.25rem - 1px) calc(.25rem - 1px) 0 0}.card-footer{padding:.5rem 1rem;background-color:rgba(0,0,0,.03);border-top:1px solid rgba(0,0,0,.125)}.card-footer:last-child{border-radius:0 0 calc(.25rem - 1px) calc(.25rem - 1px)}.card-header-tabs{margin-right:-.5rem;margin-bottom:-.5rem;margin-left:-.5rem;border-bottom:0}.card-header-pills{margin-right:-.5rem;margin-left:-.5rem}.card-img-overlay{position:absolute;top:0;right:0;bottom:0;left:0;padding:1rem;border-radius:calc(.25rem - 1px)}.card-img,.card-img-bottom,.card-img-top{width:100%}.card-img,.card-img-top{border-top-left-radius:calc(.25rem - 1px);border-top-right-radius:calc(.25rem - 1px)}.card-img,.card-img-bottom{border-bottom-right-radius:calc(.25rem - 1px);border-bottom-left-radius:calc(.25rem - 1px)}.card-group>.card{margin-bottom:.75rem}@media (min-width:576px){.card-group{display:flex;flex-flow:row wrap}.card-group>.card{flex:1 0 0%;margin-bottom:0}.card-group>.card+.card{margin-left:0;border-left:0}.card-group>.card:not(:last-child){border-top-right-radius:0;border-bottom-right-radius:0}.card-group>.card:not(:last-child) .card-header,.card-group>.card:not(:last-child) .card-img-top{border-top-right-radius:0}.card-group>.card:not(:last-child) .card-footer,.card-group>.card:not(:last-child) .card-img-bottom{border-bottom-right-radius:0}.card-group>.card:not(:first-child){border-top-left-radius:0;border-bottom-left-radius:0}.card-group>.card:not(:first-child) .card-header,.card-group>.card:not(:first-child) .card-img-top{border-top-left-radius:0}.card-group>.card:not(:first-child) .card-footer,.card-group>.card:not(:first-child) .card-img-bottom{border-bottom-left-radius:0}}.accordion-button{position:relative;display:flex;align-items:center;width:100%;padding:1rem 1.25rem;font-size:1rem;color:#212529;text-align:left;background-color:#fff;border:0;border-radius:0;overflow-anchor:none;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out,border-radius .15s ease}@media (prefers-reduced-motion:reduce){.accordion-button{transition:none}}.accordion-button:not(.collapsed){color:#0c63e4;background-color:#e7f1ff;box-shadow:inset 0 -1px 0 rgba(0,0,0,.125)}.accordion-button:not(.collapsed)::after{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%230c63e4'%3e%3cpath fill-rule='evenodd' d='M1.646 4.646a.5.5 0 0 1 .708 0L8 10.293l5.646-5.647a.5.5 0 0 1 .708.708l-6 6a.5.5 0 0 1-.708 0l-6-6a.5.5 0 0 1 0-.708z'/%3e%3c/svg%3e");transform:rotate(-180deg)}.accordion-button::after{flex-shrink:0;width:1.25rem;height:1.25rem;margin-left:auto;content:"";background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%23212529'%3e%3cpath fill-rule='evenodd' d='M1.646 4.646a.5.5 0 0 1 .708 0L8 10.293l5.646-5.647a.5.5 0 0 1 .708.708l-6 6a.5.5 0 0 1-.708 0l-6-6a.5.5 0 0 1 0-.708z'/%3e%3c/svg%3e");background-repeat:no-repeat;background-size:1.25rem;transition:transform .2s ease-in-out}@media (prefers-reduced-motion:reduce){.accordion-button::after{transition:none}}.accordion-button:hover{z-index:2}.accordion-button:focus{z-index:3;border-color:#86b7fe;outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.accordion-header{margin-bottom:0}.accordion-item{background-color:#fff;border:1px solid rgba(0,0,0,.125)}.accordion-item:first-of-type{border-top-left-radius:.25rem;border-top-right-radius:.25rem}.accordion-item:first-of-type .accordion-button{border-top-left-radius:calc(.25rem - 1px);border-top-right-radius:calc(.25rem - 1px)}.accordion-item:not(:first-of-type){border-top:0}.accordion-item:last-of-type{border-bottom-right-radius:.25rem;border-bottom-left-radius:.25rem}.accordion-item:last-of-type .accordion-button.collapsed{border-bottom-right-radius:calc(.25rem - 1px);border-bottom-left-radius:calc(.25rem - 1px)}.accordion-item:last-of-type .accordion-collapse{border-bottom-right-radius:.25rem;border-bottom-left-radius:.25rem}.accordion-body{padding:1rem 1.25rem}.accordion-flush .accordion-collapse{border-width:0}.accordion-flush .accordion-item{border-right:0;border-left:0;border-radius:0}.accordion-flush .accordion-item:first-child{border-top:0}.accordion-flush .accordion-item:last-child{border-bottom:0}.accordion-flush .accordion-item .accordion-button{border-radius:0}.breadcrumb{display:flex;flex-wrap:wrap;padding:0 0;margin-bottom:1rem;list-style:none}.breadcrumb-item+.breadcrumb-item{padding-left:.5rem}.breadcrumb-item+.breadcrumb-item::before{float:left;padding-right:.5rem;color:#6c757d;content:var(--bs-breadcrumb-divider, "/")}.breadcrumb-item.active{color:#6c757d}.pagination{display:flex;padding-left:0;list-style:none}.page-link{position:relative;display:block;color:#0d6efd;text-decoration:none;background-color:#fff;border:1px solid #dee2e6;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.page-link{transition:none}}.page-link:hover{z-index:2;color:#0a58ca;background-color:#e9ecef;border-color:#dee2e6}.page-link:focus{z-index:3;color:#0a58ca;background-color:#e9ecef;outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.page-item:not(:first-child) .page-link{margin-left:-1px}.page-item.active .page-link{z-index:3;color:#fff;background-color:#0d6efd;border-color:#0d6efd}.page-item.disabled .page-link{color:#6c757d;pointer-events:none;background-color:#fff;border-color:#dee2e6}.page-link{padding:.375rem .75rem}.page-item:first-child .page-link{border-top-left-radius:.25rem;border-bottom-left-radius:.25rem}.page-item:last-child .page-link{border-top-right-radius:.25rem;border-bottom-right-radius:.25rem}.pagination-lg .page-link{padding:.75rem 1.5rem;font-size:1.25rem}.pagination-lg .page-item:first-child .page-link{border-top-left-radius:.3rem;border-bottom-left-radius:.3rem}.pagination-lg .page-item:last-child .page-link{border-top-right-radius:.3rem;border-bottom-right-radius:.3rem}.pagination-sm .page-link{padding:.25rem .5rem;font-size:.875rem}.pagination-sm .page-item:first-child .page-link{border-top-left-radius:.2rem;border-bottom-left-radius:.2rem}.pagination-sm .page-item:last-child .page-link{border-top-right-radius:.2rem;border-bottom-right-radius:.2rem}.badge{display:inline-block;padding:.35em .65em;font-size:.75em;font-weight:700;line-height:1;color:#fff;text-align:center;white-space:nowrap;vertical-align:baseline;border-radius:.25rem}.badge:empty{display:none}.btn .badge{position:relative;top:-1px}.alert{position:relative;padding:1rem 1rem;margin-bottom:1rem;border:1px solid transparent;border-radius:.25rem}.alert-heading{color:inherit}.alert-link{font-weight:700}.alert-dismissible{padding-right:3rem}.alert-dismissible .btn-close{position:absolute;top:0;right:0;z-index:2;padding:1.25rem 1rem}.alert-primary{color:#084298;background-color:#cfe2ff;border-color:#b6d4fe}.alert-primary .alert-link{color:#06357a}.alert-secondary{color:#41464b;background-color:#e2e3e5;border-color:#d3d6d8}.alert-secondary .alert-link{color:#34383c}.alert-success{color:#0f5132;background-color:#d1e7dd;border-color:#badbcc}.alert-success .alert-link{color:#0c4128}.alert-info{color:#055160;background-color:#cff4fc;border-color:#b6effb}.alert-info .alert-link{color:#04414d}.alert-warning{color:#664d03;background-color:#fff3cd;border-color:#ffecb5}.alert-warning .alert-link{color:#523e02}.alert-danger{color:#842029;background-color:#f8d7da;border-color:#f5c2c7}.alert-danger .alert-link{color:#6a1a21}.alert-light{color:#636464;background-color:#fefefe;border-color:#fdfdfe}.alert-light .alert-link{color:#4f5050}.alert-dark{color:#141619;background-color:#d3d3d4;border-color:#bcbebf}.alert-dark .alert-link{color:#101214}@-webkit-keyframes progress-bar-stripes{0%{background-position-x:1rem}}@keyframes progress-bar-stripes{0%{background-position-x:1rem}}.progress{display:flex;height:1rem;overflow:hidden;font-size:.75rem;background-color:#e9ecef;border-radius:.25rem}.progress-bar{display:flex;flex-direction:column;justify-content:center;overflow:hidden;color:#fff;text-align:center;white-space:nowrap;background-color:#0d6efd;transition:width .6s ease}@media (prefers-reduced-motion:reduce){.progress-bar{transition:none}}.progress-bar-striped{background-image:linear-gradient(45deg,rgba(255,255,255,.15) 25%,transparent 25%,transparent 50%,rgba(255,255,255,.15) 50%,rgba(255,255,255,.15) 75%,transparent 75%,transparent);background-size:1rem 1rem}.progress-bar-animated{-webkit-animation:1s linear infinite progress-bar-stripes;animation:1s linear infinite progress-bar-stripes}@media (prefers-reduced-motion:reduce){.progress-bar-animated{-webkit-animation:none;animation:none}}.list-group{display:flex;flex-direction:column;padding-left:0;margin-bottom:0;border-radius:.25rem}.list-group-numbered{list-style-type:none;counter-reset:section}.list-group-numbered>li::before{content:counters(section, ".") ". ";counter-increment:section}.list-group-item-action{width:100%;color:#495057;text-align:inherit}.list-group-item-action:focus,.list-group-item-action:hover{z-index:1;color:#495057;text-decoration:none;background-color:#f8f9fa}.list-group-item-action:active{color:#212529;background-color:#e9ecef}.list-group-item{position:relative;display:block;padding:.5rem 1rem;color:#212529;text-decoration:none;background-color:#fff;border:1px solid rgba(0,0,0,.125)}.list-group-item:first-child{border-top-left-radius:inherit;border-top-right-radius:inherit}.list-group-item:last-child{border-bottom-right-radius:inherit;border-bottom-left-radius:inherit}.list-group-item.disabled,.list-group-item:disabled{color:#6c757d;pointer-events:none;background-color:#fff}.list-group-item.active{z-index:2;color:#fff;background-color:#0d6efd;border-color:#0d6efd}.list-group-item+.list-group-item{border-top-width:0}.list-group-item+.list-group-item.active{margin-top:-1px;border-top-width:1px}.list-group-horizontal{flex-direction:row}.list-group-horizontal>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal>.list-group-item.active{margin-top:0}.list-group-horizontal>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}@media (min-width:576px){.list-group-horizontal-sm{flex-direction:row}.list-group-horizontal-sm>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal-sm>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal-sm>.list-group-item.active{margin-top:0}.list-group-horizontal-sm>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal-sm>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}}@media (min-width:768px){.list-group-horizontal-md{flex-direction:row}.list-group-horizontal-md>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal-md>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal-md>.list-group-item.active{margin-top:0}.list-group-horizontal-md>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal-md>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}}@media (min-width:992px){.list-group-horizontal-lg{flex-direction:row}.list-group-horizontal-lg>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal-lg>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal-lg>.list-group-item.active{margin-top:0}.list-group-horizontal-lg>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal-lg>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}}@media (min-width:1200px){.list-group-horizontal-xl{flex-direction:row}.list-group-horizontal-xl>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal-xl>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal-xl>.list-group-item.active{margin-top:0}.list-group-horizontal-xl>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal-xl>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}}@media (min-width:1400px){.list-group-horizontal-xxl{flex-direction:row}.list-group-horizontal-xxl>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal-xxl>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal-xxl>.list-group-item.active{margin-top:0}.list-group-horizontal-xxl>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal-xxl>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}}.list-group-flush{border-radius:0}.list-group-flush>.list-group-item{border-width:0 0 1px}.list-group-flush>.list-group-item:last-child{border-bottom-width:0}.list-group-item-primary{color:#084298;background-color:#cfe2ff}.list-group-item-primary.list-group-item-action:focus,.list-group-item-primary.list-group-item-action:hover{color:#084298;background-color:#bacbe6}.list-group-item-primary.list-group-item-action.active{color:#fff;background-color:#084298;border-color:#084298}.list-group-item-secondary{color:#41464b;background-color:#e2e3e5}.list-group-item-secondary.list-group-item-action:focus,.list-group-item-secondary.list-group-item-action:hover{color:#41464b;background-color:#cbccce}.list-group-item-secondary.list-group-item-action.active{color:#fff;background-color:#41464b;border-color:#41464b}.list-group-item-success{color:#0f5132;background-color:#d1e7dd}.list-group-item-success.list-group-item-action:focus,.list-group-item-success.list-group-item-action:hover{color:#0f5132;background-color:#bcd0c7}.list-group-item-success.list-group-item-action.active{color:#fff;background-color:#0f5132;border-color:#0f5132}.list-group-item-info{color:#055160;background-color:#cff4fc}.list-group-item-info.list-group-item-action:focus,.list-group-item-info.list-group-item-action:hover{color:#055160;background-color:#badce3}.list-group-item-info.list-group-item-action.active{color:#fff;background-color:#055160;border-color:#055160}.list-group-item-warning{color:#664d03;background-color:#fff3cd}.list-group-item-warning.list-group-item-action:focus,.list-group-item-warning.list-group-item-action:hover{color:#664d03;background-color:#e6dbb9}.list-group-item-warning.list-group-item-action.active{color:#fff;background-color:#664d03;border-color:#664d03}.list-group-item-danger{color:#842029;background-color:#f8d7da}.list-group-item-danger.list-group-item-action:focus,.list-group-item-danger.list-group-item-action:hover{color:#842029;background-color:#dfc2c4}.list-group-item-danger.list-group-item-action.active{color:#fff;background-color:#842029;border-color:#842029}.list-group-item-light{color:#636464;background-color:#fefefe}.list-group-item-light.list-group-item-action:focus,.list-group-item-light.list-group-item-action:hover{color:#636464;background-color:#e5e5e5}.list-group-item-light.list-group-item-action.active{color:#fff;background-color:#636464;border-color:#636464}.list-group-item-dark{color:#141619;background-color:#d3d3d4}.list-group-item-dark.list-group-item-action:focus,.list-group-item-dark.list-group-item-action:hover{color:#141619;background-color:#bebebf}.list-group-item-dark.list-group-item-action.active{color:#fff;background-color:#141619;border-color:#141619}.btn-close{box-sizing:content-box;width:1em;height:1em;padding:.25em .25em;color:#000;background:transparent url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%23000'%3e%3cpath d='M.293.293a1 1 0 011.414 0L8 6.586 14.293.293a1 1 0 111.414 1.414L9.414 8l6.293 6.293a1 1 0 01-1.414 1.414L8 9.414l-6.293 6.293a1 1 0 01-1.414-1.414L6.586 8 .293 1.707a1 1 0 010-1.414z'/%3e%3c/svg%3e") center/1em auto no-repeat;border:0;border-radius:.25rem;opacity:.5}.btn-close:hover{color:#000;text-decoration:none;opacity:.75}.btn-close:focus{outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25);opacity:1}.btn-close.disabled,.btn-close:disabled{pointer-events:none;-webkit-user-select:none;-moz-user-select:none;user-select:none;opacity:.25}.btn-close-white{filter:invert(1) grayscale(100%) brightness(200%)}.toast{width:350px;max-width:100%;font-size:.875rem;pointer-events:auto;background-color:rgba(255,255,255,.85);background-clip:padding-box;border:1px solid rgba(0,0,0,.1);box-shadow:0 .5rem 1rem rgba(0,0,0,.15);border-radius:.25rem}.toast.showing{opacity:0}.toast:not(.show){display:none}.toast-container{width:-webkit-max-content;width:-moz-max-content;width:max-content;max-width:100%;pointer-events:none}.toast-container>:not(:last-child){margin-bottom:.75rem}.toast-header{display:flex;align-items:center;padding:.5rem .75rem;color:#6c757d;background-color:rgba(255,255,255,.85);background-clip:padding-box;border-bottom:1px solid rgba(0,0,0,.05);border-top-left-radius:calc(.25rem - 1px);border-top-right-radius:calc(.25rem - 1px)}.toast-header .btn-close{margin-right:-.375rem;margin-left:.75rem}.toast-body{padding:.75rem;word-wrap:break-word}.modal{position:fixed;top:0;left:0;z-index:1055;display:none;width:100%;height:100%;overflow-x:hidden;overflow-y:auto;outline:0}.modal-dialog{position:relative;width:auto;margin:.5rem;pointer-events:none}.modal.fade .modal-dialog{transition:transform .3s ease-out;transform:translate(0,-50px)}@media (prefers-reduced-motion:reduce){.modal.fade .modal-dialog{transition:none}}.modal.show .modal-dialog{transform:none}.modal.modal-static .modal-dialog{transform:scale(1.02)}.modal-dialog-scrollable{height:calc(100% - 1rem)}.modal-dialog-scrollable .modal-content{max-height:100%;overflow:hidden}.modal-dialog-scrollable .modal-body{overflow-y:auto}.modal-dialog-centered{display:flex;align-items:center;min-height:calc(100% - 1rem)}.modal-content{position:relative;display:flex;flex-direction:column;width:100%;pointer-events:auto;background-color:#fff;background-clip:padding-box;border:1px solid rgba(0,0,0,.2);border-radius:.3rem;outline:0}.modal-backdrop{position:fixed;top:0;left:0;z-index:1050;width:100vw;height:100vh;background-color:#000}.modal-backdrop.fade{opacity:0}.modal-backdrop.show{opacity:.5}.modal-header{display:flex;flex-shrink:0;align-items:center;justify-content:space-between;padding:1rem 1rem;border-bottom:1px solid #dee2e6;border-top-left-radius:calc(.3rem - 1px);border-top-right-radius:calc(.3rem - 1px)}.modal-header .btn-close{padding:.5rem .5rem;margin:-.5rem -.5rem -.5rem auto}.modal-title{margin-bottom:0;line-height:1.5}.modal-body{position:relative;flex:1 1 auto;padding:1rem}.modal-footer{display:flex;flex-wrap:wrap;flex-shrink:0;align-items:center;justify-content:flex-end;padding:.75rem;border-top:1px solid #dee2e6;border-bottom-right-radius:calc(.3rem - 1px);border-bottom-left-radius:calc(.3rem - 1px)}.modal-footer>*{margin:.25rem}@media (min-width:576px){.modal-dialog{max-width:500px;margin:1.75rem auto}.modal-dialog-scrollable{height:calc(100% - 3.5rem)}.modal-dialog-centered{min-height:calc(100% - 3.5rem)}.modal-sm{max-width:300px}}@media (min-width:992px){.modal-lg,.modal-xl{max-width:800px}}@media (min-width:1200px){.modal-xl{max-width:1140px}}.modal-fullscreen{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen .modal-header{border-radius:0}.modal-fullscreen .modal-body{overflow-y:auto}.modal-fullscreen .modal-footer{border-radius:0}@media (max-width:575.98px){.modal-fullscreen-sm-down{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen-sm-down .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen-sm-down .modal-header{border-radius:0}.modal-fullscreen-sm-down .modal-body{overflow-y:auto}.modal-fullscreen-sm-down .modal-footer{border-radius:0}}@media (max-width:767.98px){.modal-fullscreen-md-down{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen-md-down .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen-md-down .modal-header{border-radius:0}.modal-fullscreen-md-down .modal-body{overflow-y:auto}.modal-fullscreen-md-down .modal-footer{border-radius:0}}@media (max-width:991.98px){.modal-fullscreen-lg-down{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen-lg-down .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen-lg-down .modal-header{border-radius:0}.modal-fullscreen-lg-down .modal-body{overflow-y:auto}.modal-fullscreen-lg-down .modal-footer{border-radius:0}}@media (max-width:1199.98px){.modal-fullscreen-xl-down{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen-xl-down .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen-xl-down .modal-header{border-radius:0}.modal-fullscreen-xl-down .modal-body{overflow-y:auto}.modal-fullscreen-xl-down .modal-footer{border-radius:0}}@media (max-width:1399.98px){.modal-fullscreen-xxl-down{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen-xxl-down .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen-xxl-down .modal-header{border-radius:0}.modal-fullscreen-xxl-down .modal-body{overflow-y:auto}.modal-fullscreen-xxl-down .modal-footer{border-radius:0}}.tooltip{position:absolute;z-index:1080;display:block;margin:0;font-family:var(--bs-font-sans-serif);font-style:normal;font-weight:400;line-height:1.5;text-align:left;text-align:start;text-decoration:none;text-shadow:none;text-transform:none;letter-spacing:normal;word-break:normal;word-spacing:normal;white-space:normal;line-break:auto;font-size:.875rem;word-wrap:break-word;opacity:0}.tooltip.show{opacity:.9}.tooltip .tooltip-arrow{position:absolute;display:block;width:.8rem;height:.4rem}.tooltip .tooltip-arrow::before{position:absolute;content:"";border-color:transparent;border-style:solid}.bs-tooltip-auto[data-popper-placement^=top],.bs-tooltip-top{padding:.4rem 0}.bs-tooltip-auto[data-popper-placement^=top] .tooltip-arrow,.bs-tooltip-top .tooltip-arrow{bottom:0}.bs-tooltip-auto[data-popper-placement^=top] .tooltip-arrow::before,.bs-tooltip-top .tooltip-arrow::before{top:-1px;border-width:.4rem .4rem 0;border-top-color:#000}.bs-tooltip-auto[data-popper-placement^=right],.bs-tooltip-end{padding:0 .4rem}.bs-tooltip-auto[data-popper-placement^=right] .tooltip-arrow,.bs-tooltip-end .tooltip-arrow{left:0;width:.4rem;height:.8rem}.bs-tooltip-auto[data-popper-placement^=right] .tooltip-arrow::before,.bs-tooltip-end .tooltip-arrow::before{right:-1px;border-width:.4rem .4rem .4rem 0;border-right-color:#000}.bs-tooltip-auto[data-popper-placement^=bottom],.bs-tooltip-bottom{padding:.4rem 0}.bs-tooltip-auto[data-popper-placement^=bottom] .tooltip-arrow,.bs-tooltip-bottom .tooltip-arrow{top:0}.bs-tooltip-auto[data-popper-placement^=bottom] .tooltip-arrow::before,.bs-tooltip-bottom .tooltip-arrow::before{bottom:-1px;border-width:0 .4rem .4rem;border-bottom-color:#000}.bs-tooltip-auto[data-popper-placement^=left],.bs-tooltip-start{padding:0 .4rem}.bs-tooltip-auto[data-popper-placement^=left] .tooltip-arrow,.bs-tooltip-start .tooltip-arrow{right:0;width:.4rem;height:.8rem}.bs-tooltip-auto[data-popper-placement^=left] .tooltip-arrow::before,.bs-tooltip-start .tooltip-arrow::before{left:-1px;border-width:.4rem 0 .4rem .4rem;border-left-color:#000}.tooltip-inner{max-width:200px;padding:.25rem .5rem;color:#fff;text-align:center;background-color:#000;border-radius:.25rem}.popover{position:absolute;top:0;left:0;z-index:1070;display:block;max-width:276px;font-family:var(--bs-font-sans-serif);font-style:normal;font-weight:400;line-height:1.5;text-align:left;text-align:start;text-decoration:none;text-shadow:none;text-transform:none;letter-spacing:normal;word-break:normal;word-spacing:normal;white-space:normal;line-break:auto;font-size:.875rem;word-wrap:break-word;background-color:#fff;background-clip:padding-box;border:1px solid rgba(0,0,0,.2);border-radius:.3rem}.popover .popover-arrow{position:absolute;display:block;width:1rem;height:.5rem}.popover .popover-arrow::after,.popover .popover-arrow::before{position:absolute;display:block;content:"";border-color:transparent;border-style:solid}.bs-popover-auto[data-popper-placement^=top]>.popover-arrow,.bs-popover-top>.popover-arrow{bottom:calc(-.5rem - 1px)}.bs-popover-auto[data-popper-placement^=top]>.popover-arrow::before,.bs-popover-top>.popover-arrow::before{bottom:0;border-width:.5rem .5rem 0;border-top-color:rgba(0,0,0,.25)}.bs-popover-auto[data-popper-placement^=top]>.popover-arrow::after,.bs-popover-top>.popover-arrow::after{bottom:1px;border-width:.5rem .5rem 0;border-top-color:#fff}.bs-popover-auto[data-popper-placement^=right]>.popover-arrow,.bs-popover-end>.popover-arrow{left:calc(-.5rem - 1px);width:.5rem;height:1rem}.bs-popover-auto[data-popper-placement^=right]>.popover-arrow::before,.bs-popover-end>.popover-arrow::before{left:0;border-width:.5rem .5rem .5rem 0;border-right-color:rgba(0,0,0,.25)}.bs-popover-auto[data-popper-placement^=right]>.popover-arrow::after,.bs-popover-end>.popover-arrow::after{left:1px;border-width:.5rem .5rem .5rem 0;border-right-color:#fff}.bs-popover-auto[data-popper-placement^=bottom]>.popover-arrow,.bs-popover-bottom>.popover-arrow{top:calc(-.5rem - 1px)}.bs-popover-auto[data-popper-placement^=bottom]>.popover-arrow::before,.bs-popover-bottom>.popover-arrow::before{top:0;border-width:0 .5rem .5rem .5rem;border-bottom-color:rgba(0,0,0,.25)}.bs-popover-auto[data-popper-placement^=bottom]>.popover-arrow::after,.bs-popover-bottom>.popover-arrow::after{top:1px;border-width:0 .5rem .5rem .5rem;border-bottom-color:#fff}.bs-popover-auto[data-popper-placement^=bottom] .popover-header::before,.bs-popover-bottom .popover-header::before{position:absolute;top:0;left:50%;display:block;width:1rem;margin-left:-.5rem;content:"";border-bottom:1px solid #f0f0f0}.bs-popover-auto[data-popper-placement^=left]>.popover-arrow,.bs-popover-start>.popover-arrow{right:calc(-.5rem - 1px);width:.5rem;height:1rem}.bs-popover-auto[data-popper-placement^=left]>.popover-arrow::before,.bs-popover-start>.popover-arrow::before{right:0;border-width:.5rem 0 .5rem .5rem;border-left-color:rgba(0,0,0,.25)}.bs-popover-auto[data-popper-placement^=left]>.popover-arrow::after,.bs-popover-start>.popover-arrow::after{right:1px;border-width:.5rem 0 .5rem .5rem;border-left-color:#fff}.popover-header{padding:.5rem 1rem;margin-bottom:0;font-size:1rem;background-color:#f0f0f0;border-bottom:1px solid rgba(0,0,0,.2);border-top-left-radius:calc(.3rem - 1px);border-top-right-radius:calc(.3rem - 1px)}.popover-header:empty{display:none}.popover-body{padding:1rem 1rem;color:#212529}.carousel{position:relative}.carousel.pointer-event{touch-action:pan-y}.carousel-inner{position:relative;width:100%;overflow:hidden}.carousel-inner::after{display:block;clear:both;content:""}.carousel-item{position:relative;display:none;float:left;width:100%;margin-right:-100%;-webkit-backface-visibility:hidden;backface-visibility:hidden;transition:transform .6s ease-in-out}@media (prefers-reduced-motion:reduce){.carousel-item{transition:none}}.carousel-item-next,.carousel-item-prev,.carousel-item.active{display:block}.active.carousel-item-end,.carousel-item-next:not(.carousel-item-start){transform:translateX(100%)}.active.carousel-item-start,.carousel-item-prev:not(.carousel-item-end){transform:translateX(-100%)}.carousel-fade .carousel-item{opacity:0;transition-property:opacity;transform:none}.carousel-fade .carousel-item-next.carousel-item-start,.carousel-fade .carousel-item-prev.carousel-item-end,.carousel-fade .carousel-item.active{z-index:1;opacity:1}.carousel-fade .active.carousel-item-end,.carousel-fade .active.carousel-item-start{z-index:0;opacity:0;transition:opacity 0s .6s}@media (prefers-reduced-motion:reduce){.carousel-fade .active.carousel-item-end,.carousel-fade .active.carousel-item-start{transition:none}}.carousel-control-next,.carousel-control-prev{position:absolute;top:0;bottom:0;z-index:1;display:flex;align-items:center;justify-content:center;width:15%;padding:0;color:#fff;text-align:center;background:0 0;border:0;opacity:.5;transition:opacity .15s ease}@media (prefers-reduced-motion:reduce){.carousel-control-next,.carousel-control-prev{transition:none}}.carousel-control-next:focus,.carousel-control-next:hover,.carousel-control-prev:focus,.carousel-control-prev:hover{color:#fff;text-decoration:none;outline:0;opacity:.9}.carousel-control-prev{left:0}.carousel-control-next{right:0}.carousel-control-next-icon,.carousel-control-prev-icon{display:inline-block;width:2rem;height:2rem;background-repeat:no-repeat;background-position:50%;background-size:100% 100%}.carousel-control-prev-icon{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%23fff'%3e%3cpath d='M11.354 1.646a.5.5 0 0 1 0 .708L5.707 8l5.647 5.646a.5.5 0 0 1-.708.708l-6-6a.5.5 0 0 1 0-.708l6-6a.5.5 0 0 1 .708 0z'/%3e%3c/svg%3e")}.carousel-control-next-icon{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%23fff'%3e%3cpath d='M4.646 1.646a.5.5 0 0 1 .708 0l6 6a.5.5 0 0 1 0 .708l-6 6a.5.5 0 0 1-.708-.708L10.293 8 4.646 2.354a.5.5 0 0 1 0-.708z'/%3e%3c/svg%3e")}.carousel-indicators{position:absolute;right:0;bottom:0;left:0;z-index:2;display:flex;justify-content:center;padding:0;margin-right:15%;margin-bottom:1rem;margin-left:15%;list-style:none}.carousel-indicators [data-bs-target]{box-sizing:content-box;flex:0 1 auto;width:30px;height:3px;padding:0;margin-right:3px;margin-left:3px;text-indent:-999px;cursor:pointer;background-color:#fff;background-clip:padding-box;border:0;border-top:10px solid transparent;border-bottom:10px solid transparent;opacity:.5;transition:opacity .6s ease}@media (prefers-reduced-motion:reduce){.carousel-indicators [data-bs-target]{transition:none}}.carousel-indicators .active{opacity:1}.carousel-caption{position:absolute;right:15%;bottom:1.25rem;left:15%;padding-top:1.25rem;padding-bottom:1.25rem;color:#fff;text-align:center}.carousel-dark .carousel-control-next-icon,.carousel-dark .carousel-control-prev-icon{filter:invert(1) grayscale(100)}.carousel-dark .carousel-indicators [data-bs-target]{background-color:#000}.carousel-dark .carousel-caption{color:#000}@-webkit-keyframes spinner-border{to{transform:rotate(360deg)}}@keyframes spinner-border{to{transform:rotate(360deg)}}.spinner-border{display:inline-block;width:2rem;height:2rem;vertical-align:-.125em;border:.25em solid currentColor;border-right-color:transparent;border-radius:50%;-webkit-animation:.75s linear infinite spinner-border;animation:.75s linear infinite spinner-border}.spinner-border-sm{width:1rem;height:1rem;border-width:.2em}@-webkit-keyframes spinner-grow{0%{transform:scale(0)}50%{opacity:1;transform:none}}@keyframes spinner-grow{0%{transform:scale(0)}50%{opacity:1;transform:none}}.spinner-grow{display:inline-block;width:2rem;height:2rem;vertical-align:-.125em;background-color:currentColor;border-radius:50%;opacity:0;-webkit-animation:.75s linear infinite spinner-grow;animation:.75s linear infinite spinner-grow}.spinner-grow-sm{width:1rem;height:1rem}@media (prefers-reduced-motion:reduce){.spinner-border,.spinner-grow{-webkit-animation-duration:1.5s;animation-duration:1.5s}}.offcanvas{position:fixed;bottom:0;z-index:1045;display:flex;flex-direction:column;max-width:100%;visibility:hidden;background-color:#fff;background-clip:padding-box;outline:0;transition:transform .3s ease-in-out}@media (prefers-reduced-motion:reduce){.offcanvas{transition:none}}.offcanvas-backdrop{position:fixed;top:0;left:0;z-index:1040;width:100vw;height:100vh;background-color:#000}.offcanvas-backdrop.fade{opacity:0}.offcanvas-backdrop.show{opacity:.5}.offcanvas-header{display:flex;align-items:center;justify-content:space-between;padding:1rem 1rem}.offcanvas-header .btn-close{padding:.5rem .5rem;margin-top:-.5rem;margin-right:-.5rem;margin-bottom:-.5rem}.offcanvas-title{margin-bottom:0;line-height:1.5}.offcanvas-body{flex-grow:1;padding:1rem 1rem;overflow-y:auto}.offcanvas-start{top:0;left:0;width:400px;border-right:1px solid rgba(0,0,0,.2);transform:translateX(-100%)}.offcanvas-end{top:0;right:0;width:400px;border-left:1px solid rgba(0,0,0,.2);transform:translateX(100%)}.offcanvas-top{top:0;right:0;left:0;height:30vh;max-height:100%;border-bottom:1px solid rgba(0,0,0,.2);transform:translateY(-100%)}.offcanvas-bottom{right:0;left:0;height:30vh;max-height:100%;border-top:1px solid rgba(0,0,0,.2);transform:translateY(100%)}.offcanvas.show{transform:none}.placeholder{display:inline-block;min-height:1em;vertical-align:middle;cursor:wait;background-color:currentColor;opacity:.5}.placeholder.btn::before{display:inline-block;content:""}.placeholder-xs{min-height:.6em}.placeholder-sm{min-height:.8em}.placeholder-lg{min-height:1.2em}.placeholder-glow .placeholder{-webkit-animation:placeholder-glow 2s ease-in-out infinite;animation:placeholder-glow 2s ease-in-out infinite}@-webkit-keyframes placeholder-glow{50%{opacity:.2}}@keyframes placeholder-glow{50%{opacity:.2}}.placeholder-wave{-webkit-mask-image:linear-gradient(130deg,#000 55%,rgba(0,0,0,0.8) 75%,#000 95%);mask-image:linear-gradient(130deg,#000 55%,rgba(0,0,0,0.8) 75%,#000 95%);-webkit-mask-size:200% 100%;mask-size:200% 100%;-webkit-animation:placeholder-wave 2s linear infinite;animation:placeholder-wave 2s linear infinite}@-webkit-keyframes placeholder-wave{100%{-webkit-mask-position:-200% 0%;mask-position:-200% 0%}}@keyframes placeholder-wave{100%{-webkit-mask-position:-200% 0%;mask-position:-200% 0%}}.clearfix::after{display:block;clear:both;content:""}.link-primary{color:#0d6efd}.link-primary:focus,.link-primary:hover{color:#0a58ca}.link-secondary{color:#6c757d}.link-secondary:focus,.link-secondary:hover{color:#565e64}.link-success{color:#198754}.link-success:focus,.link-success:hover{color:#146c43}.link-info{color:#0dcaf0}.link-info:focus,.link-info:hover{color:#3dd5f3}.link-warning{color:#ffc107}.link-warning:focus,.link-warning:hover{color:#ffcd39}.link-danger{color:#dc3545}.link-danger:focus,.link-danger:hover{color:#b02a37}.link-light{color:#f8f9fa}.link-light:focus,.link-light:hover{color:#f9fafb}.link-dark{color:#212529}.link-dark:focus,.link-dark:hover{color:#1a1e21}.ratio{position:relative;width:100%}.ratio::before{display:block;padding-top:var(--bs-aspect-ratio);content:""}.ratio>*{position:absolute;top:0;left:0;width:100%;height:100%}.ratio-1x1{--bs-aspect-ratio:100%}.ratio-4x3{--bs-aspect-ratio:75%}.ratio-16x9{--bs-aspect-ratio:56.25%}.ratio-21x9{--bs-aspect-ratio:42.8571428571%}.fixed-top{position:fixed;top:0;right:0;left:0;z-index:1030}.fixed-bottom{position:fixed;right:0;bottom:0;left:0;z-index:1030}.sticky-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}@media (min-width:576px){.sticky-sm-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}}@media (min-width:768px){.sticky-md-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}}@media (min-width:992px){.sticky-lg-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}}@media (min-width:1200px){.sticky-xl-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}}@media (min-width:1400px){.sticky-xxl-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}}.hstack{display:flex;flex-direction:row;align-items:center;align-self:stretch}.vstack{display:flex;flex:1 1 auto;flex-direction:column;align-self:stretch}.visually-hidden,.visually-hidden-focusable:not(:focus):not(:focus-within){position:absolute!important;width:1px!important;height:1px!important;padding:0!important;margin:-1px!important;overflow:hidden!important;clip:rect(0,0,0,0)!important;white-space:nowrap!important;border:0!important}.stretched-link::after{position:absolute;top:0;right:0;bottom:0;left:0;z-index:1;content:""}.text-truncate{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.vr{display:inline-block;align-self:stretch;width:1px;min-height:1em;background-color:currentColor;opacity:.25}.align-baseline{vertical-align:baseline!important}.align-top{vertical-align:top!important}.align-middle{vertical-align:middle!important}.align-bottom{vertical-align:bottom!important}.align-text-bottom{vertical-align:text-bottom!important}.align-text-top{vertical-align:text-top!important}.float-start{float:left!important}.float-end{float:right!important}.float-none{float:none!important}.opacity-0{opacity:0!important}.opacity-25{opacity:.25!important}.opacity-50{opacity:.5!important}.opacity-75{opacity:.75!important}.opacity-100{opacity:1!important}.overflow-auto{overflow:auto!important}.overflow-hidden{overflow:hidden!important}.overflow-visible{overflow:visible!important}.overflow-scroll{overflow:scroll!important}.d-inline{display:inline!important}.d-inline-block{display:inline-block!important}.d-block{display:block!important}.d-grid{display:grid!important}.d-table{display:table!important}.d-table-row{display:table-row!important}.d-table-cell{display:table-cell!important}.d-flex{display:flex!important}.d-inline-flex{display:inline-flex!important}.d-none{display:none!important}.shadow{box-shadow:0 .5rem 1rem rgba(0,0,0,.15)!important}.shadow-sm{box-shadow:0 .125rem .25rem rgba(0,0,0,.075)!important}.shadow-lg{box-shadow:0 1rem 3rem rgba(0,0,0,.175)!important}.shadow-none{box-shadow:none!important}.position-static{position:static!important}.position-relative{position:relative!important}.position-absolute{position:absolute!important}.position-fixed{position:fixed!important}.position-sticky{position:-webkit-sticky!important;position:sticky!important}.top-0{top:0!important}.top-50{top:50%!important}.top-100{top:100%!important}.bottom-0{bottom:0!important}.bottom-50{bottom:50%!important}.bottom-100{bottom:100%!important}.start-0{left:0!important}.start-50{left:50%!important}.start-100{left:100%!important}.end-0{right:0!important}.end-50{right:50%!important}.end-100{right:100%!important}.translate-middle{transform:translate(-50%,-50%)!important}.translate-middle-x{transform:translateX(-50%)!important}.translate-middle-y{transform:translateY(-50%)!important}.border{border:1px solid #dee2e6!important}.border-0{border:0!important}.border-top{border-top:1px solid #dee2e6!important}.border-top-0{border-top:0!important}.border-end{border-right:1px solid #dee2e6!important}.border-end-0{border-right:0!important}.border-bottom{border-bottom:1px solid #dee2e6!important}.border-bottom-0{border-bottom:0!important}.border-start{border-left:1px solid #dee2e6!important}.border-start-0{border-left:0!important}.border-primary{border-color:#0d6efd!important}.border-secondary{border-color:#6c757d!important}.border-success{border-color:#198754!important}.border-info{border-color:#0dcaf0!important}.border-warning{border-color:#ffc107!important}.border-danger{border-color:#dc3545!important}.border-light{border-color:#f8f9fa!important}.border-dark{border-color:#212529!important}.border-white{border-color:#fff!important}.border-1{border-width:1px!important}.border-2{border-width:2px!important}.border-3{border-width:3px!important}.border-4{border-width:4px!important}.border-5{border-width:5px!important}.w-25{width:25%!important}.w-50{width:50%!important}.w-75{width:75%!important}.w-100{width:100%!important}.w-auto{width:auto!important}.mw-100{max-width:100%!important}.vw-100{width:100vw!important}.min-vw-100{min-width:100vw!important}.h-25{height:25%!important}.h-50{height:50%!important}.h-75{height:75%!important}.h-100{height:100%!important}.h-auto{height:auto!important}.mh-100{max-height:100%!important}.vh-100{height:100vh!important}.min-vh-100{min-height:100vh!important}.flex-fill{flex:1 1 auto!important}.flex-row{flex-direction:row!important}.flex-column{flex-direction:column!important}.flex-row-reverse{flex-direction:row-reverse!important}.flex-column-reverse{flex-direction:column-reverse!important}.flex-grow-0{flex-grow:0!important}.flex-grow-1{flex-grow:1!important}.flex-shrink-0{flex-shrink:0!important}.flex-shrink-1{flex-shrink:1!important}.flex-wrap{flex-wrap:wrap!important}.flex-nowrap{flex-wrap:nowrap!important}.flex-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-0{gap:0!important}.gap-1{gap:.25rem!important}.gap-2{gap:.5rem!important}.gap-3{gap:1rem!important}.gap-4{gap:1.5rem!important}.gap-5{gap:3rem!important}.justify-content-start{justify-content:flex-start!important}.justify-content-end{justify-content:flex-end!important}.justify-content-center{justify-content:center!important}.justify-content-between{justify-content:space-between!important}.justify-content-around{justify-content:space-around!important}.justify-content-evenly{justify-content:space-evenly!important}.align-items-start{align-items:flex-start!important}.align-items-end{align-items:flex-end!important}.align-items-center{align-items:center!important}.align-items-baseline{align-items:baseline!important}.align-items-stretch{align-items:stretch!important}.align-content-start{align-content:flex-start!important}.align-content-end{align-content:flex-end!important}.align-content-center{align-content:center!important}.align-content-between{align-content:space-between!important}.align-content-around{align-content:space-around!important}.align-content-stretch{align-content:stretch!important}.align-self-auto{align-self:auto!important}.align-self-start{align-self:flex-start!important}.align-self-end{align-self:flex-end!important}.align-self-center{align-self:center!important}.align-self-baseline{align-self:baseline!important}.align-self-stretch{align-self:stretch!important}.order-first{order:-1!important}.order-0{order:0!important}.order-1{order:1!important}.order-2{order:2!important}.order-3{order:3!important}.order-4{order:4!important}.order-5{order:5!important}.order-last{order:6!important}.m-0{margin:0!important}.m-1{margin:.25rem!important}.m-2{margin:.5rem!important}.m-3{margin:1rem!important}.m-4{margin:1.5rem!important}.m-5{margin:3rem!important}.m-auto{margin:auto!important}.mx-0{margin-right:0!important;margin-left:0!important}.mx-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-3{margin-right:1rem!important;margin-left:1rem!important}.mx-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-5{margin-right:3rem!important;margin-left:3rem!important}.mx-auto{margin-right:auto!important;margin-left:auto!important}.my-0{margin-top:0!important;margin-bottom:0!important}.my-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-0{margin-top:0!important}.mt-1{margin-top:.25rem!important}.mt-2{margin-top:.5rem!important}.mt-3{margin-top:1rem!important}.mt-4{margin-top:1.5rem!important}.mt-5{margin-top:3rem!important}.mt-auto{margin-top:auto!important}.me-0{margin-right:0!important}.me-1{margin-right:.25rem!important}.me-2{margin-right:.5rem!important}.me-3{margin-right:1rem!important}.me-4{margin-right:1.5rem!important}.me-5{margin-right:3rem!important}.me-auto{margin-right:auto!important}.mb-0{margin-bottom:0!important}.mb-1{margin-bottom:.25rem!important}.mb-2{margin-bottom:.5rem!important}.mb-3{margin-bottom:1rem!important}.mb-4{margin-bottom:1.5rem!important}.mb-5{margin-bottom:3rem!important}.mb-auto{margin-bottom:auto!important}.ms-0{margin-left:0!important}.ms-1{margin-left:.25rem!important}.ms-2{margin-left:.5rem!important}.ms-3{margin-left:1rem!important}.ms-4{margin-left:1.5rem!important}.ms-5{margin-left:3rem!important}.ms-auto{margin-left:auto!important}.p-0{padding:0!important}.p-1{padding:.25rem!important}.p-2{padding:.5rem!important}.p-3{padding:1rem!important}.p-4{padding:1.5rem!important}.p-5{padding:3rem!important}.px-0{padding-right:0!important;padding-left:0!important}.px-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-3{padding-right:1rem!important;padding-left:1rem!important}.px-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-5{padding-right:3rem!important;padding-left:3rem!important}.py-0{padding-top:0!important;padding-bottom:0!important}.py-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-0{padding-top:0!important}.pt-1{padding-top:.25rem!important}.pt-2{padding-top:.5rem!important}.pt-3{padding-top:1rem!important}.pt-4{padding-top:1.5rem!important}.pt-5{padding-top:3rem!important}.pe-0{padding-right:0!important}.pe-1{padding-right:.25rem!important}.pe-2{padding-right:.5rem!important}.pe-3{padding-right:1rem!important}.pe-4{padding-right:1.5rem!important}.pe-5{padding-right:3rem!important}.pb-0{padding-bottom:0!important}.pb-1{padding-bottom:.25rem!important}.pb-2{padding-bottom:.5rem!important}.pb-3{padding-bottom:1rem!important}.pb-4{padding-bottom:1.5rem!important}.pb-5{padding-bottom:3rem!important}.ps-0{padding-left:0!important}.ps-1{padding-left:.25rem!important}.ps-2{padding-left:.5rem!important}.ps-3{padding-left:1rem!important}.ps-4{padding-left:1.5rem!important}.ps-5{padding-left:3rem!important}.font-monospace{font-family:var(--bs-font-monospace)!important}.fs-1{font-size:calc(1.375rem + 1.5vw)!important}.fs-2{font-size:calc(1.325rem + .9vw)!important}.fs-3{font-size:calc(1.3rem + .6vw)!important}.fs-4{font-size:calc(1.275rem + .3vw)!important}.fs-5{font-size:1.25rem!important}.fs-6{font-size:1rem!important}.fst-italic{font-style:italic!important}.fst-normal{font-style:normal!important}.fw-light{font-weight:300!important}.fw-lighter{font-weight:lighter!important}.fw-normal{font-weight:400!important}.fw-bold{font-weight:700!important}.fw-bolder{font-weight:bolder!important}.lh-1{line-height:1!important}.lh-sm{line-height:1.25!important}.lh-base{line-height:1.5!important}.lh-lg{line-height:2!important}.text-start{text-align:left!important}.text-end{text-align:right!important}.text-center{text-align:center!important}.text-decoration-none{text-decoration:none!important}.text-decoration-underline{text-decoration:underline!important}.text-decoration-line-through{text-decoration:line-through!important}.text-lowercase{text-transform:lowercase!important}.text-uppercase{text-transform:uppercase!important}.text-capitalize{text-transform:capitalize!important}.text-wrap{white-space:normal!important}.text-nowrap{white-space:nowrap!important}.text-break{word-wrap:break-word!important;word-break:break-word!important}.text-primary{--bs-text-opacity:1;color:rgba(var(--bs-primary-rgb),var(--bs-text-opacity))!important}.text-secondary{--bs-text-opacity:1;color:rgba(var(--bs-secondary-rgb),var(--bs-text-opacity))!important}.text-success{--bs-text-opacity:1;color:rgba(var(--bs-success-rgb),var(--bs-text-opacity))!important}.text-info{--bs-text-opacity:1;color:rgba(var(--bs-info-rgb),var(--bs-text-opacity))!important}.text-warning{--bs-text-opacity:1;color:rgba(var(--bs-warning-rgb),var(--bs-text-opacity))!important}.text-danger{--bs-text-opacity:1;color:rgba(var(--bs-danger-rgb),var(--bs-text-opacity))!important}.text-light{--bs-text-opacity:1;color:rgba(var(--bs-light-rgb),var(--bs-text-opacity))!important}.text-dark{--bs-text-opacity:1;color:rgba(var(--bs-dark-rgb),var(--bs-text-opacity))!important}.text-black{--bs-text-opacity:1;color:rgba(var(--bs-black-rgb),var(--bs-text-opacity))!important}.text-white{--bs-text-opacity:1;color:rgba(var(--bs-white-rgb),var(--bs-text-opacity))!important}.text-body{--bs-text-opacity:1;color:rgba(var(--bs-body-color-rgb),var(--bs-text-opacity))!important}.text-muted{--bs-text-opacity:1;color:#6c757d!important}.text-black-50{--bs-text-opacity:1;color:rgba(0,0,0,.5)!important}.text-white-50{--bs-text-opacity:1;color:rgba(255,255,255,.5)!important}.text-reset{--bs-text-opacity:1;color:inherit!important}.text-opacity-25{--bs-text-opacity:0.25}.text-opacity-50{--bs-text-opacity:0.5}.text-opacity-75{--bs-text-opacity:0.75}.text-opacity-100{--bs-text-opacity:1}.bg-primary{--bs-bg-opacity:1;background-color:rgba(var(--bs-primary-rgb),var(--bs-bg-opacity))!important}.bg-secondary{--bs-bg-opacity:1;background-color:rgba(var(--bs-secondary-rgb),var(--bs-bg-opacity))!important}.bg-success{--bs-bg-opacity:1;background-color:rgba(var(--bs-success-rgb),var(--bs-bg-opacity))!important}.bg-info{--bs-bg-opacity:1;background-color:rgba(var(--bs-info-rgb),var(--bs-bg-opacity))!important}.bg-warning{--bs-bg-opacity:1;background-color:rgba(var(--bs-warning-rgb),var(--bs-bg-opacity))!important}.bg-danger{--bs-bg-opacity:1;background-color:rgba(var(--bs-danger-rgb),var(--bs-bg-opacity))!important}.bg-light{--bs-bg-opacity:1;background-color:rgba(var(--bs-light-rgb),var(--bs-bg-opacity))!important}.bg-dark{--bs-bg-opacity:1;background-color:rgba(var(--bs-dark-rgb),var(--bs-bg-opacity))!important}.bg-black{--bs-bg-opacity:1;background-color:rgba(var(--bs-black-rgb),var(--bs-bg-opacity))!important}.bg-white{--bs-bg-opacity:1;background-color:rgba(var(--bs-white-rgb),var(--bs-bg-opacity))!important}.bg-body{--bs-bg-opacity:1;background-color:rgba(var(--bs-body-bg-rgb),var(--bs-bg-opacity))!important}.bg-transparent{--bs-bg-opacity:1;background-color:transparent!important}.bg-opacity-10{--bs-bg-opacity:0.1}.bg-opacity-25{--bs-bg-opacity:0.25}.bg-opacity-50{--bs-bg-opacity:0.5}.bg-opacity-75{--bs-bg-opacity:0.75}.bg-opacity-100{--bs-bg-opacity:1}.bg-gradient{background-image:var(--bs-gradient)!important}.user-select-all{-webkit-user-select:all!important;-moz-user-select:all!important;user-select:all!important}.user-select-auto{-webkit-user-select:auto!important;-moz-user-select:auto!important;user-select:auto!important}.user-select-none{-webkit-user-select:none!important;-moz-user-select:none!important;user-select:none!important}.pe-none{pointer-events:none!important}.pe-auto{pointer-events:auto!important}.rounded{border-radius:.25rem!important}.rounded-0{border-radius:0!important}.rounded-1{border-radius:.2rem!important}.rounded-2{border-radius:.25rem!important}.rounded-3{border-radius:.3rem!important}.rounded-circle{border-radius:50%!important}.rounded-pill{border-radius:50rem!important}.rounded-top{border-top-left-radius:.25rem!important;border-top-right-radius:.25rem!important}.rounded-end{border-top-right-radius:.25rem!important;border-bottom-right-radius:.25rem!important}.rounded-bottom{border-bottom-right-radius:.25rem!important;border-bottom-left-radius:.25rem!important}.rounded-start{border-bottom-left-radius:.25rem!important;border-top-left-radius:.25rem!important}.visible{visibility:visible!important}.invisible{visibility:hidden!important}@media (min-width:576px){.float-sm-start{float:left!important}.float-sm-end{float:right!important}.float-sm-none{float:none!important}.d-sm-inline{display:inline!important}.d-sm-inline-block{display:inline-block!important}.d-sm-block{display:block!important}.d-sm-grid{display:grid!important}.d-sm-table{display:table!important}.d-sm-table-row{display:table-row!important}.d-sm-table-cell{display:table-cell!important}.d-sm-flex{display:flex!important}.d-sm-inline-flex{display:inline-flex!important}.d-sm-none{display:none!important}.flex-sm-fill{flex:1 1 auto!important}.flex-sm-row{flex-direction:row!important}.flex-sm-column{flex-direction:column!important}.flex-sm-row-reverse{flex-direction:row-reverse!important}.flex-sm-column-reverse{flex-direction:column-reverse!important}.flex-sm-grow-0{flex-grow:0!important}.flex-sm-grow-1{flex-grow:1!important}.flex-sm-shrink-0{flex-shrink:0!important}.flex-sm-shrink-1{flex-shrink:1!important}.flex-sm-wrap{flex-wrap:wrap!important}.flex-sm-nowrap{flex-wrap:nowrap!important}.flex-sm-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-sm-0{gap:0!important}.gap-sm-1{gap:.25rem!important}.gap-sm-2{gap:.5rem!important}.gap-sm-3{gap:1rem!important}.gap-sm-4{gap:1.5rem!important}.gap-sm-5{gap:3rem!important}.justify-content-sm-start{justify-content:flex-start!important}.justify-content-sm-end{justify-content:flex-end!important}.justify-content-sm-center{justify-content:center!important}.justify-content-sm-between{justify-content:space-between!important}.justify-content-sm-around{justify-content:space-around!important}.justify-content-sm-evenly{justify-content:space-evenly!important}.align-items-sm-start{align-items:flex-start!important}.align-items-sm-end{align-items:flex-end!important}.align-items-sm-center{align-items:center!important}.align-items-sm-baseline{align-items:baseline!important}.align-items-sm-stretch{align-items:stretch!important}.align-content-sm-start{align-content:flex-start!important}.align-content-sm-end{align-content:flex-end!important}.align-content-sm-center{align-content:center!important}.align-content-sm-between{align-content:space-between!important}.align-content-sm-around{align-content:space-around!important}.align-content-sm-stretch{align-content:stretch!important}.align-self-sm-auto{align-self:auto!important}.align-self-sm-start{align-self:flex-start!important}.align-self-sm-end{align-self:flex-end!important}.align-self-sm-center{align-self:center!important}.align-self-sm-baseline{align-self:baseline!important}.align-self-sm-stretch{align-self:stretch!important}.order-sm-first{order:-1!important}.order-sm-0{order:0!important}.order-sm-1{order:1!important}.order-sm-2{order:2!important}.order-sm-3{order:3!important}.order-sm-4{order:4!important}.order-sm-5{order:5!important}.order-sm-last{order:6!important}.m-sm-0{margin:0!important}.m-sm-1{margin:.25rem!important}.m-sm-2{margin:.5rem!important}.m-sm-3{margin:1rem!important}.m-sm-4{margin:1.5rem!important}.m-sm-5{margin:3rem!important}.m-sm-auto{margin:auto!important}.mx-sm-0{margin-right:0!important;margin-left:0!important}.mx-sm-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-sm-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-sm-3{margin-right:1rem!important;margin-left:1rem!important}.mx-sm-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-sm-5{margin-right:3rem!important;margin-left:3rem!important}.mx-sm-auto{margin-right:auto!important;margin-left:auto!important}.my-sm-0{margin-top:0!important;margin-bottom:0!important}.my-sm-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-sm-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-sm-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-sm-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-sm-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-sm-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-sm-0{margin-top:0!important}.mt-sm-1{margin-top:.25rem!important}.mt-sm-2{margin-top:.5rem!important}.mt-sm-3{margin-top:1rem!important}.mt-sm-4{margin-top:1.5rem!important}.mt-sm-5{margin-top:3rem!important}.mt-sm-auto{margin-top:auto!important}.me-sm-0{margin-right:0!important}.me-sm-1{margin-right:.25rem!important}.me-sm-2{margin-right:.5rem!important}.me-sm-3{margin-right:1rem!important}.me-sm-4{margin-right:1.5rem!important}.me-sm-5{margin-right:3rem!important}.me-sm-auto{margin-right:auto!important}.mb-sm-0{margin-bottom:0!important}.mb-sm-1{margin-bottom:.25rem!important}.mb-sm-2{margin-bottom:.5rem!important}.mb-sm-3{margin-bottom:1rem!important}.mb-sm-4{margin-bottom:1.5rem!important}.mb-sm-5{margin-bottom:3rem!important}.mb-sm-auto{margin-bottom:auto!important}.ms-sm-0{margin-left:0!important}.ms-sm-1{margin-left:.25rem!important}.ms-sm-2{margin-left:.5rem!important}.ms-sm-3{margin-left:1rem!important}.ms-sm-4{margin-left:1.5rem!important}.ms-sm-5{margin-left:3rem!important}.ms-sm-auto{margin-left:auto!important}.p-sm-0{padding:0!important}.p-sm-1{padding:.25rem!important}.p-sm-2{padding:.5rem!important}.p-sm-3{padding:1rem!important}.p-sm-4{padding:1.5rem!important}.p-sm-5{padding:3rem!important}.px-sm-0{padding-right:0!important;padding-left:0!important}.px-sm-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-sm-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-sm-3{padding-right:1rem!important;padding-left:1rem!important}.px-sm-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-sm-5{padding-right:3rem!important;padding-left:3rem!important}.py-sm-0{padding-top:0!important;padding-bottom:0!important}.py-sm-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-sm-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-sm-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-sm-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-sm-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-sm-0{padding-top:0!important}.pt-sm-1{padding-top:.25rem!important}.pt-sm-2{padding-top:.5rem!important}.pt-sm-3{padding-top:1rem!important}.pt-sm-4{padding-top:1.5rem!important}.pt-sm-5{padding-top:3rem!important}.pe-sm-0{padding-right:0!important}.pe-sm-1{padding-right:.25rem!important}.pe-sm-2{padding-right:.5rem!important}.pe-sm-3{padding-right:1rem!important}.pe-sm-4{padding-right:1.5rem!important}.pe-sm-5{padding-right:3rem!important}.pb-sm-0{padding-bottom:0!important}.pb-sm-1{padding-bottom:.25rem!important}.pb-sm-2{padding-bottom:.5rem!important}.pb-sm-3{padding-bottom:1rem!important}.pb-sm-4{padding-bottom:1.5rem!important}.pb-sm-5{padding-bottom:3rem!important}.ps-sm-0{padding-left:0!important}.ps-sm-1{padding-left:.25rem!important}.ps-sm-2{padding-left:.5rem!important}.ps-sm-3{padding-left:1rem!important}.ps-sm-4{padding-left:1.5rem!important}.ps-sm-5{padding-left:3rem!important}.text-sm-start{text-align:left!important}.text-sm-end{text-align:right!important}.text-sm-center{text-align:center!important}}@media (min-width:768px){.float-md-start{float:left!important}.float-md-end{float:right!important}.float-md-none{float:none!important}.d-md-inline{display:inline!important}.d-md-inline-block{display:inline-block!important}.d-md-block{display:block!important}.d-md-grid{display:grid!important}.d-md-table{display:table!important}.d-md-table-row{display:table-row!important}.d-md-table-cell{display:table-cell!important}.d-md-flex{display:flex!important}.d-md-inline-flex{display:inline-flex!important}.d-md-none{display:none!important}.flex-md-fill{flex:1 1 auto!important}.flex-md-row{flex-direction:row!important}.flex-md-column{flex-direction:column!important}.flex-md-row-reverse{flex-direction:row-reverse!important}.flex-md-column-reverse{flex-direction:column-reverse!important}.flex-md-grow-0{flex-grow:0!important}.flex-md-grow-1{flex-grow:1!important}.flex-md-shrink-0{flex-shrink:0!important}.flex-md-shrink-1{flex-shrink:1!important}.flex-md-wrap{flex-wrap:wrap!important}.flex-md-nowrap{flex-wrap:nowrap!important}.flex-md-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-md-0{gap:0!important}.gap-md-1{gap:.25rem!important}.gap-md-2{gap:.5rem!important}.gap-md-3{gap:1rem!important}.gap-md-4{gap:1.5rem!important}.gap-md-5{gap:3rem!important}.justify-content-md-start{justify-content:flex-start!important}.justify-content-md-end{justify-content:flex-end!important}.justify-content-md-center{justify-content:center!important}.justify-content-md-between{justify-content:space-between!important}.justify-content-md-around{justify-content:space-around!important}.justify-content-md-evenly{justify-content:space-evenly!important}.align-items-md-start{align-items:flex-start!important}.align-items-md-end{align-items:flex-end!important}.align-items-md-center{align-items:center!important}.align-items-md-baseline{align-items:baseline!important}.align-items-md-stretch{align-items:stretch!important}.align-content-md-start{align-content:flex-start!important}.align-content-md-end{align-content:flex-end!important}.align-content-md-center{align-content:center!important}.align-content-md-between{align-content:space-between!important}.align-content-md-around{align-content:space-around!important}.align-content-md-stretch{align-content:stretch!important}.align-self-md-auto{align-self:auto!important}.align-self-md-start{align-self:flex-start!important}.align-self-md-end{align-self:flex-end!important}.align-self-md-center{align-self:center!important}.align-self-md-baseline{align-self:baseline!important}.align-self-md-stretch{align-self:stretch!important}.order-md-first{order:-1!important}.order-md-0{order:0!important}.order-md-1{order:1!important}.order-md-2{order:2!important}.order-md-3{order:3!important}.order-md-4{order:4!important}.order-md-5{order:5!important}.order-md-last{order:6!important}.m-md-0{margin:0!important}.m-md-1{margin:.25rem!important}.m-md-2{margin:.5rem!important}.m-md-3{margin:1rem!important}.m-md-4{margin:1.5rem!important}.m-md-5{margin:3rem!important}.m-md-auto{margin:auto!important}.mx-md-0{margin-right:0!important;margin-left:0!important}.mx-md-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-md-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-md-3{margin-right:1rem!important;margin-left:1rem!important}.mx-md-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-md-5{margin-right:3rem!important;margin-left:3rem!important}.mx-md-auto{margin-right:auto!important;margin-left:auto!important}.my-md-0{margin-top:0!important;margin-bottom:0!important}.my-md-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-md-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-md-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-md-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-md-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-md-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-md-0{margin-top:0!important}.mt-md-1{margin-top:.25rem!important}.mt-md-2{margin-top:.5rem!important}.mt-md-3{margin-top:1rem!important}.mt-md-4{margin-top:1.5rem!important}.mt-md-5{margin-top:3rem!important}.mt-md-auto{margin-top:auto!important}.me-md-0{margin-right:0!important}.me-md-1{margin-right:.25rem!important}.me-md-2{margin-right:.5rem!important}.me-md-3{margin-right:1rem!important}.me-md-4{margin-right:1.5rem!important}.me-md-5{margin-right:3rem!important}.me-md-auto{margin-right:auto!important}.mb-md-0{margin-bottom:0!important}.mb-md-1{margin-bottom:.25rem!important}.mb-md-2{margin-bottom:.5rem!important}.mb-md-3{margin-bottom:1rem!important}.mb-md-4{margin-bottom:1.5rem!important}.mb-md-5{margin-bottom:3rem!important}.mb-md-auto{margin-bottom:auto!important}.ms-md-0{margin-left:0!important}.ms-md-1{margin-left:.25rem!important}.ms-md-2{margin-left:.5rem!important}.ms-md-3{margin-left:1rem!important}.ms-md-4{margin-left:1.5rem!important}.ms-md-5{margin-left:3rem!important}.ms-md-auto{margin-left:auto!important}.p-md-0{padding:0!important}.p-md-1{padding:.25rem!important}.p-md-2{padding:.5rem!important}.p-md-3{padding:1rem!important}.p-md-4{padding:1.5rem!important}.p-md-5{padding:3rem!important}.px-md-0{padding-right:0!important;padding-left:0!important}.px-md-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-md-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-md-3{padding-right:1rem!important;padding-left:1rem!important}.px-md-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-md-5{padding-right:3rem!important;padding-left:3rem!important}.py-md-0{padding-top:0!important;padding-bottom:0!important}.py-md-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-md-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-md-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-md-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-md-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-md-0{padding-top:0!important}.pt-md-1{padding-top:.25rem!important}.pt-md-2{padding-top:.5rem!important}.pt-md-3{padding-top:1rem!important}.pt-md-4{padding-top:1.5rem!important}.pt-md-5{padding-top:3rem!important}.pe-md-0{padding-right:0!important}.pe-md-1{padding-right:.25rem!important}.pe-md-2{padding-right:.5rem!important}.pe-md-3{padding-right:1rem!important}.pe-md-4{padding-right:1.5rem!important}.pe-md-5{padding-right:3rem!important}.pb-md-0{padding-bottom:0!important}.pb-md-1{padding-bottom:.25rem!important}.pb-md-2{padding-bottom:.5rem!important}.pb-md-3{padding-bottom:1rem!important}.pb-md-4{padding-bottom:1.5rem!important}.pb-md-5{padding-bottom:3rem!important}.ps-md-0{padding-left:0!important}.ps-md-1{padding-left:.25rem!important}.ps-md-2{padding-left:.5rem!important}.ps-md-3{padding-left:1rem!important}.ps-md-4{padding-left:1.5rem!important}.ps-md-5{padding-left:3rem!important}.text-md-start{text-align:left!important}.text-md-end{text-align:right!important}.text-md-center{text-align:center!important}}@media (min-width:992px){.float-lg-start{float:left!important}.float-lg-end{float:right!important}.float-lg-none{float:none!important}.d-lg-inline{display:inline!important}.d-lg-inline-block{display:inline-block!important}.d-lg-block{display:block!important}.d-lg-grid{display:grid!important}.d-lg-table{display:table!important}.d-lg-table-row{display:table-row!important}.d-lg-table-cell{display:table-cell!important}.d-lg-flex{display:flex!important}.d-lg-inline-flex{display:inline-flex!important}.d-lg-none{display:none!important}.flex-lg-fill{flex:1 1 auto!important}.flex-lg-row{flex-direction:row!important}.flex-lg-column{flex-direction:column!important}.flex-lg-row-reverse{flex-direction:row-reverse!important}.flex-lg-column-reverse{flex-direction:column-reverse!important}.flex-lg-grow-0{flex-grow:0!important}.flex-lg-grow-1{flex-grow:1!important}.flex-lg-shrink-0{flex-shrink:0!important}.flex-lg-shrink-1{flex-shrink:1!important}.flex-lg-wrap{flex-wrap:wrap!important}.flex-lg-nowrap{flex-wrap:nowrap!important}.flex-lg-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-lg-0{gap:0!important}.gap-lg-1{gap:.25rem!important}.gap-lg-2{gap:.5rem!important}.gap-lg-3{gap:1rem!important}.gap-lg-4{gap:1.5rem!important}.gap-lg-5{gap:3rem!important}.justify-content-lg-start{justify-content:flex-start!important}.justify-content-lg-end{justify-content:flex-end!important}.justify-content-lg-center{justify-content:center!important}.justify-content-lg-between{justify-content:space-between!important}.justify-content-lg-around{justify-content:space-around!important}.justify-content-lg-evenly{justify-content:space-evenly!important}.align-items-lg-start{align-items:flex-start!important}.align-items-lg-end{align-items:flex-end!important}.align-items-lg-center{align-items:center!important}.align-items-lg-baseline{align-items:baseline!important}.align-items-lg-stretch{align-items:stretch!important}.align-content-lg-start{align-content:flex-start!important}.align-content-lg-end{align-content:flex-end!important}.align-content-lg-center{align-content:center!important}.align-content-lg-between{align-content:space-between!important}.align-content-lg-around{align-content:space-around!important}.align-content-lg-stretch{align-content:stretch!important}.align-self-lg-auto{align-self:auto!important}.align-self-lg-start{align-self:flex-start!important}.align-self-lg-end{align-self:flex-end!important}.align-self-lg-center{align-self:center!important}.align-self-lg-baseline{align-self:baseline!important}.align-self-lg-stretch{align-self:stretch!important}.order-lg-first{order:-1!important}.order-lg-0{order:0!important}.order-lg-1{order:1!important}.order-lg-2{order:2!important}.order-lg-3{order:3!important}.order-lg-4{order:4!important}.order-lg-5{order:5!important}.order-lg-last{order:6!important}.m-lg-0{margin:0!important}.m-lg-1{margin:.25rem!important}.m-lg-2{margin:.5rem!important}.m-lg-3{margin:1rem!important}.m-lg-4{margin:1.5rem!important}.m-lg-5{margin:3rem!important}.m-lg-auto{margin:auto!important}.mx-lg-0{margin-right:0!important;margin-left:0!important}.mx-lg-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-lg-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-lg-3{margin-right:1rem!important;margin-left:1rem!important}.mx-lg-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-lg-5{margin-right:3rem!important;margin-left:3rem!important}.mx-lg-auto{margin-right:auto!important;margin-left:auto!important}.my-lg-0{margin-top:0!important;margin-bottom:0!important}.my-lg-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-lg-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-lg-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-lg-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-lg-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-lg-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-lg-0{margin-top:0!important}.mt-lg-1{margin-top:.25rem!important}.mt-lg-2{margin-top:.5rem!important}.mt-lg-3{margin-top:1rem!important}.mt-lg-4{margin-top:1.5rem!important}.mt-lg-5{margin-top:3rem!important}.mt-lg-auto{margin-top:auto!important}.me-lg-0{margin-right:0!important}.me-lg-1{margin-right:.25rem!important}.me-lg-2{margin-right:.5rem!important}.me-lg-3{margin-right:1rem!important}.me-lg-4{margin-right:1.5rem!important}.me-lg-5{margin-right:3rem!important}.me-lg-auto{margin-right:auto!important}.mb-lg-0{margin-bottom:0!important}.mb-lg-1{margin-bottom:.25rem!important}.mb-lg-2{margin-bottom:.5rem!important}.mb-lg-3{margin-bottom:1rem!important}.mb-lg-4{margin-bottom:1.5rem!important}.mb-lg-5{margin-bottom:3rem!important}.mb-lg-auto{margin-bottom:auto!important}.ms-lg-0{margin-left:0!important}.ms-lg-1{margin-left:.25rem!important}.ms-lg-2{margin-left:.5rem!important}.ms-lg-3{margin-left:1rem!important}.ms-lg-4{margin-left:1.5rem!important}.ms-lg-5{margin-left:3rem!important}.ms-lg-auto{margin-left:auto!important}.p-lg-0{padding:0!important}.p-lg-1{padding:.25rem!important}.p-lg-2{padding:.5rem!important}.p-lg-3{padding:1rem!important}.p-lg-4{padding:1.5rem!important}.p-lg-5{padding:3rem!important}.px-lg-0{padding-right:0!important;padding-left:0!important}.px-lg-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-lg-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-lg-3{padding-right:1rem!important;padding-left:1rem!important}.px-lg-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-lg-5{padding-right:3rem!important;padding-left:3rem!important}.py-lg-0{padding-top:0!important;padding-bottom:0!important}.py-lg-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-lg-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-lg-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-lg-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-lg-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-lg-0{padding-top:0!important}.pt-lg-1{padding-top:.25rem!important}.pt-lg-2{padding-top:.5rem!important}.pt-lg-3{padding-top:1rem!important}.pt-lg-4{padding-top:1.5rem!important}.pt-lg-5{padding-top:3rem!important}.pe-lg-0{padding-right:0!important}.pe-lg-1{padding-right:.25rem!important}.pe-lg-2{padding-right:.5rem!important}.pe-lg-3{padding-right:1rem!important}.pe-lg-4{padding-right:1.5rem!important}.pe-lg-5{padding-right:3rem!important}.pb-lg-0{padding-bottom:0!important}.pb-lg-1{padding-bottom:.25rem!important}.pb-lg-2{padding-bottom:.5rem!important}.pb-lg-3{padding-bottom:1rem!important}.pb-lg-4{padding-bottom:1.5rem!important}.pb-lg-5{padding-bottom:3rem!important}.ps-lg-0{padding-left:0!important}.ps-lg-1{padding-left:.25rem!important}.ps-lg-2{padding-left:.5rem!important}.ps-lg-3{padding-left:1rem!important}.ps-lg-4{padding-left:1.5rem!important}.ps-lg-5{padding-left:3rem!important}.text-lg-start{text-align:left!important}.text-lg-end{text-align:right!important}.text-lg-center{text-align:center!important}}@media (min-width:1200px){.float-xl-start{float:left!important}.float-xl-end{float:right!important}.float-xl-none{float:none!important}.d-xl-inline{display:inline!important}.d-xl-inline-block{display:inline-block!important}.d-xl-block{display:block!important}.d-xl-grid{display:grid!important}.d-xl-table{display:table!important}.d-xl-table-row{display:table-row!important}.d-xl-table-cell{display:table-cell!important}.d-xl-flex{display:flex!important}.d-xl-inline-flex{display:inline-flex!important}.d-xl-none{display:none!important}.flex-xl-fill{flex:1 1 auto!important}.flex-xl-row{flex-direction:row!important}.flex-xl-column{flex-direction:column!important}.flex-xl-row-reverse{flex-direction:row-reverse!important}.flex-xl-column-reverse{flex-direction:column-reverse!important}.flex-xl-grow-0{flex-grow:0!important}.flex-xl-grow-1{flex-grow:1!important}.flex-xl-shrink-0{flex-shrink:0!important}.flex-xl-shrink-1{flex-shrink:1!important}.flex-xl-wrap{flex-wrap:wrap!important}.flex-xl-nowrap{flex-wrap:nowrap!important}.flex-xl-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-xl-0{gap:0!important}.gap-xl-1{gap:.25rem!important}.gap-xl-2{gap:.5rem!important}.gap-xl-3{gap:1rem!important}.gap-xl-4{gap:1.5rem!important}.gap-xl-5{gap:3rem!important}.justify-content-xl-start{justify-content:flex-start!important}.justify-content-xl-end{justify-content:flex-end!important}.justify-content-xl-center{justify-content:center!important}.justify-content-xl-between{justify-content:space-between!important}.justify-content-xl-around{justify-content:space-around!important}.justify-content-xl-evenly{justify-content:space-evenly!important}.align-items-xl-start{align-items:flex-start!important}.align-items-xl-end{align-items:flex-end!important}.align-items-xl-center{align-items:center!important}.align-items-xl-baseline{align-items:baseline!important}.align-items-xl-stretch{align-items:stretch!important}.align-content-xl-start{align-content:flex-start!important}.align-content-xl-end{align-content:flex-end!important}.align-content-xl-center{align-content:center!important}.align-content-xl-between{align-content:space-between!important}.align-content-xl-around{align-content:space-around!important}.align-content-xl-stretch{align-content:stretch!important}.align-self-xl-auto{align-self:auto!important}.align-self-xl-start{align-self:flex-start!important}.align-self-xl-end{align-self:flex-end!important}.align-self-xl-center{align-self:center!important}.align-self-xl-baseline{align-self:baseline!important}.align-self-xl-stretch{align-self:stretch!important}.order-xl-first{order:-1!important}.order-xl-0{order:0!important}.order-xl-1{order:1!important}.order-xl-2{order:2!important}.order-xl-3{order:3!important}.order-xl-4{order:4!important}.order-xl-5{order:5!important}.order-xl-last{order:6!important}.m-xl-0{margin:0!important}.m-xl-1{margin:.25rem!important}.m-xl-2{margin:.5rem!important}.m-xl-3{margin:1rem!important}.m-xl-4{margin:1.5rem!important}.m-xl-5{margin:3rem!important}.m-xl-auto{margin:auto!important}.mx-xl-0{margin-right:0!important;margin-left:0!important}.mx-xl-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-xl-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-xl-3{margin-right:1rem!important;margin-left:1rem!important}.mx-xl-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-xl-5{margin-right:3rem!important;margin-left:3rem!important}.mx-xl-auto{margin-right:auto!important;margin-left:auto!important}.my-xl-0{margin-top:0!important;margin-bottom:0!important}.my-xl-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-xl-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-xl-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-xl-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-xl-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-xl-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-xl-0{margin-top:0!important}.mt-xl-1{margin-top:.25rem!important}.mt-xl-2{margin-top:.5rem!important}.mt-xl-3{margin-top:1rem!important}.mt-xl-4{margin-top:1.5rem!important}.mt-xl-5{margin-top:3rem!important}.mt-xl-auto{margin-top:auto!important}.me-xl-0{margin-right:0!important}.me-xl-1{margin-right:.25rem!important}.me-xl-2{margin-right:.5rem!important}.me-xl-3{margin-right:1rem!important}.me-xl-4{margin-right:1.5rem!important}.me-xl-5{margin-right:3rem!important}.me-xl-auto{margin-right:auto!important}.mb-xl-0{margin-bottom:0!important}.mb-xl-1{margin-bottom:.25rem!important}.mb-xl-2{margin-bottom:.5rem!important}.mb-xl-3{margin-bottom:1rem!important}.mb-xl-4{margin-bottom:1.5rem!important}.mb-xl-5{margin-bottom:3rem!important}.mb-xl-auto{margin-bottom:auto!important}.ms-xl-0{margin-left:0!important}.ms-xl-1{margin-left:.25rem!important}.ms-xl-2{margin-left:.5rem!important}.ms-xl-3{margin-left:1rem!important}.ms-xl-4{margin-left:1.5rem!important}.ms-xl-5{margin-left:3rem!important}.ms-xl-auto{margin-left:auto!important}.p-xl-0{padding:0!important}.p-xl-1{padding:.25rem!important}.p-xl-2{padding:.5rem!important}.p-xl-3{padding:1rem!important}.p-xl-4{padding:1.5rem!important}.p-xl-5{padding:3rem!important}.px-xl-0{padding-right:0!important;padding-left:0!important}.px-xl-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-xl-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-xl-3{padding-right:1rem!important;padding-left:1rem!important}.px-xl-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-xl-5{padding-right:3rem!important;padding-left:3rem!important}.py-xl-0{padding-top:0!important;padding-bottom:0!important}.py-xl-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-xl-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-xl-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-xl-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-xl-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-xl-0{padding-top:0!important}.pt-xl-1{padding-top:.25rem!important}.pt-xl-2{padding-top:.5rem!important}.pt-xl-3{padding-top:1rem!important}.pt-xl-4{padding-top:1.5rem!important}.pt-xl-5{padding-top:3rem!important}.pe-xl-0{padding-right:0!important}.pe-xl-1{padding-right:.25rem!important}.pe-xl-2{padding-right:.5rem!important}.pe-xl-3{padding-right:1rem!important}.pe-xl-4{padding-right:1.5rem!important}.pe-xl-5{padding-right:3rem!important}.pb-xl-0{padding-bottom:0!important}.pb-xl-1{padding-bottom:.25rem!important}.pb-xl-2{padding-bottom:.5rem!important}.pb-xl-3{padding-bottom:1rem!important}.pb-xl-4{padding-bottom:1.5rem!important}.pb-xl-5{padding-bottom:3rem!important}.ps-xl-0{padding-left:0!important}.ps-xl-1{padding-left:.25rem!important}.ps-xl-2{padding-left:.5rem!important}.ps-xl-3{padding-left:1rem!important}.ps-xl-4{padding-left:1.5rem!important}.ps-xl-5{padding-left:3rem!important}.text-xl-start{text-align:left!important}.text-xl-end{text-align:right!important}.text-xl-center{text-align:center!important}}@media (min-width:1400px){.float-xxl-start{float:left!important}.float-xxl-end{float:right!important}.float-xxl-none{float:none!important}.d-xxl-inline{display:inline!important}.d-xxl-inline-block{display:inline-block!important}.d-xxl-block{display:block!important}.d-xxl-grid{display:grid!important}.d-xxl-table{display:table!important}.d-xxl-table-row{display:table-row!important}.d-xxl-table-cell{display:table-cell!important}.d-xxl-flex{display:flex!important}.d-xxl-inline-flex{display:inline-flex!important}.d-xxl-none{display:none!important}.flex-xxl-fill{flex:1 1 auto!important}.flex-xxl-row{flex-direction:row!important}.flex-xxl-column{flex-direction:column!important}.flex-xxl-row-reverse{flex-direction:row-reverse!important}.flex-xxl-column-reverse{flex-direction:column-reverse!important}.flex-xxl-grow-0{flex-grow:0!important}.flex-xxl-grow-1{flex-grow:1!important}.flex-xxl-shrink-0{flex-shrink:0!important}.flex-xxl-shrink-1{flex-shrink:1!important}.flex-xxl-wrap{flex-wrap:wrap!important}.flex-xxl-nowrap{flex-wrap:nowrap!important}.flex-xxl-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-xxl-0{gap:0!important}.gap-xxl-1{gap:.25rem!important}.gap-xxl-2{gap:.5rem!important}.gap-xxl-3{gap:1rem!important}.gap-xxl-4{gap:1.5rem!important}.gap-xxl-5{gap:3rem!important}.justify-content-xxl-start{justify-content:flex-start!important}.justify-content-xxl-end{justify-content:flex-end!important}.justify-content-xxl-center{justify-content:center!important}.justify-content-xxl-between{justify-content:space-between!important}.justify-content-xxl-around{justify-content:space-around!important}.justify-content-xxl-evenly{justify-content:space-evenly!important}.align-items-xxl-start{align-items:flex-start!important}.align-items-xxl-end{align-items:flex-end!important}.align-items-xxl-center{align-items:center!important}.align-items-xxl-baseline{align-items:baseline!important}.align-items-xxl-stretch{align-items:stretch!important}.align-content-xxl-start{align-content:flex-start!important}.align-content-xxl-end{align-content:flex-end!important}.align-content-xxl-center{align-content:center!important}.align-content-xxl-between{align-content:space-between!important}.align-content-xxl-around{align-content:space-around!important}.align-content-xxl-stretch{align-content:stretch!important}.align-self-xxl-auto{align-self:auto!important}.align-self-xxl-start{align-self:flex-start!important}.align-self-xxl-end{align-self:flex-end!important}.align-self-xxl-center{align-self:center!important}.align-self-xxl-baseline{align-self:baseline!important}.align-self-xxl-stretch{align-self:stretch!important}.order-xxl-first{order:-1!important}.order-xxl-0{order:0!important}.order-xxl-1{order:1!important}.order-xxl-2{order:2!important}.order-xxl-3{order:3!important}.order-xxl-4{order:4!important}.order-xxl-5{order:5!important}.order-xxl-last{order:6!important}.m-xxl-0{margin:0!important}.m-xxl-1{margin:.25rem!important}.m-xxl-2{margin:.5rem!important}.m-xxl-3{margin:1rem!important}.m-xxl-4{margin:1.5rem!important}.m-xxl-5{margin:3rem!important}.m-xxl-auto{margin:auto!important}.mx-xxl-0{margin-right:0!important;margin-left:0!important}.mx-xxl-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-xxl-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-xxl-3{margin-right:1rem!important;margin-left:1rem!important}.mx-xxl-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-xxl-5{margin-right:3rem!important;margin-left:3rem!important}.mx-xxl-auto{margin-right:auto!important;margin-left:auto!important}.my-xxl-0{margin-top:0!important;margin-bottom:0!important}.my-xxl-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-xxl-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-xxl-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-xxl-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-xxl-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-xxl-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-xxl-0{margin-top:0!important}.mt-xxl-1{margin-top:.25rem!important}.mt-xxl-2{margin-top:.5rem!important}.mt-xxl-3{margin-top:1rem!important}.mt-xxl-4{margin-top:1.5rem!important}.mt-xxl-5{margin-top:3rem!important}.mt-xxl-auto{margin-top:auto!important}.me-xxl-0{margin-right:0!important}.me-xxl-1{margin-right:.25rem!important}.me-xxl-2{margin-right:.5rem!important}.me-xxl-3{margin-right:1rem!important}.me-xxl-4{margin-right:1.5rem!important}.me-xxl-5{margin-right:3rem!important}.me-xxl-auto{margin-right:auto!important}.mb-xxl-0{margin-bottom:0!important}.mb-xxl-1{margin-bottom:.25rem!important}.mb-xxl-2{margin-bottom:.5rem!important}.mb-xxl-3{margin-bottom:1rem!important}.mb-xxl-4{margin-bottom:1.5rem!important}.mb-xxl-5{margin-bottom:3rem!important}.mb-xxl-auto{margin-bottom:auto!important}.ms-xxl-0{margin-left:0!important}.ms-xxl-1{margin-left:.25rem!important}.ms-xxl-2{margin-left:.5rem!important}.ms-xxl-3{margin-left:1rem!important}.ms-xxl-4{margin-left:1.5rem!important}.ms-xxl-5{margin-left:3rem!important}.ms-xxl-auto{margin-left:auto!important}.p-xxl-0{padding:0!important}.p-xxl-1{padding:.25rem!important}.p-xxl-2{padding:.5rem!important}.p-xxl-3{padding:1rem!important}.p-xxl-4{padding:1.5rem!important}.p-xxl-5{padding:3rem!important}.px-xxl-0{padding-right:0!important;padding-left:0!important}.px-xxl-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-xxl-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-xxl-3{padding-right:1rem!important;padding-left:1rem!important}.px-xxl-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-xxl-5{padding-right:3rem!important;padding-left:3rem!important}.py-xxl-0{padding-top:0!important;padding-bottom:0!important}.py-xxl-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-xxl-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-xxl-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-xxl-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-xxl-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-xxl-0{padding-top:0!important}.pt-xxl-1{padding-top:.25rem!important}.pt-xxl-2{padding-top:.5rem!important}.pt-xxl-3{padding-top:1rem!important}.pt-xxl-4{padding-top:1.5rem!important}.pt-xxl-5{padding-top:3rem!important}.pe-xxl-0{padding-right:0!important}.pe-xxl-1{padding-right:.25rem!important}.pe-xxl-2{padding-right:.5rem!important}.pe-xxl-3{padding-right:1rem!important}.pe-xxl-4{padding-right:1.5rem!important}.pe-xxl-5{padding-right:3rem!important}.pb-xxl-0{padding-bottom:0!important}.pb-xxl-1{padding-bottom:.25rem!important}.pb-xxl-2{padding-bottom:.5rem!important}.pb-xxl-3{padding-bottom:1rem!important}.pb-xxl-4{padding-bottom:1.5rem!important}.pb-xxl-5{padding-bottom:3rem!important}.ps-xxl-0{padding-left:0!important}.ps-xxl-1{padding-left:.25rem!important}.ps-xxl-2{padding-left:.5rem!important}.ps-xxl-3{padding-left:1rem!important}.ps-xxl-4{padding-left:1.5rem!important}.ps-xxl-5{padding-left:3rem!important}.text-xxl-start{text-align:left!important}.text-xxl-end{text-align:right!important}.text-xxl-center{text-align:center!important}}@media (min-width:1200px){.fs-1{font-size:2.5rem!important}.fs-2{font-size:2rem!important}.fs-3{font-size:1.75rem!important}.fs-4{font-size:1.5rem!important}}@media print{.d-print-inline{display:inline!important}.d-print-inline-block{display:inline-block!important}.d-print-block{display:block!important}.d-print-grid{display:grid!important}.d-print-table{display:table!important}.d-print-table-row{display:table-row!important}.d-print-table-cell{display:table-cell!important}.d-print-flex{display:flex!important}.d-print-inline-flex{display:inline-flex!important}.d-print-none{display:none!important}}
			/*# sourceMappingURL=bootstrap.min.css.map */
		</style>
		<style type="text/css">
			/**
			  * bootstrap-table - An extended table to integration with some of the most widely used CSS frameworks. (Supports Bootstrap, Semantic UI, Bulma, Material Design, Foundation)
			  *
			  * @version v1.21.0
			  * @homepage https://bootstrap-table.com
			  * @author wenzhixin <wenzhixin2010@gmail.com> (http://wenzhixin.net.cn/)
			  * @license MIT
			  */

			.bootstrap-table .fixed-table-toolbar::after{content:"";display:block;clear:both}.bootstrap-table .fixed-table-toolbar .bs-bars,.bootstrap-table .fixed-table-toolbar .columns,.bootstrap-table .fixed-table-toolbar .search{position:relative;margin-top:10px;margin-bottom:10px}.bootstrap-table .fixed-table-toolbar .columns .btn-group>.btn-group{display:inline-block;margin-left:-1px!important}.bootstrap-table .fixed-table-toolbar .columns .btn-group>.btn-group>.btn{border-radius:0}.bootstrap-table .fixed-table-toolbar .columns .btn-group>.btn-group:first-child>.btn{border-top-left-radius:4px;border-bottom-left-radius:4px}.bootstrap-table .fixed-table-toolbar .columns .btn-group>.btn-group:last-child>.btn{border-top-right-radius:4px;border-bottom-right-radius:4px}.bootstrap-table .fixed-table-toolbar .columns .dropdown-menu{text-align:left;max-height:300px;overflow:auto;-ms-overflow-style:scrollbar;z-index:1001}.bootstrap-table .fixed-table-toolbar .columns label{display:block;padding:3px 20px;clear:both;font-weight:400;line-height:1.4286}.bootstrap-table .fixed-table-toolbar .columns-left{margin-right:5px}.bootstrap-table .fixed-table-toolbar .columns-right{margin-left:5px}.bootstrap-table .fixed-table-toolbar .pull-right .dropdown-menu{right:0;left:auto}.bootstrap-table .fixed-table-container{position:relative;clear:both}.bootstrap-table .fixed-table-container .table{width:100%;margin-bottom:0!important}.bootstrap-table .fixed-table-container .table td,.bootstrap-table .fixed-table-container .table th{vertical-align:middle;box-sizing:border-box}.bootstrap-table .fixed-table-container .table thead th{vertical-align:bottom;padding:0;margin:0}.bootstrap-table .fixed-table-container .table thead th:focus{outline:0 solid transparent}.bootstrap-table .fixed-table-container .table thead th.detail{width:30px}.bootstrap-table .fixed-table-container .table thead th .th-inner{padding:.75rem;vertical-align:bottom;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.bootstrap-table .fixed-table-container .table thead th .sortable{cursor:pointer;background-position:right;background-repeat:no-repeat;padding-right:30px!important}.bootstrap-table .fixed-table-container .table thead th .sortable.sortable-center{padding-left:20px!important;padding-right:20px!important}.bootstrap-table .fixed-table-container .table thead th .both{background-image:url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABMAAAATCAQAAADYWf5HAAAAkElEQVQoz7X QMQ5AQBCF4dWQSJxC5wwax1Cq1e7BAdxD5SL+Tq/QCM1oNiJidwox0355mXnG/DrEtIQ6azioNZQxI0ykPhTQIwhCR+BmBYtlK7kLJYwWCcJA9M4qdrZrd8pPjZWPtOqdRQy320YSV17OatFC4euts6z39GYMKRPCTKY9UnPQ6P+GtMRfGtPnBCiqhAeJPmkqAAAAAElFTkSuQmCC")}.bootstrap-table .fixed-table-container .table thead th .asc{background-image:url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABMAAAATCAYAAAByUDbMAAAAZ0lEQVQ4y2NgGLKgquEuFxBPAGI2ahhWCsS/gDibUoO0gPgxEP8H4ttArEyuQYxAPBdqEAxPBImTY5gjEL9DM+wTENuQahAvEO9DMwiGdwAxOymGJQLxTyD+jgWDxCMZRsEoGAVoAADeemwtPcZI2wAAAABJRU5ErkJggg==")}.bootstrap-table .fixed-table-container .table thead th .desc{background-image:url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABMAAAATCAYAAAByUDbMAAAAZUlEQVQ4y2NgGAWjYBSggaqGu5FA/BOIv2PBIPFEUgxjB+IdQPwfC94HxLykus4GiD+hGfQOiB3J8SojEE9EM2wuSJzcsFMG4ttQgx4DsRalkZENxL+AuJQaMcsGxBOAmGvopk8AVz1sLZgg0bsAAAAASUVORK5CYII= ")}.bootstrap-table .fixed-table-container .table tbody tr.selected td{background-color:rgba(0,0,0,.075)}.bootstrap-table .fixed-table-container .table tbody tr.no-records-found td{text-align:center}.bootstrap-table .fixed-table-container .table tbody tr .card-view{display:flex}.bootstrap-table .fixed-table-container .table tbody tr .card-view .card-view-title{font-weight:700;display:inline-block;min-width:30%;width:auto!important;text-align:left!important}.bootstrap-table .fixed-table-container .table tbody tr .card-view .card-view-value{width:100%!important;text-align:left!important}.bootstrap-table .fixed-table-container .table .bs-checkbox{text-align:center}.bootstrap-table .fixed-table-container .table .bs-checkbox label{margin-bottom:0}.bootstrap-table .fixed-table-container .table .bs-checkbox label input[type=checkbox],.bootstrap-table .fixed-table-container .table .bs-checkbox label input[type=radio]{margin:0 auto!important}.bootstrap-table .fixed-table-container .table.table-sm .th-inner{padding:.3rem}.bootstrap-table .fixed-table-container.fixed-height:not(.has-footer){border-bottom:1px solid #dee2e6}.bootstrap-table .fixed-table-container.fixed-height.has-card-view{border-top:1px solid #dee2e6;border-bottom:1px solid #dee2e6}.bootstrap-table .fixed-table-container.fixed-height .fixed-table-border{border-left:1px solid #dee2e6;border-right:1px solid #dee2e6}.bootstrap-table .fixed-table-container.fixed-height .table thead th{border-bottom:1px solid #dee2e6}.bootstrap-table .fixed-table-container.fixed-height .table-dark thead th{border-bottom:1px solid #32383e}.bootstrap-table .fixed-table-container .fixed-table-header{overflow:hidden}.bootstrap-table .fixed-table-container .fixed-table-body{overflow-x:auto;overflow-y:auto;height:100%}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading{align-items:center;background:#fff;display:flex;justify-content:center;position:absolute;bottom:0;width:100%;max-width:100%;z-index:1000;transition:visibility 0s,opacity .15s ease-in-out;opacity:0;visibility:hidden}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading.open{visibility:visible;opacity:1}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap{align-items:baseline;display:flex;justify-content:center}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .loading-text{margin-right:6px}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-wrap{align-items:center;display:flex;justify-content:center}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-dot,.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-wrap::after,.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-wrap::before{content:"";animation-duration:1.5s;animation-iteration-count:infinite;animation-name:loading;background:#212529;border-radius:50%;display:block;height:5px;margin:0 4px;opacity:0;width:5px}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-dot{animation-delay:.3s}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-wrap::after{animation-delay:.6s}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading.table-dark{background:#212529}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading.table-dark .animation-dot,.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading.table-dark .animation-wrap::after,.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading.table-dark .animation-wrap::before{background:#fff}.bootstrap-table .fixed-table-container .fixed-table-footer{overflow:hidden}.bootstrap-table .fixed-table-pagination::after{content:"";display:block;clear:both}.bootstrap-table .fixed-table-pagination>.pagination,.bootstrap-table .fixed-table-pagination>.pagination-detail{margin-top:10px;margin-bottom:10px}.bootstrap-table .fixed-table-pagination>.pagination-detail .pagination-info{line-height:34px;margin-right:5px}.bootstrap-table .fixed-table-pagination>.pagination-detail .page-list{display:inline-block}.bootstrap-table .fixed-table-pagination>.pagination-detail .page-list .btn-group{position:relative;display:inline-block;vertical-align:middle}.bootstrap-table .fixed-table-pagination>.pagination-detail .page-list .btn-group .dropdown-menu{margin-bottom:0}.bootstrap-table .fixed-table-pagination>.pagination ul.pagination{margin:0}.bootstrap-table .fixed-table-pagination>.pagination ul.pagination li.page-intermediate a{color:#c8c8c8}.bootstrap-table .fixed-table-pagination>.pagination ul.pagination li.page-intermediate a::before{content:"\2B05"}.bootstrap-table .fixed-table-pagination>.pagination ul.pagination li.page-intermediate a::after{content:"\27A1"}.bootstrap-table .fixed-table-pagination>.pagination ul.pagination li.disabled a{pointer-events:none;cursor:default}.bootstrap-table.fullscreen{position:fixed;top:0;left:0;z-index:1050;width:100%!important;background:#fff;height:calc(100vh);overflow-y:scroll}.bootstrap-table.bootstrap4 .pagination-lg .page-link,.bootstrap-table.bootstrap5 .pagination-lg .page-link{padding:.5rem 1rem}.bootstrap-table.bootstrap5 .float-left{float:left}.bootstrap-table.bootstrap5 .float-right{float:right}div.fixed-table-scroll-inner{width:100%;height:200px}div.fixed-table-scroll-outer{top:0;left:0;visibility:hidden;width:200px;height:150px;overflow:hidden}@keyframes loading{0%{opacity:0}50%{opacity:1}to{opacity:0}}
		</style>
		<title>_ReportTitle_</title>
	</head>
	<body>
		<div class="container theme-showcase" role="main">
			<div class="p-5 mb-4 bg-light rounded-3 d-print-block">
				<h2 class="display-5 fw-bold d-print-block">_ReportTitle_</h2>
				<p>_ReportDescription_</p>
			</div>_ReportBody_
		</div>_ReportScript_
	</body>
</html>
"@
}
function Get-JavaScript {
    @'
		<script>
			//src="https://code.jquery.com/jquery-3.6.1.min.js" integrity="sha256-o88AwQnZB+VDvE9tvIXrMQaPlFFSUTR+nldQm1LuPXQ=" crossorigin="anonymous"
			/*! jQuery v3.6.1 | (c) OpenJS Foundation and other contributors | jquery.org/license */
			!function(e,t){"use strict";"object"==typeof module&&"object"==typeof module.exports?module.exports=e.document?t(e,!0):function(e){if(!e.document)throw new Error("jQuery requires a window with a document");return t(e)}:t(e)}("undefined"!=typeof window?window:this,function(C,e){"use strict";var t=[],r=Object.getPrototypeOf,s=t.slice,g=t.flat?function(e){return t.flat.call(e)}:function(e){return t.concat.apply([],e)},u=t.push,i=t.indexOf,n={},o=n.toString,y=n.hasOwnProperty,a=y.toString,l=a.call(Object),v={},m=function(e){return"function"==typeof e&&"number"!=typeof e.nodeType&&"function"!=typeof e.item},x=function(e){return null!=e&&e===e.window},E=C.document,c={type:!0,src:!0,nonce:!0,noModule:!0};function b(e,t,n){var r,i,o=(n=n||E).createElement("script");if(o.text=e,t)for(r in c)(i=t[r]||t.getAttribute&&t.getAttribute(r))&&o.setAttribute(r,i);n.head.appendChild(o).parentNode.removeChild(o)}function w(e){return null==e?e+"":"object"==typeof e||"function"==typeof e?n[o.call(e)]||"object":typeof e}var f="3.6.1",S=function(e,t){return new S.fn.init(e,t)};function p(e){var t=!!e&&"length"in e&&e.length,n=w(e);return!m(e)&&!x(e)&&("array"===n||0===t||"number"==typeof t&&0<t&&t-1 in e)}S.fn=S.prototype={jquery:f,constructor:S,length:0,toArray:function(){return s.call(this)},get:function(e){return null==e?s.call(this):e<0?this[e+this.length]:this[e]},pushStack:function(e){var t=S.merge(this.constructor(),e);return t.prevObject=this,t},each:function(e){return S.each(this,e)},map:function(n){return this.pushStack(S.map(this,function(e,t){return n.call(e,t,e)}))},slice:function(){return this.pushStack(s.apply(this,arguments))},first:function(){return this.eq(0)},last:function(){return this.eq(-1)},even:function(){return this.pushStack(S.grep(this,function(e,t){return(t+1)%2}))},odd:function(){return this.pushStack(S.grep(this,function(e,t){return t%2}))},eq:function(e){var t=this.length,n=+e+(e<0?t:0);return this.pushStack(0<=n&&n<t?[this[n]]:[])},end:function(){return this.prevObject||this.constructor()},push:u,sort:t.sort,splice:t.splice},S.extend=S.fn.extend=function(){var e,t,n,r,i,o,a=arguments[0]||{},s=1,u=arguments.length,l=!1;for("boolean"==typeof a&&(l=a,a=arguments[s]||{},s++),"object"==typeof a||m(a)||(a={}),s===u&&(a=this,s--);s<u;s++)if(null!=(e=arguments[s]))for(t in e)r=e[t],"__proto__"!==t&&a!==r&&(l&&r&&(S.isPlainObject(r)||(i=Array.isArray(r)))?(n=a[t],o=i&&!Array.isArray(n)?[]:i||S.isPlainObject(n)?n:{},i=!1,a[t]=S.extend(l,o,r)):void 0!==r&&(a[t]=r));return a},S.extend({expando:"jQuery"+(f+Math.random()).replace(/\D/g,""),isReady:!0,error:function(e){throw new Error(e)},noop:function(){},isPlainObject:function(e){var t,n;return!(!e||"[object Object]"!==o.call(e))&&(!(t=r(e))||"function"==typeof(n=y.call(t,"constructor")&&t.constructor)&&a.call(n)===l)},isEmptyObject:function(e){var t;for(t in e)return!1;return!0},globalEval:function(e,t,n){b(e,{nonce:t&&t.nonce},n)},each:function(e,t){var n,r=0;if(p(e)){for(n=e.length;r<n;r++)if(!1===t.call(e[r],r,e[r]))break}else for(r in e)if(!1===t.call(e[r],r,e[r]))break;return e},makeArray:function(e,t){var n=t||[];return null!=e&&(p(Object(e))?S.merge(n,"string"==typeof e?[e]:e):u.call(n,e)),n},inArray:function(e,t,n){return null==t?-1:i.call(t,e,n)},merge:function(e,t){for(var n=+t.length,r=0,i=e.length;r<n;r++)e[i++]=t[r];return e.length=i,e},grep:function(e,t,n){for(var r=[],i=0,o=e.length,a=!n;i<o;i++)!t(e[i],i)!==a&&r.push(e[i]);return r},map:function(e,t,n){var r,i,o=0,a=[];if(p(e))for(r=e.length;o<r;o++)null!=(i=t(e[o],o,n))&&a.push(i);else for(o in e)null!=(i=t(e[o],o,n))&&a.push(i);return g(a)},guid:1,support:v}),"function"==typeof Symbol&&(S.fn[Symbol.iterator]=t[Symbol.iterator]),S.each("Boolean Number String Function Array Date RegExp Object Error Symbol".split(" "),function(e,t){n["[object "+t+"]"]=t.toLowerCase()});var d=function(n){var e,d,b,o,i,h,f,g,w,u,l,T,C,a,E,y,s,c,v,S="sizzle"+1*new Date,p=n.document,k=0,r=0,m=ue(),x=ue(),A=ue(),N=ue(),j=function(e,t){return e===t&&(l=!0),0},D={}.hasOwnProperty,t=[],q=t.pop,L=t.push,H=t.push,O=t.slice,P=function(e,t){for(var n=0,r=e.length;n<r;n++)if(e[n]===t)return n;return-1},R="checked|selected|async|autofocus|autoplay|controls|defer|disabled|hidden|ismap|loop|multiple|open|readonly|required|scoped",M="[\\x20\\t\\r\\n\\f]",I="(?:\\\\[\\da-fA-F]{1,6}"+M+"?|\\\\[^\\r\\n\\f]|[\\w-]|[^\0-\\x7f])+",W="\\["+M+"*("+I+")(?:"+M+"*([*^$|!~]?=)"+M+"*(?:'((?:\\\\.|[^\\\\'])*)'|\"((?:\\\\.|[^\\\\\"])*)\"|("+I+"))|)"+M+"*\\]",F=":("+I+")(?:\\((('((?:\\\\.|[^\\\\'])*)'|\"((?:\\\\.|[^\\\\\"])*)\")|((?:\\\\.|[^\\\\()[\\]]|"+W+")*)|.*)\\)|)",$=new RegExp(M+"+","g"),B=new RegExp("^"+M+"+|((?:^|[^\\\\])(?:\\\\.)*)"+M+"+$","g"),_=new RegExp("^"+M+"*,"+M+"*"),z=new RegExp("^"+M+"*([>+~]|"+M+")"+M+"*"),U=new RegExp(M+"|>"),X=new RegExp(F),V=new RegExp("^"+I+"$"),G={ID:new RegExp("^#("+I+")"),CLASS:new RegExp("^\\.("+I+")"),TAG:new RegExp("^("+I+"|[*])"),ATTR:new RegExp("^"+W),PSEUDO:new RegExp("^"+F),CHILD:new RegExp("^:(only|first|last|nth|nth-last)-(child|of-type)(?:\\("+M+"*(even|odd|(([+-]|)(\\d*)n|)"+M+"*(?:([+-]|)"+M+"*(\\d+)|))"+M+"*\\)|)","i"),bool:new RegExp("^(?:"+R+")$","i"),needsContext:new RegExp("^"+M+"*[>+~]|:(even|odd|eq|gt|lt|nth|first|last)(?:\\("+M+"*((?:-\\d)?\\d*)"+M+"*\\)|)(?=[^-]|$)","i")},Y=/HTML$/i,Q=/^(?:input|select|textarea|button)$/i,J=/^h\d$/i,K=/^[^{]+\{\s*\[native \w/,Z=/^(?:#([\w-]+)|(\w+)|\.([\w-]+))$/,ee=/[+~]/,te=new RegExp("\\\\[\\da-fA-F]{1,6}"+M+"?|\\\\([^\\r\\n\\f])","g"),ne=function(e,t){var n="0x"+e.slice(1)-65536;return t||(n<0?String.fromCharCode(n+65536):String.fromCharCode(n>>10|55296,1023&n|56320))},re=/([\0-\x1f\x7f]|^-?\d)|^-$|[^\0-\x1f\x7f-\uFFFF\w-]/g,ie=function(e,t){return t?"\0"===e?"\ufffd":e.slice(0,-1)+"\\"+e.charCodeAt(e.length-1).toString(16)+" ":"\\"+e},oe=function(){T()},ae=be(function(e){return!0===e.disabled&&"fieldset"===e.nodeName.toLowerCase()},{dir:"parentNode",next:"legend"});try{H.apply(t=O.call(p.childNodes),p.childNodes),t[p.childNodes.length].nodeType}catch(e){H={apply:t.length?function(e,t){L.apply(e,O.call(t))}:function(e,t){var n=e.length,r=0;while(e[n++]=t[r++]);e.length=n-1}}}function se(t,e,n,r){var i,o,a,s,u,l,c,f=e&&e.ownerDocument,p=e?e.nodeType:9;if(n=n||[],"string"!=typeof t||!t||1!==p&&9!==p&&11!==p)return n;if(!r&&(T(e),e=e||C,E)){if(11!==p&&(u=Z.exec(t)))if(i=u[1]){if(9===p){if(!(a=e.getElementById(i)))return n;if(a.id===i)return n.push(a),n}else if(f&&(a=f.getElementById(i))&&v(e,a)&&a.id===i)return n.push(a),n}else{if(u[2])return H.apply(n,e.getElementsByTagName(t)),n;if((i=u[3])&&d.getElementsByClassName&&e.getElementsByClassName)return H.apply(n,e.getElementsByClassName(i)),n}if(d.qsa&&!N[t+" "]&&(!y||!y.test(t))&&(1!==p||"object"!==e.nodeName.toLowerCase())){if(c=t,f=e,1===p&&(U.test(t)||z.test(t))){(f=ee.test(t)&&ve(e.parentNode)||e)===e&&d.scope||((s=e.getAttribute("id"))?s=s.replace(re,ie):e.setAttribute("id",s=S)),o=(l=h(t)).length;while(o--)l[o]=(s?"#"+s:":scope")+" "+xe(l[o]);c=l.join(",")}try{return H.apply(n,f.querySelectorAll(c)),n}catch(e){N(t,!0)}finally{s===S&&e.removeAttribute("id")}}}return g(t.replace(B,"$1"),e,n,r)}function ue(){var r=[];return function e(t,n){return r.push(t+" ")>b.cacheLength&&delete e[r.shift()],e[t+" "]=n}}function le(e){return e[S]=!0,e}function ce(e){var t=C.createElement("fieldset");try{return!!e(t)}catch(e){return!1}finally{t.parentNode&&t.parentNode.removeChild(t),t=null}}function fe(e,t){var n=e.split("|"),r=n.length;while(r--)b.attrHandle[n[r]]=t}function pe(e,t){var n=t&&e,r=n&&1===e.nodeType&&1===t.nodeType&&e.sourceIndex-t.sourceIndex;if(r)return r;if(n)while(n=n.nextSibling)if(n===t)return-1;return e?1:-1}function de(t){return function(e){return"input"===e.nodeName.toLowerCase()&&e.type===t}}function he(n){return function(e){var t=e.nodeName.toLowerCase();return("input"===t||"button"===t)&&e.type===n}}function ge(t){return function(e){return"form"in e?e.parentNode&&!1===e.disabled?"label"in e?"label"in e.parentNode?e.parentNode.disabled===t:e.disabled===t:e.isDisabled===t||e.isDisabled!==!t&&ae(e)===t:e.disabled===t:"label"in e&&e.disabled===t}}function ye(a){return le(function(o){return o=+o,le(function(e,t){var n,r=a([],e.length,o),i=r.length;while(i--)e[n=r[i]]&&(e[n]=!(t[n]=e[n]))})})}function ve(e){return e&&"undefined"!=typeof e.getElementsByTagName&&e}for(e in d=se.support={},i=se.isXML=function(e){var t=e&&e.namespaceURI,n=e&&(e.ownerDocument||e).documentElement;return!Y.test(t||n&&n.nodeName||"HTML")},T=se.setDocument=function(e){var t,n,r=e?e.ownerDocument||e:p;return r!=C&&9===r.nodeType&&r.documentElement&&(a=(C=r).documentElement,E=!i(C),p!=C&&(n=C.defaultView)&&n.top!==n&&(n.addEventListener?n.addEventListener("unload",oe,!1):n.attachEvent&&n.attachEvent("onunload",oe)),d.scope=ce(function(e){return a.appendChild(e).appendChild(C.createElement("div")),"undefined"!=typeof e.querySelectorAll&&!e.querySelectorAll(":scope fieldset div").length}),d.attributes=ce(function(e){return e.className="i",!e.getAttribute("className")}),d.getElementsByTagName=ce(function(e){return e.appendChild(C.createComment("")),!e.getElementsByTagName("*").length}),d.getElementsByClassName=K.test(C.getElementsByClassName),d.getById=ce(function(e){return a.appendChild(e).id=S,!C.getElementsByName||!C.getElementsByName(S).length}),d.getById?(b.filter.ID=function(e){var t=e.replace(te,ne);return function(e){return e.getAttribute("id")===t}},b.find.ID=function(e,t){if("undefined"!=typeof t.getElementById&&E){var n=t.getElementById(e);return n?[n]:[]}}):(b.filter.ID=function(e){var n=e.replace(te,ne);return function(e){var t="undefined"!=typeof e.getAttributeNode&&e.getAttributeNode("id");return t&&t.value===n}},b.find.ID=function(e,t){if("undefined"!=typeof t.getElementById&&E){var n,r,i,o=t.getElementById(e);if(o){if((n=o.getAttributeNode("id"))&&n.value===e)return[o];i=t.getElementsByName(e),r=0;while(o=i[r++])if((n=o.getAttributeNode("id"))&&n.value===e)return[o]}return[]}}),b.find.TAG=d.getElementsByTagName?function(e,t){return"undefined"!=typeof t.getElementsByTagName?t.getElementsByTagName(e):d.qsa?t.querySelectorAll(e):void 0}:function(e,t){var n,r=[],i=0,o=t.getElementsByTagName(e);if("*"===e){while(n=o[i++])1===n.nodeType&&r.push(n);return r}return o},b.find.CLASS=d.getElementsByClassName&&function(e,t){if("undefined"!=typeof t.getElementsByClassName&&E)return t.getElementsByClassName(e)},s=[],y=[],(d.qsa=K.test(C.querySelectorAll))&&(ce(function(e){var t;a.appendChild(e).innerHTML="<a id='"+S+"'></a><select id='"+S+"-\r\\' msallowcapture=''><option selected=''></option></select>",e.querySelectorAll("[msallowcapture^='']").length&&y.push("[*^$]="+M+"*(?:''|\"\")"),e.querySelectorAll("[selected]").length||y.push("\\["+M+"*(?:value|"+R+")"),e.querySelectorAll("[id~="+S+"-]").length||y.push("~="),(t=C.createElement("input")).setAttribute("name",""),e.appendChild(t),e.querySelectorAll("[name='']").length||y.push("\\["+M+"*name"+M+"*="+M+"*(?:''|\"\")"),e.querySelectorAll(":checked").length||y.push(":checked"),e.querySelectorAll("a#"+S+"+*").length||y.push(".#.+[+~]"),e.querySelectorAll("\\\f"),y.push("[\\r\\n\\f]")}),ce(function(e){e.innerHTML="<a href='' disabled='disabled'></a><select disabled='disabled'><option/></select>";var t=C.createElement("input");t.setAttribute("type","hidden"),e.appendChild(t).setAttribute("name","D"),e.querySelectorAll("[name=d]").length&&y.push("name"+M+"*[*^$|!~]?="),2!==e.querySelectorAll(":enabled").length&&y.push(":enabled",":disabled"),a.appendChild(e).disabled=!0,2!==e.querySelectorAll(":disabled").length&&y.push(":enabled",":disabled"),e.querySelectorAll("*,:x"),y.push(",.*:")})),(d.matchesSelector=K.test(c=a.matches||a.webkitMatchesSelector||a.mozMatchesSelector||a.oMatchesSelector||a.msMatchesSelector))&&ce(function(e){d.disconnectedMatch=c.call(e,"*"),c.call(e,"[s!='']:x"),s.push("!=",F)}),y=y.length&&new RegExp(y.join("|")),s=s.length&&new RegExp(s.join("|")),t=K.test(a.compareDocumentPosition),v=t||K.test(a.contains)?function(e,t){var n=9===e.nodeType?e.documentElement:e,r=t&&t.parentNode;return e===r||!(!r||1!==r.nodeType||!(n.contains?n.contains(r):e.compareDocumentPosition&&16&e.compareDocumentPosition(r)))}:function(e,t){if(t)while(t=t.parentNode)if(t===e)return!0;return!1},j=t?function(e,t){if(e===t)return l=!0,0;var n=!e.compareDocumentPosition-!t.compareDocumentPosition;return n||(1&(n=(e.ownerDocument||e)==(t.ownerDocument||t)?e.compareDocumentPosition(t):1)||!d.sortDetached&&t.compareDocumentPosition(e)===n?e==C||e.ownerDocument==p&&v(p,e)?-1:t==C||t.ownerDocument==p&&v(p,t)?1:u?P(u,e)-P(u,t):0:4&n?-1:1)}:function(e,t){if(e===t)return l=!0,0;var n,r=0,i=e.parentNode,o=t.parentNode,a=[e],s=[t];if(!i||!o)return e==C?-1:t==C?1:i?-1:o?1:u?P(u,e)-P(u,t):0;if(i===o)return pe(e,t);n=e;while(n=n.parentNode)a.unshift(n);n=t;while(n=n.parentNode)s.unshift(n);while(a[r]===s[r])r++;return r?pe(a[r],s[r]):a[r]==p?-1:s[r]==p?1:0}),C},se.matches=function(e,t){return se(e,null,null,t)},se.matchesSelector=function(e,t){if(T(e),d.matchesSelector&&E&&!N[t+" "]&&(!s||!s.test(t))&&(!y||!y.test(t)))try{var n=c.call(e,t);if(n||d.disconnectedMatch||e.document&&11!==e.document.nodeType)return n}catch(e){N(t,!0)}return 0<se(t,C,null,[e]).length},se.contains=function(e,t){return(e.ownerDocument||e)!=C&&T(e),v(e,t)},se.attr=function(e,t){(e.ownerDocument||e)!=C&&T(e);var n=b.attrHandle[t.toLowerCase()],r=n&&D.call(b.attrHandle,t.toLowerCase())?n(e,t,!E):void 0;return void 0!==r?r:d.attributes||!E?e.getAttribute(t):(r=e.getAttributeNode(t))&&r.specified?r.value:null},se.escape=function(e){return(e+"").replace(re,ie)},se.error=function(e){throw new Error("Syntax error, unrecognized expression: "+e)},se.uniqueSort=function(e){var t,n=[],r=0,i=0;if(l=!d.detectDuplicates,u=!d.sortStable&&e.slice(0),e.sort(j),l){while(t=e[i++])t===e[i]&&(r=n.push(i));while(r--)e.splice(n[r],1)}return u=null,e},o=se.getText=function(e){var t,n="",r=0,i=e.nodeType;if(i){if(1===i||9===i||11===i){if("string"==typeof e.textContent)return e.textContent;for(e=e.firstChild;e;e=e.nextSibling)n+=o(e)}else if(3===i||4===i)return e.nodeValue}else while(t=e[r++])n+=o(t);return n},(b=se.selectors={cacheLength:50,createPseudo:le,match:G,attrHandle:{},find:{},relative:{">":{dir:"parentNode",first:!0}," ":{dir:"parentNode"},"+":{dir:"previousSibling",first:!0},"~":{dir:"previousSibling"}},preFilter:{ATTR:function(e){return e[1]=e[1].replace(te,ne),e[3]=(e[3]||e[4]||e[5]||"").replace(te,ne),"~="===e[2]&&(e[3]=" "+e[3]+" "),e.slice(0,4)},CHILD:function(e){return e[1]=e[1].toLowerCase(),"nth"===e[1].slice(0,3)?(e[3]||se.error(e[0]),e[4]=+(e[4]?e[5]+(e[6]||1):2*("even"===e[3]||"odd"===e[3])),e[5]=+(e[7]+e[8]||"odd"===e[3])):e[3]&&se.error(e[0]),e},PSEUDO:function(e){var t,n=!e[6]&&e[2];return G.CHILD.test(e[0])?null:(e[3]?e[2]=e[4]||e[5]||"":n&&X.test(n)&&(t=h(n,!0))&&(t=n.indexOf(")",n.length-t)-n.length)&&(e[0]=e[0].slice(0,t),e[2]=n.slice(0,t)),e.slice(0,3))}},filter:{TAG:function(e){var t=e.replace(te,ne).toLowerCase();return"*"===e?function(){return!0}:function(e){return e.nodeName&&e.nodeName.toLowerCase()===t}},CLASS:function(e){var t=m[e+" "];return t||(t=new RegExp("(^|"+M+")"+e+"("+M+"|$)"))&&m(e,function(e){return t.test("string"==typeof e.className&&e.className||"undefined"!=typeof e.getAttribute&&e.getAttribute("class")||"")})},ATTR:function(n,r,i){return function(e){var t=se.attr(e,n);return null==t?"!="===r:!r||(t+="","="===r?t===i:"!="===r?t!==i:"^="===r?i&&0===t.indexOf(i):"*="===r?i&&-1<t.indexOf(i):"$="===r?i&&t.slice(-i.length)===i:"~="===r?-1<(" "+t.replace($," ")+" ").indexOf(i):"|="===r&&(t===i||t.slice(0,i.length+1)===i+"-"))}},CHILD:function(h,e,t,g,y){var v="nth"!==h.slice(0,3),m="last"!==h.slice(-4),x="of-type"===e;return 1===g&&0===y?function(e){return!!e.parentNode}:function(e,t,n){var r,i,o,a,s,u,l=v!==m?"nextSibling":"previousSibling",c=e.parentNode,f=x&&e.nodeName.toLowerCase(),p=!n&&!x,d=!1;if(c){if(v){while(l){a=e;while(a=a[l])if(x?a.nodeName.toLowerCase()===f:1===a.nodeType)return!1;u=l="only"===h&&!u&&"nextSibling"}return!0}if(u=[m?c.firstChild:c.lastChild],m&&p){d=(s=(r=(i=(o=(a=c)[S]||(a[S]={}))[a.uniqueID]||(o[a.uniqueID]={}))[h]||[])[0]===k&&r[1])&&r[2],a=s&&c.childNodes[s];while(a=++s&&a&&a[l]||(d=s=0)||u.pop())if(1===a.nodeType&&++d&&a===e){i[h]=[k,s,d];break}}else if(p&&(d=s=(r=(i=(o=(a=e)[S]||(a[S]={}))[a.uniqueID]||(o[a.uniqueID]={}))[h]||[])[0]===k&&r[1]),!1===d)while(a=++s&&a&&a[l]||(d=s=0)||u.pop())if((x?a.nodeName.toLowerCase()===f:1===a.nodeType)&&++d&&(p&&((i=(o=a[S]||(a[S]={}))[a.uniqueID]||(o[a.uniqueID]={}))[h]=[k,d]),a===e))break;return(d-=y)===g||d%g==0&&0<=d/g}}},PSEUDO:function(e,o){var t,a=b.pseudos[e]||b.setFilters[e.toLowerCase()]||se.error("unsupported pseudo: "+e);return a[S]?a(o):1<a.length?(t=[e,e,"",o],b.setFilters.hasOwnProperty(e.toLowerCase())?le(function(e,t){var n,r=a(e,o),i=r.length;while(i--)e[n=P(e,r[i])]=!(t[n]=r[i])}):function(e){return a(e,0,t)}):a}},pseudos:{not:le(function(e){var r=[],i=[],s=f(e.replace(B,"$1"));return s[S]?le(function(e,t,n,r){var i,o=s(e,null,r,[]),a=e.length;while(a--)(i=o[a])&&(e[a]=!(t[a]=i))}):function(e,t,n){return r[0]=e,s(r,null,n,i),r[0]=null,!i.pop()}}),has:le(function(t){return function(e){return 0<se(t,e).length}}),contains:le(function(t){return t=t.replace(te,ne),function(e){return-1<(e.textContent||o(e)).indexOf(t)}}),lang:le(function(n){return V.test(n||"")||se.error("unsupported lang: "+n),n=n.replace(te,ne).toLowerCase(),function(e){var t;do{if(t=E?e.lang:e.getAttribute("xml:lang")||e.getAttribute("lang"))return(t=t.toLowerCase())===n||0===t.indexOf(n+"-")}while((e=e.parentNode)&&1===e.nodeType);return!1}}),target:function(e){var t=n.location&&n.location.hash;return t&&t.slice(1)===e.id},root:function(e){return e===a},focus:function(e){return e===C.activeElement&&(!C.hasFocus||C.hasFocus())&&!!(e.type||e.href||~e.tabIndex)},enabled:ge(!1),disabled:ge(!0),checked:function(e){var t=e.nodeName.toLowerCase();return"input"===t&&!!e.checked||"option"===t&&!!e.selected},selected:function(e){return e.parentNode&&e.parentNode.selectedIndex,!0===e.selected},empty:function(e){for(e=e.firstChild;e;e=e.nextSibling)if(e.nodeType<6)return!1;return!0},parent:function(e){return!b.pseudos.empty(e)},header:function(e){return J.test(e.nodeName)},input:function(e){return Q.test(e.nodeName)},button:function(e){var t=e.nodeName.toLowerCase();return"input"===t&&"button"===e.type||"button"===t},text:function(e){var t;return"input"===e.nodeName.toLowerCase()&&"text"===e.type&&(null==(t=e.getAttribute("type"))||"text"===t.toLowerCase())},first:ye(function(){return[0]}),last:ye(function(e,t){return[t-1]}),eq:ye(function(e,t,n){return[n<0?n+t:n]}),even:ye(function(e,t){for(var n=0;n<t;n+=2)e.push(n);return e}),odd:ye(function(e,t){for(var n=1;n<t;n+=2)e.push(n);return e}),lt:ye(function(e,t,n){for(var r=n<0?n+t:t<n?t:n;0<=--r;)e.push(r);return e}),gt:ye(function(e,t,n){for(var r=n<0?n+t:n;++r<t;)e.push(r);return e})}}).pseudos.nth=b.pseudos.eq,{radio:!0,checkbox:!0,file:!0,password:!0,image:!0})b.pseudos[e]=de(e);for(e in{submit:!0,reset:!0})b.pseudos[e]=he(e);function me(){}function xe(e){for(var t=0,n=e.length,r="";t<n;t++)r+=e[t].value;return r}function be(s,e,t){var u=e.dir,l=e.next,c=l||u,f=t&&"parentNode"===c,p=r++;return e.first?function(e,t,n){while(e=e[u])if(1===e.nodeType||f)return s(e,t,n);return!1}:function(e,t,n){var r,i,o,a=[k,p];if(n){while(e=e[u])if((1===e.nodeType||f)&&s(e,t,n))return!0}else while(e=e[u])if(1===e.nodeType||f)if(i=(o=e[S]||(e[S]={}))[e.uniqueID]||(o[e.uniqueID]={}),l&&l===e.nodeName.toLowerCase())e=e[u]||e;else{if((r=i[c])&&r[0]===k&&r[1]===p)return a[2]=r[2];if((i[c]=a)[2]=s(e,t,n))return!0}return!1}}function we(i){return 1<i.length?function(e,t,n){var r=i.length;while(r--)if(!i[r](e,t,n))return!1;return!0}:i[0]}function Te(e,t,n,r,i){for(var o,a=[],s=0,u=e.length,l=null!=t;s<u;s++)(o=e[s])&&(n&&!n(o,r,i)||(a.push(o),l&&t.push(s)));return a}function Ce(d,h,g,y,v,e){return y&&!y[S]&&(y=Ce(y)),v&&!v[S]&&(v=Ce(v,e)),le(function(e,t,n,r){var i,o,a,s=[],u=[],l=t.length,c=e||function(e,t,n){for(var r=0,i=t.length;r<i;r++)se(e,t[r],n);return n}(h||"*",n.nodeType?[n]:n,[]),f=!d||!e&&h?c:Te(c,s,d,n,r),p=g?v||(e?d:l||y)?[]:t:f;if(g&&g(f,p,n,r),y){i=Te(p,u),y(i,[],n,r),o=i.length;while(o--)(a=i[o])&&(p[u[o]]=!(f[u[o]]=a))}if(e){if(v||d){if(v){i=[],o=p.length;while(o--)(a=p[o])&&i.push(f[o]=a);v(null,p=[],i,r)}o=p.length;while(o--)(a=p[o])&&-1<(i=v?P(e,a):s[o])&&(e[i]=!(t[i]=a))}}else p=Te(p===t?p.splice(l,p.length):p),v?v(null,t,p,r):H.apply(t,p)})}function Ee(e){for(var i,t,n,r=e.length,o=b.relative[e[0].type],a=o||b.relative[" "],s=o?1:0,u=be(function(e){return e===i},a,!0),l=be(function(e){return-1<P(i,e)},a,!0),c=[function(e,t,n){var r=!o&&(n||t!==w)||((i=t).nodeType?u(e,t,n):l(e,t,n));return i=null,r}];s<r;s++)if(t=b.relative[e[s].type])c=[be(we(c),t)];else{if((t=b.filter[e[s].type].apply(null,e[s].matches))[S]){for(n=++s;n<r;n++)if(b.relative[e[n].type])break;return Ce(1<s&&we(c),1<s&&xe(e.slice(0,s-1).concat({value:" "===e[s-2].type?"*":""})).replace(B,"$1"),t,s<n&&Ee(e.slice(s,n)),n<r&&Ee(e=e.slice(n)),n<r&&xe(e))}c.push(t)}return we(c)}return me.prototype=b.filters=b.pseudos,b.setFilters=new me,h=se.tokenize=function(e,t){var n,r,i,o,a,s,u,l=x[e+" "];if(l)return t?0:l.slice(0);a=e,s=[],u=b.preFilter;while(a){for(o in n&&!(r=_.exec(a))||(r&&(a=a.slice(r[0].length)||a),s.push(i=[])),n=!1,(r=z.exec(a))&&(n=r.shift(),i.push({value:n,type:r[0].replace(B," ")}),a=a.slice(n.length)),b.filter)!(r=G[o].exec(a))||u[o]&&!(r=u[o](r))||(n=r.shift(),i.push({value:n,type:o,matches:r}),a=a.slice(n.length));if(!n)break}return t?a.length:a?se.error(e):x(e,s).slice(0)},f=se.compile=function(e,t){var n,y,v,m,x,r,i=[],o=[],a=A[e+" "];if(!a){t||(t=h(e)),n=t.length;while(n--)(a=Ee(t[n]))[S]?i.push(a):o.push(a);(a=A(e,(y=o,m=0<(v=i).length,x=0<y.length,r=function(e,t,n,r,i){var o,a,s,u=0,l="0",c=e&&[],f=[],p=w,d=e||x&&b.find.TAG("*",i),h=k+=null==p?1:Math.random()||.1,g=d.length;for(i&&(w=t==C||t||i);l!==g&&null!=(o=d[l]);l++){if(x&&o){a=0,t||o.ownerDocument==C||(T(o),n=!E);while(s=y[a++])if(s(o,t||C,n)){r.push(o);break}i&&(k=h)}m&&((o=!s&&o)&&u--,e&&c.push(o))}if(u+=l,m&&l!==u){a=0;while(s=v[a++])s(c,f,t,n);if(e){if(0<u)while(l--)c[l]||f[l]||(f[l]=q.call(r));f=Te(f)}H.apply(r,f),i&&!e&&0<f.length&&1<u+v.length&&se.uniqueSort(r)}return i&&(k=h,w=p),c},m?le(r):r))).selector=e}return a},g=se.select=function(e,t,n,r){var i,o,a,s,u,l="function"==typeof e&&e,c=!r&&h(e=l.selector||e);if(n=n||[],1===c.length){if(2<(o=c[0]=c[0].slice(0)).length&&"ID"===(a=o[0]).type&&9===t.nodeType&&E&&b.relative[o[1].type]){if(!(t=(b.find.ID(a.matches[0].replace(te,ne),t)||[])[0]))return n;l&&(t=t.parentNode),e=e.slice(o.shift().value.length)}i=G.needsContext.test(e)?0:o.length;while(i--){if(a=o[i],b.relative[s=a.type])break;if((u=b.find[s])&&(r=u(a.matches[0].replace(te,ne),ee.test(o[0].type)&&ve(t.parentNode)||t))){if(o.splice(i,1),!(e=r.length&&xe(o)))return H.apply(n,r),n;break}}}return(l||f(e,c))(r,t,!E,n,!t||ee.test(e)&&ve(t.parentNode)||t),n},d.sortStable=S.split("").sort(j).join("")===S,d.detectDuplicates=!!l,T(),d.sortDetached=ce(function(e){return 1&e.compareDocumentPosition(C.createElement("fieldset"))}),ce(function(e){return e.innerHTML="<a href='#'></a>","#"===e.firstChild.getAttribute("href")})||fe("type|href|height|width",function(e,t,n){if(!n)return e.getAttribute(t,"type"===t.toLowerCase()?1:2)}),d.attributes&&ce(function(e){return e.innerHTML="<input/>",e.firstChild.setAttribute("value",""),""===e.firstChild.getAttribute("value")})||fe("value",function(e,t,n){if(!n&&"input"===e.nodeName.toLowerCase())return e.defaultValue}),ce(function(e){return null==e.getAttribute("disabled")})||fe(R,function(e,t,n){var r;if(!n)return!0===e[t]?t.toLowerCase():(r=e.getAttributeNode(t))&&r.specified?r.value:null}),se}(C);S.find=d,S.expr=d.selectors,S.expr[":"]=S.expr.pseudos,S.uniqueSort=S.unique=d.uniqueSort,S.text=d.getText,S.isXMLDoc=d.isXML,S.contains=d.contains,S.escapeSelector=d.escape;var h=function(e,t,n){var r=[],i=void 0!==n;while((e=e[t])&&9!==e.nodeType)if(1===e.nodeType){if(i&&S(e).is(n))break;r.push(e)}return r},T=function(e,t){for(var n=[];e;e=e.nextSibling)1===e.nodeType&&e!==t&&n.push(e);return n},k=S.expr.match.needsContext;function A(e,t){return e.nodeName&&e.nodeName.toLowerCase()===t.toLowerCase()}var N=/^<([a-z][^\/\0>:\x20\t\r\n\f]*)[\x20\t\r\n\f]*\/?>(?:<\/\1>|)$/i;function j(e,n,r){return m(n)?S.grep(e,function(e,t){return!!n.call(e,t,e)!==r}):n.nodeType?S.grep(e,function(e){return e===n!==r}):"string"!=typeof n?S.grep(e,function(e){return-1<i.call(n,e)!==r}):S.filter(n,e,r)}S.filter=function(e,t,n){var r=t[0];return n&&(e=":not("+e+")"),1===t.length&&1===r.nodeType?S.find.matchesSelector(r,e)?[r]:[]:S.find.matches(e,S.grep(t,function(e){return 1===e.nodeType}))},S.fn.extend({find:function(e){var t,n,r=this.length,i=this;if("string"!=typeof e)return this.pushStack(S(e).filter(function(){for(t=0;t<r;t++)if(S.contains(i[t],this))return!0}));for(n=this.pushStack([]),t=0;t<r;t++)S.find(e,i[t],n);return 1<r?S.uniqueSort(n):n},filter:function(e){return this.pushStack(j(this,e||[],!1))},not:function(e){return this.pushStack(j(this,e||[],!0))},is:function(e){return!!j(this,"string"==typeof e&&k.test(e)?S(e):e||[],!1).length}});var D,q=/^(?:\s*(<[\w\W]+>)[^>]*|#([\w-]+))$/;(S.fn.init=function(e,t,n){var r,i;if(!e)return this;if(n=n||D,"string"==typeof e){if(!(r="<"===e[0]&&">"===e[e.length-1]&&3<=e.length?[null,e,null]:q.exec(e))||!r[1]&&t)return!t||t.jquery?(t||n).find(e):this.constructor(t).find(e);if(r[1]){if(t=t instanceof S?t[0]:t,S.merge(this,S.parseHTML(r[1],t&&t.nodeType?t.ownerDocument||t:E,!0)),N.test(r[1])&&S.isPlainObject(t))for(r in t)m(this[r])?this[r](t[r]):this.attr(r,t[r]);return this}return(i=E.getElementById(r[2]))&&(this[0]=i,this.length=1),this}return e.nodeType?(this[0]=e,this.length=1,this):m(e)?void 0!==n.ready?n.ready(e):e(S):S.makeArray(e,this)}).prototype=S.fn,D=S(E);var L=/^(?:parents|prev(?:Until|All))/,H={children:!0,contents:!0,next:!0,prev:!0};function O(e,t){while((e=e[t])&&1!==e.nodeType);return e}S.fn.extend({has:function(e){var t=S(e,this),n=t.length;return this.filter(function(){for(var e=0;e<n;e++)if(S.contains(this,t[e]))return!0})},closest:function(e,t){var n,r=0,i=this.length,o=[],a="string"!=typeof e&&S(e);if(!k.test(e))for(;r<i;r++)for(n=this[r];n&&n!==t;n=n.parentNode)if(n.nodeType<11&&(a?-1<a.index(n):1===n.nodeType&&S.find.matchesSelector(n,e))){o.push(n);break}return this.pushStack(1<o.length?S.uniqueSort(o):o)},index:function(e){return e?"string"==typeof e?i.call(S(e),this[0]):i.call(this,e.jquery?e[0]:e):this[0]&&this[0].parentNode?this.first().prevAll().length:-1},add:function(e,t){return this.pushStack(S.uniqueSort(S.merge(this.get(),S(e,t))))},addBack:function(e){return this.add(null==e?this.prevObject:this.prevObject.filter(e))}}),S.each({parent:function(e){var t=e.parentNode;return t&&11!==t.nodeType?t:null},parents:function(e){return h(e,"parentNode")},parentsUntil:function(e,t,n){return h(e,"parentNode",n)},next:function(e){return O(e,"nextSibling")},prev:function(e){return O(e,"previousSibling")},nextAll:function(e){return h(e,"nextSibling")},prevAll:function(e){return h(e,"previousSibling")},nextUntil:function(e,t,n){return h(e,"nextSibling",n)},prevUntil:function(e,t,n){return h(e,"previousSibling",n)},siblings:function(e){return T((e.parentNode||{}).firstChild,e)},children:function(e){return T(e.firstChild)},contents:function(e){return null!=e.contentDocument&&r(e.contentDocument)?e.contentDocument:(A(e,"template")&&(e=e.content||e),S.merge([],e.childNodes))}},function(r,i){S.fn[r]=function(e,t){var n=S.map(this,i,e);return"Until"!==r.slice(-5)&&(t=e),t&&"string"==typeof t&&(n=S.filter(t,n)),1<this.length&&(H[r]||S.uniqueSort(n),L.test(r)&&n.reverse()),this.pushStack(n)}});var P=/[^\x20\t\r\n\f]+/g;function R(e){return e}function M(e){throw e}function I(e,t,n,r){var i;try{e&&m(i=e.promise)?i.call(e).done(t).fail(n):e&&m(i=e.then)?i.call(e,t,n):t.apply(void 0,[e].slice(r))}catch(e){n.apply(void 0,[e])}}S.Callbacks=function(r){var e,n;r="string"==typeof r?(e=r,n={},S.each(e.match(P)||[],function(e,t){n[t]=!0}),n):S.extend({},r);var i,t,o,a,s=[],u=[],l=-1,c=function(){for(a=a||r.once,o=i=!0;u.length;l=-1){t=u.shift();while(++l<s.length)!1===s[l].apply(t[0],t[1])&&r.stopOnFalse&&(l=s.length,t=!1)}r.memory||(t=!1),i=!1,a&&(s=t?[]:"")},f={add:function(){return s&&(t&&!i&&(l=s.length-1,u.push(t)),function n(e){S.each(e,function(e,t){m(t)?r.unique&&f.has(t)||s.push(t):t&&t.length&&"string"!==w(t)&&n(t)})}(arguments),t&&!i&&c()),this},remove:function(){return S.each(arguments,function(e,t){var n;while(-1<(n=S.inArray(t,s,n)))s.splice(n,1),n<=l&&l--}),this},has:function(e){return e?-1<S.inArray(e,s):0<s.length},empty:function(){return s&&(s=[]),this},disable:function(){return a=u=[],s=t="",this},disabled:function(){return!s},lock:function(){return a=u=[],t||i||(s=t=""),this},locked:function(){return!!a},fireWith:function(e,t){return a||(t=[e,(t=t||[]).slice?t.slice():t],u.push(t),i||c()),this},fire:function(){return f.fireWith(this,arguments),this},fired:function(){return!!o}};return f},S.extend({Deferred:function(e){var o=[["notify","progress",S.Callbacks("memory"),S.Callbacks("memory"),2],["resolve","done",S.Callbacks("once memory"),S.Callbacks("once memory"),0,"resolved"],["reject","fail",S.Callbacks("once memory"),S.Callbacks("once memory"),1,"rejected"]],i="pending",a={state:function(){return i},always:function(){return s.done(arguments).fail(arguments),this},"catch":function(e){return a.then(null,e)},pipe:function(){var i=arguments;return S.Deferred(function(r){S.each(o,function(e,t){var n=m(i[t[4]])&&i[t[4]];s[t[1]](function(){var e=n&&n.apply(this,arguments);e&&m(e.promise)?e.promise().progress(r.notify).done(r.resolve).fail(r.reject):r[t[0]+"With"](this,n?[e]:arguments)})}),i=null}).promise()},then:function(t,n,r){var u=0;function l(i,o,a,s){return function(){var n=this,r=arguments,e=function(){var e,t;if(!(i<u)){if((e=a.apply(n,r))===o.promise())throw new TypeError("Thenable self-resolution");t=e&&("object"==typeof e||"function"==typeof e)&&e.then,m(t)?s?t.call(e,l(u,o,R,s),l(u,o,M,s)):(u++,t.call(e,l(u,o,R,s),l(u,o,M,s),l(u,o,R,o.notifyWith))):(a!==R&&(n=void 0,r=[e]),(s||o.resolveWith)(n,r))}},t=s?e:function(){try{e()}catch(e){S.Deferred.exceptionHook&&S.Deferred.exceptionHook(e,t.stackTrace),u<=i+1&&(a!==M&&(n=void 0,r=[e]),o.rejectWith(n,r))}};i?t():(S.Deferred.getStackHook&&(t.stackTrace=S.Deferred.getStackHook()),C.setTimeout(t))}}return S.Deferred(function(e){o[0][3].add(l(0,e,m(r)?r:R,e.notifyWith)),o[1][3].add(l(0,e,m(t)?t:R)),o[2][3].add(l(0,e,m(n)?n:M))}).promise()},promise:function(e){return null!=e?S.extend(e,a):a}},s={};return S.each(o,function(e,t){var n=t[2],r=t[5];a[t[1]]=n.add,r&&n.add(function(){i=r},o[3-e][2].disable,o[3-e][3].disable,o[0][2].lock,o[0][3].lock),n.add(t[3].fire),s[t[0]]=function(){return s[t[0]+"With"](this===s?void 0:this,arguments),this},s[t[0]+"With"]=n.fireWith}),a.promise(s),e&&e.call(s,s),s},when:function(e){var n=arguments.length,t=n,r=Array(t),i=s.call(arguments),o=S.Deferred(),a=function(t){return function(e){r[t]=this,i[t]=1<arguments.length?s.call(arguments):e,--n||o.resolveWith(r,i)}};if(n<=1&&(I(e,o.done(a(t)).resolve,o.reject,!n),"pending"===o.state()||m(i[t]&&i[t].then)))return o.then();while(t--)I(i[t],a(t),o.reject);return o.promise()}});var W=/^(Eval|Internal|Range|Reference|Syntax|Type|URI)Error$/;S.Deferred.exceptionHook=function(e,t){C.console&&C.console.warn&&e&&W.test(e.name)&&C.console.warn("jQuery.Deferred exception: "+e.message,e.stack,t)},S.readyException=function(e){C.setTimeout(function(){throw e})};var F=S.Deferred();function $(){E.removeEventListener("DOMContentLoaded",$),C.removeEventListener("load",$),S.ready()}S.fn.ready=function(e){return F.then(e)["catch"](function(e){S.readyException(e)}),this},S.extend({isReady:!1,readyWait:1,ready:function(e){(!0===e?--S.readyWait:S.isReady)||(S.isReady=!0)!==e&&0<--S.readyWait||F.resolveWith(E,[S])}}),S.ready.then=F.then,"complete"===E.readyState||"loading"!==E.readyState&&!E.documentElement.doScroll?C.setTimeout(S.ready):(E.addEventListener("DOMContentLoaded",$),C.addEventListener("load",$));var B=function(e,t,n,r,i,o,a){var s=0,u=e.length,l=null==n;if("object"===w(n))for(s in i=!0,n)B(e,t,s,n[s],!0,o,a);else if(void 0!==r&&(i=!0,m(r)||(a=!0),l&&(a?(t.call(e,r),t=null):(l=t,t=function(e,t,n){return l.call(S(e),n)})),t))for(;s<u;s++)t(e[s],n,a?r:r.call(e[s],s,t(e[s],n)));return i?e:l?t.call(e):u?t(e[0],n):o},_=/^-ms-/,z=/-([a-z])/g;function U(e,t){return t.toUpperCase()}function X(e){return e.replace(_,"ms-").replace(z,U)}var V=function(e){return 1===e.nodeType||9===e.nodeType||!+e.nodeType};function G(){this.expando=S.expando+G.uid++}G.uid=1,G.prototype={cache:function(e){var t=e[this.expando];return t||(t={},V(e)&&(e.nodeType?e[this.expando]=t:Object.defineProperty(e,this.expando,{value:t,configurable:!0}))),t},set:function(e,t,n){var r,i=this.cache(e);if("string"==typeof t)i[X(t)]=n;else for(r in t)i[X(r)]=t[r];return i},get:function(e,t){return void 0===t?this.cache(e):e[this.expando]&&e[this.expando][X(t)]},access:function(e,t,n){return void 0===t||t&&"string"==typeof t&&void 0===n?this.get(e,t):(this.set(e,t,n),void 0!==n?n:t)},remove:function(e,t){var n,r=e[this.expando];if(void 0!==r){if(void 0!==t){n=(t=Array.isArray(t)?t.map(X):(t=X(t))in r?[t]:t.match(P)||[]).length;while(n--)delete r[t[n]]}(void 0===t||S.isEmptyObject(r))&&(e.nodeType?e[this.expando]=void 0:delete e[this.expando])}},hasData:function(e){var t=e[this.expando];return void 0!==t&&!S.isEmptyObject(t)}};var Y=new G,Q=new G,J=/^(?:\{[\w\W]*\}|\[[\w\W]*\])$/,K=/[A-Z]/g;function Z(e,t,n){var r,i;if(void 0===n&&1===e.nodeType)if(r="data-"+t.replace(K,"-$&").toLowerCase(),"string"==typeof(n=e.getAttribute(r))){try{n="true"===(i=n)||"false"!==i&&("null"===i?null:i===+i+""?+i:J.test(i)?JSON.parse(i):i)}catch(e){}Q.set(e,t,n)}else n=void 0;return n}S.extend({hasData:function(e){return Q.hasData(e)||Y.hasData(e)},data:function(e,t,n){return Q.access(e,t,n)},removeData:function(e,t){Q.remove(e,t)},_data:function(e,t,n){return Y.access(e,t,n)},_removeData:function(e,t){Y.remove(e,t)}}),S.fn.extend({data:function(n,e){var t,r,i,o=this[0],a=o&&o.attributes;if(void 0===n){if(this.length&&(i=Q.get(o),1===o.nodeType&&!Y.get(o,"hasDataAttrs"))){t=a.length;while(t--)a[t]&&0===(r=a[t].name).indexOf("data-")&&(r=X(r.slice(5)),Z(o,r,i[r]));Y.set(o,"hasDataAttrs",!0)}return i}return"object"==typeof n?this.each(function(){Q.set(this,n)}):B(this,function(e){var t;if(o&&void 0===e)return void 0!==(t=Q.get(o,n))?t:void 0!==(t=Z(o,n))?t:void 0;this.each(function(){Q.set(this,n,e)})},null,e,1<arguments.length,null,!0)},removeData:function(e){return this.each(function(){Q.remove(this,e)})}}),S.extend({queue:function(e,t,n){var r;if(e)return t=(t||"fx")+"queue",r=Y.get(e,t),n&&(!r||Array.isArray(n)?r=Y.access(e,t,S.makeArray(n)):r.push(n)),r||[]},dequeue:function(e,t){t=t||"fx";var n=S.queue(e,t),r=n.length,i=n.shift(),o=S._queueHooks(e,t);"inprogress"===i&&(i=n.shift(),r--),i&&("fx"===t&&n.unshift("inprogress"),delete o.stop,i.call(e,function(){S.dequeue(e,t)},o)),!r&&o&&o.empty.fire()},_queueHooks:function(e,t){var n=t+"queueHooks";return Y.get(e,n)||Y.access(e,n,{empty:S.Callbacks("once memory").add(function(){Y.remove(e,[t+"queue",n])})})}}),S.fn.extend({queue:function(t,n){var e=2;return"string"!=typeof t&&(n=t,t="fx",e--),arguments.length<e?S.queue(this[0],t):void 0===n?this:this.each(function(){var e=S.queue(this,t,n);S._queueHooks(this,t),"fx"===t&&"inprogress"!==e[0]&&S.dequeue(this,t)})},dequeue:function(e){return this.each(function(){S.dequeue(this,e)})},clearQueue:function(e){return this.queue(e||"fx",[])},promise:function(e,t){var n,r=1,i=S.Deferred(),o=this,a=this.length,s=function(){--r||i.resolveWith(o,[o])};"string"!=typeof e&&(t=e,e=void 0),e=e||"fx";while(a--)(n=Y.get(o[a],e+"queueHooks"))&&n.empty&&(r++,n.empty.add(s));return s(),i.promise(t)}});var ee=/[+-]?(?:\d*\.|)\d+(?:[eE][+-]?\d+|)/.source,te=new RegExp("^(?:([+-])=|)("+ee+")([a-z%]*)$","i"),ne=["Top","Right","Bottom","Left"],re=E.documentElement,ie=function(e){return S.contains(e.ownerDocument,e)},oe={composed:!0};re.getRootNode&&(ie=function(e){return S.contains(e.ownerDocument,e)||e.getRootNode(oe)===e.ownerDocument});var ae=function(e,t){return"none"===(e=t||e).style.display||""===e.style.display&&ie(e)&&"none"===S.css(e,"display")};function se(e,t,n,r){var i,o,a=20,s=r?function(){return r.cur()}:function(){return S.css(e,t,"")},u=s(),l=n&&n[3]||(S.cssNumber[t]?"":"px"),c=e.nodeType&&(S.cssNumber[t]||"px"!==l&&+u)&&te.exec(S.css(e,t));if(c&&c[3]!==l){u/=2,l=l||c[3],c=+u||1;while(a--)S.style(e,t,c+l),(1-o)*(1-(o=s()/u||.5))<=0&&(a=0),c/=o;c*=2,S.style(e,t,c+l),n=n||[]}return n&&(c=+c||+u||0,i=n[1]?c+(n[1]+1)*n[2]:+n[2],r&&(r.unit=l,r.start=c,r.end=i)),i}var ue={};function le(e,t){for(var n,r,i,o,a,s,u,l=[],c=0,f=e.length;c<f;c++)(r=e[c]).style&&(n=r.style.display,t?("none"===n&&(l[c]=Y.get(r,"display")||null,l[c]||(r.style.display="")),""===r.style.display&&ae(r)&&(l[c]=(u=a=o=void 0,a=(i=r).ownerDocument,s=i.nodeName,(u=ue[s])||(o=a.body.appendChild(a.createElement(s)),u=S.css(o,"display"),o.parentNode.removeChild(o),"none"===u&&(u="block"),ue[s]=u)))):"none"!==n&&(l[c]="none",Y.set(r,"display",n)));for(c=0;c<f;c++)null!=l[c]&&(e[c].style.display=l[c]);return e}S.fn.extend({show:function(){return le(this,!0)},hide:function(){return le(this)},toggle:function(e){return"boolean"==typeof e?e?this.show():this.hide():this.each(function(){ae(this)?S(this).show():S(this).hide()})}});var ce,fe,pe=/^(?:checkbox|radio)$/i,de=/<([a-z][^\/\0>\x20\t\r\n\f]*)/i,he=/^$|^module$|\/(?:java|ecma)script/i;ce=E.createDocumentFragment().appendChild(E.createElement("div")),(fe=E.createElement("input")).setAttribute("type","radio"),fe.setAttribute("checked","checked"),fe.setAttribute("name","t"),ce.appendChild(fe),v.checkClone=ce.cloneNode(!0).cloneNode(!0).lastChild.checked,ce.innerHTML="<textarea>x</textarea>",v.noCloneChecked=!!ce.cloneNode(!0).lastChild.defaultValue,ce.innerHTML="<option></option>",v.option=!!ce.lastChild;var ge={thead:[1,"<table>","</table>"],col:[2,"<table><colgroup>","</colgroup></table>"],tr:[2,"<table><tbody>","</tbody></table>"],td:[3,"<table><tbody><tr>","</tr></tbody></table>"],_default:[0,"",""]};function ye(e,t){var n;return n="undefined"!=typeof e.getElementsByTagName?e.getElementsByTagName(t||"*"):"undefined"!=typeof e.querySelectorAll?e.querySelectorAll(t||"*"):[],void 0===t||t&&A(e,t)?S.merge([e],n):n}function ve(e,t){for(var n=0,r=e.length;n<r;n++)Y.set(e[n],"globalEval",!t||Y.get(t[n],"globalEval"))}ge.tbody=ge.tfoot=ge.colgroup=ge.caption=ge.thead,ge.th=ge.td,v.option||(ge.optgroup=ge.option=[1,"<select multiple='multiple'>","</select>"]);var me=/<|&#?\w+;/;function xe(e,t,n,r,i){for(var o,a,s,u,l,c,f=t.createDocumentFragment(),p=[],d=0,h=e.length;d<h;d++)if((o=e[d])||0===o)if("object"===w(o))S.merge(p,o.nodeType?[o]:o);else if(me.test(o)){a=a||f.appendChild(t.createElement("div")),s=(de.exec(o)||["",""])[1].toLowerCase(),u=ge[s]||ge._default,a.innerHTML=u[1]+S.htmlPrefilter(o)+u[2],c=u[0];while(c--)a=a.lastChild;S.merge(p,a.childNodes),(a=f.firstChild).textContent=""}else p.push(t.createTextNode(o));f.textContent="",d=0;while(o=p[d++])if(r&&-1<S.inArray(o,r))i&&i.push(o);else if(l=ie(o),a=ye(f.appendChild(o),"script"),l&&ve(a),n){c=0;while(o=a[c++])he.test(o.type||"")&&n.push(o)}return f}var be=/^([^.]*)(?:\.(.+)|)/;function we(){return!0}function Te(){return!1}function Ce(e,t){return e===function(){try{return E.activeElement}catch(e){}}()==("focus"===t)}function Ee(e,t,n,r,i,o){var a,s;if("object"==typeof t){for(s in"string"!=typeof n&&(r=r||n,n=void 0),t)Ee(e,s,n,r,t[s],o);return e}if(null==r&&null==i?(i=n,r=n=void 0):null==i&&("string"==typeof n?(i=r,r=void 0):(i=r,r=n,n=void 0)),!1===i)i=Te;else if(!i)return e;return 1===o&&(a=i,(i=function(e){return S().off(e),a.apply(this,arguments)}).guid=a.guid||(a.guid=S.guid++)),e.each(function(){S.event.add(this,t,i,r,n)})}function Se(e,i,o){o?(Y.set(e,i,!1),S.event.add(e,i,{namespace:!1,handler:function(e){var t,n,r=Y.get(this,i);if(1&e.isTrigger&&this[i]){if(r.length)(S.event.special[i]||{}).delegateType&&e.stopPropagation();else if(r=s.call(arguments),Y.set(this,i,r),t=o(this,i),this[i](),r!==(n=Y.get(this,i))||t?Y.set(this,i,!1):n={},r!==n)return e.stopImmediatePropagation(),e.preventDefault(),n&&n.value}else r.length&&(Y.set(this,i,{value:S.event.trigger(S.extend(r[0],S.Event.prototype),r.slice(1),this)}),e.stopImmediatePropagation())}})):void 0===Y.get(e,i)&&S.event.add(e,i,we)}S.event={global:{},add:function(t,e,n,r,i){var o,a,s,u,l,c,f,p,d,h,g,y=Y.get(t);if(V(t)){n.handler&&(n=(o=n).handler,i=o.selector),i&&S.find.matchesSelector(re,i),n.guid||(n.guid=S.guid++),(u=y.events)||(u=y.events=Object.create(null)),(a=y.handle)||(a=y.handle=function(e){return"undefined"!=typeof S&&S.event.triggered!==e.type?S.event.dispatch.apply(t,arguments):void 0}),l=(e=(e||"").match(P)||[""]).length;while(l--)d=g=(s=be.exec(e[l])||[])[1],h=(s[2]||"").split(".").sort(),d&&(f=S.event.special[d]||{},d=(i?f.delegateType:f.bindType)||d,f=S.event.special[d]||{},c=S.extend({type:d,origType:g,data:r,handler:n,guid:n.guid,selector:i,needsContext:i&&S.expr.match.needsContext.test(i),namespace:h.join(".")},o),(p=u[d])||((p=u[d]=[]).delegateCount=0,f.setup&&!1!==f.setup.call(t,r,h,a)||t.addEventListener&&t.addEventListener(d,a)),f.add&&(f.add.call(t,c),c.handler.guid||(c.handler.guid=n.guid)),i?p.splice(p.delegateCount++,0,c):p.push(c),S.event.global[d]=!0)}},remove:function(e,t,n,r,i){var o,a,s,u,l,c,f,p,d,h,g,y=Y.hasData(e)&&Y.get(e);if(y&&(u=y.events)){l=(t=(t||"").match(P)||[""]).length;while(l--)if(d=g=(s=be.exec(t[l])||[])[1],h=(s[2]||"").split(".").sort(),d){f=S.event.special[d]||{},p=u[d=(r?f.delegateType:f.bindType)||d]||[],s=s[2]&&new RegExp("(^|\\.)"+h.join("\\.(?:.*\\.|)")+"(\\.|$)"),a=o=p.length;while(o--)c=p[o],!i&&g!==c.origType||n&&n.guid!==c.guid||s&&!s.test(c.namespace)||r&&r!==c.selector&&("**"!==r||!c.selector)||(p.splice(o,1),c.selector&&p.delegateCount--,f.remove&&f.remove.call(e,c));a&&!p.length&&(f.teardown&&!1!==f.teardown.call(e,h,y.handle)||S.removeEvent(e,d,y.handle),delete u[d])}else for(d in u)S.event.remove(e,d+t[l],n,r,!0);S.isEmptyObject(u)&&Y.remove(e,"handle events")}},dispatch:function(e){var t,n,r,i,o,a,s=new Array(arguments.length),u=S.event.fix(e),l=(Y.get(this,"events")||Object.create(null))[u.type]||[],c=S.event.special[u.type]||{};for(s[0]=u,t=1;t<arguments.length;t++)s[t]=arguments[t];if(u.delegateTarget=this,!c.preDispatch||!1!==c.preDispatch.call(this,u)){a=S.event.handlers.call(this,u,l),t=0;while((i=a[t++])&&!u.isPropagationStopped()){u.currentTarget=i.elem,n=0;while((o=i.handlers[n++])&&!u.isImmediatePropagationStopped())u.rnamespace&&!1!==o.namespace&&!u.rnamespace.test(o.namespace)||(u.handleObj=o,u.data=o.data,void 0!==(r=((S.event.special[o.origType]||{}).handle||o.handler).apply(i.elem,s))&&!1===(u.result=r)&&(u.preventDefault(),u.stopPropagation()))}return c.postDispatch&&c.postDispatch.call(this,u),u.result}},handlers:function(e,t){var n,r,i,o,a,s=[],u=t.delegateCount,l=e.target;if(u&&l.nodeType&&!("click"===e.type&&1<=e.button))for(;l!==this;l=l.parentNode||this)if(1===l.nodeType&&("click"!==e.type||!0!==l.disabled)){for(o=[],a={},n=0;n<u;n++)void 0===a[i=(r=t[n]).selector+" "]&&(a[i]=r.needsContext?-1<S(i,this).index(l):S.find(i,this,null,[l]).length),a[i]&&o.push(r);o.length&&s.push({elem:l,handlers:o})}return l=this,u<t.length&&s.push({elem:l,handlers:t.slice(u)}),s},addProp:function(t,e){Object.defineProperty(S.Event.prototype,t,{enumerable:!0,configurable:!0,get:m(e)?function(){if(this.originalEvent)return e(this.originalEvent)}:function(){if(this.originalEvent)return this.originalEvent[t]},set:function(e){Object.defineProperty(this,t,{enumerable:!0,configurable:!0,writable:!0,value:e})}})},fix:function(e){return e[S.expando]?e:new S.Event(e)},special:{load:{noBubble:!0},click:{setup:function(e){var t=this||e;return pe.test(t.type)&&t.click&&A(t,"input")&&Se(t,"click",we),!1},trigger:function(e){var t=this||e;return pe.test(t.type)&&t.click&&A(t,"input")&&Se(t,"click"),!0},_default:function(e){var t=e.target;return pe.test(t.type)&&t.click&&A(t,"input")&&Y.get(t,"click")||A(t,"a")}},beforeunload:{postDispatch:function(e){void 0!==e.result&&e.originalEvent&&(e.originalEvent.returnValue=e.result)}}}},S.removeEvent=function(e,t,n){e.removeEventListener&&e.removeEventListener(t,n)},S.Event=function(e,t){if(!(this instanceof S.Event))return new S.Event(e,t);e&&e.type?(this.originalEvent=e,this.type=e.type,this.isDefaultPrevented=e.defaultPrevented||void 0===e.defaultPrevented&&!1===e.returnValue?we:Te,this.target=e.target&&3===e.target.nodeType?e.target.parentNode:e.target,this.currentTarget=e.currentTarget,this.relatedTarget=e.relatedTarget):this.type=e,t&&S.extend(this,t),this.timeStamp=e&&e.timeStamp||Date.now(),this[S.expando]=!0},S.Event.prototype={constructor:S.Event,isDefaultPrevented:Te,isPropagationStopped:Te,isImmediatePropagationStopped:Te,isSimulated:!1,preventDefault:function(){var e=this.originalEvent;this.isDefaultPrevented=we,e&&!this.isSimulated&&e.preventDefault()},stopPropagation:function(){var e=this.originalEvent;this.isPropagationStopped=we,e&&!this.isSimulated&&e.stopPropagation()},stopImmediatePropagation:function(){var e=this.originalEvent;this.isImmediatePropagationStopped=we,e&&!this.isSimulated&&e.stopImmediatePropagation(),this.stopPropagation()}},S.each({altKey:!0,bubbles:!0,cancelable:!0,changedTouches:!0,ctrlKey:!0,detail:!0,eventPhase:!0,metaKey:!0,pageX:!0,pageY:!0,shiftKey:!0,view:!0,"char":!0,code:!0,charCode:!0,key:!0,keyCode:!0,button:!0,buttons:!0,clientX:!0,clientY:!0,offsetX:!0,offsetY:!0,pointerId:!0,pointerType:!0,screenX:!0,screenY:!0,targetTouches:!0,toElement:!0,touches:!0,which:!0},S.event.addProp),S.each({focus:"focusin",blur:"focusout"},function(t,e){S.event.special[t]={setup:function(){return Se(this,t,Ce),!1},trigger:function(){return Se(this,t),!0},_default:function(e){return Y.get(e.target,t)},delegateType:e}}),S.each({mouseenter:"mouseover",mouseleave:"mouseout",pointerenter:"pointerover",pointerleave:"pointerout"},function(e,i){S.event.special[e]={delegateType:i,bindType:i,handle:function(e){var t,n=e.relatedTarget,r=e.handleObj;return n&&(n===this||S.contains(this,n))||(e.type=r.origType,t=r.handler.apply(this,arguments),e.type=i),t}}}),S.fn.extend({on:function(e,t,n,r){return Ee(this,e,t,n,r)},one:function(e,t,n,r){return Ee(this,e,t,n,r,1)},off:function(e,t,n){var r,i;if(e&&e.preventDefault&&e.handleObj)return r=e.handleObj,S(e.delegateTarget).off(r.namespace?r.origType+"."+r.namespace:r.origType,r.selector,r.handler),this;if("object"==typeof e){for(i in e)this.off(i,t,e[i]);return this}return!1!==t&&"function"!=typeof t||(n=t,t=void 0),!1===n&&(n=Te),this.each(function(){S.event.remove(this,e,n,t)})}});var ke=/<script|<style|<link/i,Ae=/checked\s*(?:[^=]|=\s*.checked.)/i,Ne=/^\s*<!\[CDATA\[|\]\]>\s*$/g;function je(e,t){return A(e,"table")&&A(11!==t.nodeType?t:t.firstChild,"tr")&&S(e).children("tbody")[0]||e}function De(e){return e.type=(null!==e.getAttribute("type"))+"/"+e.type,e}function qe(e){return"true/"===(e.type||"").slice(0,5)?e.type=e.type.slice(5):e.removeAttribute("type"),e}function Le(e,t){var n,r,i,o,a,s;if(1===t.nodeType){if(Y.hasData(e)&&(s=Y.get(e).events))for(i in Y.remove(t,"handle events"),s)for(n=0,r=s[i].length;n<r;n++)S.event.add(t,i,s[i][n]);Q.hasData(e)&&(o=Q.access(e),a=S.extend({},o),Q.set(t,a))}}function He(n,r,i,o){r=g(r);var e,t,a,s,u,l,c=0,f=n.length,p=f-1,d=r[0],h=m(d);if(h||1<f&&"string"==typeof d&&!v.checkClone&&Ae.test(d))return n.each(function(e){var t=n.eq(e);h&&(r[0]=d.call(this,e,t.html())),He(t,r,i,o)});if(f&&(t=(e=xe(r,n[0].ownerDocument,!1,n,o)).firstChild,1===e.childNodes.length&&(e=t),t||o)){for(s=(a=S.map(ye(e,"script"),De)).length;c<f;c++)u=e,c!==p&&(u=S.clone(u,!0,!0),s&&S.merge(a,ye(u,"script"))),i.call(n[c],u,c);if(s)for(l=a[a.length-1].ownerDocument,S.map(a,qe),c=0;c<s;c++)u=a[c],he.test(u.type||"")&&!Y.access(u,"globalEval")&&S.contains(l,u)&&(u.src&&"module"!==(u.type||"").toLowerCase()?S._evalUrl&&!u.noModule&&S._evalUrl(u.src,{nonce:u.nonce||u.getAttribute("nonce")},l):b(u.textContent.replace(Ne,""),u,l))}return n}function Oe(e,t,n){for(var r,i=t?S.filter(t,e):e,o=0;null!=(r=i[o]);o++)n||1!==r.nodeType||S.cleanData(ye(r)),r.parentNode&&(n&&ie(r)&&ve(ye(r,"script")),r.parentNode.removeChild(r));return e}S.extend({htmlPrefilter:function(e){return e},clone:function(e,t,n){var r,i,o,a,s,u,l,c=e.cloneNode(!0),f=ie(e);if(!(v.noCloneChecked||1!==e.nodeType&&11!==e.nodeType||S.isXMLDoc(e)))for(a=ye(c),r=0,i=(o=ye(e)).length;r<i;r++)s=o[r],u=a[r],void 0,"input"===(l=u.nodeName.toLowerCase())&&pe.test(s.type)?u.checked=s.checked:"input"!==l&&"textarea"!==l||(u.defaultValue=s.defaultValue);if(t)if(n)for(o=o||ye(e),a=a||ye(c),r=0,i=o.length;r<i;r++)Le(o[r],a[r]);else Le(e,c);return 0<(a=ye(c,"script")).length&&ve(a,!f&&ye(e,"script")),c},cleanData:function(e){for(var t,n,r,i=S.event.special,o=0;void 0!==(n=e[o]);o++)if(V(n)){if(t=n[Y.expando]){if(t.events)for(r in t.events)i[r]?S.event.remove(n,r):S.removeEvent(n,r,t.handle);n[Y.expando]=void 0}n[Q.expando]&&(n[Q.expando]=void 0)}}}),S.fn.extend({detach:function(e){return Oe(this,e,!0)},remove:function(e){return Oe(this,e)},text:function(e){return B(this,function(e){return void 0===e?S.text(this):this.empty().each(function(){1!==this.nodeType&&11!==this.nodeType&&9!==this.nodeType||(this.textContent=e)})},null,e,arguments.length)},append:function(){return He(this,arguments,function(e){1!==this.nodeType&&11!==this.nodeType&&9!==this.nodeType||je(this,e).appendChild(e)})},prepend:function(){return He(this,arguments,function(e){if(1===this.nodeType||11===this.nodeType||9===this.nodeType){var t=je(this,e);t.insertBefore(e,t.firstChild)}})},before:function(){return He(this,arguments,function(e){this.parentNode&&this.parentNode.insertBefore(e,this)})},after:function(){return He(this,arguments,function(e){this.parentNode&&this.parentNode.insertBefore(e,this.nextSibling)})},empty:function(){for(var e,t=0;null!=(e=this[t]);t++)1===e.nodeType&&(S.cleanData(ye(e,!1)),e.textContent="");return this},clone:function(e,t){return e=null!=e&&e,t=null==t?e:t,this.map(function(){return S.clone(this,e,t)})},html:function(e){return B(this,function(e){var t=this[0]||{},n=0,r=this.length;if(void 0===e&&1===t.nodeType)return t.innerHTML;if("string"==typeof e&&!ke.test(e)&&!ge[(de.exec(e)||["",""])[1].toLowerCase()]){e=S.htmlPrefilter(e);try{for(;n<r;n++)1===(t=this[n]||{}).nodeType&&(S.cleanData(ye(t,!1)),t.innerHTML=e);t=0}catch(e){}}t&&this.empty().append(e)},null,e,arguments.length)},replaceWith:function(){var n=[];return He(this,arguments,function(e){var t=this.parentNode;S.inArray(this,n)<0&&(S.cleanData(ye(this)),t&&t.replaceChild(e,this))},n)}}),S.each({appendTo:"append",prependTo:"prepend",insertBefore:"before",insertAfter:"after",replaceAll:"replaceWith"},function(e,a){S.fn[e]=function(e){for(var t,n=[],r=S(e),i=r.length-1,o=0;o<=i;o++)t=o===i?this:this.clone(!0),S(r[o])[a](t),u.apply(n,t.get());return this.pushStack(n)}});var Pe=new RegExp("^("+ee+")(?!px)[a-z%]+$","i"),Re=/^--/,Me=function(e){var t=e.ownerDocument.defaultView;return t&&t.opener||(t=C),t.getComputedStyle(e)},Ie=function(e,t,n){var r,i,o={};for(i in t)o[i]=e.style[i],e.style[i]=t[i];for(i in r=n.call(e),t)e.style[i]=o[i];return r},We=new RegExp(ne.join("|"),"i"),Fe="[\\x20\\t\\r\\n\\f]",$e=new RegExp("^"+Fe+"+|((?:^|[^\\\\])(?:\\\\.)*)"+Fe+"+$","g");function Be(e,t,n){var r,i,o,a,s=Re.test(t),u=e.style;return(n=n||Me(e))&&(a=n.getPropertyValue(t)||n[t],s&&(a=a.replace($e,"$1")),""!==a||ie(e)||(a=S.style(e,t)),!v.pixelBoxStyles()&&Pe.test(a)&&We.test(t)&&(r=u.width,i=u.minWidth,o=u.maxWidth,u.minWidth=u.maxWidth=u.width=a,a=n.width,u.width=r,u.minWidth=i,u.maxWidth=o)),void 0!==a?a+"":a}function _e(e,t){return{get:function(){if(!e())return(this.get=t).apply(this,arguments);delete this.get}}}!function(){function e(){if(l){u.style.cssText="position:absolute;left:-11111px;width:60px;margin-top:1px;padding:0;border:0",l.style.cssText="position:relative;display:block;box-sizing:border-box;overflow:scroll;margin:auto;border:1px;padding:1px;width:60%;top:1%",re.appendChild(u).appendChild(l);var e=C.getComputedStyle(l);n="1%"!==e.top,s=12===t(e.marginLeft),l.style.right="60%",o=36===t(e.right),r=36===t(e.width),l.style.position="absolute",i=12===t(l.offsetWidth/3),re.removeChild(u),l=null}}function t(e){return Math.round(parseFloat(e))}var n,r,i,o,a,s,u=E.createElement("div"),l=E.createElement("div");l.style&&(l.style.backgroundClip="content-box",l.cloneNode(!0).style.backgroundClip="",v.clearCloneStyle="content-box"===l.style.backgroundClip,S.extend(v,{boxSizingReliable:function(){return e(),r},pixelBoxStyles:function(){return e(),o},pixelPosition:function(){return e(),n},reliableMarginLeft:function(){return e(),s},scrollboxSize:function(){return e(),i},reliableTrDimensions:function(){var e,t,n,r;return null==a&&(e=E.createElement("table"),t=E.createElement("tr"),n=E.createElement("div"),e.style.cssText="position:absolute;left:-11111px;border-collapse:separate",t.style.cssText="border:1px solid",t.style.height="1px",n.style.height="9px",n.style.display="block",re.appendChild(e).appendChild(t).appendChild(n),r=C.getComputedStyle(t),a=parseInt(r.height,10)+parseInt(r.borderTopWidth,10)+parseInt(r.borderBottomWidth,10)===t.offsetHeight,re.removeChild(e)),a}}))}();var ze=["Webkit","Moz","ms"],Ue=E.createElement("div").style,Xe={};function Ve(e){var t=S.cssProps[e]||Xe[e];return t||(e in Ue?e:Xe[e]=function(e){var t=e[0].toUpperCase()+e.slice(1),n=ze.length;while(n--)if((e=ze[n]+t)in Ue)return e}(e)||e)}var Ge=/^(none|table(?!-c[ea]).+)/,Ye={position:"absolute",visibility:"hidden",display:"block"},Qe={letterSpacing:"0",fontWeight:"400"};function Je(e,t,n){var r=te.exec(t);return r?Math.max(0,r[2]-(n||0))+(r[3]||"px"):t}function Ke(e,t,n,r,i,o){var a="width"===t?1:0,s=0,u=0;if(n===(r?"border":"content"))return 0;for(;a<4;a+=2)"margin"===n&&(u+=S.css(e,n+ne[a],!0,i)),r?("content"===n&&(u-=S.css(e,"padding"+ne[a],!0,i)),"margin"!==n&&(u-=S.css(e,"border"+ne[a]+"Width",!0,i))):(u+=S.css(e,"padding"+ne[a],!0,i),"padding"!==n?u+=S.css(e,"border"+ne[a]+"Width",!0,i):s+=S.css(e,"border"+ne[a]+"Width",!0,i));return!r&&0<=o&&(u+=Math.max(0,Math.ceil(e["offset"+t[0].toUpperCase()+t.slice(1)]-o-u-s-.5))||0),u}function Ze(e,t,n){var r=Me(e),i=(!v.boxSizingReliable()||n)&&"border-box"===S.css(e,"boxSizing",!1,r),o=i,a=Be(e,t,r),s="offset"+t[0].toUpperCase()+t.slice(1);if(Pe.test(a)){if(!n)return a;a="auto"}return(!v.boxSizingReliable()&&i||!v.reliableTrDimensions()&&A(e,"tr")||"auto"===a||!parseFloat(a)&&"inline"===S.css(e,"display",!1,r))&&e.getClientRects().length&&(i="border-box"===S.css(e,"boxSizing",!1,r),(o=s in e)&&(a=e[s])),(a=parseFloat(a)||0)+Ke(e,t,n||(i?"border":"content"),o,r,a)+"px"}function et(e,t,n,r,i){return new et.prototype.init(e,t,n,r,i)}S.extend({cssHooks:{opacity:{get:function(e,t){if(t){var n=Be(e,"opacity");return""===n?"1":n}}}},cssNumber:{animationIterationCount:!0,columnCount:!0,fillOpacity:!0,flexGrow:!0,flexShrink:!0,fontWeight:!0,gridArea:!0,gridColumn:!0,gridColumnEnd:!0,gridColumnStart:!0,gridRow:!0,gridRowEnd:!0,gridRowStart:!0,lineHeight:!0,opacity:!0,order:!0,orphans:!0,widows:!0,zIndex:!0,zoom:!0},cssProps:{},style:function(e,t,n,r){if(e&&3!==e.nodeType&&8!==e.nodeType&&e.style){var i,o,a,s=X(t),u=Re.test(t),l=e.style;if(u||(t=Ve(s)),a=S.cssHooks[t]||S.cssHooks[s],void 0===n)return a&&"get"in a&&void 0!==(i=a.get(e,!1,r))?i:l[t];"string"===(o=typeof n)&&(i=te.exec(n))&&i[1]&&(n=se(e,t,i),o="number"),null!=n&&n==n&&("number"!==o||u||(n+=i&&i[3]||(S.cssNumber[s]?"":"px")),v.clearCloneStyle||""!==n||0!==t.indexOf("background")||(l[t]="inherit"),a&&"set"in a&&void 0===(n=a.set(e,n,r))||(u?l.setProperty(t,n):l[t]=n))}},css:function(e,t,n,r){var i,o,a,s=X(t);return Re.test(t)||(t=Ve(s)),(a=S.cssHooks[t]||S.cssHooks[s])&&"get"in a&&(i=a.get(e,!0,n)),void 0===i&&(i=Be(e,t,r)),"normal"===i&&t in Qe&&(i=Qe[t]),""===n||n?(o=parseFloat(i),!0===n||isFinite(o)?o||0:i):i}}),S.each(["height","width"],function(e,u){S.cssHooks[u]={get:function(e,t,n){if(t)return!Ge.test(S.css(e,"display"))||e.getClientRects().length&&e.getBoundingClientRect().width?Ze(e,u,n):Ie(e,Ye,function(){return Ze(e,u,n)})},set:function(e,t,n){var r,i=Me(e),o=!v.scrollboxSize()&&"absolute"===i.position,a=(o||n)&&"border-box"===S.css(e,"boxSizing",!1,i),s=n?Ke(e,u,n,a,i):0;return a&&o&&(s-=Math.ceil(e["offset"+u[0].toUpperCase()+u.slice(1)]-parseFloat(i[u])-Ke(e,u,"border",!1,i)-.5)),s&&(r=te.exec(t))&&"px"!==(r[3]||"px")&&(e.style[u]=t,t=S.css(e,u)),Je(0,t,s)}}}),S.cssHooks.marginLeft=_e(v.reliableMarginLeft,function(e,t){if(t)return(parseFloat(Be(e,"marginLeft"))||e.getBoundingClientRect().left-Ie(e,{marginLeft:0},function(){return e.getBoundingClientRect().left}))+"px"}),S.each({margin:"",padding:"",border:"Width"},function(i,o){S.cssHooks[i+o]={expand:function(e){for(var t=0,n={},r="string"==typeof e?e.split(" "):[e];t<4;t++)n[i+ne[t]+o]=r[t]||r[t-2]||r[0];return n}},"margin"!==i&&(S.cssHooks[i+o].set=Je)}),S.fn.extend({css:function(e,t){return B(this,function(e,t,n){var r,i,o={},a=0;if(Array.isArray(t)){for(r=Me(e),i=t.length;a<i;a++)o[t[a]]=S.css(e,t[a],!1,r);return o}return void 0!==n?S.style(e,t,n):S.css(e,t)},e,t,1<arguments.length)}}),((S.Tween=et).prototype={constructor:et,init:function(e,t,n,r,i,o){this.elem=e,this.prop=n,this.easing=i||S.easing._default,this.options=t,this.start=this.now=this.cur(),this.end=r,this.unit=o||(S.cssNumber[n]?"":"px")},cur:function(){var e=et.propHooks[this.prop];return e&&e.get?e.get(this):et.propHooks._default.get(this)},run:function(e){var t,n=et.propHooks[this.prop];return this.options.duration?this.pos=t=S.easing[this.easing](e,this.options.duration*e,0,1,this.options.duration):this.pos=t=e,this.now=(this.end-this.start)*t+this.start,this.options.step&&this.options.step.call(this.elem,this.now,this),n&&n.set?n.set(this):et.propHooks._default.set(this),this}}).init.prototype=et.prototype,(et.propHooks={_default:{get:function(e){var t;return 1!==e.elem.nodeType||null!=e.elem[e.prop]&&null==e.elem.style[e.prop]?e.elem[e.prop]:(t=S.css(e.elem,e.prop,""))&&"auto"!==t?t:0},set:function(e){S.fx.step[e.prop]?S.fx.step[e.prop](e):1!==e.elem.nodeType||!S.cssHooks[e.prop]&&null==e.elem.style[Ve(e.prop)]?e.elem[e.prop]=e.now:S.style(e.elem,e.prop,e.now+e.unit)}}}).scrollTop=et.propHooks.scrollLeft={set:function(e){e.elem.nodeType&&e.elem.parentNode&&(e.elem[e.prop]=e.now)}},S.easing={linear:function(e){return e},swing:function(e){return.5-Math.cos(e*Math.PI)/2},_default:"swing"},S.fx=et.prototype.init,S.fx.step={};var tt,nt,rt,it,ot=/^(?:toggle|show|hide)$/,at=/queueHooks$/;function st(){nt&&(!1===E.hidden&&C.requestAnimationFrame?C.requestAnimationFrame(st):C.setTimeout(st,S.fx.interval),S.fx.tick())}function ut(){return C.setTimeout(function(){tt=void 0}),tt=Date.now()}function lt(e,t){var n,r=0,i={height:e};for(t=t?1:0;r<4;r+=2-t)i["margin"+(n=ne[r])]=i["padding"+n]=e;return t&&(i.opacity=i.width=e),i}function ct(e,t,n){for(var r,i=(ft.tweeners[t]||[]).concat(ft.tweeners["*"]),o=0,a=i.length;o<a;o++)if(r=i[o].call(n,t,e))return r}function ft(o,e,t){var n,a,r=0,i=ft.prefilters.length,s=S.Deferred().always(function(){delete u.elem}),u=function(){if(a)return!1;for(var e=tt||ut(),t=Math.max(0,l.startTime+l.duration-e),n=1-(t/l.duration||0),r=0,i=l.tweens.length;r<i;r++)l.tweens[r].run(n);return s.notifyWith(o,[l,n,t]),n<1&&i?t:(i||s.notifyWith(o,[l,1,0]),s.resolveWith(o,[l]),!1)},l=s.promise({elem:o,props:S.extend({},e),opts:S.extend(!0,{specialEasing:{},easing:S.easing._default},t),originalProperties:e,originalOptions:t,startTime:tt||ut(),duration:t.duration,tweens:[],createTween:function(e,t){var n=S.Tween(o,l.opts,e,t,l.opts.specialEasing[e]||l.opts.easing);return l.tweens.push(n),n},stop:function(e){var t=0,n=e?l.tweens.length:0;if(a)return this;for(a=!0;t<n;t++)l.tweens[t].run(1);return e?(s.notifyWith(o,[l,1,0]),s.resolveWith(o,[l,e])):s.rejectWith(o,[l,e]),this}}),c=l.props;for(!function(e,t){var n,r,i,o,a;for(n in e)if(i=t[r=X(n)],o=e[n],Array.isArray(o)&&(i=o[1],o=e[n]=o[0]),n!==r&&(e[r]=o,delete e[n]),(a=S.cssHooks[r])&&"expand"in a)for(n in o=a.expand(o),delete e[r],o)n in e||(e[n]=o[n],t[n]=i);else t[r]=i}(c,l.opts.specialEasing);r<i;r++)if(n=ft.prefilters[r].call(l,o,c,l.opts))return m(n.stop)&&(S._queueHooks(l.elem,l.opts.queue).stop=n.stop.bind(n)),n;return S.map(c,ct,l),m(l.opts.start)&&l.opts.start.call(o,l),l.progress(l.opts.progress).done(l.opts.done,l.opts.complete).fail(l.opts.fail).always(l.opts.always),S.fx.timer(S.extend(u,{elem:o,anim:l,queue:l.opts.queue})),l}S.Animation=S.extend(ft,{tweeners:{"*":[function(e,t){var n=this.createTween(e,t);return se(n.elem,e,te.exec(t),n),n}]},tweener:function(e,t){m(e)?(t=e,e=["*"]):e=e.match(P);for(var n,r=0,i=e.length;r<i;r++)n=e[r],ft.tweeners[n]=ft.tweeners[n]||[],ft.tweeners[n].unshift(t)},prefilters:[function(e,t,n){var r,i,o,a,s,u,l,c,f="width"in t||"height"in t,p=this,d={},h=e.style,g=e.nodeType&&ae(e),y=Y.get(e,"fxshow");for(r in n.queue||(null==(a=S._queueHooks(e,"fx")).unqueued&&(a.unqueued=0,s=a.empty.fire,a.empty.fire=function(){a.unqueued||s()}),a.unqueued++,p.always(function(){p.always(function(){a.unqueued--,S.queue(e,"fx").length||a.empty.fire()})})),t)if(i=t[r],ot.test(i)){if(delete t[r],o=o||"toggle"===i,i===(g?"hide":"show")){if("show"!==i||!y||void 0===y[r])continue;g=!0}d[r]=y&&y[r]||S.style(e,r)}if((u=!S.isEmptyObject(t))||!S.isEmptyObject(d))for(r in f&&1===e.nodeType&&(n.overflow=[h.overflow,h.overflowX,h.overflowY],null==(l=y&&y.display)&&(l=Y.get(e,"display")),"none"===(c=S.css(e,"display"))&&(l?c=l:(le([e],!0),l=e.style.display||l,c=S.css(e,"display"),le([e]))),("inline"===c||"inline-block"===c&&null!=l)&&"none"===S.css(e,"float")&&(u||(p.done(function(){h.display=l}),null==l&&(c=h.display,l="none"===c?"":c)),h.display="inline-block")),n.overflow&&(h.overflow="hidden",p.always(function(){h.overflow=n.overflow[0],h.overflowX=n.overflow[1],h.overflowY=n.overflow[2]})),u=!1,d)u||(y?"hidden"in y&&(g=y.hidden):y=Y.access(e,"fxshow",{display:l}),o&&(y.hidden=!g),g&&le([e],!0),p.done(function(){for(r in g||le([e]),Y.remove(e,"fxshow"),d)S.style(e,r,d[r])})),u=ct(g?y[r]:0,r,p),r in y||(y[r]=u.start,g&&(u.end=u.start,u.start=0))}],prefilter:function(e,t){t?ft.prefilters.unshift(e):ft.prefilters.push(e)}}),S.speed=function(e,t,n){var r=e&&"object"==typeof e?S.extend({},e):{complete:n||!n&&t||m(e)&&e,duration:e,easing:n&&t||t&&!m(t)&&t};return S.fx.off?r.duration=0:"number"!=typeof r.duration&&(r.duration in S.fx.speeds?r.duration=S.fx.speeds[r.duration]:r.duration=S.fx.speeds._default),null!=r.queue&&!0!==r.queue||(r.queue="fx"),r.old=r.complete,r.complete=function(){m(r.old)&&r.old.call(this),r.queue&&S.dequeue(this,r.queue)},r},S.fn.extend({fadeTo:function(e,t,n,r){return this.filter(ae).css("opacity",0).show().end().animate({opacity:t},e,n,r)},animate:function(t,e,n,r){var i=S.isEmptyObject(t),o=S.speed(e,n,r),a=function(){var e=ft(this,S.extend({},t),o);(i||Y.get(this,"finish"))&&e.stop(!0)};return a.finish=a,i||!1===o.queue?this.each(a):this.queue(o.queue,a)},stop:function(i,e,o){var a=function(e){var t=e.stop;delete e.stop,t(o)};return"string"!=typeof i&&(o=e,e=i,i=void 0),e&&this.queue(i||"fx",[]),this.each(function(){var e=!0,t=null!=i&&i+"queueHooks",n=S.timers,r=Y.get(this);if(t)r[t]&&r[t].stop&&a(r[t]);else for(t in r)r[t]&&r[t].stop&&at.test(t)&&a(r[t]);for(t=n.length;t--;)n[t].elem!==this||null!=i&&n[t].queue!==i||(n[t].anim.stop(o),e=!1,n.splice(t,1));!e&&o||S.dequeue(this,i)})},finish:function(a){return!1!==a&&(a=a||"fx"),this.each(function(){var e,t=Y.get(this),n=t[a+"queue"],r=t[a+"queueHooks"],i=S.timers,o=n?n.length:0;for(t.finish=!0,S.queue(this,a,[]),r&&r.stop&&r.stop.call(this,!0),e=i.length;e--;)i[e].elem===this&&i[e].queue===a&&(i[e].anim.stop(!0),i.splice(e,1));for(e=0;e<o;e++)n[e]&&n[e].finish&&n[e].finish.call(this);delete t.finish})}}),S.each(["toggle","show","hide"],function(e,r){var i=S.fn[r];S.fn[r]=function(e,t,n){return null==e||"boolean"==typeof e?i.apply(this,arguments):this.animate(lt(r,!0),e,t,n)}}),S.each({slideDown:lt("show"),slideUp:lt("hide"),slideToggle:lt("toggle"),fadeIn:{opacity:"show"},fadeOut:{opacity:"hide"},fadeToggle:{opacity:"toggle"}},function(e,r){S.fn[e]=function(e,t,n){return this.animate(r,e,t,n)}}),S.timers=[],S.fx.tick=function(){var e,t=0,n=S.timers;for(tt=Date.now();t<n.length;t++)(e=n[t])()||n[t]!==e||n.splice(t--,1);n.length||S.fx.stop(),tt=void 0},S.fx.timer=function(e){S.timers.push(e),S.fx.start()},S.fx.interval=13,S.fx.start=function(){nt||(nt=!0,st())},S.fx.stop=function(){nt=null},S.fx.speeds={slow:600,fast:200,_default:400},S.fn.delay=function(r,e){return r=S.fx&&S.fx.speeds[r]||r,e=e||"fx",this.queue(e,function(e,t){var n=C.setTimeout(e,r);t.stop=function(){C.clearTimeout(n)}})},rt=E.createElement("input"),it=E.createElement("select").appendChild(E.createElement("option")),rt.type="checkbox",v.checkOn=""!==rt.value,v.optSelected=it.selected,(rt=E.createElement("input")).value="t",rt.type="radio",v.radioValue="t"===rt.value;var pt,dt=S.expr.attrHandle;S.fn.extend({attr:function(e,t){return B(this,S.attr,e,t,1<arguments.length)},removeAttr:function(e){return this.each(function(){S.removeAttr(this,e)})}}),S.extend({attr:function(e,t,n){var r,i,o=e.nodeType;if(3!==o&&8!==o&&2!==o)return"undefined"==typeof e.getAttribute?S.prop(e,t,n):(1===o&&S.isXMLDoc(e)||(i=S.attrHooks[t.toLowerCase()]||(S.expr.match.bool.test(t)?pt:void 0)),void 0!==n?null===n?void S.removeAttr(e,t):i&&"set"in i&&void 0!==(r=i.set(e,n,t))?r:(e.setAttribute(t,n+""),n):i&&"get"in i&&null!==(r=i.get(e,t))?r:null==(r=S.find.attr(e,t))?void 0:r)},attrHooks:{type:{set:function(e,t){if(!v.radioValue&&"radio"===t&&A(e,"input")){var n=e.value;return e.setAttribute("type",t),n&&(e.value=n),t}}}},removeAttr:function(e,t){var n,r=0,i=t&&t.match(P);if(i&&1===e.nodeType)while(n=i[r++])e.removeAttribute(n)}}),pt={set:function(e,t,n){return!1===t?S.removeAttr(e,n):e.setAttribute(n,n),n}},S.each(S.expr.match.bool.source.match(/\w+/g),function(e,t){var a=dt[t]||S.find.attr;dt[t]=function(e,t,n){var r,i,o=t.toLowerCase();return n||(i=dt[o],dt[o]=r,r=null!=a(e,t,n)?o:null,dt[o]=i),r}});var ht=/^(?:input|select|textarea|button)$/i,gt=/^(?:a|area)$/i;function yt(e){return(e.match(P)||[]).join(" ")}function vt(e){return e.getAttribute&&e.getAttribute("class")||""}function mt(e){return Array.isArray(e)?e:"string"==typeof e&&e.match(P)||[]}S.fn.extend({prop:function(e,t){return B(this,S.prop,e,t,1<arguments.length)},removeProp:function(e){return this.each(function(){delete this[S.propFix[e]||e]})}}),S.extend({prop:function(e,t,n){var r,i,o=e.nodeType;if(3!==o&&8!==o&&2!==o)return 1===o&&S.isXMLDoc(e)||(t=S.propFix[t]||t,i=S.propHooks[t]),void 0!==n?i&&"set"in i&&void 0!==(r=i.set(e,n,t))?r:e[t]=n:i&&"get"in i&&null!==(r=i.get(e,t))?r:e[t]},propHooks:{tabIndex:{get:function(e){var t=S.find.attr(e,"tabindex");return t?parseInt(t,10):ht.test(e.nodeName)||gt.test(e.nodeName)&&e.href?0:-1}}},propFix:{"for":"htmlFor","class":"className"}}),v.optSelected||(S.propHooks.selected={get:function(e){var t=e.parentNode;return t&&t.parentNode&&t.parentNode.selectedIndex,null},set:function(e){var t=e.parentNode;t&&(t.selectedIndex,t.parentNode&&t.parentNode.selectedIndex)}}),S.each(["tabIndex","readOnly","maxLength","cellSpacing","cellPadding","rowSpan","colSpan","useMap","frameBorder","contentEditable"],function(){S.propFix[this.toLowerCase()]=this}),S.fn.extend({addClass:function(t){var e,n,r,i,o,a;return m(t)?this.each(function(e){S(this).addClass(t.call(this,e,vt(this)))}):(e=mt(t)).length?this.each(function(){if(r=vt(this),n=1===this.nodeType&&" "+yt(r)+" "){for(o=0;o<e.length;o++)i=e[o],n.indexOf(" "+i+" ")<0&&(n+=i+" ");a=yt(n),r!==a&&this.setAttribute("class",a)}}):this},removeClass:function(t){var e,n,r,i,o,a;return m(t)?this.each(function(e){S(this).removeClass(t.call(this,e,vt(this)))}):arguments.length?(e=mt(t)).length?this.each(function(){if(r=vt(this),n=1===this.nodeType&&" "+yt(r)+" "){for(o=0;o<e.length;o++){i=e[o];while(-1<n.indexOf(" "+i+" "))n=n.replace(" "+i+" "," ")}a=yt(n),r!==a&&this.setAttribute("class",a)}}):this:this.attr("class","")},toggleClass:function(t,n){var e,r,i,o,a=typeof t,s="string"===a||Array.isArray(t);return m(t)?this.each(function(e){S(this).toggleClass(t.call(this,e,vt(this),n),n)}):"boolean"==typeof n&&s?n?this.addClass(t):this.removeClass(t):(e=mt(t),this.each(function(){if(s)for(o=S(this),i=0;i<e.length;i++)r=e[i],o.hasClass(r)?o.removeClass(r):o.addClass(r);else void 0!==t&&"boolean"!==a||((r=vt(this))&&Y.set(this,"__className__",r),this.setAttribute&&this.setAttribute("class",r||!1===t?"":Y.get(this,"__className__")||""))}))},hasClass:function(e){var t,n,r=0;t=" "+e+" ";while(n=this[r++])if(1===n.nodeType&&-1<(" "+yt(vt(n))+" ").indexOf(t))return!0;return!1}});var xt=/\r/g;S.fn.extend({val:function(n){var r,e,i,t=this[0];return arguments.length?(i=m(n),this.each(function(e){var t;1===this.nodeType&&(null==(t=i?n.call(this,e,S(this).val()):n)?t="":"number"==typeof t?t+="":Array.isArray(t)&&(t=S.map(t,function(e){return null==e?"":e+""})),(r=S.valHooks[this.type]||S.valHooks[this.nodeName.toLowerCase()])&&"set"in r&&void 0!==r.set(this,t,"value")||(this.value=t))})):t?(r=S.valHooks[t.type]||S.valHooks[t.nodeName.toLowerCase()])&&"get"in r&&void 0!==(e=r.get(t,"value"))?e:"string"==typeof(e=t.value)?e.replace(xt,""):null==e?"":e:void 0}}),S.extend({valHooks:{option:{get:function(e){var t=S.find.attr(e,"value");return null!=t?t:yt(S.text(e))}},select:{get:function(e){var t,n,r,i=e.options,o=e.selectedIndex,a="select-one"===e.type,s=a?null:[],u=a?o+1:i.length;for(r=o<0?u:a?o:0;r<u;r++)if(((n=i[r]).selected||r===o)&&!n.disabled&&(!n.parentNode.disabled||!A(n.parentNode,"optgroup"))){if(t=S(n).val(),a)return t;s.push(t)}return s},set:function(e,t){var n,r,i=e.options,o=S.makeArray(t),a=i.length;while(a--)((r=i[a]).selected=-1<S.inArray(S.valHooks.option.get(r),o))&&(n=!0);return n||(e.selectedIndex=-1),o}}}}),S.each(["radio","checkbox"],function(){S.valHooks[this]={set:function(e,t){if(Array.isArray(t))return e.checked=-1<S.inArray(S(e).val(),t)}},v.checkOn||(S.valHooks[this].get=function(e){return null===e.getAttribute("value")?"on":e.value})}),v.focusin="onfocusin"in C;var bt=/^(?:focusinfocus|focusoutblur)$/,wt=function(e){e.stopPropagation()};S.extend(S.event,{trigger:function(e,t,n,r){var i,o,a,s,u,l,c,f,p=[n||E],d=y.call(e,"type")?e.type:e,h=y.call(e,"namespace")?e.namespace.split("."):[];if(o=f=a=n=n||E,3!==n.nodeType&&8!==n.nodeType&&!bt.test(d+S.event.triggered)&&(-1<d.indexOf(".")&&(d=(h=d.split(".")).shift(),h.sort()),u=d.indexOf(":")<0&&"on"+d,(e=e[S.expando]?e:new S.Event(d,"object"==typeof e&&e)).isTrigger=r?2:3,e.namespace=h.join("."),e.rnamespace=e.namespace?new RegExp("(^|\\.)"+h.join("\\.(?:.*\\.|)")+"(\\.|$)"):null,e.result=void 0,e.target||(e.target=n),t=null==t?[e]:S.makeArray(t,[e]),c=S.event.special[d]||{},r||!c.trigger||!1!==c.trigger.apply(n,t))){if(!r&&!c.noBubble&&!x(n)){for(s=c.delegateType||d,bt.test(s+d)||(o=o.parentNode);o;o=o.parentNode)p.push(o),a=o;a===(n.ownerDocument||E)&&p.push(a.defaultView||a.parentWindow||C)}i=0;while((o=p[i++])&&!e.isPropagationStopped())f=o,e.type=1<i?s:c.bindType||d,(l=(Y.get(o,"events")||Object.create(null))[e.type]&&Y.get(o,"handle"))&&l.apply(o,t),(l=u&&o[u])&&l.apply&&V(o)&&(e.result=l.apply(o,t),!1===e.result&&e.preventDefault());return e.type=d,r||e.isDefaultPrevented()||c._default&&!1!==c._default.apply(p.pop(),t)||!V(n)||u&&m(n[d])&&!x(n)&&((a=n[u])&&(n[u]=null),S.event.triggered=d,e.isPropagationStopped()&&f.addEventListener(d,wt),n[d](),e.isPropagationStopped()&&f.removeEventListener(d,wt),S.event.triggered=void 0,a&&(n[u]=a)),e.result}},simulate:function(e,t,n){var r=S.extend(new S.Event,n,{type:e,isSimulated:!0});S.event.trigger(r,null,t)}}),S.fn.extend({trigger:function(e,t){return this.each(function(){S.event.trigger(e,t,this)})},triggerHandler:function(e,t){var n=this[0];if(n)return S.event.trigger(e,t,n,!0)}}),v.focusin||S.each({focus:"focusin",blur:"focusout"},function(n,r){var i=function(e){S.event.simulate(r,e.target,S.event.fix(e))};S.event.special[r]={setup:function(){var e=this.ownerDocument||this.document||this,t=Y.access(e,r);t||e.addEventListener(n,i,!0),Y.access(e,r,(t||0)+1)},teardown:function(){var e=this.ownerDocument||this.document||this,t=Y.access(e,r)-1;t?Y.access(e,r,t):(e.removeEventListener(n,i,!0),Y.remove(e,r))}}});var Tt=C.location,Ct={guid:Date.now()},Et=/\?/;S.parseXML=function(e){var t,n;if(!e||"string"!=typeof e)return null;try{t=(new C.DOMParser).parseFromString(e,"text/xml")}catch(e){}return n=t&&t.getElementsByTagName("parsererror")[0],t&&!n||S.error("Invalid XML: "+(n?S.map(n.childNodes,function(e){return e.textContent}).join("\n"):e)),t};var St=/\[\]$/,kt=/\r?\n/g,At=/^(?:submit|button|image|reset|file)$/i,Nt=/^(?:input|select|textarea|keygen)/i;function jt(n,e,r,i){var t;if(Array.isArray(e))S.each(e,function(e,t){r||St.test(n)?i(n,t):jt(n+"["+("object"==typeof t&&null!=t?e:"")+"]",t,r,i)});else if(r||"object"!==w(e))i(n,e);else for(t in e)jt(n+"["+t+"]",e[t],r,i)}S.param=function(e,t){var n,r=[],i=function(e,t){var n=m(t)?t():t;r[r.length]=encodeURIComponent(e)+"="+encodeURIComponent(null==n?"":n)};if(null==e)return"";if(Array.isArray(e)||e.jquery&&!S.isPlainObject(e))S.each(e,function(){i(this.name,this.value)});else for(n in e)jt(n,e[n],t,i);return r.join("&")},S.fn.extend({serialize:function(){return S.param(this.serializeArray())},serializeArray:function(){return this.map(function(){var e=S.prop(this,"elements");return e?S.makeArray(e):this}).filter(function(){var e=this.type;return this.name&&!S(this).is(":disabled")&&Nt.test(this.nodeName)&&!At.test(e)&&(this.checked||!pe.test(e))}).map(function(e,t){var n=S(this).val();return null==n?null:Array.isArray(n)?S.map(n,function(e){return{name:t.name,value:e.replace(kt,"\r\n")}}):{name:t.name,value:n.replace(kt,"\r\n")}}).get()}});var Dt=/%20/g,qt=/#.*$/,Lt=/([?&])_=[^&]*/,Ht=/^(.*?):[ \t]*([^\r\n]*)$/gm,Ot=/^(?:GET|HEAD)$/,Pt=/^\/\//,Rt={},Mt={},It="*/".concat("*"),Wt=E.createElement("a");function Ft(o){return function(e,t){"string"!=typeof e&&(t=e,e="*");var n,r=0,i=e.toLowerCase().match(P)||[];if(m(t))while(n=i[r++])"+"===n[0]?(n=n.slice(1)||"*",(o[n]=o[n]||[]).unshift(t)):(o[n]=o[n]||[]).push(t)}}function $t(t,i,o,a){var s={},u=t===Mt;function l(e){var r;return s[e]=!0,S.each(t[e]||[],function(e,t){var n=t(i,o,a);return"string"!=typeof n||u||s[n]?u?!(r=n):void 0:(i.dataTypes.unshift(n),l(n),!1)}),r}return l(i.dataTypes[0])||!s["*"]&&l("*")}function Bt(e,t){var n,r,i=S.ajaxSettings.flatOptions||{};for(n in t)void 0!==t[n]&&((i[n]?e:r||(r={}))[n]=t[n]);return r&&S.extend(!0,e,r),e}Wt.href=Tt.href,S.extend({active:0,lastModified:{},etag:{},ajaxSettings:{url:Tt.href,type:"GET",isLocal:/^(?:about|app|app-storage|.+-extension|file|res|widget):$/.test(Tt.protocol),global:!0,processData:!0,async:!0,contentType:"application/x-www-form-urlencoded; charset=UTF-8",accepts:{"*":It,text:"text/plain",html:"text/html",xml:"application/xml, text/xml",json:"application/json, text/javascript"},contents:{xml:/\bxml\b/,html:/\bhtml/,json:/\bjson\b/},responseFields:{xml:"responseXML",text:"responseText",json:"responseJSON"},converters:{"* text":String,"text html":!0,"text json":JSON.parse,"text xml":S.parseXML},flatOptions:{url:!0,context:!0}},ajaxSetup:function(e,t){return t?Bt(Bt(e,S.ajaxSettings),t):Bt(S.ajaxSettings,e)},ajaxPrefilter:Ft(Rt),ajaxTransport:Ft(Mt),ajax:function(e,t){"object"==typeof e&&(t=e,e=void 0),t=t||{};var c,f,p,n,d,r,h,g,i,o,y=S.ajaxSetup({},t),v=y.context||y,m=y.context&&(v.nodeType||v.jquery)?S(v):S.event,x=S.Deferred(),b=S.Callbacks("once memory"),w=y.statusCode||{},a={},s={},u="canceled",T={readyState:0,getResponseHeader:function(e){var t;if(h){if(!n){n={};while(t=Ht.exec(p))n[t[1].toLowerCase()+" "]=(n[t[1].toLowerCase()+" "]||[]).concat(t[2])}t=n[e.toLowerCase()+" "]}return null==t?null:t.join(", ")},getAllResponseHeaders:function(){return h?p:null},setRequestHeader:function(e,t){return null==h&&(e=s[e.toLowerCase()]=s[e.toLowerCase()]||e,a[e]=t),this},overrideMimeType:function(e){return null==h&&(y.mimeType=e),this},statusCode:function(e){var t;if(e)if(h)T.always(e[T.status]);else for(t in e)w[t]=[w[t],e[t]];return this},abort:function(e){var t=e||u;return c&&c.abort(t),l(0,t),this}};if(x.promise(T),y.url=((e||y.url||Tt.href)+"").replace(Pt,Tt.protocol+"//"),y.type=t.method||t.type||y.method||y.type,y.dataTypes=(y.dataType||"*").toLowerCase().match(P)||[""],null==y.crossDomain){r=E.createElement("a");try{r.href=y.url,r.href=r.href,y.crossDomain=Wt.protocol+"//"+Wt.host!=r.protocol+"//"+r.host}catch(e){y.crossDomain=!0}}if(y.data&&y.processData&&"string"!=typeof y.data&&(y.data=S.param(y.data,y.traditional)),$t(Rt,y,t,T),h)return T;for(i in(g=S.event&&y.global)&&0==S.active++&&S.event.trigger("ajaxStart"),y.type=y.type.toUpperCase(),y.hasContent=!Ot.test(y.type),f=y.url.replace(qt,""),y.hasContent?y.data&&y.processData&&0===(y.contentType||"").indexOf("application/x-www-form-urlencoded")&&(y.data=y.data.replace(Dt,"+")):(o=y.url.slice(f.length),y.data&&(y.processData||"string"==typeof y.data)&&(f+=(Et.test(f)?"&":"?")+y.data,delete y.data),!1===y.cache&&(f=f.replace(Lt,"$1"),o=(Et.test(f)?"&":"?")+"_="+Ct.guid+++o),y.url=f+o),y.ifModified&&(S.lastModified[f]&&T.setRequestHeader("If-Modified-Since",S.lastModified[f]),S.etag[f]&&T.setRequestHeader("If-None-Match",S.etag[f])),(y.data&&y.hasContent&&!1!==y.contentType||t.contentType)&&T.setRequestHeader("Content-Type",y.contentType),T.setRequestHeader("Accept",y.dataTypes[0]&&y.accepts[y.dataTypes[0]]?y.accepts[y.dataTypes[0]]+("*"!==y.dataTypes[0]?", "+It+"; q=0.01":""):y.accepts["*"]),y.headers)T.setRequestHeader(i,y.headers[i]);if(y.beforeSend&&(!1===y.beforeSend.call(v,T,y)||h))return T.abort();if(u="abort",b.add(y.complete),T.done(y.success),T.fail(y.error),c=$t(Mt,y,t,T)){if(T.readyState=1,g&&m.trigger("ajaxSend",[T,y]),h)return T;y.async&&0<y.timeout&&(d=C.setTimeout(function(){T.abort("timeout")},y.timeout));try{h=!1,c.send(a,l)}catch(e){if(h)throw e;l(-1,e)}}else l(-1,"No Transport");function l(e,t,n,r){var i,o,a,s,u,l=t;h||(h=!0,d&&C.clearTimeout(d),c=void 0,p=r||"",T.readyState=0<e?4:0,i=200<=e&&e<300||304===e,n&&(s=function(e,t,n){var r,i,o,a,s=e.contents,u=e.dataTypes;while("*"===u[0])u.shift(),void 0===r&&(r=e.mimeType||t.getResponseHeader("Content-Type"));if(r)for(i in s)if(s[i]&&s[i].test(r)){u.unshift(i);break}if(u[0]in n)o=u[0];else{for(i in n){if(!u[0]||e.converters[i+" "+u[0]]){o=i;break}a||(a=i)}o=o||a}if(o)return o!==u[0]&&u.unshift(o),n[o]}(y,T,n)),!i&&-1<S.inArray("script",y.dataTypes)&&S.inArray("json",y.dataTypes)<0&&(y.converters["text script"]=function(){}),s=function(e,t,n,r){var i,o,a,s,u,l={},c=e.dataTypes.slice();if(c[1])for(a in e.converters)l[a.toLowerCase()]=e.converters[a];o=c.shift();while(o)if(e.responseFields[o]&&(n[e.responseFields[o]]=t),!u&&r&&e.dataFilter&&(t=e.dataFilter(t,e.dataType)),u=o,o=c.shift())if("*"===o)o=u;else if("*"!==u&&u!==o){if(!(a=l[u+" "+o]||l["* "+o]))for(i in l)if((s=i.split(" "))[1]===o&&(a=l[u+" "+s[0]]||l["* "+s[0]])){!0===a?a=l[i]:!0!==l[i]&&(o=s[0],c.unshift(s[1]));break}if(!0!==a)if(a&&e["throws"])t=a(t);else try{t=a(t)}catch(e){return{state:"parsererror",error:a?e:"No conversion from "+u+" to "+o}}}return{state:"success",data:t}}(y,s,T,i),i?(y.ifModified&&((u=T.getResponseHeader("Last-Modified"))&&(S.lastModified[f]=u),(u=T.getResponseHeader("etag"))&&(S.etag[f]=u)),204===e||"HEAD"===y.type?l="nocontent":304===e?l="notmodified":(l=s.state,o=s.data,i=!(a=s.error))):(a=l,!e&&l||(l="error",e<0&&(e=0))),T.status=e,T.statusText=(t||l)+"",i?x.resolveWith(v,[o,l,T]):x.rejectWith(v,[T,l,a]),T.statusCode(w),w=void 0,g&&m.trigger(i?"ajaxSuccess":"ajaxError",[T,y,i?o:a]),b.fireWith(v,[T,l]),g&&(m.trigger("ajaxComplete",[T,y]),--S.active||S.event.trigger("ajaxStop")))}return T},getJSON:function(e,t,n){return S.get(e,t,n,"json")},getScript:function(e,t){return S.get(e,void 0,t,"script")}}),S.each(["get","post"],function(e,i){S[i]=function(e,t,n,r){return m(t)&&(r=r||n,n=t,t=void 0),S.ajax(S.extend({url:e,type:i,dataType:r,data:t,success:n},S.isPlainObject(e)&&e))}}),S.ajaxPrefilter(function(e){var t;for(t in e.headers)"content-type"===t.toLowerCase()&&(e.contentType=e.headers[t]||"")}),S._evalUrl=function(e,t,n){return S.ajax({url:e,type:"GET",dataType:"script",cache:!0,async:!1,global:!1,converters:{"text script":function(){}},dataFilter:function(e){S.globalEval(e,t,n)}})},S.fn.extend({wrapAll:function(e){var t;return this[0]&&(m(e)&&(e=e.call(this[0])),t=S(e,this[0].ownerDocument).eq(0).clone(!0),this[0].parentNode&&t.insertBefore(this[0]),t.map(function(){var e=this;while(e.firstElementChild)e=e.firstElementChild;return e}).append(this)),this},wrapInner:function(n){return m(n)?this.each(function(e){S(this).wrapInner(n.call(this,e))}):this.each(function(){var e=S(this),t=e.contents();t.length?t.wrapAll(n):e.append(n)})},wrap:function(t){var n=m(t);return this.each(function(e){S(this).wrapAll(n?t.call(this,e):t)})},unwrap:function(e){return this.parent(e).not("body").each(function(){S(this).replaceWith(this.childNodes)}),this}}),S.expr.pseudos.hidden=function(e){return!S.expr.pseudos.visible(e)},S.expr.pseudos.visible=function(e){return!!(e.offsetWidth||e.offsetHeight||e.getClientRects().length)},S.ajaxSettings.xhr=function(){try{return new C.XMLHttpRequest}catch(e){}};var _t={0:200,1223:204},zt=S.ajaxSettings.xhr();v.cors=!!zt&&"withCredentials"in zt,v.ajax=zt=!!zt,S.ajaxTransport(function(i){var o,a;if(v.cors||zt&&!i.crossDomain)return{send:function(e,t){var n,r=i.xhr();if(r.open(i.type,i.url,i.async,i.username,i.password),i.xhrFields)for(n in i.xhrFields)r[n]=i.xhrFields[n];for(n in i.mimeType&&r.overrideMimeType&&r.overrideMimeType(i.mimeType),i.crossDomain||e["X-Requested-With"]||(e["X-Requested-With"]="XMLHttpRequest"),e)r.setRequestHeader(n,e[n]);o=function(e){return function(){o&&(o=a=r.onload=r.onerror=r.onabort=r.ontimeout=r.onreadystatechange=null,"abort"===e?r.abort():"error"===e?"number"!=typeof r.status?t(0,"error"):t(r.status,r.statusText):t(_t[r.status]||r.status,r.statusText,"text"!==(r.responseType||"text")||"string"!=typeof r.responseText?{binary:r.response}:{text:r.responseText},r.getAllResponseHeaders()))}},r.onload=o(),a=r.onerror=r.ontimeout=o("error"),void 0!==r.onabort?r.onabort=a:r.onreadystatechange=function(){4===r.readyState&&C.setTimeout(function(){o&&a()})},o=o("abort");try{r.send(i.hasContent&&i.data||null)}catch(e){if(o)throw e}},abort:function(){o&&o()}}}),S.ajaxPrefilter(function(e){e.crossDomain&&(e.contents.script=!1)}),S.ajaxSetup({accepts:{script:"text/javascript, application/javascript, application/ecmascript, application/x-ecmascript"},contents:{script:/\b(?:java|ecma)script\b/},converters:{"text script":function(e){return S.globalEval(e),e}}}),S.ajaxPrefilter("script",function(e){void 0===e.cache&&(e.cache=!1),e.crossDomain&&(e.type="GET")}),S.ajaxTransport("script",function(n){var r,i;if(n.crossDomain||n.scriptAttrs)return{send:function(e,t){r=S("<script>").attr(n.scriptAttrs||{}).prop({charset:n.scriptCharset,src:n.url}).on("load error",i=function(e){r.remove(),i=null,e&&t("error"===e.type?404:200,e.type)}),E.head.appendChild(r[0])},abort:function(){i&&i()}}});var Ut,Xt=[],Vt=/(=)\?(?=&|$)|\?\?/;S.ajaxSetup({jsonp:"callback",jsonpCallback:function(){var e=Xt.pop()||S.expando+"_"+Ct.guid++;return this[e]=!0,e}}),S.ajaxPrefilter("json jsonp",function(e,t,n){var r,i,o,a=!1!==e.jsonp&&(Vt.test(e.url)?"url":"string"==typeof e.data&&0===(e.contentType||"").indexOf("application/x-www-form-urlencoded")&&Vt.test(e.data)&&"data");if(a||"jsonp"===e.dataTypes[0])return r=e.jsonpCallback=m(e.jsonpCallback)?e.jsonpCallback():e.jsonpCallback,a?e[a]=e[a].replace(Vt,"$1"+r):!1!==e.jsonp&&(e.url+=(Et.test(e.url)?"&":"?")+e.jsonp+"="+r),e.converters["script json"]=function(){return o||S.error(r+" was not called"),o[0]},e.dataTypes[0]="json",i=C[r],C[r]=function(){o=arguments},n.always(function(){void 0===i?S(C).removeProp(r):C[r]=i,e[r]&&(e.jsonpCallback=t.jsonpCallback,Xt.push(r)),o&&m(i)&&i(o[0]),o=i=void 0}),"script"}),v.createHTMLDocument=((Ut=E.implementation.createHTMLDocument("").body).innerHTML="<form></form><form></form>",2===Ut.childNodes.length),S.parseHTML=function(e,t,n){return"string"!=typeof e?[]:("boolean"==typeof t&&(n=t,t=!1),t||(v.createHTMLDocument?((r=(t=E.implementation.createHTMLDocument("")).createElement("base")).href=E.location.href,t.head.appendChild(r)):t=E),o=!n&&[],(i=N.exec(e))?[t.createElement(i[1])]:(i=xe([e],t,o),o&&o.length&&S(o).remove(),S.merge([],i.childNodes)));var r,i,o},S.fn.load=function(e,t,n){var r,i,o,a=this,s=e.indexOf(" ");return-1<s&&(r=yt(e.slice(s)),e=e.slice(0,s)),m(t)?(n=t,t=void 0):t&&"object"==typeof t&&(i="POST"),0<a.length&&S.ajax({url:e,type:i||"GET",dataType:"html",data:t}).done(function(e){o=arguments,a.html(r?S("<div>").append(S.parseHTML(e)).find(r):e)}).always(n&&function(e,t){a.each(function(){n.apply(this,o||[e.responseText,t,e])})}),this},S.expr.pseudos.animated=function(t){return S.grep(S.timers,function(e){return t===e.elem}).length},S.offset={setOffset:function(e,t,n){var r,i,o,a,s,u,l=S.css(e,"position"),c=S(e),f={};"static"===l&&(e.style.position="relative"),s=c.offset(),o=S.css(e,"top"),u=S.css(e,"left"),("absolute"===l||"fixed"===l)&&-1<(o+u).indexOf("auto")?(a=(r=c.position()).top,i=r.left):(a=parseFloat(o)||0,i=parseFloat(u)||0),m(t)&&(t=t.call(e,n,S.extend({},s))),null!=t.top&&(f.top=t.top-s.top+a),null!=t.left&&(f.left=t.left-s.left+i),"using"in t?t.using.call(e,f):c.css(f)}},S.fn.extend({offset:function(t){if(arguments.length)return void 0===t?this:this.each(function(e){S.offset.setOffset(this,t,e)});var e,n,r=this[0];return r?r.getClientRects().length?(e=r.getBoundingClientRect(),n=r.ownerDocument.defaultView,{top:e.top+n.pageYOffset,left:e.left+n.pageXOffset}):{top:0,left:0}:void 0},position:function(){if(this[0]){var e,t,n,r=this[0],i={top:0,left:0};if("fixed"===S.css(r,"position"))t=r.getBoundingClientRect();else{t=this.offset(),n=r.ownerDocument,e=r.offsetParent||n.documentElement;while(e&&(e===n.body||e===n.documentElement)&&"static"===S.css(e,"position"))e=e.parentNode;e&&e!==r&&1===e.nodeType&&((i=S(e).offset()).top+=S.css(e,"borderTopWidth",!0),i.left+=S.css(e,"borderLeftWidth",!0))}return{top:t.top-i.top-S.css(r,"marginTop",!0),left:t.left-i.left-S.css(r,"marginLeft",!0)}}},offsetParent:function(){return this.map(function(){var e=this.offsetParent;while(e&&"static"===S.css(e,"position"))e=e.offsetParent;return e||re})}}),S.each({scrollLeft:"pageXOffset",scrollTop:"pageYOffset"},function(t,i){var o="pageYOffset"===i;S.fn[t]=function(e){return B(this,function(e,t,n){var r;if(x(e)?r=e:9===e.nodeType&&(r=e.defaultView),void 0===n)return r?r[i]:e[t];r?r.scrollTo(o?r.pageXOffset:n,o?n:r.pageYOffset):e[t]=n},t,e,arguments.length)}}),S.each(["top","left"],function(e,n){S.cssHooks[n]=_e(v.pixelPosition,function(e,t){if(t)return t=Be(e,n),Pe.test(t)?S(e).position()[n]+"px":t})}),S.each({Height:"height",Width:"width"},function(a,s){S.each({padding:"inner"+a,content:s,"":"outer"+a},function(r,o){S.fn[o]=function(e,t){var n=arguments.length&&(r||"boolean"!=typeof e),i=r||(!0===e||!0===t?"margin":"border");return B(this,function(e,t,n){var r;return x(e)?0===o.indexOf("outer")?e["inner"+a]:e.document.documentElement["client"+a]:9===e.nodeType?(r=e.documentElement,Math.max(e.body["scroll"+a],r["scroll"+a],e.body["offset"+a],r["offset"+a],r["client"+a])):void 0===n?S.css(e,t,i):S.style(e,t,n,i)},s,n?e:void 0,n)}})}),S.each(["ajaxStart","ajaxStop","ajaxComplete","ajaxError","ajaxSuccess","ajaxSend"],function(e,t){S.fn[t]=function(e){return this.on(t,e)}}),S.fn.extend({bind:function(e,t,n){return this.on(e,null,t,n)},unbind:function(e,t){return this.off(e,null,t)},delegate:function(e,t,n,r){return this.on(t,e,n,r)},undelegate:function(e,t,n){return 1===arguments.length?this.off(e,"**"):this.off(t,e||"**",n)},hover:function(e,t){return this.mouseenter(e).mouseleave(t||e)}}),S.each("blur focus focusin focusout resize scroll click dblclick mousedown mouseup mousemove mouseover mouseout mouseenter mouseleave change select submit keydown keypress keyup contextmenu".split(" "),function(e,n){S.fn[n]=function(e,t){return 0<arguments.length?this.on(n,null,e,t):this.trigger(n)}});var Gt=/^[\s\uFEFF\xA0]+|([^\s\uFEFF\xA0])[\s\uFEFF\xA0]+$/g;S.proxy=function(e,t){var n,r,i;if("string"==typeof t&&(n=e[t],t=e,e=n),m(e))return r=s.call(arguments,2),(i=function(){return e.apply(t||this,r.concat(s.call(arguments)))}).guid=e.guid=e.guid||S.guid++,i},S.holdReady=function(e){e?S.readyWait++:S.ready(!0)},S.isArray=Array.isArray,S.parseJSON=JSON.parse,S.nodeName=A,S.isFunction=m,S.isWindow=x,S.camelCase=X,S.type=w,S.now=Date.now,S.isNumeric=function(e){var t=S.type(e);return("number"===t||"string"===t)&&!isNaN(e-parseFloat(e))},S.trim=function(e){return null==e?"":(e+"").replace(Gt,"$1")},"function"==typeof define&&define.amd&&define("jquery",[],function(){return S});var Yt=C.jQuery,Qt=C.$;return S.noConflict=function(e){return C.$===S&&(C.$=Qt),e&&C.jQuery===S&&(C.jQuery=Yt),S},"undefined"==typeof e&&(C.jQuery=C.$=S),S});
		</script>
		<script>
			//src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js" integrity="sha384-ka7Sk0Gln4gmtz2MlQnikT1wXgYsOg+OMhuP+IlRH9sENBO0LRn5q+8nbTov4+1p" crossorigin="anonymous"
			/*!
				* Bootstrap v5.1.3 (https://getbootstrap.com/)
				* Copyright 2011-2021 The Bootstrap Authors (https://github.com/twbs/bootstrap/graphs/contributors)
				* Licensed under MIT (https://github.com/twbs/bootstrap/blob/main/LICENSE)
			*/
			!function(t,e){"object"==typeof exports&&"undefined"!=typeof module?module.exports=e(require("@popperjs/core")):"function"==typeof define&&define.amd?define(["@popperjs/core"],e):(t="undefined"!=typeof globalThis?globalThis:t||self).bootstrap=e(t.Popper)}(this,(function(t){"use strict";function e(t){if(t&&t.__esModule)return t;const e=Object.create(null);if(t)for(const i in t)if("default"!==i){const s=Object.getOwnPropertyDescriptor(t,i);Object.defineProperty(e,i,s.get?s:{enumerable:!0,get:()=>t[i]})}return e.default=t,Object.freeze(e)}const i=e(t),s="transitionend",n=t=>{let e=t.getAttribute("data-bs-target");if(!e||"#"===e){let i=t.getAttribute("href");if(!i||!i.includes("#")&&!i.startsWith("."))return null;i.includes("#")&&!i.startsWith("#")&&(i=`#${i.split("#")[1]}`),e=i&&"#"!==i?i.trim():null}return e},o=t=>{const e=n(t);return e&&document.querySelector(e)?e:null},r=t=>{const e=n(t);return e?document.querySelector(e):null},a=t=>{t.dispatchEvent(new Event(s))},l=t=>!(!t||"object"!=typeof t)&&(void 0!==t.jquery&&(t=t[0]),void 0!==t.nodeType),c=t=>l(t)?t.jquery?t[0]:t:"string"==typeof t&&t.length>0?document.querySelector(t):null,h=(t,e,i)=>{Object.keys(i).forEach((s=>{const n=i[s],o=e[s],r=o&&l(o)?"element":null==(a=o)?`${a}`:{}.toString.call(a).match(/\s([a-z]+)/i)[1].toLowerCase();var a;if(!new RegExp(n).test(r))throw new TypeError(`${t.toUpperCase()}: Option "${s}" provided type "${r}" but expected type "${n}".`)}))},d=t=>!(!l(t)||0===t.getClientRects().length)&&"visible"===getComputedStyle(t).getPropertyValue("visibility"),u=t=>!t||t.nodeType!==Node.ELEMENT_NODE||!!t.classList.contains("disabled")||(void 0!==t.disabled?t.disabled:t.hasAttribute("disabled")&&"false"!==t.getAttribute("disabled")),g=t=>{if(!document.documentElement.attachShadow)return null;if("function"==typeof t.getRootNode){const e=t.getRootNode();return e instanceof ShadowRoot?e:null}return t instanceof ShadowRoot?t:t.parentNode?g(t.parentNode):null},_=()=>{},f=t=>{t.offsetHeight},p=()=>{const{jQuery:t}=window;return t&&!document.body.hasAttribute("data-bs-no-jquery")?t:null},m=[],b=()=>"rtl"===document.documentElement.dir,v=t=>{var e;e=()=>{const e=p();if(e){const i=t.NAME,s=e.fn[i];e.fn[i]=t.jQueryInterface,e.fn[i].Constructor=t,e.fn[i].noConflict=()=>(e.fn[i]=s,t.jQueryInterface)}},"loading"===document.readyState?(m.length||document.addEventListener("DOMContentLoaded",(()=>{m.forEach((t=>t()))})),m.push(e)):e()},y=t=>{"function"==typeof t&&t()},E=(t,e,i=!0)=>{if(!i)return void y(t);const n=(t=>{if(!t)return 0;let{transitionDuration:e,transitionDelay:i}=window.getComputedStyle(t);const s=Number.parseFloat(e),n=Number.parseFloat(i);return s||n?(e=e.split(",")[0],i=i.split(",")[0],1e3*(Number.parseFloat(e)+Number.parseFloat(i))):0})(e)+5;let o=!1;const r=({target:i})=>{i===e&&(o=!0,e.removeEventListener(s,r),y(t))};e.addEventListener(s,r),setTimeout((()=>{o||a(e)}),n)},w=(t,e,i,s)=>{let n=t.indexOf(e);if(-1===n)return t[!i&&s?t.length-1:0];const o=t.length;return n+=i?1:-1,s&&(n=(n+o)%o),t[Math.max(0,Math.min(n,o-1))]},A=/[^.]*(?=\..*)\.|.*/,T=/\..*/,C=/::\d+$/,k={};let L=1;const S={mouseenter:"mouseover",mouseleave:"mouseout"},O=/^(mouseenter|mouseleave)/i,N=new Set(["click","dblclick","mouseup","mousedown","contextmenu","mousewheel","DOMMouseScroll","mouseover","mouseout","mousemove","selectstart","selectend","keydown","keypress","keyup","orientationchange","touchstart","touchmove","touchend","touchcancel","pointerdown","pointermove","pointerup","pointerleave","pointercancel","gesturestart","gesturechange","gestureend","focus","blur","change","reset","select","submit","focusin","focusout","load","unload","beforeunload","resize","move","DOMContentLoaded","readystatechange","error","abort","scroll"]);function D(t,e){return e&&`${e}::${L++}`||t.uidEvent||L++}function I(t){const e=D(t);return t.uidEvent=e,k[e]=k[e]||{},k[e]}function P(t,e,i=null){const s=Object.keys(t);for(let n=0,o=s.length;n<o;n++){const o=t[s[n]];if(o.originalHandler===e&&o.delegationSelector===i)return o}return null}function x(t,e,i){const s="string"==typeof e,n=s?i:e;let o=H(t);return N.has(o)||(o=t),[s,n,o]}function M(t,e,i,s,n){if("string"!=typeof e||!t)return;if(i||(i=s,s=null),O.test(e)){const t=t=>function(e){if(!e.relatedTarget||e.relatedTarget!==e.delegateTarget&&!e.delegateTarget.contains(e.relatedTarget))return t.call(this,e)};s?s=t(s):i=t(i)}const[o,r,a]=x(e,i,s),l=I(t),c=l[a]||(l[a]={}),h=P(c,r,o?i:null);if(h)return void(h.oneOff=h.oneOff&&n);const d=D(r,e.replace(A,"")),u=o?function(t,e,i){return function s(n){const o=t.querySelectorAll(e);for(let{target:r}=n;r&&r!==this;r=r.parentNode)for(let a=o.length;a--;)if(o[a]===r)return n.delegateTarget=r,s.oneOff&&$.off(t,n.type,e,i),i.apply(r,[n]);return null}}(t,i,s):function(t,e){return function i(s){return s.delegateTarget=t,i.oneOff&&$.off(t,s.type,e),e.apply(t,[s])}}(t,i);u.delegationSelector=o?i:null,u.originalHandler=r,u.oneOff=n,u.uidEvent=d,c[d]=u,t.addEventListener(a,u,o)}function j(t,e,i,s,n){const o=P(e[i],s,n);o&&(t.removeEventListener(i,o,Boolean(n)),delete e[i][o.uidEvent])}function H(t){return t=t.replace(T,""),S[t]||t}const $={on(t,e,i,s){M(t,e,i,s,!1)},one(t,e,i,s){M(t,e,i,s,!0)},off(t,e,i,s){if("string"!=typeof e||!t)return;const[n,o,r]=x(e,i,s),a=r!==e,l=I(t),c=e.startsWith(".");if(void 0!==o){if(!l||!l[r])return;return void j(t,l,r,o,n?i:null)}c&&Object.keys(l).forEach((i=>{!function(t,e,i,s){const n=e[i]||{};Object.keys(n).forEach((o=>{if(o.includes(s)){const s=n[o];j(t,e,i,s.originalHandler,s.delegationSelector)}}))}(t,l,i,e.slice(1))}));const h=l[r]||{};Object.keys(h).forEach((i=>{const s=i.replace(C,"");if(!a||e.includes(s)){const e=h[i];j(t,l,r,e.originalHandler,e.delegationSelector)}}))},trigger(t,e,i){if("string"!=typeof e||!t)return null;const s=p(),n=H(e),o=e!==n,r=N.has(n);let a,l=!0,c=!0,h=!1,d=null;return o&&s&&(a=s.Event(e,i),s(t).trigger(a),l=!a.isPropagationStopped(),c=!a.isImmediatePropagationStopped(),h=a.isDefaultPrevented()),r?(d=document.createEvent("HTMLEvents"),d.initEvent(n,l,!0)):d=new CustomEvent(e,{bubbles:l,cancelable:!0}),void 0!==i&&Object.keys(i).forEach((t=>{Object.defineProperty(d,t,{get:()=>i[t]})})),h&&d.preventDefault(),c&&t.dispatchEvent(d),d.defaultPrevented&&void 0!==a&&a.preventDefault(),d}},B=new Map,z={set(t,e,i){B.has(t)||B.set(t,new Map);const s=B.get(t);s.has(e)||0===s.size?s.set(e,i):console.error(`Bootstrap doesn't allow more than one instance per element. Bound instance: ${Array.from(s.keys())[0]}.`)},get:(t,e)=>B.has(t)&&B.get(t).get(e)||null,remove(t,e){if(!B.has(t))return;const i=B.get(t);i.delete(e),0===i.size&&B.delete(t)}};class R{constructor(t){(t=c(t))&&(this._element=t,z.set(this._element,this.constructor.DATA_KEY,this))}dispose(){z.remove(this._element,this.constructor.DATA_KEY),$.off(this._element,this.constructor.EVENT_KEY),Object.getOwnPropertyNames(this).forEach((t=>{this[t]=null}))}_queueCallback(t,e,i=!0){E(t,e,i)}static getInstance(t){return z.get(c(t),this.DATA_KEY)}static getOrCreateInstance(t,e={}){return this.getInstance(t)||new this(t,"object"==typeof e?e:null)}static get VERSION(){return"5.1.3"}static get NAME(){throw new Error('You have to implement the static method "NAME", for each component!')}static get DATA_KEY(){return`bs.${this.NAME}`}static get EVENT_KEY(){return`.${this.DATA_KEY}`}}const F=(t,e="hide")=>{const i=`click.dismiss${t.EVENT_KEY}`,s=t.NAME;$.on(document,i,`[data-bs-dismiss="${s}"]`,(function(i){if(["A","AREA"].includes(this.tagName)&&i.preventDefault(),u(this))return;const n=r(this)||this.closest(`.${s}`);t.getOrCreateInstance(n)[e]()}))};class q extends R{static get NAME(){return"alert"}close(){if($.trigger(this._element,"close.bs.alert").defaultPrevented)return;this._element.classList.remove("show");const t=this._element.classList.contains("fade");this._queueCallback((()=>this._destroyElement()),this._element,t)}_destroyElement(){this._element.remove(),$.trigger(this._element,"closed.bs.alert"),this.dispose()}static jQueryInterface(t){return this.each((function(){const e=q.getOrCreateInstance(this);if("string"==typeof t){if(void 0===e[t]||t.startsWith("_")||"constructor"===t)throw new TypeError(`No method named "${t}"`);e[t](this)}}))}}F(q,"close"),v(q);const W='[data-bs-toggle="button"]';class U extends R{static get NAME(){return"button"}toggle(){this._element.setAttribute("aria-pressed",this._element.classList.toggle("active"))}static jQueryInterface(t){return this.each((function(){const e=U.getOrCreateInstance(this);"toggle"===t&&e[t]()}))}}function K(t){return"true"===t||"false"!==t&&(t===Number(t).toString()?Number(t):""===t||"null"===t?null:t)}function V(t){return t.replace(/[A-Z]/g,(t=>`-${t.toLowerCase()}`))}$.on(document,"click.bs.button.data-api",W,(t=>{t.preventDefault();const e=t.target.closest(W);U.getOrCreateInstance(e).toggle()})),v(U);const X={setDataAttribute(t,e,i){t.setAttribute(`data-bs-${V(e)}`,i)},removeDataAttribute(t,e){t.removeAttribute(`data-bs-${V(e)}`)},getDataAttributes(t){if(!t)return{};const e={};return Object.keys(t.dataset).filter((t=>t.startsWith("bs"))).forEach((i=>{let s=i.replace(/^bs/,"");s=s.charAt(0).toLowerCase()+s.slice(1,s.length),e[s]=K(t.dataset[i])})),e},getDataAttribute:(t,e)=>K(t.getAttribute(`data-bs-${V(e)}`)),offset(t){const e=t.getBoundingClientRect();return{top:e.top+window.pageYOffset,left:e.left+window.pageXOffset}},position:t=>({top:t.offsetTop,left:t.offsetLeft})},Y={find:(t,e=document.documentElement)=>[].concat(...Element.prototype.querySelectorAll.call(e,t)),findOne:(t,e=document.documentElement)=>Element.prototype.querySelector.call(e,t),children:(t,e)=>[].concat(...t.children).filter((t=>t.matches(e))),parents(t,e){const i=[];let s=t.parentNode;for(;s&&s.nodeType===Node.ELEMENT_NODE&&3!==s.nodeType;)s.matches(e)&&i.push(s),s=s.parentNode;return i},prev(t,e){let i=t.previousElementSibling;for(;i;){if(i.matches(e))return[i];i=i.previousElementSibling}return[]},next(t,e){let i=t.nextElementSibling;for(;i;){if(i.matches(e))return[i];i=i.nextElementSibling}return[]},focusableChildren(t){const e=["a","button","input","textarea","select","details","[tabindex]",'[contenteditable="true"]'].map((t=>`${t}:not([tabindex^="-"])`)).join(", ");return this.find(e,t).filter((t=>!u(t)&&d(t)))}},Q="carousel",G={interval:5e3,keyboard:!0,slide:!1,pause:"hover",wrap:!0,touch:!0},Z={interval:"(number|boolean)",keyboard:"boolean",slide:"(boolean|string)",pause:"(string|boolean)",wrap:"boolean",touch:"boolean"},J="next",tt="prev",et="left",it="right",st={ArrowLeft:it,ArrowRight:et},nt="slid.bs.carousel",ot="active",rt=".active.carousel-item";class at extends R{constructor(t,e){super(t),this._items=null,this._interval=null,this._activeElement=null,this._isPaused=!1,this._isSliding=!1,this.touchTimeout=null,this.touchStartX=0,this.touchDeltaX=0,this._config=this._getConfig(e),this._indicatorsElement=Y.findOne(".carousel-indicators",this._element),this._touchSupported="ontouchstart"in document.documentElement||navigator.maxTouchPoints>0,this._pointerEvent=Boolean(window.PointerEvent),this._addEventListeners()}static get Default(){return G}static get NAME(){return Q}next(){this._slide(J)}nextWhenVisible(){!document.hidden&&d(this._element)&&this.next()}prev(){this._slide(tt)}pause(t){t||(this._isPaused=!0),Y.findOne(".carousel-item-next, .carousel-item-prev",this._element)&&(a(this._element),this.cycle(!0)),clearInterval(this._interval),this._interval=null}cycle(t){t||(this._isPaused=!1),this._interval&&(clearInterval(this._interval),this._interval=null),this._config&&this._config.interval&&!this._isPaused&&(this._updateInterval(),this._interval=setInterval((document.visibilityState?this.nextWhenVisible:this.next).bind(this),this._config.interval))}to(t){this._activeElement=Y.findOne(rt,this._element);const e=this._getItemIndex(this._activeElement);if(t>this._items.length-1||t<0)return;if(this._isSliding)return void $.one(this._element,nt,(()=>this.to(t)));if(e===t)return this.pause(),void this.cycle();const i=t>e?J:tt;this._slide(i,this._items[t])}_getConfig(t){return t={...G,...X.getDataAttributes(this._element),..."object"==typeof t?t:{}},h(Q,t,Z),t}_handleSwipe(){const t=Math.abs(this.touchDeltaX);if(t<=40)return;const e=t/this.touchDeltaX;this.touchDeltaX=0,e&&this._slide(e>0?it:et)}_addEventListeners(){this._config.keyboard&&$.on(this._element,"keydown.bs.carousel",(t=>this._keydown(t))),"hover"===this._config.pause&&($.on(this._element,"mouseenter.bs.carousel",(t=>this.pause(t))),$.on(this._element,"mouseleave.bs.carousel",(t=>this.cycle(t)))),this._config.touch&&this._touchSupported&&this._addTouchEventListeners()}_addTouchEventListeners(){const t=t=>this._pointerEvent&&("pen"===t.pointerType||"touch"===t.pointerType),e=e=>{t(e)?this.touchStartX=e.clientX:this._pointerEvent||(this.touchStartX=e.touches[0].clientX)},i=t=>{this.touchDeltaX=t.touches&&t.touches.length>1?0:t.touches[0].clientX-this.touchStartX},s=e=>{t(e)&&(this.touchDeltaX=e.clientX-this.touchStartX),this._handleSwipe(),"hover"===this._config.pause&&(this.pause(),this.touchTimeout&&clearTimeout(this.touchTimeout),this.touchTimeout=setTimeout((t=>this.cycle(t)),500+this._config.interval))};Y.find(".carousel-item img",this._element).forEach((t=>{$.on(t,"dragstart.bs.carousel",(t=>t.preventDefault()))})),this._pointerEvent?($.on(this._element,"pointerdown.bs.carousel",(t=>e(t))),$.on(this._element,"pointerup.bs.carousel",(t=>s(t))),this._element.classList.add("pointer-event")):($.on(this._element,"touchstart.bs.carousel",(t=>e(t))),$.on(this._element,"touchmove.bs.carousel",(t=>i(t))),$.on(this._element,"touchend.bs.carousel",(t=>s(t))))}_keydown(t){if(/input|textarea/i.test(t.target.tagName))return;const e=st[t.key];e&&(t.preventDefault(),this._slide(e))}_getItemIndex(t){return this._items=t&&t.parentNode?Y.find(".carousel-item",t.parentNode):[],this._items.indexOf(t)}_getItemByOrder(t,e){const i=t===J;return w(this._items,e,i,this._config.wrap)}_triggerSlideEvent(t,e){const i=this._getItemIndex(t),s=this._getItemIndex(Y.findOne(rt,this._element));return $.trigger(this._element,"slide.bs.carousel",{relatedTarget:t,direction:e,from:s,to:i})}_setActiveIndicatorElement(t){if(this._indicatorsElement){const e=Y.findOne(".active",this._indicatorsElement);e.classList.remove(ot),e.removeAttribute("aria-current");const i=Y.find("[data-bs-target]",this._indicatorsElement);for(let e=0;e<i.length;e++)if(Number.parseInt(i[e].getAttribute("data-bs-slide-to"),10)===this._getItemIndex(t)){i[e].classList.add(ot),i[e].setAttribute("aria-current","true");break}}}_updateInterval(){const t=this._activeElement||Y.findOne(rt,this._element);if(!t)return;const e=Number.parseInt(t.getAttribute("data-bs-interval"),10);e?(this._config.defaultInterval=this._config.defaultInterval||this._config.interval,this._config.interval=e):this._config.interval=this._config.defaultInterval||this._config.interval}_slide(t,e){const i=this._directionToOrder(t),s=Y.findOne(rt,this._element),n=this._getItemIndex(s),o=e||this._getItemByOrder(i,s),r=this._getItemIndex(o),a=Boolean(this._interval),l=i===J,c=l?"carousel-item-start":"carousel-item-end",h=l?"carousel-item-next":"carousel-item-prev",d=this._orderToDirection(i);if(o&&o.classList.contains(ot))return void(this._isSliding=!1);if(this._isSliding)return;if(this._triggerSlideEvent(o,d).defaultPrevented)return;if(!s||!o)return;this._isSliding=!0,a&&this.pause(),this._setActiveIndicatorElement(o),this._activeElement=o;const u=()=>{$.trigger(this._element,nt,{relatedTarget:o,direction:d,from:n,to:r})};if(this._element.classList.contains("slide")){o.classList.add(h),f(o),s.classList.add(c),o.classList.add(c);const t=()=>{o.classList.remove(c,h),o.classList.add(ot),s.classList.remove(ot,h,c),this._isSliding=!1,setTimeout(u,0)};this._queueCallback(t,s,!0)}else s.classList.remove(ot),o.classList.add(ot),this._isSliding=!1,u();a&&this.cycle()}_directionToOrder(t){return[it,et].includes(t)?b()?t===et?tt:J:t===et?J:tt:t}_orderToDirection(t){return[J,tt].includes(t)?b()?t===tt?et:it:t===tt?it:et:t}static carouselInterface(t,e){const i=at.getOrCreateInstance(t,e);let{_config:s}=i;"object"==typeof e&&(s={...s,...e});const n="string"==typeof e?e:s.slide;if("number"==typeof e)i.to(e);else if("string"==typeof n){if(void 0===i[n])throw new TypeError(`No method named "${n}"`);i[n]()}else s.interval&&s.ride&&(i.pause(),i.cycle())}static jQueryInterface(t){return this.each((function(){at.carouselInterface(this,t)}))}static dataApiClickHandler(t){const e=r(this);if(!e||!e.classList.contains("carousel"))return;const i={...X.getDataAttributes(e),...X.getDataAttributes(this)},s=this.getAttribute("data-bs-slide-to");s&&(i.interval=!1),at.carouselInterface(e,i),s&&at.getInstance(e).to(s),t.preventDefault()}}$.on(document,"click.bs.carousel.data-api","[data-bs-slide], [data-bs-slide-to]",at.dataApiClickHandler),$.on(window,"load.bs.carousel.data-api",(()=>{const t=Y.find('[data-bs-ride="carousel"]');for(let e=0,i=t.length;e<i;e++)at.carouselInterface(t[e],at.getInstance(t[e]))})),v(at);const lt="collapse",ct={toggle:!0,parent:null},ht={toggle:"boolean",parent:"(null|element)"},dt="show",ut="collapse",gt="collapsing",_t="collapsed",ft=":scope .collapse .collapse",pt='[data-bs-toggle="collapse"]';class mt extends R{constructor(t,e){super(t),this._isTransitioning=!1,this._config=this._getConfig(e),this._triggerArray=[];const i=Y.find(pt);for(let t=0,e=i.length;t<e;t++){const e=i[t],s=o(e),n=Y.find(s).filter((t=>t===this._element));null!==s&&n.length&&(this._selector=s,this._triggerArray.push(e))}this._initializeChildren(),this._config.parent||this._addAriaAndCollapsedClass(this._triggerArray,this._isShown()),this._config.toggle&&this.toggle()}static get Default(){return ct}static get NAME(){return lt}toggle(){this._isShown()?this.hide():this.show()}show(){if(this._isTransitioning||this._isShown())return;let t,e=[];if(this._config.parent){const t=Y.find(ft,this._config.parent);e=Y.find(".collapse.show, .collapse.collapsing",this._config.parent).filter((e=>!t.includes(e)))}const i=Y.findOne(this._selector);if(e.length){const s=e.find((t=>i!==t));if(t=s?mt.getInstance(s):null,t&&t._isTransitioning)return}if($.trigger(this._element,"show.bs.collapse").defaultPrevented)return;e.forEach((e=>{i!==e&&mt.getOrCreateInstance(e,{toggle:!1}).hide(),t||z.set(e,"bs.collapse",null)}));const s=this._getDimension();this._element.classList.remove(ut),this._element.classList.add(gt),this._element.style[s]=0,this._addAriaAndCollapsedClass(this._triggerArray,!0),this._isTransitioning=!0;const n=`scroll${s[0].toUpperCase()+s.slice(1)}`;this._queueCallback((()=>{this._isTransitioning=!1,this._element.classList.remove(gt),this._element.classList.add(ut,dt),this._element.style[s]="",$.trigger(this._element,"shown.bs.collapse")}),this._element,!0),this._element.style[s]=`${this._element[n]}px`}hide(){if(this._isTransitioning||!this._isShown())return;if($.trigger(this._element,"hide.bs.collapse").defaultPrevented)return;const t=this._getDimension();this._element.style[t]=`${this._element.getBoundingClientRect()[t]}px`,f(this._element),this._element.classList.add(gt),this._element.classList.remove(ut,dt);const e=this._triggerArray.length;for(let t=0;t<e;t++){const e=this._triggerArray[t],i=r(e);i&&!this._isShown(i)&&this._addAriaAndCollapsedClass([e],!1)}this._isTransitioning=!0,this._element.style[t]="",this._queueCallback((()=>{this._isTransitioning=!1,this._element.classList.remove(gt),this._element.classList.add(ut),$.trigger(this._element,"hidden.bs.collapse")}),this._element,!0)}_isShown(t=this._element){return t.classList.contains(dt)}_getConfig(t){return(t={...ct,...X.getDataAttributes(this._element),...t}).toggle=Boolean(t.toggle),t.parent=c(t.parent),h(lt,t,ht),t}_getDimension(){return this._element.classList.contains("collapse-horizontal")?"width":"height"}_initializeChildren(){if(!this._config.parent)return;const t=Y.find(ft,this._config.parent);Y.find(pt,this._config.parent).filter((e=>!t.includes(e))).forEach((t=>{const e=r(t);e&&this._addAriaAndCollapsedClass([t],this._isShown(e))}))}_addAriaAndCollapsedClass(t,e){t.length&&t.forEach((t=>{e?t.classList.remove(_t):t.classList.add(_t),t.setAttribute("aria-expanded",e)}))}static jQueryInterface(t){return this.each((function(){const e={};"string"==typeof t&&/show|hide/.test(t)&&(e.toggle=!1);const i=mt.getOrCreateInstance(this,e);if("string"==typeof t){if(void 0===i[t])throw new TypeError(`No method named "${t}"`);i[t]()}}))}}$.on(document,"click.bs.collapse.data-api",pt,(function(t){("A"===t.target.tagName||t.delegateTarget&&"A"===t.delegateTarget.tagName)&&t.preventDefault();const e=o(this);Y.find(e).forEach((t=>{mt.getOrCreateInstance(t,{toggle:!1}).toggle()}))})),v(mt);const bt="dropdown",vt="Escape",yt="Space",Et="ArrowUp",wt="ArrowDown",At=new RegExp("ArrowUp|ArrowDown|Escape"),Tt="click.bs.dropdown.data-api",Ct="keydown.bs.dropdown.data-api",kt="show",Lt='[data-bs-toggle="dropdown"]',St=".dropdown-menu",Ot=b()?"top-end":"top-start",Nt=b()?"top-start":"top-end",Dt=b()?"bottom-end":"bottom-start",It=b()?"bottom-start":"bottom-end",Pt=b()?"left-start":"right-start",xt=b()?"right-start":"left-start",Mt={offset:[0,2],boundary:"clippingParents",reference:"toggle",display:"dynamic",popperConfig:null,autoClose:!0},jt={offset:"(array|string|function)",boundary:"(string|element)",reference:"(string|element|object)",display:"string",popperConfig:"(null|object|function)",autoClose:"(boolean|string)"};class Ht extends R{constructor(t,e){super(t),this._popper=null,this._config=this._getConfig(e),this._menu=this._getMenuElement(),this._inNavbar=this._detectNavbar()}static get Default(){return Mt}static get DefaultType(){return jt}static get NAME(){return bt}toggle(){return this._isShown()?this.hide():this.show()}show(){if(u(this._element)||this._isShown(this._menu))return;const t={relatedTarget:this._element};if($.trigger(this._element,"show.bs.dropdown",t).defaultPrevented)return;const e=Ht.getParentFromElement(this._element);this._inNavbar?X.setDataAttribute(this._menu,"popper","none"):this._createPopper(e),"ontouchstart"in document.documentElement&&!e.closest(".navbar-nav")&&[].concat(...document.body.children).forEach((t=>$.on(t,"mouseover",_))),this._element.focus(),this._element.setAttribute("aria-expanded",!0),this._menu.classList.add(kt),this._element.classList.add(kt),$.trigger(this._element,"shown.bs.dropdown",t)}hide(){if(u(this._element)||!this._isShown(this._menu))return;const t={relatedTarget:this._element};this._completeHide(t)}dispose(){this._popper&&this._popper.destroy(),super.dispose()}update(){this._inNavbar=this._detectNavbar(),this._popper&&this._popper.update()}_completeHide(t){$.trigger(this._element,"hide.bs.dropdown",t).defaultPrevented||("ontouchstart"in document.documentElement&&[].concat(...document.body.children).forEach((t=>$.off(t,"mouseover",_))),this._popper&&this._popper.destroy(),this._menu.classList.remove(kt),this._element.classList.remove(kt),this._element.setAttribute("aria-expanded","false"),X.removeDataAttribute(this._menu,"popper"),$.trigger(this._element,"hidden.bs.dropdown",t))}_getConfig(t){if(t={...this.constructor.Default,...X.getDataAttributes(this._element),...t},h(bt,t,this.constructor.DefaultType),"object"==typeof t.reference&&!l(t.reference)&&"function"!=typeof t.reference.getBoundingClientRect)throw new TypeError(`${bt.toUpperCase()}: Option "reference" provided type "object" without a required "getBoundingClientRect" method.`);return t}_createPopper(t){if(void 0===i)throw new TypeError("Bootstrap's dropdowns require Popper (https://popper.js.org)");let e=this._element;"parent"===this._config.reference?e=t:l(this._config.reference)?e=c(this._config.reference):"object"==typeof this._config.reference&&(e=this._config.reference);const s=this._getPopperConfig(),n=s.modifiers.find((t=>"applyStyles"===t.name&&!1===t.enabled));this._popper=i.createPopper(e,this._menu,s),n&&X.setDataAttribute(this._menu,"popper","static")}_isShown(t=this._element){return t.classList.contains(kt)}_getMenuElement(){return Y.next(this._element,St)[0]}_getPlacement(){const t=this._element.parentNode;if(t.classList.contains("dropend"))return Pt;if(t.classList.contains("dropstart"))return xt;const e="end"===getComputedStyle(this._menu).getPropertyValue("--bs-position").trim();return t.classList.contains("dropup")?e?Nt:Ot:e?It:Dt}_detectNavbar(){return null!==this._element.closest(".navbar")}_getOffset(){const{offset:t}=this._config;return"string"==typeof t?t.split(",").map((t=>Number.parseInt(t,10))):"function"==typeof t?e=>t(e,this._element):t}_getPopperConfig(){const t={placement:this._getPlacement(),modifiers:[{name:"preventOverflow",options:{boundary:this._config.boundary}},{name:"offset",options:{offset:this._getOffset()}}]};return"static"===this._config.display&&(t.modifiers=[{name:"applyStyles",enabled:!1}]),{...t,..."function"==typeof this._config.popperConfig?this._config.popperConfig(t):this._config.popperConfig}}_selectMenuItem({key:t,target:e}){const i=Y.find(".dropdown-menu .dropdown-item:not(.disabled):not(:disabled)",this._menu).filter(d);i.length&&w(i,e,t===wt,!i.includes(e)).focus()}static jQueryInterface(t){return this.each((function(){const e=Ht.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t]()}}))}static clearMenus(t){if(t&&(2===t.button||"keyup"===t.type&&"Tab"!==t.key))return;const e=Y.find(Lt);for(let i=0,s=e.length;i<s;i++){const s=Ht.getInstance(e[i]);if(!s||!1===s._config.autoClose)continue;if(!s._isShown())continue;const n={relatedTarget:s._element};if(t){const e=t.composedPath(),i=e.includes(s._menu);if(e.includes(s._element)||"inside"===s._config.autoClose&&!i||"outside"===s._config.autoClose&&i)continue;if(s._menu.contains(t.target)&&("keyup"===t.type&&"Tab"===t.key||/input|select|option|textarea|form/i.test(t.target.tagName)))continue;"click"===t.type&&(n.clickEvent=t)}s._completeHide(n)}}static getParentFromElement(t){return r(t)||t.parentNode}static dataApiKeydownHandler(t){if(/input|textarea/i.test(t.target.tagName)?t.key===yt||t.key!==vt&&(t.key!==wt&&t.key!==Et||t.target.closest(St)):!At.test(t.key))return;const e=this.classList.contains(kt);if(!e&&t.key===vt)return;if(t.preventDefault(),t.stopPropagation(),u(this))return;const i=this.matches(Lt)?this:Y.prev(this,Lt)[0],s=Ht.getOrCreateInstance(i);if(t.key!==vt)return t.key===Et||t.key===wt?(e||s.show(),void s._selectMenuItem(t)):void(e&&t.key!==yt||Ht.clearMenus());s.hide()}}$.on(document,Ct,Lt,Ht.dataApiKeydownHandler),$.on(document,Ct,St,Ht.dataApiKeydownHandler),$.on(document,Tt,Ht.clearMenus),$.on(document,"keyup.bs.dropdown.data-api",Ht.clearMenus),$.on(document,Tt,Lt,(function(t){t.preventDefault(),Ht.getOrCreateInstance(this).toggle()})),v(Ht);const $t=".fixed-top, .fixed-bottom, .is-fixed, .sticky-top",Bt=".sticky-top";class zt{constructor(){this._element=document.body}getWidth(){const t=document.documentElement.clientWidth;return Math.abs(window.innerWidth-t)}hide(){const t=this.getWidth();this._disableOverFlow(),this._setElementAttributes(this._element,"paddingRight",(e=>e+t)),this._setElementAttributes($t,"paddingRight",(e=>e+t)),this._setElementAttributes(Bt,"marginRight",(e=>e-t))}_disableOverFlow(){this._saveInitialAttribute(this._element,"overflow"),this._element.style.overflow="hidden"}_setElementAttributes(t,e,i){const s=this.getWidth();this._applyManipulationCallback(t,(t=>{if(t!==this._element&&window.innerWidth>t.clientWidth+s)return;this._saveInitialAttribute(t,e);const n=window.getComputedStyle(t)[e];t.style[e]=`${i(Number.parseFloat(n))}px`}))}reset(){this._resetElementAttributes(this._element,"overflow"),this._resetElementAttributes(this._element,"paddingRight"),this._resetElementAttributes($t,"paddingRight"),this._resetElementAttributes(Bt,"marginRight")}_saveInitialAttribute(t,e){const i=t.style[e];i&&X.setDataAttribute(t,e,i)}_resetElementAttributes(t,e){this._applyManipulationCallback(t,(t=>{const i=X.getDataAttribute(t,e);void 0===i?t.style.removeProperty(e):(X.removeDataAttribute(t,e),t.style[e]=i)}))}_applyManipulationCallback(t,e){l(t)?e(t):Y.find(t,this._element).forEach(e)}isOverflowing(){return this.getWidth()>0}}const Rt={className:"modal-backdrop",isVisible:!0,isAnimated:!1,rootElement:"body",clickCallback:null},Ft={className:"string",isVisible:"boolean",isAnimated:"boolean",rootElement:"(element|string)",clickCallback:"(function|null)"},qt="show",Wt="mousedown.bs.backdrop";class Ut{constructor(t){this._config=this._getConfig(t),this._isAppended=!1,this._element=null}show(t){this._config.isVisible?(this._append(),this._config.isAnimated&&f(this._getElement()),this._getElement().classList.add(qt),this._emulateAnimation((()=>{y(t)}))):y(t)}hide(t){this._config.isVisible?(this._getElement().classList.remove(qt),this._emulateAnimation((()=>{this.dispose(),y(t)}))):y(t)}_getElement(){if(!this._element){const t=document.createElement("div");t.className=this._config.className,this._config.isAnimated&&t.classList.add("fade"),this._element=t}return this._element}_getConfig(t){return(t={...Rt,..."object"==typeof t?t:{}}).rootElement=c(t.rootElement),h("backdrop",t,Ft),t}_append(){this._isAppended||(this._config.rootElement.append(this._getElement()),$.on(this._getElement(),Wt,(()=>{y(this._config.clickCallback)})),this._isAppended=!0)}dispose(){this._isAppended&&($.off(this._element,Wt),this._element.remove(),this._isAppended=!1)}_emulateAnimation(t){E(t,this._getElement(),this._config.isAnimated)}}const Kt={trapElement:null,autofocus:!0},Vt={trapElement:"element",autofocus:"boolean"},Xt=".bs.focustrap",Yt="backward";class Qt{constructor(t){this._config=this._getConfig(t),this._isActive=!1,this._lastTabNavDirection=null}activate(){const{trapElement:t,autofocus:e}=this._config;this._isActive||(e&&t.focus(),$.off(document,Xt),$.on(document,"focusin.bs.focustrap",(t=>this._handleFocusin(t))),$.on(document,"keydown.tab.bs.focustrap",(t=>this._handleKeydown(t))),this._isActive=!0)}deactivate(){this._isActive&&(this._isActive=!1,$.off(document,Xt))}_handleFocusin(t){const{target:e}=t,{trapElement:i}=this._config;if(e===document||e===i||i.contains(e))return;const s=Y.focusableChildren(i);0===s.length?i.focus():this._lastTabNavDirection===Yt?s[s.length-1].focus():s[0].focus()}_handleKeydown(t){"Tab"===t.key&&(this._lastTabNavDirection=t.shiftKey?Yt:"forward")}_getConfig(t){return t={...Kt,..."object"==typeof t?t:{}},h("focustrap",t,Vt),t}}const Gt="modal",Zt="Escape",Jt={backdrop:!0,keyboard:!0,focus:!0},te={backdrop:"(boolean|string)",keyboard:"boolean",focus:"boolean"},ee="hidden.bs.modal",ie="show.bs.modal",se="resize.bs.modal",ne="click.dismiss.bs.modal",oe="keydown.dismiss.bs.modal",re="mousedown.dismiss.bs.modal",ae="modal-open",le="show",ce="modal-static";class he extends R{constructor(t,e){super(t),this._config=this._getConfig(e),this._dialog=Y.findOne(".modal-dialog",this._element),this._backdrop=this._initializeBackDrop(),this._focustrap=this._initializeFocusTrap(),this._isShown=!1,this._ignoreBackdropClick=!1,this._isTransitioning=!1,this._scrollBar=new zt}static get Default(){return Jt}static get NAME(){return Gt}toggle(t){return this._isShown?this.hide():this.show(t)}show(t){this._isShown||this._isTransitioning||$.trigger(this._element,ie,{relatedTarget:t}).defaultPrevented||(this._isShown=!0,this._isAnimated()&&(this._isTransitioning=!0),this._scrollBar.hide(),document.body.classList.add(ae),this._adjustDialog(),this._setEscapeEvent(),this._setResizeEvent(),$.on(this._dialog,re,(()=>{$.one(this._element,"mouseup.dismiss.bs.modal",(t=>{t.target===this._element&&(this._ignoreBackdropClick=!0)}))})),this._showBackdrop((()=>this._showElement(t))))}hide(){if(!this._isShown||this._isTransitioning)return;if($.trigger(this._element,"hide.bs.modal").defaultPrevented)return;this._isShown=!1;const t=this._isAnimated();t&&(this._isTransitioning=!0),this._setEscapeEvent(),this._setResizeEvent(),this._focustrap.deactivate(),this._element.classList.remove(le),$.off(this._element,ne),$.off(this._dialog,re),this._queueCallback((()=>this._hideModal()),this._element,t)}dispose(){[window,this._dialog].forEach((t=>$.off(t,".bs.modal"))),this._backdrop.dispose(),this._focustrap.deactivate(),super.dispose()}handleUpdate(){this._adjustDialog()}_initializeBackDrop(){return new Ut({isVisible:Boolean(this._config.backdrop),isAnimated:this._isAnimated()})}_initializeFocusTrap(){return new Qt({trapElement:this._element})}_getConfig(t){return t={...Jt,...X.getDataAttributes(this._element),..."object"==typeof t?t:{}},h(Gt,t,te),t}_showElement(t){const e=this._isAnimated(),i=Y.findOne(".modal-body",this._dialog);this._element.parentNode&&this._element.parentNode.nodeType===Node.ELEMENT_NODE||document.body.append(this._element),this._element.style.display="block",this._element.removeAttribute("aria-hidden"),this._element.setAttribute("aria-modal",!0),this._element.setAttribute("role","dialog"),this._element.scrollTop=0,i&&(i.scrollTop=0),e&&f(this._element),this._element.classList.add(le),this._queueCallback((()=>{this._config.focus&&this._focustrap.activate(),this._isTransitioning=!1,$.trigger(this._element,"shown.bs.modal",{relatedTarget:t})}),this._dialog,e)}_setEscapeEvent(){this._isShown?$.on(this._element,oe,(t=>{this._config.keyboard&&t.key===Zt?(t.preventDefault(),this.hide()):this._config.keyboard||t.key!==Zt||this._triggerBackdropTransition()})):$.off(this._element,oe)}_setResizeEvent(){this._isShown?$.on(window,se,(()=>this._adjustDialog())):$.off(window,se)}_hideModal(){this._element.style.display="none",this._element.setAttribute("aria-hidden",!0),this._element.removeAttribute("aria-modal"),this._element.removeAttribute("role"),this._isTransitioning=!1,this._backdrop.hide((()=>{document.body.classList.remove(ae),this._resetAdjustments(),this._scrollBar.reset(),$.trigger(this._element,ee)}))}_showBackdrop(t){$.on(this._element,ne,(t=>{this._ignoreBackdropClick?this._ignoreBackdropClick=!1:t.target===t.currentTarget&&(!0===this._config.backdrop?this.hide():"static"===this._config.backdrop&&this._triggerBackdropTransition())})),this._backdrop.show(t)}_isAnimated(){return this._element.classList.contains("fade")}_triggerBackdropTransition(){if($.trigger(this._element,"hidePrevented.bs.modal").defaultPrevented)return;const{classList:t,scrollHeight:e,style:i}=this._element,s=e>document.documentElement.clientHeight;!s&&"hidden"===i.overflowY||t.contains(ce)||(s||(i.overflowY="hidden"),t.add(ce),this._queueCallback((()=>{t.remove(ce),s||this._queueCallback((()=>{i.overflowY=""}),this._dialog)}),this._dialog),this._element.focus())}_adjustDialog(){const t=this._element.scrollHeight>document.documentElement.clientHeight,e=this._scrollBar.getWidth(),i=e>0;(!i&&t&&!b()||i&&!t&&b())&&(this._element.style.paddingLeft=`${e}px`),(i&&!t&&!b()||!i&&t&&b())&&(this._element.style.paddingRight=`${e}px`)}_resetAdjustments(){this._element.style.paddingLeft="",this._element.style.paddingRight=""}static jQueryInterface(t,e){return this.each((function(){const i=he.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===i[t])throw new TypeError(`No method named "${t}"`);i[t](e)}}))}}$.on(document,"click.bs.modal.data-api",'[data-bs-toggle="modal"]',(function(t){const e=r(this);["A","AREA"].includes(this.tagName)&&t.preventDefault(),$.one(e,ie,(t=>{t.defaultPrevented||$.one(e,ee,(()=>{d(this)&&this.focus()}))}));const i=Y.findOne(".modal.show");i&&he.getInstance(i).hide(),he.getOrCreateInstance(e).toggle(this)})),F(he),v(he);const de="offcanvas",ue={backdrop:!0,keyboard:!0,scroll:!1},ge={backdrop:"boolean",keyboard:"boolean",scroll:"boolean"},_e="show",fe=".offcanvas.show",pe="hidden.bs.offcanvas";class me extends R{constructor(t,e){super(t),this._config=this._getConfig(e),this._isShown=!1,this._backdrop=this._initializeBackDrop(),this._focustrap=this._initializeFocusTrap(),this._addEventListeners()}static get NAME(){return de}static get Default(){return ue}toggle(t){return this._isShown?this.hide():this.show(t)}show(t){this._isShown||$.trigger(this._element,"show.bs.offcanvas",{relatedTarget:t}).defaultPrevented||(this._isShown=!0,this._element.style.visibility="visible",this._backdrop.show(),this._config.scroll||(new zt).hide(),this._element.removeAttribute("aria-hidden"),this._element.setAttribute("aria-modal",!0),this._element.setAttribute("role","dialog"),this._element.classList.add(_e),this._queueCallback((()=>{this._config.scroll||this._focustrap.activate(),$.trigger(this._element,"shown.bs.offcanvas",{relatedTarget:t})}),this._element,!0))}hide(){this._isShown&&($.trigger(this._element,"hide.bs.offcanvas").defaultPrevented||(this._focustrap.deactivate(),this._element.blur(),this._isShown=!1,this._element.classList.remove(_e),this._backdrop.hide(),this._queueCallback((()=>{this._element.setAttribute("aria-hidden",!0),this._element.removeAttribute("aria-modal"),this._element.removeAttribute("role"),this._element.style.visibility="hidden",this._config.scroll||(new zt).reset(),$.trigger(this._element,pe)}),this._element,!0)))}dispose(){this._backdrop.dispose(),this._focustrap.deactivate(),super.dispose()}_getConfig(t){return t={...ue,...X.getDataAttributes(this._element),..."object"==typeof t?t:{}},h(de,t,ge),t}_initializeBackDrop(){return new Ut({className:"offcanvas-backdrop",isVisible:this._config.backdrop,isAnimated:!0,rootElement:this._element.parentNode,clickCallback:()=>this.hide()})}_initializeFocusTrap(){return new Qt({trapElement:this._element})}_addEventListeners(){$.on(this._element,"keydown.dismiss.bs.offcanvas",(t=>{this._config.keyboard&&"Escape"===t.key&&this.hide()}))}static jQueryInterface(t){return this.each((function(){const e=me.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t]||t.startsWith("_")||"constructor"===t)throw new TypeError(`No method named "${t}"`);e[t](this)}}))}}$.on(document,"click.bs.offcanvas.data-api",'[data-bs-toggle="offcanvas"]',(function(t){const e=r(this);if(["A","AREA"].includes(this.tagName)&&t.preventDefault(),u(this))return;$.one(e,pe,(()=>{d(this)&&this.focus()}));const i=Y.findOne(fe);i&&i!==e&&me.getInstance(i).hide(),me.getOrCreateInstance(e).toggle(this)})),$.on(window,"load.bs.offcanvas.data-api",(()=>Y.find(fe).forEach((t=>me.getOrCreateInstance(t).show())))),F(me),v(me);const be=new Set(["background","cite","href","itemtype","longdesc","poster","src","xlink:href"]),ve=/^(?:(?:https?|mailto|ftp|tel|file|sms):|[^#&/:?]*(?:[#/?]|$))/i,ye=/^data:(?:image\/(?:bmp|gif|jpeg|jpg|png|tiff|webp)|video\/(?:mpeg|mp4|ogg|webm)|audio\/(?:mp3|oga|ogg|opus));base64,[\d+/a-z]+=*$/i,Ee=(t,e)=>{const i=t.nodeName.toLowerCase();if(e.includes(i))return!be.has(i)||Boolean(ve.test(t.nodeValue)||ye.test(t.nodeValue));const s=e.filter((t=>t instanceof RegExp));for(let t=0,e=s.length;t<e;t++)if(s[t].test(i))return!0;return!1};function we(t,e,i){if(!t.length)return t;if(i&&"function"==typeof i)return i(t);const s=(new window.DOMParser).parseFromString(t,"text/html"),n=[].concat(...s.body.querySelectorAll("*"));for(let t=0,i=n.length;t<i;t++){const i=n[t],s=i.nodeName.toLowerCase();if(!Object.keys(e).includes(s)){i.remove();continue}const o=[].concat(...i.attributes),r=[].concat(e["*"]||[],e[s]||[]);o.forEach((t=>{Ee(t,r)||i.removeAttribute(t.nodeName)}))}return s.body.innerHTML}const Ae="tooltip",Te=new Set(["sanitize","allowList","sanitizeFn"]),Ce={animation:"boolean",template:"string",title:"(string|element|function)",trigger:"string",delay:"(number|object)",html:"boolean",selector:"(string|boolean)",placement:"(string|function)",offset:"(array|string|function)",container:"(string|element|boolean)",fallbackPlacements:"array",boundary:"(string|element)",customClass:"(string|function)",sanitize:"boolean",sanitizeFn:"(null|function)",allowList:"object",popperConfig:"(null|object|function)"},ke={AUTO:"auto",TOP:"top",RIGHT:b()?"left":"right",BOTTOM:"bottom",LEFT:b()?"right":"left"},Le={animation:!0,template:'<div class="tooltip" role="tooltip"><div class="tooltip-arrow"></div><div class="tooltip-inner"></div></div>',trigger:"hover focus",title:"",delay:0,html:!1,selector:!1,placement:"top",offset:[0,0],container:!1,fallbackPlacements:["top","right","bottom","left"],boundary:"clippingParents",customClass:"",sanitize:!0,sanitizeFn:null,allowList:{"*":["class","dir","id","lang","role",/^aria-[\w-]*$/i],a:["target","href","title","rel"],area:[],b:[],br:[],col:[],code:[],div:[],em:[],hr:[],h1:[],h2:[],h3:[],h4:[],h5:[],h6:[],i:[],img:["src","srcset","alt","title","width","height"],li:[],ol:[],p:[],pre:[],s:[],small:[],span:[],sub:[],sup:[],strong:[],u:[],ul:[]},popperConfig:null},Se={HIDE:"hide.bs.tooltip",HIDDEN:"hidden.bs.tooltip",SHOW:"show.bs.tooltip",SHOWN:"shown.bs.tooltip",INSERTED:"inserted.bs.tooltip",CLICK:"click.bs.tooltip",FOCUSIN:"focusin.bs.tooltip",FOCUSOUT:"focusout.bs.tooltip",MOUSEENTER:"mouseenter.bs.tooltip",MOUSELEAVE:"mouseleave.bs.tooltip"},Oe="fade",Ne="show",De="show",Ie="out",Pe=".tooltip-inner",xe=".modal",Me="hide.bs.modal",je="hover",He="focus";class $e extends R{constructor(t,e){if(void 0===i)throw new TypeError("Bootstrap's tooltips require Popper (https://popper.js.org)");super(t),this._isEnabled=!0,this._timeout=0,this._hoverState="",this._activeTrigger={},this._popper=null,this._config=this._getConfig(e),this.tip=null,this._setListeners()}static get Default(){return Le}static get NAME(){return Ae}static get Event(){return Se}static get DefaultType(){return Ce}enable(){this._isEnabled=!0}disable(){this._isEnabled=!1}toggleEnabled(){this._isEnabled=!this._isEnabled}toggle(t){if(this._isEnabled)if(t){const e=this._initializeOnDelegatedTarget(t);e._activeTrigger.click=!e._activeTrigger.click,e._isWithActiveTrigger()?e._enter(null,e):e._leave(null,e)}else{if(this.getTipElement().classList.contains(Ne))return void this._leave(null,this);this._enter(null,this)}}dispose(){clearTimeout(this._timeout),$.off(this._element.closest(xe),Me,this._hideModalHandler),this.tip&&this.tip.remove(),this._disposePopper(),super.dispose()}show(){if("none"===this._element.style.display)throw new Error("Please use show on visible elements");if(!this.isWithContent()||!this._isEnabled)return;const t=$.trigger(this._element,this.constructor.Event.SHOW),e=g(this._element),s=null===e?this._element.ownerDocument.documentElement.contains(this._element):e.contains(this._element);if(t.defaultPrevented||!s)return;"tooltip"===this.constructor.NAME&&this.tip&&this.getTitle()!==this.tip.querySelector(Pe).innerHTML&&(this._disposePopper(),this.tip.remove(),this.tip=null);const n=this.getTipElement(),o=(t=>{do{t+=Math.floor(1e6*Math.random())}while(document.getElementById(t));return t})(this.constructor.NAME);n.setAttribute("id",o),this._element.setAttribute("aria-describedby",o),this._config.animation&&n.classList.add(Oe);const r="function"==typeof this._config.placement?this._config.placement.call(this,n,this._element):this._config.placement,a=this._getAttachment(r);this._addAttachmentClass(a);const{container:l}=this._config;z.set(n,this.constructor.DATA_KEY,this),this._element.ownerDocument.documentElement.contains(this.tip)||(l.append(n),$.trigger(this._element,this.constructor.Event.INSERTED)),this._popper?this._popper.update():this._popper=i.createPopper(this._element,n,this._getPopperConfig(a)),n.classList.add(Ne);const c=this._resolvePossibleFunction(this._config.customClass);c&&n.classList.add(...c.split(" ")),"ontouchstart"in document.documentElement&&[].concat(...document.body.children).forEach((t=>{$.on(t,"mouseover",_)}));const h=this.tip.classList.contains(Oe);this._queueCallback((()=>{const t=this._hoverState;this._hoverState=null,$.trigger(this._element,this.constructor.Event.SHOWN),t===Ie&&this._leave(null,this)}),this.tip,h)}hide(){if(!this._popper)return;const t=this.getTipElement();if($.trigger(this._element,this.constructor.Event.HIDE).defaultPrevented)return;t.classList.remove(Ne),"ontouchstart"in document.documentElement&&[].concat(...document.body.children).forEach((t=>$.off(t,"mouseover",_))),this._activeTrigger.click=!1,this._activeTrigger.focus=!1,this._activeTrigger.hover=!1;const e=this.tip.classList.contains(Oe);this._queueCallback((()=>{this._isWithActiveTrigger()||(this._hoverState!==De&&t.remove(),this._cleanTipClass(),this._element.removeAttribute("aria-describedby"),$.trigger(this._element,this.constructor.Event.HIDDEN),this._disposePopper())}),this.tip,e),this._hoverState=""}update(){null!==this._popper&&this._popper.update()}isWithContent(){return Boolean(this.getTitle())}getTipElement(){if(this.tip)return this.tip;const t=document.createElement("div");t.innerHTML=this._config.template;const e=t.children[0];return this.setContent(e),e.classList.remove(Oe,Ne),this.tip=e,this.tip}setContent(t){this._sanitizeAndSetContent(t,this.getTitle(),Pe)}_sanitizeAndSetContent(t,e,i){const s=Y.findOne(i,t);e||!s?this.setElementContent(s,e):s.remove()}setElementContent(t,e){if(null!==t)return l(e)?(e=c(e),void(this._config.html?e.parentNode!==t&&(t.innerHTML="",t.append(e)):t.textContent=e.textContent)):void(this._config.html?(this._config.sanitize&&(e=we(e,this._config.allowList,this._config.sanitizeFn)),t.innerHTML=e):t.textContent=e)}getTitle(){const t=this._element.getAttribute("data-bs-original-title")||this._config.title;return this._resolvePossibleFunction(t)}updateAttachment(t){return"right"===t?"end":"left"===t?"start":t}_initializeOnDelegatedTarget(t,e){return e||this.constructor.getOrCreateInstance(t.delegateTarget,this._getDelegateConfig())}_getOffset(){const{offset:t}=this._config;return"string"==typeof t?t.split(",").map((t=>Number.parseInt(t,10))):"function"==typeof t?e=>t(e,this._element):t}_resolvePossibleFunction(t){return"function"==typeof t?t.call(this._element):t}_getPopperConfig(t){const e={placement:t,modifiers:[{name:"flip",options:{fallbackPlacements:this._config.fallbackPlacements}},{name:"offset",options:{offset:this._getOffset()}},{name:"preventOverflow",options:{boundary:this._config.boundary}},{name:"arrow",options:{element:`.${this.constructor.NAME}-arrow`}},{name:"onChange",enabled:!0,phase:"afterWrite",fn:t=>this._handlePopperPlacementChange(t)}],onFirstUpdate:t=>{t.options.placement!==t.placement&&this._handlePopperPlacementChange(t)}};return{...e,..."function"==typeof this._config.popperConfig?this._config.popperConfig(e):this._config.popperConfig}}_addAttachmentClass(t){this.getTipElement().classList.add(`${this._getBasicClassPrefix()}-${this.updateAttachment(t)}`)}_getAttachment(t){return ke[t.toUpperCase()]}_setListeners(){this._config.trigger.split(" ").forEach((t=>{if("click"===t)$.on(this._element,this.constructor.Event.CLICK,this._config.selector,(t=>this.toggle(t)));else if("manual"!==t){const e=t===je?this.constructor.Event.MOUSEENTER:this.constructor.Event.FOCUSIN,i=t===je?this.constructor.Event.MOUSELEAVE:this.constructor.Event.FOCUSOUT;$.on(this._element,e,this._config.selector,(t=>this._enter(t))),$.on(this._element,i,this._config.selector,(t=>this._leave(t)))}})),this._hideModalHandler=()=>{this._element&&this.hide()},$.on(this._element.closest(xe),Me,this._hideModalHandler),this._config.selector?this._config={...this._config,trigger:"manual",selector:""}:this._fixTitle()}_fixTitle(){const t=this._element.getAttribute("title"),e=typeof this._element.getAttribute("data-bs-original-title");(t||"string"!==e)&&(this._element.setAttribute("data-bs-original-title",t||""),!t||this._element.getAttribute("aria-label")||this._element.textContent||this._element.setAttribute("aria-label",t),this._element.setAttribute("title",""))}_enter(t,e){e=this._initializeOnDelegatedTarget(t,e),t&&(e._activeTrigger["focusin"===t.type?He:je]=!0),e.getTipElement().classList.contains(Ne)||e._hoverState===De?e._hoverState=De:(clearTimeout(e._timeout),e._hoverState=De,e._config.delay&&e._config.delay.show?e._timeout=setTimeout((()=>{e._hoverState===De&&e.show()}),e._config.delay.show):e.show())}_leave(t,e){e=this._initializeOnDelegatedTarget(t,e),t&&(e._activeTrigger["focusout"===t.type?He:je]=e._element.contains(t.relatedTarget)),e._isWithActiveTrigger()||(clearTimeout(e._timeout),e._hoverState=Ie,e._config.delay&&e._config.delay.hide?e._timeout=setTimeout((()=>{e._hoverState===Ie&&e.hide()}),e._config.delay.hide):e.hide())}_isWithActiveTrigger(){for(const t in this._activeTrigger)if(this._activeTrigger[t])return!0;return!1}_getConfig(t){const e=X.getDataAttributes(this._element);return Object.keys(e).forEach((t=>{Te.has(t)&&delete e[t]})),(t={...this.constructor.Default,...e,..."object"==typeof t&&t?t:{}}).container=!1===t.container?document.body:c(t.container),"number"==typeof t.delay&&(t.delay={show:t.delay,hide:t.delay}),"number"==typeof t.title&&(t.title=t.title.toString()),"number"==typeof t.content&&(t.content=t.content.toString()),h(Ae,t,this.constructor.DefaultType),t.sanitize&&(t.template=we(t.template,t.allowList,t.sanitizeFn)),t}_getDelegateConfig(){const t={};for(const e in this._config)this.constructor.Default[e]!==this._config[e]&&(t[e]=this._config[e]);return t}_cleanTipClass(){const t=this.getTipElement(),e=new RegExp(`(^|\\s)${this._getBasicClassPrefix()}\\S+`,"g"),i=t.getAttribute("class").match(e);null!==i&&i.length>0&&i.map((t=>t.trim())).forEach((e=>t.classList.remove(e)))}_getBasicClassPrefix(){return"bs-tooltip"}_handlePopperPlacementChange(t){const{state:e}=t;e&&(this.tip=e.elements.popper,this._cleanTipClass(),this._addAttachmentClass(this._getAttachment(e.placement)))}_disposePopper(){this._popper&&(this._popper.destroy(),this._popper=null)}static jQueryInterface(t){return this.each((function(){const e=$e.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t]()}}))}}v($e);const Be={...$e.Default,placement:"right",offset:[0,8],trigger:"click",content:"",template:'<div class="popover" role="tooltip"><div class="popover-arrow"></div><h3 class="popover-header"></h3><div class="popover-body"></div></div>'},ze={...$e.DefaultType,content:"(string|element|function)"},Re={HIDE:"hide.bs.popover",HIDDEN:"hidden.bs.popover",SHOW:"show.bs.popover",SHOWN:"shown.bs.popover",INSERTED:"inserted.bs.popover",CLICK:"click.bs.popover",FOCUSIN:"focusin.bs.popover",FOCUSOUT:"focusout.bs.popover",MOUSEENTER:"mouseenter.bs.popover",MOUSELEAVE:"mouseleave.bs.popover"};class Fe extends $e{static get Default(){return Be}static get NAME(){return"popover"}static get Event(){return Re}static get DefaultType(){return ze}isWithContent(){return this.getTitle()||this._getContent()}setContent(t){this._sanitizeAndSetContent(t,this.getTitle(),".popover-header"),this._sanitizeAndSetContent(t,this._getContent(),".popover-body")}_getContent(){return this._resolvePossibleFunction(this._config.content)}_getBasicClassPrefix(){return"bs-popover"}static jQueryInterface(t){return this.each((function(){const e=Fe.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t]()}}))}}v(Fe);const qe="scrollspy",We={offset:10,method:"auto",target:""},Ue={offset:"number",method:"string",target:"(string|element)"},Ke="active",Ve=".nav-link, .list-group-item, .dropdown-item",Xe="position";class Ye extends R{constructor(t,e){super(t),this._scrollElement="BODY"===this._element.tagName?window:this._element,this._config=this._getConfig(e),this._offsets=[],this._targets=[],this._activeTarget=null,this._scrollHeight=0,$.on(this._scrollElement,"scroll.bs.scrollspy",(()=>this._process())),this.refresh(),this._process()}static get Default(){return We}static get NAME(){return qe}refresh(){const t=this._scrollElement===this._scrollElement.window?"offset":Xe,e="auto"===this._config.method?t:this._config.method,i=e===Xe?this._getScrollTop():0;this._offsets=[],this._targets=[],this._scrollHeight=this._getScrollHeight(),Y.find(Ve,this._config.target).map((t=>{const s=o(t),n=s?Y.findOne(s):null;if(n){const t=n.getBoundingClientRect();if(t.width||t.height)return[X[e](n).top+i,s]}return null})).filter((t=>t)).sort(((t,e)=>t[0]-e[0])).forEach((t=>{this._offsets.push(t[0]),this._targets.push(t[1])}))}dispose(){$.off(this._scrollElement,".bs.scrollspy"),super.dispose()}_getConfig(t){return(t={...We,...X.getDataAttributes(this._element),..."object"==typeof t&&t?t:{}}).target=c(t.target)||document.documentElement,h(qe,t,Ue),t}_getScrollTop(){return this._scrollElement===window?this._scrollElement.pageYOffset:this._scrollElement.scrollTop}_getScrollHeight(){return this._scrollElement.scrollHeight||Math.max(document.body.scrollHeight,document.documentElement.scrollHeight)}_getOffsetHeight(){return this._scrollElement===window?window.innerHeight:this._scrollElement.getBoundingClientRect().height}_process(){const t=this._getScrollTop()+this._config.offset,e=this._getScrollHeight(),i=this._config.offset+e-this._getOffsetHeight();if(this._scrollHeight!==e&&this.refresh(),t>=i){const t=this._targets[this._targets.length-1];this._activeTarget!==t&&this._activate(t)}else{if(this._activeTarget&&t<this._offsets[0]&&this._offsets[0]>0)return this._activeTarget=null,void this._clear();for(let e=this._offsets.length;e--;)this._activeTarget!==this._targets[e]&&t>=this._offsets[e]&&(void 0===this._offsets[e+1]||t<this._offsets[e+1])&&this._activate(this._targets[e])}}_activate(t){this._activeTarget=t,this._clear();const e=Ve.split(",").map((e=>`${e}[data-bs-target="${t}"],${e}[href="${t}"]`)),i=Y.findOne(e.join(","),this._config.target);i.classList.add(Ke),i.classList.contains("dropdown-item")?Y.findOne(".dropdown-toggle",i.closest(".dropdown")).classList.add(Ke):Y.parents(i,".nav, .list-group").forEach((t=>{Y.prev(t,".nav-link, .list-group-item").forEach((t=>t.classList.add(Ke))),Y.prev(t,".nav-item").forEach((t=>{Y.children(t,".nav-link").forEach((t=>t.classList.add(Ke)))}))})),$.trigger(this._scrollElement,"activate.bs.scrollspy",{relatedTarget:t})}_clear(){Y.find(Ve,this._config.target).filter((t=>t.classList.contains(Ke))).forEach((t=>t.classList.remove(Ke)))}static jQueryInterface(t){return this.each((function(){const e=Ye.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t]()}}))}}$.on(window,"load.bs.scrollspy.data-api",(()=>{Y.find('[data-bs-spy="scroll"]').forEach((t=>new Ye(t)))})),v(Ye);const Qe="active",Ge="fade",Ze="show",Je=".active",ti=":scope > li > .active";class ei extends R{static get NAME(){return"tab"}show(){if(this._element.parentNode&&this._element.parentNode.nodeType===Node.ELEMENT_NODE&&this._element.classList.contains(Qe))return;let t;const e=r(this._element),i=this._element.closest(".nav, .list-group");if(i){const e="UL"===i.nodeName||"OL"===i.nodeName?ti:Je;t=Y.find(e,i),t=t[t.length-1]}const s=t?$.trigger(t,"hide.bs.tab",{relatedTarget:this._element}):null;if($.trigger(this._element,"show.bs.tab",{relatedTarget:t}).defaultPrevented||null!==s&&s.defaultPrevented)return;this._activate(this._element,i);const n=()=>{$.trigger(t,"hidden.bs.tab",{relatedTarget:this._element}),$.trigger(this._element,"shown.bs.tab",{relatedTarget:t})};e?this._activate(e,e.parentNode,n):n()}_activate(t,e,i){const s=(!e||"UL"!==e.nodeName&&"OL"!==e.nodeName?Y.children(e,Je):Y.find(ti,e))[0],n=i&&s&&s.classList.contains(Ge),o=()=>this._transitionComplete(t,s,i);s&&n?(s.classList.remove(Ze),this._queueCallback(o,t,!0)):o()}_transitionComplete(t,e,i){if(e){e.classList.remove(Qe);const t=Y.findOne(":scope > .dropdown-menu .active",e.parentNode);t&&t.classList.remove(Qe),"tab"===e.getAttribute("role")&&e.setAttribute("aria-selected",!1)}t.classList.add(Qe),"tab"===t.getAttribute("role")&&t.setAttribute("aria-selected",!0),f(t),t.classList.contains(Ge)&&t.classList.add(Ze);let s=t.parentNode;if(s&&"LI"===s.nodeName&&(s=s.parentNode),s&&s.classList.contains("dropdown-menu")){const e=t.closest(".dropdown");e&&Y.find(".dropdown-toggle",e).forEach((t=>t.classList.add(Qe))),t.setAttribute("aria-expanded",!0)}i&&i()}static jQueryInterface(t){return this.each((function(){const e=ei.getOrCreateInstance(this);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t]()}}))}}$.on(document,"click.bs.tab.data-api",'[data-bs-toggle="tab"], [data-bs-toggle="pill"], [data-bs-toggle="list"]',(function(t){["A","AREA"].includes(this.tagName)&&t.preventDefault(),u(this)||ei.getOrCreateInstance(this).show()})),v(ei);const ii="toast",si="hide",ni="show",oi="showing",ri={animation:"boolean",autohide:"boolean",delay:"number"},ai={animation:!0,autohide:!0,delay:5e3};class li extends R{constructor(t,e){super(t),this._config=this._getConfig(e),this._timeout=null,this._hasMouseInteraction=!1,this._hasKeyboardInteraction=!1,this._setListeners()}static get DefaultType(){return ri}static get Default(){return ai}static get NAME(){return ii}show(){$.trigger(this._element,"show.bs.toast").defaultPrevented||(this._clearTimeout(),this._config.animation&&this._element.classList.add("fade"),this._element.classList.remove(si),f(this._element),this._element.classList.add(ni),this._element.classList.add(oi),this._queueCallback((()=>{this._element.classList.remove(oi),$.trigger(this._element,"shown.bs.toast"),this._maybeScheduleHide()}),this._element,this._config.animation))}hide(){this._element.classList.contains(ni)&&($.trigger(this._element,"hide.bs.toast").defaultPrevented||(this._element.classList.add(oi),this._queueCallback((()=>{this._element.classList.add(si),this._element.classList.remove(oi),this._element.classList.remove(ni),$.trigger(this._element,"hidden.bs.toast")}),this._element,this._config.animation)))}dispose(){this._clearTimeout(),this._element.classList.contains(ni)&&this._element.classList.remove(ni),super.dispose()}_getConfig(t){return t={...ai,...X.getDataAttributes(this._element),..."object"==typeof t&&t?t:{}},h(ii,t,this.constructor.DefaultType),t}_maybeScheduleHide(){this._config.autohide&&(this._hasMouseInteraction||this._hasKeyboardInteraction||(this._timeout=setTimeout((()=>{this.hide()}),this._config.delay)))}_onInteraction(t,e){switch(t.type){case"mouseover":case"mouseout":this._hasMouseInteraction=e;break;case"focusin":case"focusout":this._hasKeyboardInteraction=e}if(e)return void this._clearTimeout();const i=t.relatedTarget;this._element===i||this._element.contains(i)||this._maybeScheduleHide()}_setListeners(){$.on(this._element,"mouseover.bs.toast",(t=>this._onInteraction(t,!0))),$.on(this._element,"mouseout.bs.toast",(t=>this._onInteraction(t,!1))),$.on(this._element,"focusin.bs.toast",(t=>this._onInteraction(t,!0))),$.on(this._element,"focusout.bs.toast",(t=>this._onInteraction(t,!1)))}_clearTimeout(){clearTimeout(this._timeout),this._timeout=null}static jQueryInterface(t){return this.each((function(){const e=li.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t](this)}}))}}return F(li),v(li),{Alert:q,Button:U,Carousel:at,Collapse:mt,Dropdown:Ht,Modal:he,Offcanvas:me,Popover:Fe,ScrollSpy:Ye,Tab:ei,Toast:li,Tooltip:$e}}));
		</script>
		<script>
			//src="https://unpkg.com/bootstrap-table@1.21.0/dist/bootstrap-table.min.js"
			/**
			  * bootstrap-table - An extended table to integration with some of the most widely used CSS frameworks. (Supports Bootstrap, Semantic UI, Bulma, Material Design, Foundation)
			  *
			  * @version v1.21.0
			  * @homepage https://bootstrap-table.com
			  * @author wenzhixin <wenzhixin2010@gmail.com> (http://wenzhixin.net.cn/)
			  * @license MIT
			  */
			!function(t,e){"object"==typeof exports&&"undefined"!=typeof module?module.exports=e(require("jquery")):"function"==typeof define&&define.amd?define(["jquery"],e):(t="undefined"!=typeof globalThis?globalThis:t||self).BootstrapTable=e(t.jQuery)}(this,(function(t){"use strict";function e(t){return t&&"object"==typeof t&&"default"in t?t:{default:t}}var i=e(t);function n(t){return n="function"==typeof Symbol&&"symbol"==typeof Symbol.iterator?function(t){return typeof t}:function(t){return t&&"function"==typeof Symbol&&t.constructor===Symbol&&t!==Symbol.prototype?"symbol":typeof t},n(t)}function o(t,e){if(!(t instanceof e))throw new TypeError("Cannot call a class as a function")}function a(t,e){for(var i=0;i<e.length;i++){var n=e[i];n.enumerable=n.enumerable||!1,n.configurable=!0,"value"in n&&(n.writable=!0),Object.defineProperty(t,n.key,n)}}function r(t,e,i){return e&&a(t.prototype,e),i&&a(t,i),Object.defineProperty(t,"prototype",{writable:!1}),t}function s(t,e){return function(t){if(Array.isArray(t))return t}(t)||function(t,e){var i=null==t?null:"undefined"!=typeof Symbol&&t[Symbol.iterator]||t["@@iterator"];if(null==i)return;var n,o,a=[],r=!0,s=!1;try{for(i=i.call(t);!(r=(n=i.next()).done)&&(a.push(n.value),!e||a.length!==e);r=!0);}catch(t){s=!0,o=t}finally{try{r||null==i.return||i.return()}finally{if(s)throw o}}return a}(t,e)||c(t,e)||function(){throw new TypeError("Invalid attempt to destructure non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.")}()}function l(t){return function(t){if(Array.isArray(t))return h(t)}(t)||function(t){if("undefined"!=typeof Symbol&&null!=t[Symbol.iterator]||null!=t["@@iterator"])return Array.from(t)}(t)||c(t)||function(){throw new TypeError("Invalid attempt to spread non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.")}()}function c(t,e){if(t){if("string"==typeof t)return h(t,e);var i=Object.prototype.toString.call(t).slice(8,-1);return"Object"===i&&t.constructor&&(i=t.constructor.name),"Map"===i||"Set"===i?Array.from(t):"Arguments"===i||/^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(i)?h(t,e):void 0}}function h(t,e){(null==e||e>t.length)&&(e=t.length);for(var i=0,n=new Array(e);i<e;i++)n[i]=t[i];return n}function u(t,e){var i="undefined"!=typeof Symbol&&t[Symbol.iterator]||t["@@iterator"];if(!i){if(Array.isArray(t)||(i=c(t))||e&&t&&"number"==typeof t.length){i&&(t=i);var n=0,o=function(){};return{s:o,n:function(){return n>=t.length?{done:!0}:{done:!1,value:t[n++]}},e:function(t){throw t},f:o}}throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.")}var a,r=!0,s=!1;return{s:function(){i=i.call(t)},n:function(){var t=i.next();return r=t.done,t},e:function(t){s=!0,a=t},f:function(){try{r||null==i.return||i.return()}finally{if(s)throw a}}}}var d="undefined"!=typeof globalThis?globalThis:"undefined"!=typeof window?window:"undefined"!=typeof global?global:"undefined"!=typeof self?self:{},f=function(t){return t&&t.Math==Math&&t},p=f("object"==typeof globalThis&&globalThis)||f("object"==typeof window&&window)||f("object"==typeof self&&self)||f("object"==typeof d&&d)||function(){return this}()||Function("return this")(),g={},v=function(t){try{return!!t()}catch(t){return!0}},b=!v((function(){return 7!=Object.defineProperty({},1,{get:function(){return 7}})[1]})),m=!v((function(){var t=function(){}.bind();return"function"!=typeof t||t.hasOwnProperty("prototype")})),y=m,w=Function.prototype.call,S=y?w.bind(w):function(){return w.apply(w,arguments)},x={},k={}.propertyIsEnumerable,O=Object.getOwnPropertyDescriptor,C=O&&!k.call({1:2},1);x.f=C?function(t){var e=O(this,t);return!!e&&e.enumerable}:k;var T,I,P=function(t,e){return{enumerable:!(1&t),configurable:!(2&t),writable:!(4&t),value:e}},A=m,$=Function.prototype,R=$.bind,E=$.call,j=A&&R.bind(E,E),F=A?function(t){return t&&j(t)}:function(t){return t&&function(){return E.apply(t,arguments)}},N=F,_=N({}.toString),D=N("".slice),V=function(t){return D(_(t),8,-1)},B=v,L=V,H=Object,M=F("".split),U=B((function(){return!H("z").propertyIsEnumerable(0)}))?function(t){return"String"==L(t)?M(t,""):H(t)}:H,z=TypeError,q=function(t){if(null==t)throw z("Can't call method on "+t);return t},W=U,G=q,K=function(t){return W(G(t))},Y=function(t){return"function"==typeof t},J=Y,X=function(t){return"object"==typeof t?null!==t:J(t)},Q=p,Z=Y,tt=function(t){return Z(t)?t:void 0},et=function(t,e){return arguments.length<2?tt(Q[t]):Q[t]&&Q[t][e]},it=F({}.isPrototypeOf),nt=et("navigator","userAgent")||"",ot=p,at=nt,rt=ot.process,st=ot.Deno,lt=rt&&rt.versions||st&&st.version,ct=lt&&lt.v8;ct&&(I=(T=ct.split("."))[0]>0&&T[0]<4?1:+(T[0]+T[1])),!I&&at&&(!(T=at.match(/Edge\/(\d+)/))||T[1]>=74)&&(T=at.match(/Chrome\/(\d+)/))&&(I=+T[1]);var ht=I,ut=ht,dt=v,ft=!!Object.getOwnPropertySymbols&&!dt((function(){var t=Symbol();return!String(t)||!(Object(t)instanceof Symbol)||!Symbol.sham&&ut&&ut<41})),pt=ft&&!Symbol.sham&&"symbol"==typeof Symbol.iterator,gt=et,vt=Y,bt=it,mt=Object,yt=pt?function(t){return"symbol"==typeof t}:function(t){var e=gt("Symbol");return vt(e)&&bt(e.prototype,mt(t))},wt=String,St=function(t){try{return wt(t)}catch(t){return"Object"}},xt=Y,kt=St,Ot=TypeError,Ct=function(t){if(xt(t))return t;throw Ot(kt(t)+" is not a function")},Tt=Ct,It=function(t,e){var i=t[e];return null==i?void 0:Tt(i)},Pt=S,At=Y,$t=X,Rt=TypeError,Et={exports:{}},jt=p,Ft=Object.defineProperty,Nt=function(t,e){try{Ft(jt,t,{value:e,configurable:!0,writable:!0})}catch(i){jt[t]=e}return e},_t=Nt,Dt="__core-js_shared__",Vt=p[Dt]||_t(Dt,{}),Bt=Vt;(Et.exports=function(t,e){return Bt[t]||(Bt[t]=void 0!==e?e:{})})("versions",[]).push({version:"3.22.8",mode:"global",copyright:"© 2014-2022 Denis Pushkarev (zloirock.ru)",license:"https://github.com/zloirock/core-js/blob/v3.22.8/LICENSE",source:"https://github.com/zloirock/core-js"});var Lt=q,Ht=Object,Mt=function(t){return Ht(Lt(t))},Ut=Mt,zt=F({}.hasOwnProperty),qt=Object.hasOwn||function(t,e){return zt(Ut(t),e)},Wt=F,Gt=0,Kt=Math.random(),Yt=Wt(1..toString),Jt=function(t){return"Symbol("+(void 0===t?"":t)+")_"+Yt(++Gt+Kt,36)},Xt=p,Qt=Et.exports,Zt=qt,te=Jt,ee=ft,ie=pt,ne=Qt("wks"),oe=Xt.Symbol,ae=oe&&oe.for,re=ie?oe:oe&&oe.withoutSetter||te,se=function(t){if(!Zt(ne,t)||!ee&&"string"!=typeof ne[t]){var e="Symbol."+t;ee&&Zt(oe,t)?ne[t]=oe[t]:ne[t]=ie&&ae?ae(e):re(e)}return ne[t]},le=S,ce=X,he=yt,ue=It,de=function(t,e){var i,n;if("string"===e&&At(i=t.toString)&&!$t(n=Pt(i,t)))return n;if(At(i=t.valueOf)&&!$t(n=Pt(i,t)))return n;if("string"!==e&&At(i=t.toString)&&!$t(n=Pt(i,t)))return n;throw Rt("Can't convert object to primitive value")},fe=TypeError,pe=se("toPrimitive"),ge=function(t,e){if(!ce(t)||he(t))return t;var i,n=ue(t,pe);if(n){if(void 0===e&&(e="default"),i=le(n,t,e),!ce(i)||he(i))return i;throw fe("Can't convert object to primitive value")}return void 0===e&&(e="number"),de(t,e)},ve=ge,be=yt,me=function(t){var e=ve(t,"string");return be(e)?e:e+""},ye=X,we=p.document,Se=ye(we)&&ye(we.createElement),xe=function(t){return Se?we.createElement(t):{}},ke=xe,Oe=!b&&!v((function(){return 7!=Object.defineProperty(ke("div"),"a",{get:function(){return 7}}).a})),Ce=b,Te=S,Ie=x,Pe=P,Ae=K,$e=me,Re=qt,Ee=Oe,je=Object.getOwnPropertyDescriptor;g.f=Ce?je:function(t,e){if(t=Ae(t),e=$e(e),Ee)try{return je(t,e)}catch(t){}if(Re(t,e))return Pe(!Te(Ie.f,t,e),t[e])};var Fe={},Ne=b&&v((function(){return 42!=Object.defineProperty((function(){}),"prototype",{value:42,writable:!1}).prototype})),_e=X,De=String,Ve=TypeError,Be=function(t){if(_e(t))return t;throw Ve(De(t)+" is not an object")},Le=b,He=Oe,Me=Ne,Ue=Be,ze=me,qe=TypeError,We=Object.defineProperty,Ge=Object.getOwnPropertyDescriptor,Ke="enumerable",Ye="configurable",Je="writable";Fe.f=Le?Me?function(t,e,i){if(Ue(t),e=ze(e),Ue(i),"function"==typeof t&&"prototype"===e&&"value"in i&&Je in i&&!i.writable){var n=Ge(t,e);n&&n.writable&&(t[e]=i.value,i={configurable:Ye in i?i.configurable:n.configurable,enumerable:Ke in i?i.enumerable:n.enumerable,writable:!1})}return We(t,e,i)}:We:function(t,e,i){if(Ue(t),e=ze(e),Ue(i),He)try{return We(t,e,i)}catch(t){}if("get"in i||"set"in i)throw qe("Accessors not supported");return"value"in i&&(t[e]=i.value),t};var Xe=Fe,Qe=P,Ze=b?function(t,e,i){return Xe.f(t,e,Qe(1,i))}:function(t,e,i){return t[e]=i,t},ti={exports:{}},ei=b,ii=qt,ni=Function.prototype,oi=ei&&Object.getOwnPropertyDescriptor,ai=ii(ni,"name"),ri={EXISTS:ai,PROPER:ai&&"something"===function(){}.name,CONFIGURABLE:ai&&(!ei||ei&&oi(ni,"name").configurable)},si=Y,li=Vt,ci=F(Function.toString);si(li.inspectSource)||(li.inspectSource=function(t){return ci(t)});var hi,ui,di,fi=li.inspectSource,pi=Y,gi=fi,vi=p.WeakMap,bi=pi(vi)&&/native code/.test(gi(vi)),mi=Et.exports,yi=Jt,wi=mi("keys"),Si=function(t){return wi[t]||(wi[t]=yi(t))},xi={},ki=bi,Oi=p,Ci=F,Ti=X,Ii=Ze,Pi=qt,Ai=Vt,$i=Si,Ri=xi,Ei="Object already initialized",ji=Oi.TypeError,Fi=Oi.WeakMap;if(ki||Ai.state){var Ni=Ai.state||(Ai.state=new Fi),_i=Ci(Ni.get),Di=Ci(Ni.has),Vi=Ci(Ni.set);hi=function(t,e){if(Di(Ni,t))throw new ji(Ei);return e.facade=t,Vi(Ni,t,e),e},ui=function(t){return _i(Ni,t)||{}},di=function(t){return Di(Ni,t)}}else{var Bi=$i("state");Ri[Bi]=!0,hi=function(t,e){if(Pi(t,Bi))throw new ji(Ei);return e.facade=t,Ii(t,Bi,e),e},ui=function(t){return Pi(t,Bi)?t[Bi]:{}},di=function(t){return Pi(t,Bi)}}var Li={set:hi,get:ui,has:di,enforce:function(t){return di(t)?ui(t):hi(t,{})},getterFor:function(t){return function(e){var i;if(!Ti(e)||(i=ui(e)).type!==t)throw ji("Incompatible receiver, "+t+" required");return i}}},Hi=v,Mi=Y,Ui=qt,zi=b,qi=ri.CONFIGURABLE,Wi=fi,Gi=Li.enforce,Ki=Li.get,Yi=Object.defineProperty,Ji=zi&&!Hi((function(){return 8!==Yi((function(){}),"length",{value:8}).length})),Xi=String(String).split("String"),Qi=ti.exports=function(t,e,i){"Symbol("===String(e).slice(0,7)&&(e="["+String(e).replace(/^Symbol\(([^)]*)\)/,"$1")+"]"),i&&i.getter&&(e="get "+e),i&&i.setter&&(e="set "+e),(!Ui(t,"name")||qi&&t.name!==e)&&Yi(t,"name",{value:e,configurable:!0}),Ji&&i&&Ui(i,"arity")&&t.length!==i.arity&&Yi(t,"length",{value:i.arity});try{i&&Ui(i,"constructor")&&i.constructor?zi&&Yi(t,"prototype",{writable:!1}):t.prototype&&(t.prototype=void 0)}catch(t){}var n=Gi(t);return Ui(n,"source")||(n.source=Xi.join("string"==typeof e?e:"")),t};Function.prototype.toString=Qi((function(){return Mi(this)&&Ki(this).source||Wi(this)}),"toString");var Zi=Y,tn=Ze,en=ti.exports,nn=Nt,on=function(t,e,i,n){n||(n={});var o=n.enumerable,a=void 0!==n.name?n.name:e;return Zi(i)&&en(i,a,n),n.global?o?t[e]=i:nn(e,i):(n.unsafe?t[e]&&(o=!0):delete t[e],o?t[e]=i:tn(t,e,i)),t},an={},rn=Math.ceil,sn=Math.floor,ln=Math.trunc||function(t){var e=+t;return(e>0?sn:rn)(e)},cn=function(t){var e=+t;return e!=e||0===e?0:ln(e)},hn=cn,un=Math.max,dn=Math.min,fn=function(t,e){var i=hn(t);return i<0?un(i+e,0):dn(i,e)},pn=cn,gn=Math.min,vn=function(t){return t>0?gn(pn(t),9007199254740991):0},bn=vn,mn=function(t){return bn(t.length)},yn=K,wn=fn,Sn=mn,xn=function(t){return function(e,i,n){var o,a=yn(e),r=Sn(a),s=wn(n,r);if(t&&i!=i){for(;r>s;)if((o=a[s++])!=o)return!0}else for(;r>s;s++)if((t||s in a)&&a[s]===i)return t||s||0;return!t&&-1}},kn={includes:xn(!0),indexOf:xn(!1)},On=qt,Cn=K,Tn=kn.indexOf,In=xi,Pn=F([].push),An=function(t,e){var i,n=Cn(t),o=0,a=[];for(i in n)!On(In,i)&&On(n,i)&&Pn(a,i);for(;e.length>o;)On(n,i=e[o++])&&(~Tn(a,i)||Pn(a,i));return a},$n=["constructor","hasOwnProperty","isPrototypeOf","propertyIsEnumerable","toLocaleString","toString","valueOf"],Rn=An,En=$n.concat("length","prototype");an.f=Object.getOwnPropertyNames||function(t){return Rn(t,En)};var jn={};jn.f=Object.getOwnPropertySymbols;var Fn=et,Nn=an,_n=jn,Dn=Be,Vn=F([].concat),Bn=Fn("Reflect","ownKeys")||function(t){var e=Nn.f(Dn(t)),i=_n.f;return i?Vn(e,i(t)):e},Ln=qt,Hn=Bn,Mn=g,Un=Fe,zn=v,qn=Y,Wn=/#|\.prototype\./,Gn=function(t,e){var i=Yn[Kn(t)];return i==Xn||i!=Jn&&(qn(e)?zn(e):!!e)},Kn=Gn.normalize=function(t){return String(t).replace(Wn,".").toLowerCase()},Yn=Gn.data={},Jn=Gn.NATIVE="N",Xn=Gn.POLYFILL="P",Qn=Gn,Zn=p,to=g.f,eo=Ze,io=on,no=Nt,oo=function(t,e,i){for(var n=Hn(e),o=Un.f,a=Mn.f,r=0;r<n.length;r++){var s=n[r];Ln(t,s)||i&&Ln(i,s)||o(t,s,a(e,s))}},ao=Qn,ro=function(t,e){var i,n,o,a,r,s=t.target,l=t.global,c=t.stat;if(i=l?Zn:c?Zn[s]||no(s,{}):(Zn[s]||{}).prototype)for(n in e){if(a=e[n],o=t.dontCallGetSet?(r=to(i,n))&&r.value:i[n],!ao(l?n:s+(c?".":"#")+n,t.forced)&&void 0!==o){if(typeof a==typeof o)continue;oo(a,o)}(t.sham||o&&o.sham)&&eo(a,"sham",!0),io(i,n,a,t)}},so=An,lo=$n,co=Object.keys||function(t){return so(t,lo)},ho=b,uo=F,fo=S,po=v,go=co,vo=jn,bo=x,mo=Mt,yo=U,wo=Object.assign,So=Object.defineProperty,xo=uo([].concat),ko=!wo||po((function(){if(ho&&1!==wo({b:1},wo(So({},"a",{enumerable:!0,get:function(){So(this,"b",{value:3,enumerable:!1})}}),{b:2})).b)return!0;var t={},e={},i=Symbol(),n="abcdefghijklmnopqrst";return t[i]=7,n.split("").forEach((function(t){e[t]=t})),7!=wo({},t)[i]||go(wo({},e)).join("")!=n}))?function(t,e){for(var i=mo(t),n=arguments.length,o=1,a=vo.f,r=bo.f;n>o;)for(var s,l=yo(arguments[o++]),c=a?xo(go(l),a(l)):go(l),h=c.length,u=0;h>u;)s=c[u++],ho&&!fo(r,l,s)||(i[s]=l[s]);return i}:wo,Oo=ko;ro({target:"Object",stat:!0,arity:2,forced:Object.assign!==Oo},{assign:Oo});var Co={};Co[se("toStringTag")]="z";var To="[object z]"===String(Co),Io=To,Po=Y,Ao=V,$o=se("toStringTag"),Ro=Object,Eo="Arguments"==Ao(function(){return arguments}()),jo=Io?Ao:function(t){var e,i,n;return void 0===t?"Undefined":null===t?"Null":"string"==typeof(i=function(t,e){try{return t[e]}catch(t){}}(e=Ro(t),$o))?i:Eo?Ao(e):"Object"==(n=Ao(e))&&Po(e.callee)?"Arguments":n},Fo=jo,No=String,_o=function(t){if("Symbol"===Fo(t))throw TypeError("Cannot convert a Symbol value to a string");return No(t)},Do="\t\n\v\f\r                　\u2028\u2029\ufeff",Vo=q,Bo=_o,Lo=F("".replace),Ho="[\t\n\v\f\r                　\u2028\u2029\ufeff]",Mo=RegExp("^"+Ho+Ho+"*"),Uo=RegExp(Ho+Ho+"*$"),zo=function(t){return function(e){var i=Bo(Vo(e));return 1&t&&(i=Lo(i,Mo,"")),2&t&&(i=Lo(i,Uo,"")),i}},qo={start:zo(1),end:zo(2),trim:zo(3)},Wo=ri.PROPER,Go=v,Ko=Do,Yo=qo.trim;ro({target:"String",proto:!0,forced:function(t){return Go((function(){return!!Ko[t]()||"​᠎"!=="​᠎"[t]()||Wo&&Ko[t].name!==t}))}("trim")},{trim:function(){return Yo(this)}});var Jo=v,Xo=function(t,e){var i=[][t];return!!i&&Jo((function(){i.call(null,e||function(){return 1},1)}))},Qo=ro,Zo=U,ta=K,ea=Xo,ia=F([].join),na=Zo!=Object,oa=ea("join",",");Qo({target:"Array",proto:!0,forced:na||!oa},{join:function(t){return ia(ta(this),void 0===t?",":t)}});var aa=Be,ra=function(){var t=aa(this),e="";return t.hasIndices&&(e+="d"),t.global&&(e+="g"),t.ignoreCase&&(e+="i"),t.multiline&&(e+="m"),t.dotAll&&(e+="s"),t.unicode&&(e+="u"),t.sticky&&(e+="y"),e},sa=v,la=p.RegExp,ca=sa((function(){var t=la("a","y");return t.lastIndex=2,null!=t.exec("abcd")})),ha=ca||sa((function(){return!la("a","y").sticky})),ua={BROKEN_CARET:ca||sa((function(){var t=la("^r","gy");return t.lastIndex=2,null!=t.exec("str")})),MISSED_STICKY:ha,UNSUPPORTED_Y:ca},da={},fa=b,pa=Ne,ga=Fe,va=Be,ba=K,ma=co;da.f=fa&&!pa?Object.defineProperties:function(t,e){va(t);for(var i,n=ba(e),o=ma(e),a=o.length,r=0;a>r;)ga.f(t,i=o[r++],n[i]);return t};var ya,wa=et("document","documentElement"),Sa=Be,xa=da,ka=$n,Oa=xi,Ca=wa,Ta=xe,Ia=Si("IE_PROTO"),Pa=function(){},Aa=function(t){return"<script>"+t+"</"+"script>"},$a=function(t){t.write(Aa("")),t.close();var e=t.parentWindow.Object;return t=null,e},Ra=function(){try{ya=new ActiveXObject("htmlfile")}catch(t){}var t,e;Ra="undefined"!=typeof document?document.domain&&ya?$a(ya):((e=Ta("iframe")).style.display="none",Ca.appendChild(e),e.src=String("javascript:"),(t=e.contentWindow.document).open(),t.write(Aa("document.F=Object")),t.close(),t.F):$a(ya);for(var i=ka.length;i--;)delete Ra.prototype[ka[i]];return Ra()};Oa[Ia]=!0;var Ea=Object.create||function(t,e){var i;return null!==t?(Pa.prototype=Sa(t),i=new Pa,Pa.prototype=null,i[Ia]=t):i=Ra(),void 0===e?i:xa.f(i,e)},ja=v,Fa=p.RegExp,Na=ja((function(){var t=Fa(".","s");return!(t.dotAll&&t.exec("\n")&&"s"===t.flags)})),_a=v,Da=p.RegExp,Va=_a((function(){var t=Da("(?<a>b)","g");return"b"!==t.exec("b").groups.a||"bc"!=="b".replace(t,"$<a>c")})),Ba=S,La=F,Ha=_o,Ma=ra,Ua=ua,za=Et.exports,qa=Ea,Wa=Li.get,Ga=Na,Ka=Va,Ya=za("native-string-replace",String.prototype.replace),Ja=RegExp.prototype.exec,Xa=Ja,Qa=La("".charAt),Za=La("".indexOf),tr=La("".replace),er=La("".slice),ir=function(){var t=/a/,e=/b*/g;return Ba(Ja,t,"a"),Ba(Ja,e,"a"),0!==t.lastIndex||0!==e.lastIndex}(),nr=Ua.BROKEN_CARET,or=void 0!==/()??/.exec("")[1];(ir||or||nr||Ga||Ka)&&(Xa=function(t){var e,i,n,o,a,r,s,l=this,c=Wa(l),h=Ha(t),u=c.raw;if(u)return u.lastIndex=l.lastIndex,e=Ba(Xa,u,h),l.lastIndex=u.lastIndex,e;var d=c.groups,f=nr&&l.sticky,p=Ba(Ma,l),g=l.source,v=0,b=h;if(f&&(p=tr(p,"y",""),-1===Za(p,"g")&&(p+="g"),b=er(h,l.lastIndex),l.lastIndex>0&&(!l.multiline||l.multiline&&"\n"!==Qa(h,l.lastIndex-1))&&(g="(?: "+g+")",b=" "+b,v++),i=new RegExp("^(?:"+g+")",p)),or&&(i=new RegExp("^"+g+"$(?!\\s)",p)),ir&&(n=l.lastIndex),o=Ba(Ja,f?i:l,b),f?o?(o.input=er(o.input,v),o[0]=er(o[0],v),o.index=l.lastIndex,l.lastIndex+=o[0].length):l.lastIndex=0:ir&&o&&(l.lastIndex=l.global?o.index+o[0].length:n),or&&o&&o.length>1&&Ba(Ya,o[0],i,(function(){for(a=1;a<arguments.length-2;a++)void 0===arguments[a]&&(o[a]=void 0)})),o&&d)for(o.groups=r=qa(null),a=0;a<d.length;a++)r[(s=d[a])[0]]=o[s[1]];return o});var ar=Xa;ro({target:"RegExp",proto:!0,forced:/./.exec!==ar},{exec:ar});var rr=m,sr=Function.prototype,lr=sr.apply,cr=sr.call,hr="object"==typeof Reflect&&Reflect.apply||(rr?cr.bind(lr):function(){return cr.apply(lr,arguments)}),ur=F,dr=on,fr=ar,pr=v,gr=se,vr=Ze,br=gr("species"),mr=RegExp.prototype,yr=function(t,e,i,n){var o=gr(t),a=!pr((function(){var e={};return e[o]=function(){return 7},7!=""[t](e)})),r=a&&!pr((function(){var e=!1,i=/a/;return"split"===t&&((i={}).constructor={},i.constructor[br]=function(){return i},i.flags="",i[o]=/./[o]),i.exec=function(){return e=!0,null},i[o](""),!e}));if(!a||!r||i){var s=ur(/./[o]),l=e(o,""[t],(function(t,e,i,n,o){var r=ur(t),l=e.exec;return l===fr||l===mr.exec?a&&!o?{done:!0,value:s(e,i,n)}:{done:!0,value:r(i,e,n)}:{done:!1}}));dr(String.prototype,t,l[0]),dr(mr,o,l[1])}n&&vr(mr[o],"sham",!0)},wr=X,Sr=V,xr=se("match"),kr=function(t){var e;return wr(t)&&(void 0!==(e=t[xr])?!!e:"RegExp"==Sr(t))},Or=F,Cr=v,Tr=Y,Ir=jo,Pr=fi,Ar=function(){},$r=[],Rr=et("Reflect","construct"),Er=/^\s*(?:class|function)\b/,jr=Or(Er.exec),Fr=!Er.exec(Ar),Nr=function(t){if(!Tr(t))return!1;try{return Rr(Ar,$r,t),!0}catch(t){return!1}},_r=function(t){if(!Tr(t))return!1;switch(Ir(t)){case"AsyncFunction":case"GeneratorFunction":case"AsyncGeneratorFunction":return!1}try{return Fr||!!jr(Er,Pr(t))}catch(t){return!0}};_r.sham=!0;var Dr=!Rr||Cr((function(){var t;return Nr(Nr.call)||!Nr(Object)||!Nr((function(){t=!0}))||t}))?_r:Nr,Vr=Dr,Br=St,Lr=TypeError,Hr=Be,Mr=function(t){if(Vr(t))return t;throw Lr(Br(t)+" is not a constructor")},Ur=se("species"),zr=F,qr=cn,Wr=_o,Gr=q,Kr=zr("".charAt),Yr=zr("".charCodeAt),Jr=zr("".slice),Xr=function(t){return function(e,i){var n,o,a=Wr(Gr(e)),r=qr(i),s=a.length;return r<0||r>=s?t?"":void 0:(n=Yr(a,r))<55296||n>56319||r+1===s||(o=Yr(a,r+1))<56320||o>57343?t?Kr(a,r):n:t?Jr(a,r,r+2):o-56320+(n-55296<<10)+65536}},Qr={codeAt:Xr(!1),charAt:Xr(!0)}.charAt,Zr=function(t,e,i){return e+(i?Qr(t,e).length:1)},ts=me,es=Fe,is=P,ns=function(t,e,i){var n=ts(e);n in t?es.f(t,n,is(0,i)):t[n]=i},os=fn,as=mn,rs=ns,ss=Array,ls=Math.max,cs=function(t,e,i){for(var n=as(t),o=os(e,n),a=os(void 0===i?n:i,n),r=ss(ls(a-o,0)),s=0;o<a;o++,s++)rs(r,s,t[o]);return r.length=s,r},hs=S,us=Be,ds=Y,fs=V,ps=ar,gs=TypeError,vs=function(t,e){var i=t.exec;if(ds(i)){var n=hs(i,t,e);return null!==n&&us(n),n}if("RegExp"===fs(t))return hs(ps,t,e);throw gs("RegExp#exec called on incompatible receiver")},bs=hr,ms=S,ys=F,ws=yr,Ss=kr,xs=Be,ks=q,Os=function(t,e){var i,n=Hr(t).constructor;return void 0===n||null==(i=Hr(n)[Ur])?e:Mr(i)},Cs=Zr,Ts=vn,Is=_o,Ps=It,As=cs,$s=vs,Rs=ar,Es=v,js=ua.UNSUPPORTED_Y,Fs=4294967295,Ns=Math.min,_s=[].push,Ds=ys(/./.exec),Vs=ys(_s),Bs=ys("".slice),Ls=!Es((function(){var t=/(?:)/,e=t.exec;t.exec=function(){return e.apply(this,arguments)};var i="ab".split(t);return 2!==i.length||"a"!==i[0]||"b"!==i[1]}));ws("split",(function(t,e,i){var n;return n="c"=="abbc".split(/(b)*/)[1]||4!="test".split(/(?:)/,-1).length||2!="ab".split(/(?:ab)*/).length||4!=".".split(/(.?)(.?)/).length||".".split(/()()/).length>1||"".split(/.?/).length?function(t,i){var n=Is(ks(this)),o=void 0===i?Fs:i>>>0;if(0===o)return[];if(void 0===t)return[n];if(!Ss(t))return ms(e,n,t,o);for(var a,r,s,l=[],c=(t.ignoreCase?"i":"")+(t.multiline?"m":"")+(t.unicode?"u":"")+(t.sticky?"y":""),h=0,u=new RegExp(t.source,c+"g");(a=ms(Rs,u,n))&&!((r=u.lastIndex)>h&&(Vs(l,Bs(n,h,a.index)),a.length>1&&a.index<n.length&&bs(_s,l,As(a,1)),s=a[0].length,h=r,l.length>=o));)u.lastIndex===a.index&&u.lastIndex++;return h===n.length?!s&&Ds(u,"")||Vs(l,""):Vs(l,Bs(n,h)),l.length>o?As(l,0,o):l}:"0".split(void 0,0).length?function(t,i){return void 0===t&&0===i?[]:ms(e,this,t,i)}:e,[function(e,i){var o=ks(this),a=null==e?void 0:Ps(e,t);return a?ms(a,e,o,i):ms(n,Is(o),e,i)},function(t,o){var a=xs(this),r=Is(t),s=i(n,a,r,o,n!==e);if(s.done)return s.value;var l=Os(a,RegExp),c=a.unicode,h=(a.ignoreCase?"i":"")+(a.multiline?"m":"")+(a.unicode?"u":"")+(js?"g":"y"),u=new l(js?"^(?:"+a.source+")":a,h),d=void 0===o?Fs:o>>>0;if(0===d)return[];if(0===r.length)return null===$s(u,r)?[r]:[];for(var f=0,p=0,g=[];p<r.length;){u.lastIndex=js?0:p;var v,b=$s(u,js?Bs(r,p):r);if(null===b||(v=Ns(Ts(u.lastIndex+(js?p:0)),r.length))===f)p=Cs(r,p,c);else{if(Vs(g,Bs(r,f,p)),g.length===d)return g;for(var m=1;m<=b.length-1;m++)if(Vs(g,b[m]),g.length===d)return g;p=f=v}}return Vs(g,Bs(r,f)),g}]}),!Ls,js);var Hs=b,Ms=F,Us=co,zs=K,qs=Ms(x.f),Ws=Ms([].push),Gs=function(t){return function(e){for(var i,n=zs(e),o=Us(n),a=o.length,r=0,s=[];a>r;)i=o[r++],Hs&&!qs(n,i)||Ws(s,t?[i,n[i]]:n[i]);return s}},Ks={entries:Gs(!0),values:Gs(!1)}.entries;ro({target:"Object",stat:!0},{entries:function(t){return Ks(t)}});var Ys=se,Js=Ea,Xs=Fe.f,Qs=Ys("unscopables"),Zs=Array.prototype;null==Zs[Qs]&&Xs(Zs,Qs,{configurable:!0,value:Js(null)});var tl=function(t){Zs[Qs][t]=!0},el=kn.includes,il=tl;ro({target:"Array",proto:!0,forced:v((function(){return!Array(1).includes()}))},{includes:function(t){return el(this,t,arguments.length>1?arguments[1]:void 0)}}),il("includes");var nl=V,ol=Array.isArray||function(t){return"Array"==nl(t)},al=TypeError,rl=function(t){if(t>9007199254740991)throw al("Maximum allowed index exceeded");return t},sl=ol,ll=Dr,cl=X,hl=se("species"),ul=Array,dl=function(t){var e;return sl(t)&&(e=t.constructor,(ll(e)&&(e===ul||sl(e.prototype))||cl(e)&&null===(e=e[hl]))&&(e=void 0)),void 0===e?ul:e},fl=function(t,e){return new(dl(t))(0===e?0:e)},pl=v,gl=ht,vl=se("species"),bl=function(t){return gl>=51||!pl((function(){var e=[];return(e.constructor={})[vl]=function(){return{foo:1}},1!==e[t](Boolean).foo}))},ml=ro,yl=v,wl=ol,Sl=X,xl=Mt,kl=mn,Ol=rl,Cl=ns,Tl=fl,Il=bl,Pl=ht,Al=se("isConcatSpreadable"),$l=Pl>=51||!yl((function(){var t=[];return t[Al]=!1,t.concat()[0]!==t})),Rl=Il("concat"),El=function(t){if(!Sl(t))return!1;var e=t[Al];return void 0!==e?!!e:wl(t)};ml({target:"Array",proto:!0,arity:1,forced:!$l||!Rl},{concat:function(t){var e,i,n,o,a,r=xl(this),s=Tl(r,0),l=0;for(e=-1,n=arguments.length;e<n;e++)if(El(a=-1===e?r:arguments[e]))for(o=kl(a),Ol(l+o),i=0;i<o;i++,l++)i in a&&Cl(s,l,a[i]);else Ol(l+1),Cl(s,l++,a);return s.length=l,s}});var jl=Ct,Fl=m,Nl=F(F.bind),_l=function(t,e){return jl(t),void 0===e?t:Fl?Nl(t,e):function(){return t.apply(e,arguments)}},Dl=U,Vl=Mt,Bl=mn,Ll=fl,Hl=F([].push),Ml=function(t){var e=1==t,i=2==t,n=3==t,o=4==t,a=6==t,r=7==t,s=5==t||a;return function(l,c,h,u){for(var d,f,p=Vl(l),g=Dl(p),v=_l(c,h),b=Bl(g),m=0,y=u||Ll,w=e?y(l,b):i||r?y(l,0):void 0;b>m;m++)if((s||m in g)&&(f=v(d=g[m],m,p),t))if(e)w[m]=f;else if(f)switch(t){case 3:return!0;case 5:return d;case 6:return m;case 2:Hl(w,d)}else switch(t){case 4:return!1;case 7:Hl(w,d)}return a?-1:n||o?o:w}},Ul={forEach:Ml(0),map:Ml(1),filter:Ml(2),some:Ml(3),every:Ml(4),find:Ml(5),findIndex:Ml(6),filterReject:Ml(7)},zl=ro,ql=Ul.find,Wl=tl,Gl="find",Kl=!0;Gl in[]&&Array(1).find((function(){Kl=!1})),zl({target:"Array",proto:!0,forced:Kl},{find:function(t){return ql(this,t,arguments.length>1?arguments[1]:void 0)}}),Wl(Gl);var Yl=jo,Jl=To?{}.toString:function(){return"[object "+Yl(this)+"]"};To||on(Object.prototype,"toString",Jl,{unsafe:!0});var Xl=kr,Ql=TypeError,Zl=function(t){if(Xl(t))throw Ql("The method doesn't accept regular expressions");return t},tc=se("match"),ec=function(t){var e=/./;try{"/./"[t](e)}catch(i){try{return e[tc]=!1,"/./"[t](e)}catch(t){}}return!1},ic=ro,nc=Zl,oc=q,ac=_o,rc=ec,sc=F("".indexOf);ic({target:"String",proto:!0,forced:!rc("includes")},{includes:function(t){return!!~sc(ac(oc(this)),ac(nc(t)),arguments.length>1?arguments[1]:void 0)}});var lc={CSSRuleList:0,CSSStyleDeclaration:0,CSSValueList:0,ClientRectList:0,DOMRectList:0,DOMStringList:0,DOMTokenList:1,DataTransferItemList:0,FileList:0,HTMLAllCollection:0,HTMLCollection:0,HTMLFormElement:0,HTMLSelectElement:0,MediaList:0,MimeTypeArray:0,NamedNodeMap:0,NodeList:1,PaintRequestList:0,Plugin:0,PluginArray:0,SVGLengthList:0,SVGNumberList:0,SVGPathSegList:0,SVGPointList:0,SVGStringList:0,SVGTransformList:0,SourceBufferList:0,StyleSheetList:0,TextTrackCueList:0,TextTrackList:0,TouchList:0},cc=xe("span").classList,hc=cc&&cc.constructor&&cc.constructor.prototype,uc=hc===Object.prototype?void 0:hc,dc=Ul.forEach,fc=Xo("forEach")?[].forEach:function(t){return dc(this,t,arguments.length>1?arguments[1]:void 0)},pc=p,gc=lc,vc=uc,bc=fc,mc=Ze,yc=function(t){if(t&&t.forEach!==bc)try{mc(t,"forEach",bc)}catch(e){t.forEach=bc}};for(var wc in gc)gc[wc]&&yc(pc[wc]&&pc[wc].prototype);yc(vc);var Sc=p,xc=v,kc=_o,Oc=qo.trim,Cc=F("".charAt),Tc=Sc.parseFloat,Ic=Sc.Symbol,Pc=Ic&&Ic.iterator,Ac=1/Tc("\t\n\v\f\r                　\u2028\u2029\ufeff-0")!=-1/0||Pc&&!xc((function(){Tc(Object(Pc))}))?function(t){var e=Oc(kc(t)),i=Tc(e);return 0===i&&"-"==Cc(e,0)?-0:i}:Tc;ro({global:!0,forced:parseFloat!=Ac},{parseFloat:Ac});var $c=ro,Rc=kn.indexOf,Ec=Xo,jc=F([].indexOf),Fc=!!jc&&1/jc([1],1,-0)<0,Nc=Ec("indexOf");$c({target:"Array",proto:!0,forced:Fc||!Nc},{indexOf:function(t){var e=arguments.length>1?arguments[1]:void 0;return Fc?jc(this,t,e)||0:Rc(this,t,e)}});var _c=St,Dc=TypeError,Vc=function(t,e){if(!delete t[e])throw Dc("Cannot delete property "+_c(e)+" of "+_c(t))},Bc=cs,Lc=Math.floor,Hc=function(t,e){var i=t.length,n=Lc(i/2);return i<8?Mc(t,e):Uc(t,Hc(Bc(t,0,n),e),Hc(Bc(t,n),e),e)},Mc=function(t,e){for(var i,n,o=t.length,a=1;a<o;){for(n=a,i=t[a];n&&e(t[n-1],i)>0;)t[n]=t[--n];n!==a++&&(t[n]=i)}return t},Uc=function(t,e,i,n){for(var o=e.length,a=i.length,r=0,s=0;r<o||s<a;)t[r+s]=r<o&&s<a?n(e[r],i[s])<=0?e[r++]:i[s++]:r<o?e[r++]:i[s++];return t},zc=Hc,qc=nt.match(/firefox\/(\d+)/i),Wc=!!qc&&+qc[1],Gc=/MSIE|Trident/.test(nt),Kc=nt.match(/AppleWebKit\/(\d+)\./),Yc=!!Kc&&+Kc[1],Jc=ro,Xc=F,Qc=Ct,Zc=Mt,th=mn,eh=Vc,ih=_o,nh=v,oh=zc,ah=Xo,rh=Wc,sh=Gc,lh=ht,ch=Yc,hh=[],uh=Xc(hh.sort),dh=Xc(hh.push),fh=nh((function(){hh.sort(void 0)})),ph=nh((function(){hh.sort(null)})),gh=ah("sort"),vh=!nh((function(){if(lh)return lh<70;if(!(rh&&rh>3)){if(sh)return!0;if(ch)return ch<603;var t,e,i,n,o="";for(t=65;t<76;t++){switch(e=String.fromCharCode(t),t){case 66:case 69:case 70:case 72:i=3;break;case 68:case 71:i=4;break;default:i=2}for(n=0;n<47;n++)hh.push({k:e+n,v:i})}for(hh.sort((function(t,e){return e.v-t.v})),n=0;n<hh.length;n++)e=hh[n].k.charAt(0),o.charAt(o.length-1)!==e&&(o+=e);return"DGBEFHACIJK"!==o}}));Jc({target:"Array",proto:!0,forced:fh||!ph||!gh||!vh},{sort:function(t){void 0!==t&&Qc(t);var e=Zc(this);if(vh)return void 0===t?uh(e):uh(e,t);var i,n,o=[],a=th(e);for(n=0;n<a;n++)n in e&&dh(o,e[n]);for(oh(o,function(t){return function(e,i){return void 0===i?-1:void 0===e?1:void 0!==t?+t(e,i)||0:ih(e)>ih(i)?1:-1}}(t)),i=o.length,n=0;n<i;)e[n]=o[n++];for(;n<a;)eh(e,n++);return e}});var bh=F,mh=Mt,yh=Math.floor,wh=bh("".charAt),Sh=bh("".replace),xh=bh("".slice),kh=/\$([$&'`]|\d{1,2}|<[^>]*>)/g,Oh=/\$([$&'`]|\d{1,2})/g,Ch=hr,Th=S,Ih=F,Ph=yr,Ah=v,$h=Be,Rh=Y,Eh=cn,jh=vn,Fh=_o,Nh=q,_h=Zr,Dh=It,Vh=function(t,e,i,n,o,a){var r=i+t.length,s=n.length,l=Oh;return void 0!==o&&(o=mh(o),l=kh),Sh(a,l,(function(a,l){var c;switch(wh(l,0)){case"$":return"$";case"&":return t;case"`":return xh(e,0,i);case"'":return xh(e,r);case"<":c=o[xh(l,1,-1)];break;default:var h=+l;if(0===h)return a;if(h>s){var u=yh(h/10);return 0===u?a:u<=s?void 0===n[u-1]?wh(l,1):n[u-1]+wh(l,1):a}c=n[h-1]}return void 0===c?"":c}))},Bh=vs,Lh=se("replace"),Hh=Math.max,Mh=Math.min,Uh=Ih([].concat),zh=Ih([].push),qh=Ih("".indexOf),Wh=Ih("".slice),Gh="$0"==="a".replace(/./,"$0"),Kh=!!/./[Lh]&&""===/./[Lh]("a","$0");Ph("replace",(function(t,e,i){var n=Kh?"$":"$0";return[function(t,i){var n=Nh(this),o=null==t?void 0:Dh(t,Lh);return o?Th(o,t,n,i):Th(e,Fh(n),t,i)},function(t,o){var a=$h(this),r=Fh(t);if("string"==typeof o&&-1===qh(o,n)&&-1===qh(o,"$<")){var s=i(e,a,r,o);if(s.done)return s.value}var l=Rh(o);l||(o=Fh(o));var c=a.global;if(c){var h=a.unicode;a.lastIndex=0}for(var u=[];;){var d=Bh(a,r);if(null===d)break;if(zh(u,d),!c)break;""===Fh(d[0])&&(a.lastIndex=_h(r,jh(a.lastIndex),h))}for(var f,p="",g=0,v=0;v<u.length;v++){for(var b=Fh((d=u[v])[0]),m=Hh(Mh(Eh(d.index),r.length),0),y=[],w=1;w<d.length;w++)zh(y,void 0===(f=d[w])?f:String(f));var S=d.groups;if(l){var x=Uh([b],y,m,r);void 0!==S&&zh(x,S);var k=Fh(Ch(o,void 0,x))}else k=Vh(b,r,m,y,S,o);m>=g&&(p+=Wh(r,g,m)+k,g=m+b.length)}return p+Wh(r,g)}]}),!!Ah((function(){var t=/./;return t.exec=function(){var t=[];return t.groups={a:"7"},t},"7"!=="".replace(t,"$<a>")}))||!Gh||Kh);var Yh=Ul.filter;ro({target:"Array",proto:!0,forced:!bl("filter")},{filter:function(t){return Yh(this,t,arguments.length>1?arguments[1]:void 0)}});var Jh=Object.is||function(t,e){return t===e?0!==t||1/t==1/e:t!=t&&e!=e},Xh=S,Qh=Be,Zh=q,tu=Jh,eu=_o,iu=It,nu=vs;yr("search",(function(t,e,i){return[function(e){var i=Zh(this),n=null==e?void 0:iu(e,t);return n?Xh(n,e,i):new RegExp(e)[t](eu(i))},function(t){var n=Qh(this),o=eu(t),a=i(e,n,o);if(a.done)return a.value;var r=n.lastIndex;tu(r,0)||(n.lastIndex=0);var s=nu(n,o);return tu(n.lastIndex,r)||(n.lastIndex=r),null===s?-1:s.index}]}));var ou=p,au=v,ru=F,su=_o,lu=qo.trim,cu=Do,hu=ou.parseInt,uu=ou.Symbol,du=uu&&uu.iterator,fu=/^[+-]?0x/i,pu=ru(fu.exec),gu=8!==hu(cu+"08")||22!==hu(cu+"0x16")||du&&!au((function(){hu(Object(du))}))?function(t,e){var i=lu(su(t));return hu(i,e>>>0||(pu(fu,i)?16:10))}:hu;ro({global:!0,forced:parseInt!=gu},{parseInt:gu});var vu=Ul.map;ro({target:"Array",proto:!0,forced:!bl("map")},{map:function(t){return vu(this,t,arguments.length>1?arguments[1]:void 0)}});var bu=ro,mu=Ul.findIndex,yu=tl,wu="findIndex",Su=!0;wu in[]&&Array(1).findIndex((function(){Su=!1})),bu({target:"Array",proto:!0,forced:Su},{findIndex:function(t){return mu(this,t,arguments.length>1?arguments[1]:void 0)}}),yu(wu);var xu=Y,ku=String,Ou=TypeError,Cu=F,Tu=Be,Iu=function(t){if("object"==typeof t||xu(t))return t;throw Ou("Can't set "+ku(t)+" as a prototype")},Pu=Object.setPrototypeOf||("__proto__"in{}?function(){var t,e=!1,i={};try{(t=Cu(Object.getOwnPropertyDescriptor(Object.prototype,"__proto__").set))(i,[]),e=i instanceof Array}catch(t){}return function(i,n){return Tu(i),Iu(n),e?t(i,n):i.__proto__=n,i}}():void 0),Au=Y,$u=X,Ru=Pu,Eu=function(t,e,i){var n,o;return Ru&&Au(n=e.constructor)&&n!==i&&$u(o=n.prototype)&&o!==i.prototype&&Ru(t,o),t},ju=S,Fu=qt,Nu=it,_u=ra,Du=RegExp.prototype,Vu=function(t){var e=t.flags;return void 0!==e||"flags"in Du||Fu(t,"flags")||!Nu(Du,t)?e:ju(_u,t)},Bu=Fe.f,Lu=et,Hu=Fe,Mu=b,Uu=se("species"),zu=b,qu=p,Wu=F,Gu=Qn,Ku=Eu,Yu=Ze,Ju=an.f,Xu=it,Qu=kr,Zu=_o,td=Vu,ed=ua,id=function(t,e,i){i in t||Bu(t,i,{configurable:!0,get:function(){return e[i]},set:function(t){e[i]=t}})},nd=on,od=v,ad=qt,rd=Li.enforce,sd=function(t){var e=Lu(t),i=Hu.f;Mu&&e&&!e[Uu]&&i(e,Uu,{configurable:!0,get:function(){return this}})},ld=Na,cd=Va,hd=se("match"),ud=qu.RegExp,dd=ud.prototype,fd=qu.SyntaxError,pd=Wu(dd.exec),gd=Wu("".charAt),vd=Wu("".replace),bd=Wu("".indexOf),md=Wu("".slice),yd=/^\?<[^\s\d!#%&*+<=>@^][^\s!#%&*+<=>@^]*>/,wd=/a/g,Sd=/a/g,xd=new ud(wd)!==wd,kd=ed.MISSED_STICKY,Od=ed.UNSUPPORTED_Y,Cd=zu&&(!xd||kd||ld||cd||od((function(){return Sd[hd]=!1,ud(wd)!=wd||ud(Sd)==Sd||"/a/i"!=ud(wd,"i")})));if(Gu("RegExp",Cd)){for(var Td=function(t,e){var i,n,o,a,r,s,l=Xu(dd,this),c=Qu(t),h=void 0===e,u=[],d=t;if(!l&&c&&h&&t.constructor===Td)return t;if((c||Xu(dd,t))&&(t=t.source,h&&(e=td(d))),t=void 0===t?"":Zu(t),e=void 0===e?"":Zu(e),d=t,ld&&"dotAll"in wd&&(n=!!e&&bd(e,"s")>-1)&&(e=vd(e,/s/g,"")),i=e,kd&&"sticky"in wd&&(o=!!e&&bd(e,"y")>-1)&&Od&&(e=vd(e,/y/g,"")),cd&&(a=function(t){for(var e,i=t.length,n=0,o="",a=[],r={},s=!1,l=!1,c=0,h="";n<=i;n++){if("\\"===(e=gd(t,n)))e+=gd(t,++n);else if("]"===e)s=!1;else if(!s)switch(!0){case"["===e:s=!0;break;case"("===e:pd(yd,md(t,n+1))&&(n+=2,l=!0),o+=e,c++;continue;case">"===e&&l:if(""===h||ad(r,h))throw new fd("Invalid capture group name");r[h]=!0,a[a.length]=[h,c],l=!1,h="";continue}l?h+=e:o+=e}return[o,a]}(t),t=a[0],u=a[1]),r=Ku(ud(t,e),l?this:dd,Td),(n||o||u.length)&&(s=rd(r),n&&(s.dotAll=!0,s.raw=Td(function(t){for(var e,i=t.length,n=0,o="",a=!1;n<=i;n++)"\\"!==(e=gd(t,n))?a||"."!==e?("["===e?a=!0:"]"===e&&(a=!1),o+=e):o+="[\\s\\S]":o+=e+gd(t,++n);return o}(t),i)),o&&(s.sticky=!0),u.length&&(s.groups=u)),t!==d)try{Yu(r,"source",""===d?"(?:)":d)}catch(t){}return r},Id=Ju(ud),Pd=0;Id.length>Pd;)id(Td,ud,Id[Pd++]);dd.constructor=Td,Td.prototype=dd,nd(qu,"RegExp",Td,{constructor:!0})}sd("RegExp");var Ad=ri.PROPER,$d=on,Rd=Be,Ed=_o,jd=v,Fd=Vu,Nd="toString",_d=RegExp.prototype.toString,Dd=jd((function(){return"/a/b"!=_d.call({source:"a",flags:"b"})})),Vd=Ad&&_d.name!=Nd;(Dd||Vd)&&$d(RegExp.prototype,Nd,(function(){var t=Rd(this);return"/"+Ed(t.source)+"/"+Ed(Fd(t))}),{unsafe:!0});var Bd=F([].slice),Ld=ro,Hd=ol,Md=Dr,Ud=X,zd=fn,qd=mn,Wd=K,Gd=ns,Kd=se,Yd=Bd,Jd=bl("slice"),Xd=Kd("species"),Qd=Array,Zd=Math.max;Ld({target:"Array",proto:!0,forced:!Jd},{slice:function(t,e){var i,n,o,a=Wd(this),r=qd(a),s=zd(t,r),l=zd(void 0===e?r:e,r);if(Hd(a)&&(i=a.constructor,(Md(i)&&(i===Qd||Hd(i.prototype))||Ud(i)&&null===(i=i[Xd]))&&(i=void 0),i===Qd||void 0===i))return Yd(a,s,l);for(n=new(void 0===i?Qd:i)(Zd(l-s,0)),o=0;s<l;s++,o++)s in a&&Gd(n,o,a[s]);return n.length=o,n}});var tf,ef,nf,of={},af=!v((function(){function t(){}return t.prototype.constructor=null,Object.getPrototypeOf(new t)!==t.prototype})),rf=qt,sf=Y,lf=Mt,cf=af,hf=Si("IE_PROTO"),uf=Object,df=uf.prototype,ff=cf?uf.getPrototypeOf:function(t){var e=lf(t);if(rf(e,hf))return e[hf];var i=e.constructor;return sf(i)&&e instanceof i?i.prototype:e instanceof uf?df:null},pf=v,gf=Y,vf=ff,bf=on,mf=se("iterator"),yf=!1;[].keys&&("next"in(nf=[].keys())?(ef=vf(vf(nf)))!==Object.prototype&&(tf=ef):yf=!0);var wf=null==tf||pf((function(){var t={};return tf[mf].call(t)!==t}));wf&&(tf={}),gf(tf[mf])||bf(tf,mf,(function(){return this}));var Sf={IteratorPrototype:tf,BUGGY_SAFARI_ITERATORS:yf},xf=Fe.f,kf=qt,Of=se("toStringTag"),Cf=function(t,e,i){t&&!i&&(t=t.prototype),t&&!kf(t,Of)&&xf(t,Of,{configurable:!0,value:e})},Tf=Sf.IteratorPrototype,If=Ea,Pf=P,Af=Cf,$f=of,Rf=function(){return this},Ef=ro,jf=S,Ff=Y,Nf=function(t,e,i,n){var o=e+" Iterator";return t.prototype=If(Tf,{next:Pf(+!n,i)}),Af(t,o,!1),$f[o]=Rf,t},_f=ff,Df=Pu,Vf=Cf,Bf=Ze,Lf=on,Hf=of,Mf=ri.PROPER,Uf=ri.CONFIGURABLE,zf=Sf.IteratorPrototype,qf=Sf.BUGGY_SAFARI_ITERATORS,Wf=se("iterator"),Gf="keys",Kf="values",Yf="entries",Jf=function(){return this},Xf=K,Qf=tl,Zf=of,tp=Li,ep=Fe.f,ip=function(t,e,i,n,o,a,r){Nf(i,e,n);var s,l,c,h=function(t){if(t===o&&g)return g;if(!qf&&t in f)return f[t];switch(t){case Gf:case Kf:case Yf:return function(){return new i(this,t)}}return function(){return new i(this)}},u=e+" Iterator",d=!1,f=t.prototype,p=f[Wf]||f["@@iterator"]||o&&f[o],g=!qf&&p||h(o),v="Array"==e&&f.entries||p;if(v&&(s=_f(v.call(new t)))!==Object.prototype&&s.next&&(_f(s)!==zf&&(Df?Df(s,zf):Ff(s[Wf])||Lf(s,Wf,Jf)),Vf(s,u,!0)),Mf&&o==Kf&&p&&p.name!==Kf&&(Uf?Bf(f,"name",Kf):(d=!0,g=function(){return jf(p,this)})),o)if(l={values:h(Kf),keys:a?g:h(Gf),entries:h(Yf)},r)for(c in l)(qf||d||!(c in f))&&Lf(f,c,l[c]);else Ef({target:e,proto:!0,forced:qf||d},l);return f[Wf]!==g&&Lf(f,Wf,g,{name:o}),Hf[e]=g,l},np=b,op="Array Iterator",ap=tp.set,rp=tp.getterFor(op),sp=ip(Array,"Array",(function(t,e){ap(this,{type:op,target:Xf(t),index:0,kind:e})}),(function(){var t=rp(this),e=t.target,i=t.kind,n=t.index++;return!e||n>=e.length?(t.target=void 0,{value:void 0,done:!0}):"keys"==i?{value:n,done:!1}:"values"==i?{value:e[n],done:!1}:{value:[n,e[n]],done:!1}}),"values"),lp=Zf.Arguments=Zf.Array;if(Qf("keys"),Qf("values"),Qf("entries"),np&&"values"!==lp.name)try{ep(lp,"name",{value:"values"})}catch(t){}var cp=p,hp=lc,up=uc,dp=sp,fp=Ze,pp=se,gp=pp("iterator"),vp=pp("toStringTag"),bp=dp.values,mp=function(t,e){if(t){if(t[gp]!==bp)try{fp(t,gp,bp)}catch(e){t[gp]=bp}if(t[vp]||fp(t,vp,e),hp[e])for(var i in dp)if(t[i]!==dp[i])try{fp(t,i,dp[i])}catch(e){t[i]=dp[i]}}};for(var yp in hp)mp(cp[yp]&&cp[yp].prototype,yp);mp(up,"DOMTokenList");var wp=ro,Sp=Mt,xp=fn,kp=cn,Op=mn,Cp=rl,Tp=fl,Ip=ns,Pp=Vc,Ap=bl("splice"),$p=Math.max,Rp=Math.min;wp({target:"Array",proto:!0,forced:!Ap},{splice:function(t,e){var i,n,o,a,r,s,l=Sp(this),c=Op(l),h=xp(t,c),u=arguments.length;for(0===u?i=n=0:1===u?(i=0,n=c-h):(i=u-2,n=Rp($p(kp(e),0),c-h)),Cp(c+i-n),o=Tp(l,n),a=0;a<n;a++)(r=h+a)in l&&Ip(o,a,l[r]);if(o.length=n,i<n){for(a=h;a<c-n;a++)s=a+i,(r=a+n)in l?l[s]=l[r]:Pp(l,s);for(a=c;a>c-n+i;a--)Pp(l,a-1)}else if(i>n)for(a=c-n;a>h;a--)s=a+i-1,(r=a+n-1)in l?l[s]=l[r]:Pp(l,s);for(a=0;a<i;a++)l[a+h]=arguments[a+2];return l.length=c-n+i,o}});var Ep=F(1..valueOf),jp=b,Fp=p,Np=F,_p=Qn,Dp=on,Vp=qt,Bp=Eu,Lp=it,Hp=yt,Mp=ge,Up=v,zp=an.f,qp=g.f,Wp=Fe.f,Gp=Ep,Kp=qo.trim,Yp="Number",Jp=Fp.Number,Xp=Jp.prototype,Qp=Fp.TypeError,Zp=Np("".slice),tg=Np("".charCodeAt),eg=function(t){var e=Mp(t,"number");return"bigint"==typeof e?e:ig(e)},ig=function(t){var e,i,n,o,a,r,s,l,c=Mp(t,"number");if(Hp(c))throw Qp("Cannot convert a Symbol value to a number");if("string"==typeof c&&c.length>2)if(c=Kp(c),43===(e=tg(c,0))||45===e){if(88===(i=tg(c,2))||120===i)return NaN}else if(48===e){switch(tg(c,1)){case 66:case 98:n=2,o=49;break;case 79:case 111:n=8,o=55;break;default:return+c}for(r=(a=Zp(c,2)).length,s=0;s<r;s++)if((l=tg(a,s))<48||l>o)return NaN;return parseInt(a,n)}return+c};if(_p(Yp,!Jp(" 0o1")||!Jp("0b1")||Jp("+0x1"))){for(var ng,og=function(t){var e=arguments.length<1?0:Jp(eg(t)),i=this;return Lp(Xp,i)&&Up((function(){Gp(i)}))?Bp(Object(e),i,og):e},ag=jp?zp(Jp):"MAX_VALUE,MIN_VALUE,NaN,NEGATIVE_INFINITY,POSITIVE_INFINITY,EPSILON,MAX_SAFE_INTEGER,MIN_SAFE_INTEGER,isFinite,isInteger,isNaN,isSafeInteger,parseFloat,parseInt,fromString,range".split(","),rg=0;ag.length>rg;rg++)Vp(Jp,ng=ag[rg])&&!Vp(og,ng)&&Wp(og,ng,qp(Jp,ng));og.prototype=Xp,Xp.constructor=og,Dp(Fp,Yp,og,{constructor:!0})}var sg=ro,lg=ol,cg=F([].reverse),hg=[1,2];sg({target:"Array",proto:!0,forced:String(hg)===String(hg.reverse())},{reverse:function(){return lg(this)&&(this.length=this.length),cg(this)}});var ug=Mt,dg=co;ro({target:"Object",stat:!0,forced:v((function(){dg(1)}))},{keys:function(t){return dg(ug(t))}});var fg=S,pg=Be,gg=vn,vg=_o,bg=q,mg=It,yg=Zr,wg=vs;yr("match",(function(t,e,i){return[function(e){var i=bg(this),n=null==e?void 0:mg(e,t);return n?fg(n,e,i):new RegExp(e)[t](vg(i))},function(t){var n=pg(this),o=vg(t),a=i(e,n,o);if(a.done)return a.value;if(!n.global)return wg(n,o);var r=n.unicode;n.lastIndex=0;for(var s,l=[],c=0;null!==(s=wg(n,o));){var h=vg(s[0]);l[c]=h,""===h&&(n.lastIndex=yg(o,gg(n.lastIndex),r)),c++}return 0===c?null:l}]}));var Sg,xg=ro,kg=F,Og=g.f,Cg=vn,Tg=_o,Ig=Zl,Pg=q,Ag=ec,$g=kg("".startsWith),Rg=kg("".slice),Eg=Math.min,jg=Ag("startsWith");xg({target:"String",proto:!0,forced:!!(jg||(Sg=Og(String.prototype,"startsWith"),!Sg||Sg.writable))&&!jg},{startsWith:function(t){var e=Tg(Pg(this));Ig(t);var i=Cg(Eg(arguments.length>1?arguments[1]:void 0,e.length)),n=Tg(t);return $g?$g(e,n,i):Rg(e,i,i+n.length)===n}});var Fg=ro,Ng=F,_g=g.f,Dg=vn,Vg=_o,Bg=Zl,Lg=q,Hg=ec,Mg=Ng("".endsWith),Ug=Ng("".slice),zg=Math.min,qg=Hg("endsWith"),Wg=!qg&&!!function(){var t=_g(String.prototype,"endsWith");return t&&!t.writable}();Fg({target:"String",proto:!0,forced:!Wg&&!qg},{endsWith:function(t){var e=Vg(Lg(this));Bg(t);var i=arguments.length>1?arguments[1]:void 0,n=e.length,o=void 0===i?n:zg(Dg(i),n),a=Vg(t);return Mg?Mg(e,a,o):Ug(e,o-a.length,o)===a}});var Gg={getBootstrapVersion:function(){var t=5;try{var e=i.default.fn.dropdown.Constructor.VERSION;void 0!==e&&(t=parseInt(e,10))}catch(t){}try{var n=bootstrap.Tooltip.VERSION;void 0!==n&&(t=parseInt(n,10))}catch(t){}return t},getIconsPrefix:function(t){return{bootstrap3:"glyphicon",bootstrap4:"fa",bootstrap5:"bi","bootstrap-table":"icon",bulma:"fa",foundation:"fa",materialize:"material-icons",semantic:"fa"}[t]||"fa"},getIcons:function(t){return{glyphicon:{paginationSwitchDown:"glyphicon-collapse-down icon-chevron-down",paginationSwitchUp:"glyphicon-collapse-up icon-chevron-up",refresh:"glyphicon-refresh icon-refresh",toggleOff:"glyphicon-list-alt icon-list-alt",toggleOn:"glyphicon-list-alt icon-list-alt",columns:"glyphicon-th icon-th",detailOpen:"glyphicon-plus icon-plus",detailClose:"glyphicon-minus icon-minus",fullscreen:"glyphicon-fullscreen",search:"glyphicon-search",clearSearch:"glyphicon-trash"},fa:{paginationSwitchDown:"fa-caret-square-down",paginationSwitchUp:"fa-caret-square-up",refresh:"fa-sync",toggleOff:"fa-toggle-off",toggleOn:"fa-toggle-on",columns:"fa-th-list",detailOpen:"fa-plus",detailClose:"fa-minus",fullscreen:"fa-arrows-alt",search:"fa-search",clearSearch:"fa-trash"},bi:{paginationSwitchDown:"bi-caret-down-square",paginationSwitchUp:"bi-caret-up-square",refresh:"bi-arrow-clockwise",toggleOff:"bi-toggle-off",toggleOn:"bi-toggle-on",columns:"bi-list-ul",detailOpen:"bi-plus",detailClose:"bi-dash",fullscreen:"bi-arrows-move",search:"bi-search",clearSearch:"bi-trash"},icon:{paginationSwitchDown:"icon-arrow-up-circle",paginationSwitchUp:"icon-arrow-down-circle",refresh:"icon-refresh-cw",toggleOff:"icon-toggle-right",toggleOn:"icon-toggle-right",columns:"icon-list",detailOpen:"icon-plus",detailClose:"icon-minus",fullscreen:"icon-maximize",search:"icon-search",clearSearch:"icon-trash-2"},"material-icons":{paginationSwitchDown:"grid_on",paginationSwitchUp:"grid_off",refresh:"refresh",toggleOff:"tablet",toggleOn:"tablet_android",columns:"view_list",detailOpen:"add",detailClose:"remove",fullscreen:"fullscreen",sort:"sort",search:"search",clearSearch:"delete"}}[t]},getSearchInput:function(t){return"string"==typeof t.options.searchSelector?i.default(t.options.searchSelector):t.$toolbar.find(".search input")},sprintf:function(t){for(var e=arguments.length,i=new Array(e>1?e-1:0),n=1;n<e;n++)i[n-1]=arguments[n];var o=!0,a=0,r=t.replace(/%s/g,(function(){var t=i[a++];return void 0===t?(o=!1,""):t}));return o?r:""},isObject:function(t){return t instanceof Object&&!Array.isArray(t)},isEmptyObject:function(){var t=arguments.length>0&&void 0!==arguments[0]?arguments[0]:{};return 0===Object.entries(t).length&&t.constructor===Object},isNumeric:function(t){return!isNaN(parseFloat(t))&&isFinite(t)},getFieldTitle:function(t,e){var i,n=u(t);try{for(n.s();!(i=n.n()).done;){var o=i.value;if(o.field===e)return o.title}}catch(t){n.e(t)}finally{n.f()}return""},setFieldIndex:function(t){var e,i=0,n=[],o=u(t[0]);try{for(o.s();!(e=o.n()).done;){i+=e.value.colspan||1}}catch(t){o.e(t)}finally{o.f()}for(var a=0;a<t.length;a++){n[a]=[];for(var r=0;r<i;r++)n[a][r]=!1}for(var s=0;s<t.length;s++){var l,c=u(t[s]);try{for(c.s();!(l=c.n()).done;){var h=l.value,d=h.rowspan||1,f=h.colspan||1,p=n[s].indexOf(!1);h.colspanIndex=p,1===f?(h.fieldIndex=p,void 0===h.field&&(h.field=p)):h.colspanGroup=h.colspan;for(var g=0;g<d;g++)for(var v=0;v<f;v++)n[s+g][p+v]=!0}}catch(t){c.e(t)}finally{c.f()}}},normalizeAccent:function(t){return"string"!=typeof t?t:t.normalize("NFD").replace(/[\u0300-\u036f]/g,"")},updateFieldGroup:function(t,e){var i,n,o=(i=[]).concat.apply(i,l(t)),a=u(t);try{for(a.s();!(n=a.n()).done;){var r,s=u(n.value);try{for(s.s();!(r=s.n()).done;){var c=r.value;if(c.colspanGroup>1){for(var h=0,d=function(t){o.find((function(e){return e.fieldIndex===t})).visible&&h++},f=c.colspanIndex;f<c.colspanIndex+c.colspanGroup;f++)d(f);c.colspan=h,c.visible=h>0}}}catch(t){s.e(t)}finally{s.f()}}}catch(t){a.e(t)}finally{a.f()}if(!(t.length<2)){var p,g=u(e);try{var v=function(){var t=p.value,e=o.filter((function(e){return e.fieldIndex===t.fieldIndex}));if(e.length>1){var i,n=u(e);try{for(n.s();!(i=n.n()).done;){i.value.visible=t.visible}}catch(t){n.e(t)}finally{n.f()}}};for(g.s();!(p=g.n()).done;)v()}catch(t){g.e(t)}finally{g.f()}}},getScrollBarWidth:function(){if(void 0===this.cachedWidth){var t=i.default("<div/>").addClass("fixed-table-scroll-inner"),e=i.default("<div/>").addClass("fixed-table-scroll-outer");e.append(t),i.default("body").append(e);var n=t[0].offsetWidth;e.css("overflow","scroll");var o=t[0].offsetWidth;n===o&&(o=e[0].clientWidth),e.remove(),this.cachedWidth=n-o}return this.cachedWidth},calculateObjectValue:function(t,e,i,o){var a=e;if("string"==typeof e){var r=e.split(".");if(r.length>1){a=window;var s,c=u(r);try{for(c.s();!(s=c.n()).done;){a=a[s.value]}}catch(t){c.e(t)}finally{c.f()}}else a=window[e]}return null!==a&&"object"===n(a)?a:"function"==typeof a?a.apply(t,i||[]):!a&&"string"==typeof e&&i&&this.sprintf.apply(this,[e].concat(l(i)))?this.sprintf.apply(this,[e].concat(l(i))):o},compareObjects:function(t,e,i){var n=Object.keys(t),o=Object.keys(e);if(i&&n.length!==o.length)return!1;for(var a=0,r=n;a<r.length;a++){var s=r[a];if(o.includes(s)&&t[s]!==e[s])return!1}return!0},regexCompare:function(t,e){try{var i=e.match(/^\/(.*?)\/([gim]*)$/);if(-1!==t.toString().search(i?new RegExp(i[1],i[2]):new RegExp(e,"gim")))return!0}catch(t){return!1}return!1},escapeHTML:function(t){return t?t.toString().replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&#39;"):t},unescapeHTML:function(t){return"string"==typeof t&&t?t.toString().replace(/&amp;/g,"&").replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&quot;/g,'"').replace(/&#39;/g,"'"):t},removeHTML:function(t){return t?t.toString().replace(/(<([^>]+)>)/gi,"").replace(/&[#A-Za-z0-9]+;/gi,"").trim():t},getRealDataAttr:function(t){for(var e=0,i=Object.entries(t);e<i.length;e++){var n=s(i[e],2),o=n[0],a=n[1],r=o.split(/(?=[A-Z])/).join("-").toLowerCase();r!==o&&(t[r]=a,delete t[o])}return t},getItemField:function(t,e,i){var n=arguments.length>3&&void 0!==arguments[3]?arguments[3]:void 0,o=t;if(void 0!==n&&(i=n),"string"!=typeof e||t.hasOwnProperty(e))return i?this.escapeHTML(t[e]):t[e];var a,r=e.split("."),s=u(r);try{for(s.s();!(a=s.n()).done;){var l=a.value;o=o&&o[l]}}catch(t){s.e(t)}finally{s.f()}return i?this.escapeHTML(o):o},isIEBrowser:function(){return navigator.userAgent.includes("MSIE ")||/Trident.*rv:11\./.test(navigator.userAgent)},findIndex:function(t,e){var i,n=u(t);try{for(n.s();!(i=n.n()).done;){var o=i.value;if(JSON.stringify(o)===JSON.stringify(e))return t.indexOf(o)}}catch(t){n.e(t)}finally{n.f()}return-1},trToData:function(t,e){var n=this,o=[],a=[];return e.each((function(e,r){var s=i.default(r),l={};l._id=s.attr("id"),l._class=s.attr("class"),l._data=n.getRealDataAttr(s.data()),l._style=s.attr("style"),s.find(">td,>th").each((function(o,r){for(var s=i.default(r),c=+s.attr("colspan")||1,h=+s.attr("rowspan")||1,u=o;a[e]&&a[e][u];u++);for(var d=u;d<u+c;d++)for(var f=e;f<e+h;f++)a[f]||(a[f]=[]),a[f][d]=!0;var p=t[u].field;l[p]=s.html().trim(),l["_".concat(p,"_id")]=s.attr("id"),l["_".concat(p,"_class")]=s.attr("class"),l["_".concat(p,"_rowspan")]=s.attr("rowspan"),l["_".concat(p,"_colspan")]=s.attr("colspan"),l["_".concat(p,"_title")]=s.attr("title"),l["_".concat(p,"_data")]=n.getRealDataAttr(s.data()),l["_".concat(p,"_style")]=s.attr("style")})),o.push(l)})),o},sort:function(t,e,i,n,o,a){if(null==t&&(t=""),null==e&&(e=""),n.sortStable&&t===e&&(t=o,e=a),this.isNumeric(t)&&this.isNumeric(e))return(t=parseFloat(t))<(e=parseFloat(e))?-1*i:t>e?i:0;if(n.sortEmptyLast){if(""===t)return 1;if(""===e)return-1}return t===e?0:("string"!=typeof t&&(t=t.toString()),-1===t.localeCompare(e)?-1*i:i)},getEventName:function(t){var e=arguments.length>1&&void 0!==arguments[1]?arguments[1]:"";return e=e||"".concat(+new Date).concat(~~(1e6*Math.random())),"".concat(t,"-").concat(e)},hasDetailViewIcon:function(t){return t.detailView&&t.detailViewIcon&&!t.cardView},getDetailViewIndexOffset:function(t){return this.hasDetailViewIcon(t)&&"right"!==t.detailViewAlign?1:0},checkAutoMergeCells:function(t){var e,i=u(t);try{for(i.s();!(e=i.n()).done;)for(var n=e.value,o=0,a=Object.keys(n);o<a.length;o++){var r=a[o];if(r.startsWith("_")&&(r.endsWith("_rowspan")||r.endsWith("_colspan")))return!0}}catch(t){i.e(t)}finally{i.f()}return!1},deepCopy:function(t){return void 0===t?t:i.default.extend(!0,Array.isArray(t)?[]:{},t)},debounce:function(t,e,i){var n;return function(){var o=this,a=arguments,r=function(){n=null,i||t.apply(o,a)},s=i&&!n;clearTimeout(n),n=setTimeout(r,e),s&&t.apply(o,a)}}},Kg=Gg.getBootstrapVersion(),Yg={3:{classes:{buttonsPrefix:"btn",buttons:"default",buttonsGroup:"btn-group",buttonsDropdown:"btn-group",pull:"pull",inputGroup:"input-group",inputPrefix:"input-",input:"form-control",select:"form-control",paginationDropdown:"btn-group dropdown",dropup:"dropup",dropdownActive:"active",paginationActive:"active",buttonActive:"active"},html:{toolbarDropdown:['<ul class="dropdown-menu" role="menu">',"</ul>"],toolbarDropdownItem:'<li class="dropdown-item-marker" role="menuitem"><label>%s</label></li>',toolbarDropdownSeparator:'<li class="divider"></li>',pageDropdown:['<ul class="dropdown-menu" role="menu">',"</ul>"],pageDropdownItem:'<li role="menuitem" class="%s"><a href="#">%s</a></li>',dropdownCaret:'<span class="caret"></span>',pagination:['<ul class="pagination%s">',"</ul>"],paginationItem:'<li class="page-item%s"><a class="page-link" aria-label="%s" href="javascript:void(0)">%s</a></li>',icon:'<i class="%s %s"></i>',inputGroup:'<div class="input-group">%s<span class="input-group-btn">%s</span></div>',searchInput:'<input class="%s%s" type="text" placeholder="%s">',searchButton:'<button class="%s" type="button" name="search" title="%s">%s %s</button>',searchClearButton:'<button class="%s" type="button" name="clearSearch" title="%s">%s %s</button>'}},4:{classes:{buttonsPrefix:"btn",buttons:"secondary",buttonsGroup:"btn-group",buttonsDropdown:"btn-group",pull:"float",inputGroup:"btn-group",inputPrefix:"form-control-",input:"form-control",select:"form-control",paginationDropdown:"btn-group dropdown",dropup:"dropup",dropdownActive:"active",paginationActive:"active",buttonActive:"active"},html:{toolbarDropdown:['<div class="dropdown-menu dropdown-menu-right">',"</div>"],toolbarDropdownItem:'<label class="dropdown-item dropdown-item-marker">%s</label>',pageDropdown:['<div class="dropdown-menu">',"</div>"],pageDropdownItem:'<a class="dropdown-item %s" href="#">%s</a>',toolbarDropdownSeparator:'<div class="dropdown-divider"></div>',dropdownCaret:'<span class="caret"></span>',pagination:['<ul class="pagination%s">',"</ul>"],paginationItem:'<li class="page-item%s"><a class="page-link" aria-label="%s" href="javascript:void(0)">%s</a></li>',icon:'<i class="%s %s"></i>',inputGroup:'<div class="input-group">%s<div class="input-group-append">%s</div></div>',searchInput:'<input class="%s%s" type="text" placeholder="%s">',searchButton:'<button class="%s" type="button" name="search" title="%s">%s %s</button>',searchClearButton:'<button class="%s" type="button" name="clearSearch" title="%s">%s %s</button>'}},5:{classes:{buttonsPrefix:"btn",buttons:"secondary",buttonsGroup:"btn-group",buttonsDropdown:"btn-group",pull:"float",inputGroup:"btn-group",inputPrefix:"form-control-",input:"form-control",select:"form-select",paginationDropdown:"btn-group dropdown",dropup:"dropup",dropdownActive:"active",paginationActive:"active",buttonActive:"active"},html:{dataToggle:"data-bs-toggle",toolbarDropdown:['<div class="dropdown-menu dropdown-menu-right">',"</div>"],toolbarDropdownItem:'<label class="dropdown-item dropdown-item-marker">%s</label>',pageDropdown:['<div class="dropdown-menu">',"</div>"],pageDropdownItem:'<a class="dropdown-item %s" href="#">%s</a>',toolbarDropdownSeparator:'<div class="dropdown-divider"></div>',dropdownCaret:'<span class="caret"></span>',pagination:['<ul class="pagination%s">',"</ul>"],paginationItem:'<li class="page-item%s"><a class="page-link" aria-label="%s" href="javascript:void(0)">%s</a></li>',icon:'<i class="%s %s"></i>',inputGroup:'<div class="input-group">%s%s</div>',searchInput:'<input class="%s%s" type="text" placeholder="%s">',searchButton:'<button class="%s" type="button" name="search" title="%s">%s %s</button>',searchClearButton:'<button class="%s" type="button" name="clearSearch" title="%s">%s %s</button>'}}}[Kg],Jg={height:void 0,classes:"table table-bordered table-hover",buttons:{},theadClasses:"",headerStyle:function(t){return{}},rowStyle:function(t,e){return{}},rowAttributes:function(t,e){return{}},undefinedText:"-",locale:void 0,virtualScroll:!1,virtualScrollItemHeight:void 0,sortable:!0,sortClass:void 0,silentSort:!0,sortEmptyLast:!1,sortName:void 0,sortOrder:void 0,sortReset:!1,sortStable:!1,rememberOrder:!1,serverSort:!0,customSort:void 0,columns:[[]],data:[],url:void 0,method:"get",cache:!0,contentType:"application/json",dataType:"json",ajax:void 0,ajaxOptions:{},queryParams:function(t){return t},queryParamsType:"limit",responseHandler:function(t){return t},totalField:"total",totalNotFilteredField:"totalNotFiltered",dataField:"rows",footerField:"footer",pagination:!1,paginationParts:["pageInfo","pageSize","pageList"],showExtendedPagination:!1,paginationLoop:!0,sidePagination:"client",totalRows:0,totalNotFiltered:0,pageNumber:1,pageSize:10,pageList:[10,25,50,100],paginationHAlign:"right",paginationVAlign:"bottom",paginationDetailHAlign:"left",paginationPreText:"&lsaquo;",paginationNextText:"&rsaquo;",paginationSuccessivelySize:5,paginationPagesBySide:1,paginationUseIntermediate:!1,search:!1,searchHighlight:!1,searchOnEnterKey:!1,strictSearch:!1,regexSearch:!1,searchSelector:!1,visibleSearch:!1,showButtonIcons:!0,showButtonText:!1,showSearchButton:!1,showSearchClearButton:!1,trimOnSearch:!0,searchAlign:"right",searchTimeOut:500,searchText:"",customSearch:void 0,showHeader:!0,showFooter:!1,footerStyle:function(t){return{}},searchAccentNeutralise:!1,showColumns:!1,showColumnsToggleAll:!1,showColumnsSearch:!1,minimumCountColumns:1,showPaginationSwitch:!1,showRefresh:!1,showToggle:!1,showFullscreen:!1,smartDisplay:!0,escape:!1,filterOptions:{filterAlgorithm:"and"},idField:void 0,selectItemName:"btSelectItem",clickToSelect:!1,ignoreClickToSelectOn:function(t){var e=t.tagName;return["A","BUTTON"].includes(e)},singleSelect:!1,checkboxHeader:!0,maintainMetaData:!1,multipleSelectRow:!1,uniqueId:void 0,cardView:!1,detailView:!1,detailViewIcon:!0,detailViewByClick:!1,detailViewAlign:"left",detailFormatter:function(t,e){return""},detailFilter:function(t,e){return!0},toolbar:void 0,toolbarAlign:"left",buttonsToolbar:void 0,buttonsAlign:"right",buttonsOrder:["paginationSwitch","refresh","toggle","fullscreen","columns"],buttonsPrefix:Yg.classes.buttonsPrefix,buttonsClass:Yg.classes.buttons,iconsPrefix:void 0,icons:{},iconSize:void 0,loadingFontSize:"auto",loadingTemplate:function(t){return'<span class="loading-wrap">\n      <span class="loading-text">'.concat(t,'</span>\n      <span class="animation-wrap"><span class="animation-dot"></span></span>\n      </span>\n    ')},onAll:function(t,e){return!1},onClickCell:function(t,e,i,n){return!1},onDblClickCell:function(t,e,i,n){return!1},onClickRow:function(t,e){return!1},onDblClickRow:function(t,e){return!1},onSort:function(t,e){return!1},onCheck:function(t){return!1},onUncheck:function(t){return!1},onCheckAll:function(t){return!1},onUncheckAll:function(t){return!1},onCheckSome:function(t){return!1},onUncheckSome:function(t){return!1},onLoadSuccess:function(t){return!1},onLoadError:function(t){return!1},onColumnSwitch:function(t,e){return!1},onColumnSwitchAll:function(t){return!1},onPageChange:function(t,e){return!1},onSearch:function(t){return!1},onToggle:function(t){return!1},onPreBody:function(t){return!1},onPostBody:function(){return!1},onPostHeader:function(){return!1},onPostFooter:function(){return!1},onExpandRow:function(t,e,i){return!1},onCollapseRow:function(t,e){return!1},onRefreshOptions:function(t){return!1},onRefresh:function(t){return!1},onResetView:function(){return!1},onScrollBody:function(){return!1},onTogglePagination:function(t){return!1},onVirtualScroll:function(t,e){return!1}},Xg={formatLoadingMessage:function(){return"Loading, please wait"},formatRecordsPerPage:function(t){return"".concat(t," rows per page")},formatShowingRows:function(t,e,i,n){return void 0!==n&&n>0&&n>i?"Showing ".concat(t," to ").concat(e," of ").concat(i," rows (filtered from ").concat(n," total rows)"):"Showing ".concat(t," to ").concat(e," of ").concat(i," rows")},formatSRPaginationPreText:function(){return"previous page"},formatSRPaginationPageText:function(t){return"to page ".concat(t)},formatSRPaginationNextText:function(){return"next page"},formatDetailPagination:function(t){return"Showing ".concat(t," rows")},formatSearch:function(){return"Search"},formatClearSearch:function(){return"Clear Search"},formatNoMatches:function(){return"No matching records found"},formatPaginationSwitch:function(){return"Hide/Show pagination"},formatPaginationSwitchDown:function(){return"Show pagination"},formatPaginationSwitchUp:function(){return"Hide pagination"},formatRefresh:function(){return"Refresh"},formatToggleOn:function(){return"Show card view"},formatToggleOff:function(){return"Hide card view"},formatColumns:function(){return"Columns"},formatColumnsToggleAll:function(){return"Toggle all"},formatFullscreen:function(){return"Fullscreen"},formatAllRows:function(){return"All"}},Qg={field:void 0,title:void 0,titleTooltip:void 0,class:void 0,width:void 0,widthUnit:"px",rowspan:void 0,colspan:void 0,align:void 0,halign:void 0,falign:void 0,valign:void 0,cellStyle:void 0,radio:!1,checkbox:!1,checkboxEnabled:!0,clickToSelect:!0,showSelectTitle:!1,sortable:!1,sortName:void 0,order:"asc",sorter:void 0,visible:!0,switchable:!0,cardVisible:!0,searchable:!0,formatter:void 0,footerFormatter:void 0,detailFormatter:void 0,searchFormatter:!0,searchHighlightFormatter:!1,escape:void 0,events:void 0};Object.assign(Jg,Xg);var Zg={VERSION:"1.21.0",THEME:"bootstrap".concat(Kg),CONSTANTS:Yg,DEFAULTS:Jg,COLUMN_DEFAULTS:Qg,METHODS:["getOptions","refreshOptions","getData","getSelections","load","append","prepend","remove","removeAll","insertRow","updateRow","getRowByUniqueId","updateByUniqueId","removeByUniqueId","updateCell","updateCellByUniqueId","showRow","hideRow","getHiddenRows","showColumn","hideColumn","getVisibleColumns","getHiddenColumns","showAllColumns","hideAllColumns","mergeCells","checkAll","uncheckAll","checkInvert","check","uncheck","checkBy","uncheckBy","refresh","destroy","resetView","showLoading","hideLoading","togglePagination","toggleFullscreen","toggleView","resetSearch","filterBy","scrollTo","getScrollPosition","selectPage","prevPage","nextPage","toggleDetailView","expandRow","collapseRow","expandRowByUniqueId","collapseRowByUniqueId","expandAllRows","collapseAllRows","updateColumnTitle","updateFormatText"],EVENTS:{"all.bs.table":"onAll","click-row.bs.table":"onClickRow","dbl-click-row.bs.table":"onDblClickRow","click-cell.bs.table":"onClickCell","dbl-click-cell.bs.table":"onDblClickCell","sort.bs.table":"onSort","check.bs.table":"onCheck","uncheck.bs.table":"onUncheck","check-all.bs.table":"onCheckAll","uncheck-all.bs.table":"onUncheckAll","check-some.bs.table":"onCheckSome","uncheck-some.bs.table":"onUncheckSome","load-success.bs.table":"onLoadSuccess","load-error.bs.table":"onLoadError","column-switch.bs.table":"onColumnSwitch","column-switch-all.bs.table":"onColumnSwitchAll","page-change.bs.table":"onPageChange","search.bs.table":"onSearch","toggle.bs.table":"onToggle","pre-body.bs.table":"onPreBody","post-body.bs.table":"onPostBody","post-header.bs.table":"onPostHeader","post-footer.bs.table":"onPostFooter","expand-row.bs.table":"onExpandRow","collapse-row.bs.table":"onCollapseRow","refresh-options.bs.table":"onRefreshOptions","reset-view.bs.table":"onResetView","refresh.bs.table":"onRefresh","scroll-body.bs.table":"onScrollBody","toggle-pagination.bs.table":"onTogglePagination","virtual-scroll.bs.table":"onVirtualScroll"},LOCALES:{en:Xg,"en-US":Xg}},tv=function(){function t(e){var i=this;o(this,t),this.rows=e.rows,this.scrollEl=e.scrollEl,this.contentEl=e.contentEl,this.callback=e.callback,this.itemHeight=e.itemHeight,this.cache={},this.scrollTop=this.scrollEl.scrollTop,this.initDOM(this.rows,e.fixedScroll),this.scrollEl.scrollTop=this.scrollTop,this.lastCluster=0;var n=function(){i.lastCluster!==(i.lastCluster=i.getNum())&&(i.initDOM(i.rows),i.callback(i.startIndex,i.endIndex))};this.scrollEl.addEventListener("scroll",n,!1),this.destroy=function(){i.contentEl.innerHtml="",i.scrollEl.removeEventListener("scroll",n,!1)}}return r(t,[{key:"initDOM",value:function(t,e){void 0===this.clusterHeight&&(this.cache.scrollTop=this.scrollEl.scrollTop,this.cache.data=this.contentEl.innerHTML=t[0]+t[0]+t[0],this.getRowsHeight(t));var i=this.initData(t,this.getNum(e)),n=i.rows.join(""),o=this.checkChanges("data",n),a=this.checkChanges("top",i.topOffset),r=this.checkChanges("bottom",i.bottomOffset),s=[];o&&a?(i.topOffset&&s.push(this.getExtra("top",i.topOffset)),s.push(n),i.bottomOffset&&s.push(this.getExtra("bottom",i.bottomOffset)),this.startIndex=i.start,this.endIndex=i.end,this.contentEl.innerHTML=s.join(""),e&&(this.contentEl.scrollTop=this.cache.scrollTop)):r&&(this.contentEl.lastChild.style.height="".concat(i.bottomOffset,"px"))}},{key:"getRowsHeight",value:function(){if(void 0===this.itemHeight){var t=this.contentEl.children,e=t[Math.floor(t.length/2)];this.itemHeight=e.offsetHeight}this.blockHeight=50*this.itemHeight,this.clusterRows=200,this.clusterHeight=4*this.blockHeight}},{key:"getNum",value:function(t){return this.scrollTop=t?this.cache.scrollTop:this.scrollEl.scrollTop,Math.floor(this.scrollTop/(this.clusterHeight-this.blockHeight))||0}},{key:"initData",value:function(t,e){if(t.length<50)return{topOffset:0,bottomOffset:0,rowsAbove:0,rows:t};var i=Math.max((this.clusterRows-50)*e,0),n=i+this.clusterRows,o=Math.max(i*this.itemHeight,0),a=Math.max((t.length-n)*this.itemHeight,0),r=[],s=i;o<1&&s++;for(var l=i;l<n;l++)t[l]&&r.push(t[l]);return{start:i,end:n,topOffset:o,bottomOffset:a,rowsAbove:s,rows:r}}},{key:"checkChanges",value:function(t,e){var i=e!==this.cache[t];return this.cache[t]=e,i}},{key:"getExtra",value:function(t,e){var i=document.createElement("tr");return i.className="virtual-scroll-".concat(t),e&&(i.style.height="".concat(e,"px")),i.outerHTML}}]),t}(),ev=function(){function t(e,n){o(this,t),this.options=n,this.$el=i.default(e),this.$el_=this.$el.clone(),this.timeoutId_=0,this.timeoutFooter_=0}return r(t,[{key:"init",value:function(){this.initConstants(),this.initLocale(),this.initContainer(),this.initTable(),this.initHeader(),this.initData(),this.initHiddenRows(),this.initToolbar(),this.initPagination(),this.initBody(),this.initSearchText(),this.initServer()}},{key:"initConstants",value:function(){var t=this.options;this.constants=Zg.CONSTANTS,this.constants.theme=i.default.fn.bootstrapTable.theme,this.constants.dataToggle=this.constants.html.dataToggle||"data-toggle";var e=Gg.getIconsPrefix(i.default.fn.bootstrapTable.theme),o=Gg.getIcons(e);"string"==typeof t.icons&&(t.icons=Gg.calculateObjectValue(null,t.icons)),t.iconsPrefix=t.iconsPrefix||i.default.fn.bootstrapTable.defaults.iconsPrefix||e,t.icons=Object.assign(o,i.default.fn.bootstrapTable.defaults.icons,t.icons);var a=t.buttonsPrefix?"".concat(t.buttonsPrefix,"-"):"";this.constants.buttonsClass=[t.buttonsPrefix,a+t.buttonsClass,Gg.sprintf("".concat(a,"%s"),t.iconSize)].join(" ").trim(),this.buttons=Gg.calculateObjectValue(this,t.buttons,[],{}),"object"!==n(this.buttons)&&(this.buttons={})}},{key:"initLocale",value:function(){if(this.options.locale){var e=i.default.fn.bootstrapTable.locales,n=this.options.locale.split(/-|_/);n[0]=n[0].toLowerCase(),n[1]&&(n[1]=n[1].toUpperCase());var o={};e[this.options.locale]?o=e[this.options.locale]:e[n.join("-")]?o=e[n.join("-")]:e[n[0]]&&(o=e[n[0]]);for(var a=0,r=Object.entries(o);a<r.length;a++){var l=s(r[a],2),c=l[0],h=l[1];this.options[c]===t.DEFAULTS[c]&&(this.options[c]=h)}}}},{key:"initContainer",value:function(){var t=["top","both"].includes(this.options.paginationVAlign)?'<div class="fixed-table-pagination clearfix"></div>':"",e=["bottom","both"].includes(this.options.paginationVAlign)?'<div class="fixed-table-pagination"></div>':"",n=Gg.calculateObjectValue(this.options,this.options.loadingTemplate,[this.options.formatLoadingMessage()]);this.$container=i.default('\n      <div class="bootstrap-table '.concat(this.constants.theme,'">\n      <div class="fixed-table-toolbar"></div>\n      ').concat(t,'\n      <div class="fixed-table-container">\n      <div class="fixed-table-header"><table></table></div>\n      <div class="fixed-table-body">\n      <div class="fixed-table-loading">\n      ').concat(n,'\n      </div>\n      </div>\n      <div class="fixed-table-footer"></div>\n      </div>\n      ').concat(e,"\n      </div>\n    ")),this.$container.insertAfter(this.$el),this.$tableContainer=this.$container.find(".fixed-table-container"),this.$tableHeader=this.$container.find(".fixed-table-header"),this.$tableBody=this.$container.find(".fixed-table-body"),this.$tableLoading=this.$container.find(".fixed-table-loading"),this.$tableFooter=this.$el.find("tfoot"),this.options.buttonsToolbar?this.$toolbar=i.default("body").find(this.options.buttonsToolbar):this.$toolbar=this.$container.find(".fixed-table-toolbar"),this.$pagination=this.$container.find(".fixed-table-pagination"),this.$tableBody.append(this.$el),this.$container.after('<div class="clearfix"></div>'),this.$el.addClass(this.options.classes),this.$tableLoading.addClass(this.options.classes),this.options.height&&(this.$tableContainer.addClass("fixed-height"),this.options.showFooter&&this.$tableContainer.addClass("has-footer"),this.options.classes.split(" ").includes("table-bordered")&&(this.$tableBody.append('<div class="fixed-table-border"></div>'),this.$tableBorder=this.$tableBody.find(".fixed-table-border"),this.$tableLoading.addClass("fixed-table-border")),this.$tableFooter=this.$container.find(".fixed-table-footer"))}},{key:"initTable",value:function(){var e=this,n=[];if(this.$header=this.$el.find(">thead"),this.$header.length?this.options.theadClasses&&this.$header.addClass(this.options.theadClasses):this.$header=i.default('<thead class="'.concat(this.options.theadClasses,'"></thead>')).appendTo(this.$el),this._headerTrClasses=[],this._headerTrStyles=[],this.$header.find("tr").each((function(t,o){var a=i.default(o),r=[];a.find("th").each((function(t,e){var n=i.default(e);void 0!==n.data("field")&&n.data("field","".concat(n.data("field"))),r.push(i.default.extend({},{title:n.html(),class:n.attr("class"),titleTooltip:n.attr("title"),rowspan:n.attr("rowspan")?+n.attr("rowspan"):void 0,colspan:n.attr("colspan")?+n.attr("colspan"):void 0},n.data()))})),n.push(r),a.attr("class")&&e._headerTrClasses.push(a.attr("class")),a.attr("style")&&e._headerTrStyles.push(a.attr("style"))})),Array.isArray(this.options.columns[0])||(this.options.columns=[this.options.columns]),this.options.columns=i.default.extend(!0,[],n,this.options.columns),this.columns=[],this.fieldsColumnsIndex=[],Gg.setFieldIndex(this.options.columns),this.options.columns.forEach((function(n,o){n.forEach((function(n,a){var r=i.default.extend({},t.COLUMN_DEFAULTS,n,{passed:n});void 0!==r.fieldIndex&&(e.columns[r.fieldIndex]=r,e.fieldsColumnsIndex[r.field]=r.fieldIndex),e.options.columns[o][a]=r}))})),!this.options.data.length){var o=Gg.trToData(this.columns,this.$el.find(">tbody>tr"));o.length&&(this.options.data=o,this.fromHtml=!0)}this.options.pagination&&"server"!==this.options.sidePagination||(this.footerData=Gg.trToData(this.columns,this.$el.find(">tfoot>tr"))),this.footerData&&this.$el.find("tfoot").html("<tr></tr>"),!this.options.showFooter||this.options.cardView?this.$tableFooter.hide():this.$tableFooter.show()}},{key:"initHeader",value:function(){var t=this,e={},n=[];this.header={fields:[],styles:[],classes:[],formatters:[],detailFormatters:[],events:[],sorters:[],sortNames:[],cellStyles:[],searchables:[]},Gg.updateFieldGroup(this.options.columns,this.columns),this.options.columns.forEach((function(i,o){var a=[];a.push("<tr".concat(Gg.sprintf(' class="%s"',t._headerTrClasses[o])," ").concat(Gg.sprintf(' style="%s"',t._headerTrStyles[o]),">"));var r="";if(0===o&&Gg.hasDetailViewIcon(t.options)){var l=t.options.columns.length>1?' rowspan="'.concat(t.options.columns.length,'"'):"";r='<th class="detail"'.concat(l,'>\n          <div class="fht-cell"></div>\n          </th>')}r&&"right"!==t.options.detailViewAlign&&a.push(r),i.forEach((function(i,n){var r=Gg.sprintf(' class="%s"',i.class),l=i.widthUnit,c=parseFloat(i.width),h=i.halign?i.halign:i.align,u=Gg.sprintf("text-align: %s; ",h),d=Gg.sprintf("text-align: %s; ",i.align),f=Gg.sprintf("vertical-align: %s; ",i.valign);if(f+=Gg.sprintf("width: %s; ",!i.checkbox&&!i.radio||c?c?c+l:void 0:i.showSelectTitle?void 0:"36px"),void 0!==i.fieldIndex||i.visible){var p=Gg.calculateObjectValue(null,t.options.headerStyle,[i]),g=[],v="";if(p&&p.css)for(var b=0,m=Object.entries(p.css);b<m.length;b++){var y=s(m[b],2),w=y[0],S=y[1];g.push("".concat(w,": ").concat(S))}if(p&&p.classes&&(v=Gg.sprintf(' class="%s"',i.class?[i.class,p.classes].join(" "):p.classes)),void 0!==i.fieldIndex){if(t.header.fields[i.fieldIndex]=i.field,t.header.styles[i.fieldIndex]=d+f,t.header.classes[i.fieldIndex]=r,t.header.formatters[i.fieldIndex]=i.formatter,t.header.detailFormatters[i.fieldIndex]=i.detailFormatter,t.header.events[i.fieldIndex]=i.events,t.header.sorters[i.fieldIndex]=i.sorter,t.header.sortNames[i.fieldIndex]=i.sortName,t.header.cellStyles[i.fieldIndex]=i.cellStyle,t.header.searchables[i.fieldIndex]=i.searchable,!i.visible)return;if(t.options.cardView&&!i.cardVisible)return;e[i.field]=i}a.push("<th".concat(Gg.sprintf(' title="%s"',i.titleTooltip)),i.checkbox||i.radio?Gg.sprintf(' class="bs-checkbox %s"',i.class||""):v||r,Gg.sprintf(' style="%s"',u+f+g.join("; ")),Gg.sprintf(' rowspan="%s"',i.rowspan),Gg.sprintf(' colspan="%s"',i.colspan),Gg.sprintf(' data-field="%s"',i.field),0===n&&o>0?" data-not-first-th":"",">"),a.push(Gg.sprintf('<div class="th-inner %s">',t.options.sortable&&i.sortable?"sortable".concat("center"===h?" sortable-center":""," both"):""));var x=t.options.escape?Gg.escapeHTML(i.title):i.title,k=x;i.checkbox&&(x="",!t.options.singleSelect&&t.options.checkboxHeader&&(x='<label><input name="btSelectAll" type="checkbox" /><span></span></label>'),t.header.stateField=i.field),i.radio&&(x="",t.header.stateField=i.field),!x&&i.showSelectTitle&&(x+=k),a.push(x),a.push("</div>"),a.push('<div class="fht-cell"></div>'),a.push("</div>"),a.push("</th>")}})),r&&"right"===t.options.detailViewAlign&&a.push(r),a.push("</tr>"),a.length>3&&n.push(a.join(""))})),this.$header.html(n.join("")),this.$header.find("th[data-field]").each((function(t,n){i.default(n).data(e[i.default(n).data("field")])})),this.$container.off("click",".th-inner").on("click",".th-inner",(function(e){var n=i.default(e.currentTarget);if(t.options.detailView&&!n.parent().hasClass("bs-checkbox")&&n.closest(".bootstrap-table")[0]!==t.$container[0])return!1;t.options.sortable&&n.parent().data().sortable&&t.onSort(e)}));var o=Gg.getEventName("resize.bootstrap-table",this.$el.attr("id"));i.default(window).off(o),!this.options.showHeader||this.options.cardView?(this.$header.hide(),this.$tableHeader.hide(),this.$tableLoading.css("top",0)):(this.$header.show(),this.$tableHeader.show(),this.$tableLoading.css("top",this.$header.outerHeight()+1),this.getCaret(),i.default(window).on(o,(function(){return t.resetView()}))),this.$selectAll=this.$header.find('[name="btSelectAll"]'),this.$selectAll.off("click").on("click",(function(e){e.stopPropagation();var n=i.default(e.currentTarget).prop("checked");t[n?"checkAll":"uncheckAll"](),t.updateSelected()}))}},{key:"initData",value:function(t,e){"append"===e?this.options.data=this.options.data.concat(t):"prepend"===e?this.options.data=[].concat(t).concat(this.options.data):(t=t||Gg.deepCopy(this.options.data),this.options.data=Array.isArray(t)?t:t[this.options.dataField]),this.data=l(this.options.data),this.options.sortReset&&(this.unsortedData=l(this.data)),"server"!==this.options.sidePagination&&this.initSort()}},{key:"initSort",value:function(){var t=this,e=this.options.sortName,i="desc"===this.options.sortOrder?-1:1,n=this.header.fields.indexOf(this.options.sortName),o=0;-1!==n?(this.options.sortStable&&this.data.forEach((function(t,e){t.hasOwnProperty("_position")||(t._position=e)})),this.options.customSort?Gg.calculateObjectValue(this.options,this.options.customSort,[this.options.sortName,this.options.sortOrder,this.data]):this.data.sort((function(o,a){t.header.sortNames[n]&&(e=t.header.sortNames[n]);var r=Gg.getItemField(o,e,t.options.escape),s=Gg.getItemField(a,e,t.options.escape),l=Gg.calculateObjectValue(t.header,t.header.sorters[n],[r,s,o,a]);return void 0!==l?t.options.sortStable&&0===l?i*(o._position-a._position):i*l:Gg.sort(r,s,i,t.options,o._position,a._position)})),void 0!==this.options.sortClass&&(clearTimeout(o),o=setTimeout((function(){t.$el.removeClass(t.options.sortClass);var e=t.$header.find('[data-field="'.concat(t.options.sortName,'"]')).index();t.$el.find("tr td:nth-child(".concat(e+1,")")).addClass(t.options.sortClass)}),250))):this.options.sortReset&&(this.data=l(this.unsortedData))}},{key:"onSort",value:function(t){var e=t.type,n=t.currentTarget,o="keypress"===e?i.default(n):i.default(n).parent(),a=this.$header.find("th").eq(o.index());if(this.$header.add(this.$header_).find("span.order").remove(),this.options.sortName===o.data("field")){var r=this.options.sortOrder;void 0===r?this.options.sortOrder="asc":"asc"===r?this.options.sortOrder="desc":"desc"===this.options.sortOrder&&(this.options.sortOrder=this.options.sortReset?void 0:"asc"),void 0===this.options.sortOrder&&(this.options.sortName=void 0)}else this.options.sortName=o.data("field"),this.options.rememberOrder?this.options.sortOrder="asc"===o.data("order")?"desc":"asc":this.options.sortOrder=this.columns[this.fieldsColumnsIndex[o.data("field")]].sortOrder||this.columns[this.fieldsColumnsIndex[o.data("field")]].order;if(this.trigger("sort",this.options.sortName,this.options.sortOrder),o.add(a).data("order",this.options.sortOrder),this.getCaret(),"server"===this.options.sidePagination&&this.options.serverSort)return this.options.pageNumber=1,void this.initServer(this.options.silentSort);this.initSort(),this.initBody()}},{key:"initToolbar",value:function(){var t,e=this,o=this.options,a=[],r=0,l=0;this.$toolbar.find(".bs-bars").children().length&&i.default("body").append(i.default(o.toolbar)),this.$toolbar.html(""),"string"!=typeof o.toolbar&&"object"!==n(o.toolbar)||i.default(Gg.sprintf('<div class="bs-bars %s-%s"></div>',this.constants.classes.pull,o.toolbarAlign)).appendTo(this.$toolbar).append(i.default(o.toolbar)),a=['<div class="'.concat(["columns","columns-".concat(o.buttonsAlign),this.constants.classes.buttonsGroup,"".concat(this.constants.classes.pull,"-").concat(o.buttonsAlign)].join(" "),'">')],"string"==typeof o.buttonsOrder&&(o.buttonsOrder=o.buttonsOrder.replace(/\[|\]| |'/g,"").split(",")),this.buttons=Object.assign(this.buttons,{paginationSwitch:{text:o.pagination?o.formatPaginationSwitchUp():o.formatPaginationSwitchDown(),icon:o.pagination?o.icons.paginationSwitchDown:o.icons.paginationSwitchUp,render:!1,event:this.togglePagination,attributes:{"aria-label":o.formatPaginationSwitch(),title:o.formatPaginationSwitch()}},refresh:{text:o.formatRefresh(),icon:o.icons.refresh,render:!1,event:this.refresh,attributes:{"aria-label":o.formatRefresh(),title:o.formatRefresh()}},toggle:{text:o.formatToggleOn(),icon:o.icons.toggleOff,render:!1,event:this.toggleView,attributes:{"aria-label":o.formatToggleOn(),title:o.formatToggleOn()}},fullscreen:{text:o.formatFullscreen(),icon:o.icons.fullscreen,render:!1,event:this.toggleFullscreen,attributes:{"aria-label":o.formatFullscreen(),title:o.formatFullscreen()}},columns:{render:!1,html:function(){var t=[];if(t.push('<div class="keep-open '.concat(e.constants.classes.buttonsDropdown,'" title="').concat(o.formatColumns(),'">\n            <button class="').concat(e.constants.buttonsClass,' dropdown-toggle" type="button" ').concat(e.constants.dataToggle,'="dropdown"\n            aria-label="Columns" title="').concat(o.formatColumns(),'">\n            ').concat(o.showButtonIcons?Gg.sprintf(e.constants.html.icon,o.iconsPrefix,o.icons.columns):"","\n            ").concat(o.showButtonText?o.formatColumns():"","\n            ").concat(e.constants.html.dropdownCaret,"\n            </button>\n            ").concat(e.constants.html.toolbarDropdown[0])),o.showColumnsSearch&&(t.push(Gg.sprintf(e.constants.html.toolbarDropdownItem,Gg.sprintf('<input type="text" class="%s" name="columnsSearch" placeholder="%s" autocomplete="off">',e.constants.classes.input,o.formatSearch()))),t.push(e.constants.html.toolbarDropdownSeparator)),o.showColumnsToggleAll){var i=e.getVisibleColumns().length===e.columns.filter((function(t){return!e.isSelectionColumn(t)})).length;t.push(Gg.sprintf(e.constants.html.toolbarDropdownItem,Gg.sprintf('<input type="checkbox" class="toggle-all" %s> <span>%s</span>',i?'checked="checked"':"",o.formatColumnsToggleAll()))),t.push(e.constants.html.toolbarDropdownSeparator)}var n=0;return e.columns.forEach((function(t){t.visible&&n++})),e.columns.forEach((function(i,a){if(!e.isSelectionColumn(i)&&(!o.cardView||i.cardVisible)){var r=i.visible?' checked="checked"':"",s=n<=o.minimumCountColumns&&r?' disabled="disabled"':"";i.switchable&&(t.push(Gg.sprintf(e.constants.html.toolbarDropdownItem,Gg.sprintf('<input type="checkbox" data-field="%s" value="%s"%s%s> <span>%s</span>',i.field,a,r,s,i.title))),l++)}})),t.push(e.constants.html.toolbarDropdown[1],"</div>"),t.join("")}}});for(var c={},h=0,d=Object.entries(this.buttons);h<d.length;h++){var f=s(d[h],2),p=f[0],g=f[1],v=void 0;if(g.hasOwnProperty("html"))"function"==typeof g.html?v=g.html():"string"==typeof g.html&&(v=g.html);else{if(v='<button class="'.concat(this.constants.buttonsClass,'" type="button" name="').concat(p,'"'),g.hasOwnProperty("attributes"))for(var b=0,m=Object.entries(g.attributes);b<m.length;b++){var y=s(m[b],2),w=y[0],S=y[1];v+=" ".concat(w,'="').concat(S,'"')}v+=">",o.showButtonIcons&&g.hasOwnProperty("icon")&&(v+="".concat(Gg.sprintf(this.constants.html.icon,o.iconsPrefix,g.icon)," ")),o.showButtonText&&g.hasOwnProperty("text")&&(v+=g.text),v+="</button>"}c[p]=v;var x="show".concat(p.charAt(0).toUpperCase()).concat(p.substring(1)),k=o[x];!(!g.hasOwnProperty("render")||g.hasOwnProperty("render")&&g.render)||void 0!==k&&!0!==k||(o[x]=!0),o.buttonsOrder.includes(p)||o.buttonsOrder.push(p)}var O,C=u(o.buttonsOrder);try{for(C.s();!(O=C.n()).done;){var T=O.value;o["show".concat(T.charAt(0).toUpperCase()).concat(T.substring(1))]&&a.push(c[T])}}catch(t){C.e(t)}finally{C.f()}a.push("</div>"),(this.showToolbar||a.length>2)&&this.$toolbar.append(a.join(""));for(var I=0,P=Object.entries(this.buttons);I<P.length;I++){var A=s(P[I],2),$=A[0],R=A[1];if(R.hasOwnProperty("event")){if("function"==typeof R.event||"string"==typeof R.event)if("continue"===function(){var t="string"==typeof R.event?window[R.event]:R.event;return e.$toolbar.find('button[name="'.concat($,'"]')).off("click").on("click",(function(){return t.call(e)})),"continue"}())continue;for(var E=function(){var t=s(F[j],2),i=t[0],n=t[1],o="string"==typeof n?window[n]:n;e.$toolbar.find('button[name="'.concat($,'"]')).off(i).on(i,(function(){return o.call(e)}))},j=0,F=Object.entries(R.event);j<F.length;j++)E()}}if(o.showColumns){var N=(t=this.$toolbar.find(".keep-open")).find('input[type="checkbox"]:not(".toggle-all")'),_=t.find('input[type="checkbox"].toggle-all');if(l<=o.minimumCountColumns&&t.find("input").prop("disabled",!0),t.find("li, label").off("click").on("click",(function(t){t.stopImmediatePropagation()})),N.off("click").on("click",(function(t){var n=t.currentTarget,o=i.default(n);e._toggleColumn(o.val(),o.prop("checked"),!1),e.trigger("column-switch",o.data("field"),o.prop("checked")),_.prop("checked",N.filter(":checked").length===e.columns.filter((function(t){return!e.isSelectionColumn(t)})).length)})),_.off("click").on("click",(function(t){var n=t.currentTarget;e._toggleAllColumns(i.default(n).prop("checked")),e.trigger("column-switch-all",i.default(n).prop("checked"))})),o.showColumnsSearch){var D=t.find('[name="columnsSearch"]'),V=t.find(".dropdown-item-marker");D.on("keyup paste change",(function(t){var e=t.currentTarget,n=i.default(e).val().toLowerCase();V.show(),N.each((function(t,e){var o=i.default(e).parents(".dropdown-item-marker");o.text().toLowerCase().includes(n)||o.hide()}))}))}}var B=function(t){var i="keyup drop blur mouseup";t.off(i).on(i,(function(t){o.searchOnEnterKey&&13!==t.keyCode||[37,38,39,40].includes(t.keyCode)||(clearTimeout(r),r=setTimeout((function(){e.onSearch({currentTarget:t.currentTarget})}),o.searchTimeOut))}))};if((o.search||this.showSearchClearButton)&&"string"!=typeof o.searchSelector){a=[];var L=Gg.sprintf(this.constants.html.searchButton,this.constants.buttonsClass,o.formatSearch(),o.showButtonIcons?Gg.sprintf(this.constants.html.icon,o.iconsPrefix,o.icons.search):"",o.showButtonText?o.formatSearch():""),H=Gg.sprintf(this.constants.html.searchClearButton,this.constants.buttonsClass,o.formatClearSearch(),o.showButtonIcons?Gg.sprintf(this.constants.html.icon,o.iconsPrefix,o.icons.clearSearch):"",o.showButtonText?o.formatClearSearch():""),M='<input class="'.concat(this.constants.classes.input,"\n        ").concat(Gg.sprintf(" %s%s",this.constants.classes.inputPrefix,o.iconSize),'\n        search-input" type="search" placeholder="').concat(o.formatSearch(),'" autocomplete="off">'),U=M;if(o.showSearchButton||o.showSearchClearButton){var z=(o.showSearchButton?L:"")+(o.showSearchClearButton?H:"");U=o.search?Gg.sprintf(this.constants.html.inputGroup,M,z):z}a.push(Gg.sprintf('\n        <div class="'.concat(this.constants.classes.pull,"-").concat(o.searchAlign," search ").concat(this.constants.classes.inputGroup,'">\n          %s\n        </div>\n      '),U)),this.$toolbar.append(a.join(""));var q=Gg.getSearchInput(this);o.showSearchButton?(this.$toolbar.find(".search button[name=search]").off("click").on("click",(function(){clearTimeout(r),r=setTimeout((function(){e.onSearch({currentTarget:q})}),o.searchTimeOut)})),o.searchOnEnterKey&&B(q)):B(q),o.showSearchClearButton&&this.$toolbar.find(".search button[name=clearSearch]").click((function(){e.resetSearch()}))}else if("string"==typeof o.searchSelector){B(Gg.getSearchInput(this))}}},{key:"onSearch",value:function(){var t=arguments.length>0&&void 0!==arguments[0]?arguments[0]:{},e=t.currentTarget,n=t.firedByInitSearchText,o=!(arguments.length>1&&void 0!==arguments[1])||arguments[1];if(void 0!==e&&i.default(e).length&&o){var a=i.default(e).val().trim();if(this.options.trimOnSearch&&i.default(e).val()!==a&&i.default(e).val(a),this.searchText===a)return;var r=Gg.getSearchInput(this),s=e instanceof jQuery?e:i.default(e);(s.is(r)||s.hasClass("search-input"))&&(this.searchText=a,this.options.searchText=a)}n||this.options.cookie||(this.options.pageNumber=1),this.initSearch(),n?"client"===this.options.sidePagination&&this.updatePagination():this.updatePagination(),this.trigger("search",this.searchText)}},{key:"initSearch",value:function(){var t=this;if(this.filterOptions=this.filterOptions||this.options.filterOptions,"server"!==this.options.sidePagination){if(this.options.customSearch)return this.data=Gg.calculateObjectValue(this.options,this.options.customSearch,[this.options.data,this.searchText,this.filterColumns]),this.options.sortReset&&(this.unsortedData=l(this.data)),void this.initSort();var e=this.searchText&&(this.fromHtml?Gg.escapeHTML(this.searchText):this.searchText),i=e?e.toLowerCase():"",n=Gg.isEmptyObject(this.filterColumns)?null:this.filterColumns;this.options.searchAccentNeutralise&&(i=Gg.normalizeAccent(i)),"function"==typeof this.filterOptions.filterAlgorithm?this.data=this.options.data.filter((function(e){return t.filterOptions.filterAlgorithm.apply(null,[e,n])})):"string"==typeof this.filterOptions.filterAlgorithm&&(this.data=n?this.options.data.filter((function(e){var i=t.filterOptions.filterAlgorithm;if("and"===i){for(var o in n)if(Array.isArray(n[o])&&!n[o].includes(e[o])||!Array.isArray(n[o])&&e[o]!==n[o])return!1}else if("or"===i){var a=!1;for(var r in n)(Array.isArray(n[r])&&n[r].includes(e[r])||!Array.isArray(n[r])&&e[r]===n[r])&&(a=!0);return a}return!0})):l(this.options.data));var o=this.getVisibleFields();this.data=i?this.data.filter((function(n,a){for(var r=0;r<t.header.fields.length;r++)if(t.header.searchables[r]&&(!t.options.visibleSearch||-1!==o.indexOf(t.header.fields[r]))){var s=Gg.isNumeric(t.header.fields[r])?parseInt(t.header.fields[r],10):t.header.fields[r],l=t.columns[t.fieldsColumnsIndex[s]],c=void 0;if("string"==typeof s){c=n;for(var h=s.split("."),u=0;u<h.length;u++){if(null===c[h[u]]){c=null;break}c=c[h[u]]}}else c=n[s];if(t.options.searchAccentNeutralise&&(c=Gg.normalizeAccent(c)),l&&l.searchFormatter&&(c=Gg.calculateObjectValue(l,t.header.formatters[r],[c,n,a,l.field],c)),"string"==typeof c||"number"==typeof c){if(t.options.strictSearch&&"".concat(c).toLowerCase()===i||t.options.regexSearch&&Gg.regexCompare(c,e))return!0;var d=/(?:(<=|=>|=<|>=|>|<)(?:\s+)?(-?\d+)?|(-?\d+)?(\s+)?(<=|=>|=<|>=|>|<))/gm.exec(t.searchText),f=!1;if(d){var p=d[1]||"".concat(d[5],"l"),g=d[2]||d[3],v=parseInt(c,10),b=parseInt(g,10);switch(p){case">":case"<l":f=v>b;break;case"<":case">l":f=v<b;break;case"<=":case"=<":case">=l":case"=>l":f=v<=b;break;case">=":case"=>":case"<=l":case"=<l":f=v>=b}}if(f||"".concat(c).toLowerCase().includes(i))return!0}}return!1})):this.data,this.options.sortReset&&(this.unsortedData=l(this.data)),this.initSort()}}},{key:"initPagination",value:function(){var t=this,e=this.options;if(e.pagination){this.$pagination.show();var i,n,o,a,r,s,l,c=[],h=!1,u=this.getData({includeHiddenRows:!1}),d=e.pageList;if("string"==typeof d&&(d=d.replace(/\[|\]| /g,"").toLowerCase().split(",")),d=d.map((function(t){return"string"==typeof t?t.toLowerCase()===e.formatAllRows().toLowerCase()||["all","unlimited"].includes(t.toLowerCase())?e.formatAllRows():+t:t})),this.paginationParts=e.paginationParts,"string"==typeof this.paginationParts&&(this.paginationParts=this.paginationParts.replace(/\[|\]| |'/g,"").split(",")),"server"!==e.sidePagination&&(e.totalRows=u.length),this.totalPages=0,e.totalRows&&(e.pageSize===e.formatAllRows()&&(e.pageSize=e.totalRows,h=!0),this.totalPages=1+~~((e.totalRows-1)/e.pageSize),e.totalPages=this.totalPages),this.totalPages>0&&e.pageNumber>this.totalPages&&(e.pageNumber=this.totalPages),this.pageFrom=(e.pageNumber-1)*e.pageSize+1,this.pageTo=e.pageNumber*e.pageSize,this.pageTo>e.totalRows&&(this.pageTo=e.totalRows),this.options.pagination&&"server"!==this.options.sidePagination&&(this.options.totalNotFiltered=this.options.data.length),this.options.showExtendedPagination||(this.options.totalNotFiltered=void 0),(this.paginationParts.includes("pageInfo")||this.paginationParts.includes("pageInfoShort")||this.paginationParts.includes("pageSize"))&&c.push('<div class="'.concat(this.constants.classes.pull,"-").concat(e.paginationDetailHAlign,' pagination-detail">')),this.paginationParts.includes("pageInfo")||this.paginationParts.includes("pageInfoShort")){var f=this.paginationParts.includes("pageInfoShort")?e.formatDetailPagination(e.totalRows):e.formatShowingRows(this.pageFrom,this.pageTo,e.totalRows,e.totalNotFiltered);c.push('<span class="pagination-info">\n      '.concat(f,"\n      </span>"))}if(this.paginationParts.includes("pageSize")){c.push('<div class="page-list">');var p=['<div class="'.concat(this.constants.classes.paginationDropdown,'">\n        <button class="').concat(this.constants.buttonsClass,' dropdown-toggle" type="button" ').concat(this.constants.dataToggle,'="dropdown">\n        <span class="page-size">\n        ').concat(h?e.formatAllRows():e.pageSize,"\n        </span>\n        ").concat(this.constants.html.dropdownCaret,"\n        </button>\n        ").concat(this.constants.html.pageDropdown[0])];d.forEach((function(i,n){var o;(!e.smartDisplay||0===n||d[n-1]<e.totalRows||i===e.formatAllRows())&&(o=h?i===e.formatAllRows()?t.constants.classes.dropdownActive:"":i===e.pageSize?t.constants.classes.dropdownActive:"",p.push(Gg.sprintf(t.constants.html.pageDropdownItem,o,i)))})),p.push("".concat(this.constants.html.pageDropdown[1],"</div>")),c.push(e.formatRecordsPerPage(p.join("")))}if((this.paginationParts.includes("pageInfo")||this.paginationParts.includes("pageInfoShort")||this.paginationParts.includes("pageSize"))&&c.push("</div></div>"),this.paginationParts.includes("pageList")){c.push('<div class="'.concat(this.constants.classes.pull,"-").concat(e.paginationHAlign,' pagination">'),Gg.sprintf(this.constants.html.pagination[0],Gg.sprintf(" pagination-%s",e.iconSize)),Gg.sprintf(this.constants.html.paginationItem," page-pre",e.formatSRPaginationPreText(),e.paginationPreText)),this.totalPages<e.paginationSuccessivelySize?(n=1,o=this.totalPages):o=(n=e.pageNumber-e.paginationPagesBySide)+2*e.paginationPagesBySide,e.pageNumber<e.paginationSuccessivelySize-1&&(o=e.paginationSuccessivelySize),e.paginationSuccessivelySize>this.totalPages-n&&(n=n-(e.paginationSuccessivelySize-(this.totalPages-n))+1),n<1&&(n=1),o>this.totalPages&&(o=this.totalPages);var g=Math.round(e.paginationPagesBySide/2),v=function(i){var n=arguments.length>1&&void 0!==arguments[1]?arguments[1]:"";return Gg.sprintf(t.constants.html.paginationItem,n+(i===e.pageNumber?" ".concat(t.constants.classes.paginationActive):""),e.formatSRPaginationPageText(i),i)};if(n>1){var b=e.paginationPagesBySide;for(b>=n&&(b=n-1),i=1;i<=b;i++)c.push(v(i));n-1===b+1?(i=n-1,c.push(v(i))):n-1>b&&(n-2*e.paginationPagesBySide>e.paginationPagesBySide&&e.paginationUseIntermediate?(i=Math.round((n-g)/2+g),c.push(v(i," page-intermediate"))):c.push(Gg.sprintf(this.constants.html.paginationItem," page-first-separator disabled","","...")))}for(i=n;i<=o;i++)c.push(v(i));if(this.totalPages>o){var m=this.totalPages-(e.paginationPagesBySide-1);for(o>=m&&(m=o+1),o+1===m-1?(i=o+1,c.push(v(i))):m>o+1&&(this.totalPages-o>2*e.paginationPagesBySide&&e.paginationUseIntermediate?(i=Math.round((this.totalPages-g-o)/2+o),c.push(v(i," page-intermediate"))):c.push(Gg.sprintf(this.constants.html.paginationItem," page-last-separator disabled","","..."))),i=m;i<=this.totalPages;i++)c.push(v(i))}c.push(Gg.sprintf(this.constants.html.paginationItem," page-next",e.formatSRPaginationNextText(),e.paginationNextText)),c.push(this.constants.html.pagination[1],"</div>")}this.$pagination.html(c.join(""));var y=["bottom","both"].includes(e.paginationVAlign)?" ".concat(this.constants.classes.dropup):"";this.$pagination.last().find(".page-list > div").addClass(y),e.onlyInfoPagination||(a=this.$pagination.find(".page-list a"),r=this.$pagination.find(".page-pre"),s=this.$pagination.find(".page-next"),l=this.$pagination.find(".page-item").not(".page-next, .page-pre, .page-last-separator, .page-first-separator"),this.totalPages<=1&&this.$pagination.find("div.pagination").hide(),e.smartDisplay&&(d.length<2||e.totalRows<=d[0])&&this.$pagination.find("div.page-list").hide(),this.$pagination[this.getData().length?"show":"hide"](),e.paginationLoop||(1===e.pageNumber&&r.addClass("disabled"),e.pageNumber===this.totalPages&&s.addClass("disabled")),h&&(e.pageSize=e.formatAllRows()),a.off("click").on("click",(function(e){return t.onPageListChange(e)})),r.off("click").on("click",(function(e){return t.onPagePre(e)})),s.off("click").on("click",(function(e){return t.onPageNext(e)})),l.off("click").on("click",(function(e){return t.onPageNumber(e)})))}else this.$pagination.hide()}},{key:"updatePagination",value:function(t){t&&i.default(t.currentTarget).hasClass("disabled")||(this.options.maintainMetaData||this.resetRows(),this.initPagination(),this.trigger("page-change",this.options.pageNumber,this.options.pageSize),"server"===this.options.sidePagination?this.initServer():this.initBody())}},{key:"onPageListChange",value:function(t){t.preventDefault();var e=i.default(t.currentTarget);return e.parent().addClass(this.constants.classes.dropdownActive).siblings().removeClass(this.constants.classes.dropdownActive),this.options.pageSize=e.text().toUpperCase()===this.options.formatAllRows().toUpperCase()?this.options.formatAllRows():+e.text(),this.$toolbar.find(".page-size").text(this.options.pageSize),this.updatePagination(t),!1}},{key:"onPagePre",value:function(t){if(!i.default(t.target).hasClass("disabled"))return t.preventDefault(),this.options.pageNumber-1==0?this.options.pageNumber=this.options.totalPages:this.options.pageNumber--,this.updatePagination(t),!1}},{key:"onPageNext",value:function(t){if(!i.default(t.target).hasClass("disabled"))return t.preventDefault(),this.options.pageNumber+1>this.options.totalPages?this.options.pageNumber=1:this.options.pageNumber++,this.updatePagination(t),!1}},{key:"onPageNumber",value:function(t){if(t.preventDefault(),this.options.pageNumber!==+i.default(t.currentTarget).text())return this.options.pageNumber=+i.default(t.currentTarget).text(),this.updatePagination(t),!1}},{key:"initRow",value:function(t,e,i,o){var a=this,r=[],l={},c=[],h="",u={},d=[];if(!(Gg.findIndex(this.hiddenRows,t)>-1)){if((l=Gg.calculateObjectValue(this.options,this.options.rowStyle,[t,e],l))&&l.css)for(var f=0,p=Object.entries(l.css);f<p.length;f++){var g=s(p[f],2),v=g[0],b=g[1];c.push("".concat(v,": ").concat(b))}if(u=Gg.calculateObjectValue(this.options,this.options.rowAttributes,[t,e],u))for(var m=0,y=Object.entries(u);m<y.length;m++){var w=s(y[m],2),S=w[0],x=w[1];d.push("".concat(S,'="').concat(Gg.escapeHTML(x),'"'))}if(t._data&&!Gg.isEmptyObject(t._data))for(var k=0,O=Object.entries(t._data);k<O.length;k++){var C=s(O[k],2),T=C[0],I=C[1];if("index"===T)return;h+=" data-".concat(T,"='").concat("object"===n(I)?JSON.stringify(I):I,"'")}r.push("<tr",Gg.sprintf(" %s",d.length?d.join(" "):void 0),Gg.sprintf(' id="%s"',Array.isArray(t)?void 0:t._id),Gg.sprintf(' class="%s"',l.classes||(Array.isArray(t)?void 0:t._class)),Gg.sprintf(' style="%s"',Array.isArray(t)?void 0:t._style),' data-index="'.concat(e,'"'),Gg.sprintf(' data-uniqueid="%s"',Gg.getItemField(t,this.options.uniqueId,!1)),Gg.sprintf(' data-has-detail-view="%s"',this.options.detailView&&Gg.calculateObjectValue(null,this.options.detailFilter,[e,t])?"true":void 0),Gg.sprintf("%s",h),">"),this.options.cardView&&r.push('<td colspan="'.concat(this.header.fields.length,'"><div class="card-views">'));var P="";return Gg.hasDetailViewIcon(this.options)&&(P="<td>",Gg.calculateObjectValue(null,this.options.detailFilter,[e,t])&&(P+='\n          <a class="detail-icon" href="#">\n          '.concat(Gg.sprintf(this.constants.html.icon,this.options.iconsPrefix,this.options.icons.detailOpen),"\n          </a>\n        ")),P+="</td>"),P&&"right"!==this.options.detailViewAlign&&r.push(P),this.header.fields.forEach((function(i,n){var o=a.columns[n],l="",h=Gg.getItemField(t,i,a.options.escape,o.escape),u="",d="",f={},p="",g=a.header.classes[n],v="",b="",m="",y="",w="",S="";if((!a.fromHtml&&!a.autoMergeCells||void 0!==h||o.checkbox||o.radio)&&o.visible&&(!a.options.cardView||o.cardVisible)){if(c.concat([a.header.styles[n]]).length&&(b+="".concat(c.concat([a.header.styles[n]]).join("; "))),t["_".concat(i,"_style")]&&(b+="".concat(t["_".concat(i,"_style")])),b&&(v=' style="'.concat(b,'"')),t["_".concat(i,"_id")]&&(p=Gg.sprintf(' id="%s"',t["_".concat(i,"_id")])),t["_".concat(i,"_class")]&&(g=Gg.sprintf(' class="%s"',t["_".concat(i,"_class")])),t["_".concat(i,"_rowspan")]&&(y=Gg.sprintf(' rowspan="%s"',t["_".concat(i,"_rowspan")])),t["_".concat(i,"_colspan")]&&(w=Gg.sprintf(' colspan="%s"',t["_".concat(i,"_colspan")])),t["_".concat(i,"_title")]&&(S=Gg.sprintf(' title="%s"',t["_".concat(i,"_title")])),(f=Gg.calculateObjectValue(a.header,a.header.cellStyles[n],[h,t,e,i],f)).classes&&(g=' class="'.concat(f.classes,'"')),f.css){for(var x=[],k=0,O=Object.entries(f.css);k<O.length;k++){var C=s(O[k],2),T=C[0],I=C[1];x.push("".concat(T,": ").concat(I))}v=' style="'.concat(x.concat(a.header.styles[n]).join("; "),'"')}if(u=Gg.calculateObjectValue(o,a.header.formatters[n],[h,t,e,i],h),o.checkbox||o.radio||(u=null==u?a.options.undefinedText:u),o.searchable&&a.searchText&&a.options.searchHighlight&&!o.checkbox&&!o.radio){var P="",A=a.searchText.replace(/[.*+?^${}()|[\]\\]/g,"\\$&");if(a.options.searchAccentNeutralise){var $=new RegExp("".concat(Gg.normalizeAccent(A)),"gmi").exec(Gg.normalizeAccent(u));$&&(A=u.substring($.index,$.index+A.length))}var R=new RegExp("(".concat(A,")"),"gim"),E="<mark>$1</mark>";if(u&&/<(?=.*? .*?\/ ?>|br|hr|input|!--|wbr)[a-z]+.*?>|<([a-z]+).*?<\/\1>/i.test(u)){var j=(new DOMParser).parseFromString(u.toString(),"text/html").documentElement.textContent,F=j.replace(R,E);j=j.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),P=u.replace(new RegExp("(>\\s*)(".concat(j,")(\\s*)"),"gm"),"$1".concat(F,"$3"))}else P=u.toString().replace(R,E);u=Gg.calculateObjectValue(o,o.searchHighlightFormatter,[u,a.searchText],P)}if(t["_".concat(i,"_data")]&&!Gg.isEmptyObject(t["_".concat(i,"_data")]))for(var N=0,_=Object.entries(t["_".concat(i,"_data")]);N<_.length;N++){var D=s(_[N],2),V=D[0],B=D[1];if("index"===V)return;m+=" data-".concat(V,'="').concat(B,'"')}if(o.checkbox||o.radio){d=o.checkbox?"checkbox":d,d=o.radio?"radio":d;var L=o.class||"",H=Gg.isObject(u)&&u.hasOwnProperty("checked")?u.checked:(!0===u||h)&&!1!==u,M=!o.checkboxEnabled||u&&u.disabled;l=[a.options.cardView?'<div class="card-view '.concat(L,'">'):'<td class="bs-checkbox '.concat(L,'"').concat(g).concat(v,">"),'<label>\n            <input\n            data-index="'.concat(e,'"\n            name="').concat(a.options.selectItemName,'"\n            type="').concat(d,'"\n            ').concat(Gg.sprintf('value="%s"',t[a.options.idField]),"\n            ").concat(Gg.sprintf('checked="%s"',H?"checked":void 0),"\n            ").concat(Gg.sprintf('disabled="%s"',M?"disabled":void 0)," />\n            <span></span>\n            </label>"),a.header.formatters[n]&&"string"==typeof u?u:"",a.options.cardView?"</div>":"</td>"].join(""),t[a.header.stateField]=!0===u||!!h||u&&u.checked}else if(a.options.cardView){var U=a.options.showHeader?'<span class="card-view-title '.concat(f.classes||"",'"').concat(v,">").concat(Gg.getFieldTitle(a.columns,i),"</span>"):"";l='<div class="card-view">'.concat(U,'<span class="card-view-value ').concat(f.classes||"",'"').concat(v,">").concat(u,"</span></div>"),a.options.smartDisplay&&""===u&&(l='<div class="card-view"></div>')}else l="<td".concat(p).concat(g).concat(v).concat(m).concat(y).concat(w).concat(S,">").concat(u,"</td>");r.push(l)}})),P&&"right"===this.options.detailViewAlign&&r.push(P),this.options.cardView&&r.push("</div></td>"),r.push("</tr>"),r.join("")}}},{key:"initBody",value:function(t,e){var n=this,o=this.getData();this.trigger("pre-body",o),this.$body=this.$el.find(">tbody"),this.$body.length||(this.$body=i.default("<tbody></tbody>").appendTo(this.$el)),this.options.pagination&&"server"!==this.options.sidePagination||(this.pageFrom=1,this.pageTo=o.length);var a=[],r=i.default(document.createDocumentFragment()),s=!1,l=[];this.autoMergeCells=Gg.checkAutoMergeCells(o.slice(this.pageFrom-1,this.pageTo));for(var c=this.pageFrom-1;c<this.pageTo;c++){var h=o[c],u=this.initRow(h,c,o,r);if(s=s||!!u,u&&"string"==typeof u){var d=this.options.uniqueId;if(d&&h.hasOwnProperty(d)){var f=h[d],p=this.$body.find(Gg.sprintf('> tr[data-uniqueid="%s"][data-has-detail-view]',f)).next();p.is("tr.detail-view")&&(l.push(c),e&&f===e||(u+=p[0].outerHTML))}this.options.virtualScroll?a.push(u):r.append(u)}}s?this.options.virtualScroll?(this.virtualScroll&&this.virtualScroll.destroy(),this.virtualScroll=new tv({rows:a,fixedScroll:t,scrollEl:this.$tableBody[0],contentEl:this.$body[0],itemHeight:this.options.virtualScrollItemHeight,callback:function(t,e){n.fitHeader(),n.initBodyEvent(),n.trigger("virtual-scroll",t,e)}})):this.$body.html(r):this.$body.html('<tr class="no-records-found">'.concat(Gg.sprintf('<td colspan="%s">%s</td>',this.getVisibleFields().length+Gg.getDetailViewIndexOffset(this.options),this.options.formatNoMatches()),"</tr>")),l.forEach((function(t){n.expandRow(t)})),t||this.scrollTo(0),this.initBodyEvent(),this.initFooter(),this.resetView(),this.updateSelected(),"server"!==this.options.sidePagination&&(this.options.totalRows=o.length),this.trigger("post-body",o)}},{key:"initBodyEvent",value:function(){var t=this;this.$body.find("> tr[data-index] > td").off("click dblclick").on("click dblclick",(function(e){var n=i.default(e.currentTarget);if(!(n.find(".detail-icon").length||n.index()-Gg.getDetailViewIndexOffset(t.options)<0)){var o=n.parent(),a=i.default(e.target).parents(".card-views").children(),r=i.default(e.target).parents(".card-view"),s=o.data("index"),l=t.data[s],c=t.options.cardView?a.index(r):n[0].cellIndex,h=t.getVisibleFields()[c-Gg.getDetailViewIndexOffset(t.options)],u=t.columns[t.fieldsColumnsIndex[h]],d=Gg.getItemField(l,h,t.options.escape,u.escape);if(t.trigger("click"===e.type?"click-cell":"dbl-click-cell",h,d,l,n),t.trigger("click"===e.type?"click-row":"dbl-click-row",l,o,h),"click"===e.type&&t.options.clickToSelect&&u.clickToSelect&&!Gg.calculateObjectValue(t.options,t.options.ignoreClickToSelectOn,[e.target])){var f=o.find(Gg.sprintf('[name="%s"]',t.options.selectItemName));f.length&&f[0].click()}"click"===e.type&&t.options.detailViewByClick&&t.toggleDetailView(s,t.header.detailFormatters[t.fieldsColumnsIndex[h]])}})).off("mousedown").on("mousedown",(function(e){t.multipleSelectRowCtrlKey=e.ctrlKey||e.metaKey,t.multipleSelectRowShiftKey=e.shiftKey})),this.$body.find("> tr[data-index] > td > .detail-icon").off("click").on("click",(function(e){return e.preventDefault(),t.toggleDetailView(i.default(e.currentTarget).parent().parent().data("index")),!1})),this.$selectItem=this.$body.find(Gg.sprintf('[name="%s"]',this.options.selectItemName)),this.$selectItem.off("click").on("click",(function(e){e.stopImmediatePropagation();var n=i.default(e.currentTarget);t._toggleCheck(n.prop("checked"),n.data("index"))})),this.header.events.forEach((function(e,n){var o=e;if(o){if("string"==typeof o&&(o=Gg.calculateObjectValue(null,o)),!o)throw new Error("Unknown event in the scope: ".concat(e));var a=t.header.fields[n],r=t.getVisibleFields().indexOf(a);if(-1!==r){r+=Gg.getDetailViewIndexOffset(t.options);var s=function(e){if(!o.hasOwnProperty(e))return"continue";var n=o[e];t.$body.find(">tr:not(.no-records-found)").each((function(o,s){var l=i.default(s),c=l.find(t.options.cardView?".card-views>.card-view":">td").eq(r),h=e.indexOf(" "),u=e.substring(0,h),d=e.substring(h+1);c.find(d).off(u).on(u,(function(e){var i=l.data("index"),o=t.data[i],r=o[a];n.apply(t,[e,r,o,i])}))}))};for(var l in o)s(l)}}}))}},{key:"initServer",value:function(t,e,n){var o=this,a={},r=this.header.fields.indexOf(this.options.sortName),s={searchText:this.searchText,sortName:this.options.sortName,sortOrder:this.options.sortOrder};if(this.header.sortNames[r]&&(s.sortName=this.header.sortNames[r]),this.options.pagination&&"server"===this.options.sidePagination&&(s.pageSize=this.options.pageSize===this.options.formatAllRows()?this.options.totalRows:this.options.pageSize,s.pageNumber=this.options.pageNumber),n||this.options.url||this.options.ajax){if("limit"===this.options.queryParamsType&&(s={search:s.searchText,sort:s.sortName,order:s.sortOrder},this.options.pagination&&"server"===this.options.sidePagination&&(s.offset=this.options.pageSize===this.options.formatAllRows()?0:this.options.pageSize*(this.options.pageNumber-1),s.limit=this.options.pageSize,0!==s.limit&&this.options.pageSize!==this.options.formatAllRows()||delete s.limit)),this.options.search&&"server"===this.options.sidePagination&&this.columns.filter((function(t){return!t.searchable})).length){s.searchable=[];var l,c=u(this.columns);try{for(c.s();!(l=c.n()).done;){var h=l.value;!h.checkbox&&h.searchable&&(this.options.visibleSearch&&h.visible||!this.options.visibleSearch)&&s.searchable.push(h.field)}}catch(t){c.e(t)}finally{c.f()}}if(Gg.isEmptyObject(this.filterColumnsPartial)||(s.filter=JSON.stringify(this.filterColumnsPartial,null)),i.default.extend(s,e||{}),!1!==(a=Gg.calculateObjectValue(this.options,this.options.queryParams,[s],a))){t||this.showLoading();var d=i.default.extend({},Gg.calculateObjectValue(null,this.options.ajaxOptions),{type:this.options.method,url:n||this.options.url,data:"application/json"===this.options.contentType&&"post"===this.options.method?JSON.stringify(a):a,cache:this.options.cache,contentType:this.options.contentType,dataType:this.options.dataType,success:function(e,i,n){var a=Gg.calculateObjectValue(o.options,o.options.responseHandler,[e,n],e);o.load(a),o.trigger("load-success",a,n&&n.status,n),t||o.hideLoading(),"server"===o.options.sidePagination&&o.options.pageNumber>1&&a[o.options.totalField]>0&&!a[o.options.dataField].length&&o.updatePagination()},error:function(e){if(e&&0===e.status&&o._xhrAbort)o._xhrAbort=!1;else{var i=[];"server"===o.options.sidePagination&&((i={})[o.options.totalField]=0,i[o.options.dataField]=[]),o.load(i),o.trigger("load-error",e&&e.status,e),t||o.hideLoading()}}});return this.options.ajax?Gg.calculateObjectValue(this,this.options.ajax,[d],null):(this._xhr&&4!==this._xhr.readyState&&(this._xhrAbort=!0,this._xhr.abort()),this._xhr=i.default.ajax(d)),a}}}},{key:"initSearchText",value:function(){if(this.options.search&&(this.searchText="",""!==this.options.searchText)){var t=Gg.getSearchInput(this);t.val(this.options.searchText),this.onSearch({currentTarget:t,firedByInitSearchText:!0})}}},{key:"getCaret",value:function(){var t=this;this.$header.find("th").each((function(e,n){i.default(n).find(".sortable").removeClass("desc asc").addClass(i.default(n).data("field")===t.options.sortName?t.options.sortOrder:"both")}))}},{key:"updateSelected",value:function(){var t=this.$selectItem.filter(":enabled").length&&this.$selectItem.filter(":enabled").length===this.$selectItem.filter(":enabled").filter(":checked").length;this.$selectAll.add(this.$selectAll_).prop("checked",t),this.$selectItem.each((function(t,e){i.default(e).closest("tr")[i.default(e).prop("checked")?"addClass":"removeClass"]("selected")}))}},{key:"updateRows",value:function(){var t=this;this.$selectItem.each((function(e,n){t.data[i.default(n).data("index")][t.header.stateField]=i.default(n).prop("checked")}))}},{key:"resetRows",value:function(){var t,e=u(this.data);try{for(e.s();!(t=e.n()).done;){var i=t.value;this.$selectAll.prop("checked",!1),this.$selectItem.prop("checked",!1),this.header.stateField&&(i[this.header.stateField]=!1)}}catch(t){e.e(t)}finally{e.f()}this.initHiddenRows()}},{key:"trigger",value:function(e){for(var n,o,a="".concat(e,".bs.table"),r=arguments.length,s=new Array(r>1?r-1:0),l=1;l<r;l++)s[l-1]=arguments[l];(n=this.options)[t.EVENTS[a]].apply(n,[].concat(s,[this])),this.$el.trigger(i.default.Event(a,{sender:this}),s),(o=this.options).onAll.apply(o,[a].concat([].concat(s,[this]))),this.$el.trigger(i.default.Event("all.bs.table",{sender:this}),[a,s])}},{key:"resetHeader",value:function(){var t=this;clearTimeout(this.timeoutId_),this.timeoutId_=setTimeout((function(){return t.fitHeader()}),this.$el.is(":hidden")?100:0)}},{key:"fitHeader",value:function(){var t=this;if(this.$el.is(":hidden"))this.timeoutId_=setTimeout((function(){return t.fitHeader()}),100);else{var e=this.$tableBody.get(0),n=this.hasScrollBar&&e.scrollHeight>e.clientHeight+this.$header.outerHeight()?Gg.getScrollBarWidth():0;this.$el.css("margin-top",-this.$header.outerHeight());var o=i.default(":focus");if(o.length>0){var a=o.parents("th");if(a.length>0){var r=a.attr("data-field");if(void 0!==r){var s=this.$header.find("[data-field='".concat(r,"']"));s.length>0&&s.find(":input").addClass("focus-temp")}}}this.$header_=this.$header.clone(!0,!0),this.$selectAll_=this.$header_.find('[name="btSelectAll"]'),this.$tableHeader.css("margin-right",n).find("table").css("width",this.$el.outerWidth()).html("").attr("class",this.$el.attr("class")).append(this.$header_),this.$tableLoading.css("width",this.$el.outerWidth());var l=i.default(".focus-temp:visible:eq(0)");l.length>0&&(l.focus(),this.$header.find(".focus-temp").removeClass("focus-temp")),this.$header.find("th[data-field]").each((function(e,n){t.$header_.find(Gg.sprintf('th[data-field="%s"]',i.default(n).data("field"))).data(i.default(n).data())}));for(var c=this.getVisibleFields(),h=this.$header_.find("th"),u=this.$body.find(">tr:not(.no-records-found,.virtual-scroll-top)").eq(0);u.length&&u.find('>td[colspan]:not([colspan="1"])').length;)u=u.next();var d=u.find("> *").length;u.find("> *").each((function(e,n){var o=i.default(n);if(Gg.hasDetailViewIcon(t.options)&&(0===e&&"right"!==t.options.detailViewAlign||e===d-1&&"right"===t.options.detailViewAlign)){var a=h.filter(".detail"),r=a.innerWidth()-a.find(".fht-cell").width();a.find(".fht-cell").width(o.innerWidth()-r)}else{var s=e-Gg.getDetailViewIndexOffset(t.options),l=t.$header_.find(Gg.sprintf('th[data-field="%s"]',c[s]));l.length>1&&(l=i.default(h[o[0].cellIndex]));var u=l.innerWidth()-l.find(".fht-cell").width();l.find(".fht-cell").width(o.innerWidth()-u)}})),this.horizontalScroll(),this.trigger("post-header")}}},{key:"initFooter",value:function(){if(this.options.showFooter&&!this.options.cardView){var t=this.getData(),e=[],i="";Gg.hasDetailViewIcon(this.options)&&(i='<th class="detail"><div class="th-inner"></div><div class="fht-cell"></div></th>'),i&&"right"!==this.options.detailViewAlign&&e.push(i);var n,o=u(this.columns);try{for(o.s();!(n=o.n()).done;){var a,r,l=n.value,c=[],h={},d=Gg.sprintf(' class="%s"',l.class);if(!(!l.visible||this.footerData&&this.footerData.length>0&&!(l.field in this.footerData[0]))){if(this.options.cardView&&!l.cardVisible)return;if(a=Gg.sprintf("text-align: %s; ",l.falign?l.falign:l.align),r=Gg.sprintf("vertical-align: %s; ",l.valign),(h=Gg.calculateObjectValue(null,this.options.footerStyle,[l]))&&h.css)for(var f=0,p=Object.entries(h.css);f<p.length;f++){var g=s(p[f],2),v=g[0],b=g[1];c.push("".concat(v,": ").concat(b))}h&&h.classes&&(d=Gg.sprintf(' class="%s"',l.class?[l.class,h.classes].join(" "):h.classes)),e.push("<th",d,Gg.sprintf(' style="%s"',a+r+c.concat().join("; ")));var m=0;this.footerData&&this.footerData.length>0&&(m=this.footerData[0]["_".concat(l.field,"_colspan")]||0),m&&e.push(' colspan="'.concat(m,'" ')),e.push(">"),e.push('<div class="th-inner">');var y="";this.footerData&&this.footerData.length>0&&(y=this.footerData[0][l.field]||""),e.push(Gg.calculateObjectValue(l,l.footerFormatter,[t,y],y)),e.push("</div>"),e.push('<div class="fht-cell"></div>'),e.push("</div>"),e.push("</th>")}}}catch(t){o.e(t)}finally{o.f()}i&&"right"===this.options.detailViewAlign&&e.push(i),this.options.height||this.$tableFooter.length||(this.$el.append("<tfoot><tr></tr></tfoot>"),this.$tableFooter=this.$el.find("tfoot")),this.$tableFooter.find("tr").length||this.$tableFooter.html("<table><thead><tr></tr></thead></table>"),this.$tableFooter.find("tr").html(e.join("")),this.trigger("post-footer",this.$tableFooter)}}},{key:"fitFooter",value:function(){var t=this;if(this.$el.is(":hidden"))setTimeout((function(){return t.fitFooter()}),100);else{var e=this.$tableBody.get(0),n=this.hasScrollBar&&e.scrollHeight>e.clientHeight+this.$header.outerHeight()?Gg.getScrollBarWidth():0;this.$tableFooter.css("margin-right",n).find("table").css("width",this.$el.outerWidth()).attr("class",this.$el.attr("class"));var o=this.$tableFooter.find("th"),a=this.$body.find(">tr:first-child:not(.no-records-found)");for(o.find(".fht-cell").width("auto");a.length&&a.find('>td[colspan]:not([colspan="1"])').length;)a=a.next();var r=a.find("> *").length;a.find("> *").each((function(e,n){var a=i.default(n);if(Gg.hasDetailViewIcon(t.options)&&(0===e&&"left"===t.options.detailViewAlign||e===r-1&&"right"===t.options.detailViewAlign)){var s=o.filter(".detail"),l=s.innerWidth()-s.find(".fht-cell").width();s.find(".fht-cell").width(a.innerWidth()-l)}else{var c=o.eq(e),h=c.innerWidth()-c.find(".fht-cell").width();c.find(".fht-cell").width(a.innerWidth()-h)}})),this.horizontalScroll()}}},{key:"horizontalScroll",value:function(){var t=this;this.$tableBody.off("scroll").on("scroll",(function(){var e=t.$tableBody.scrollLeft();t.options.showHeader&&t.options.height&&t.$tableHeader.scrollLeft(e),t.options.showFooter&&!t.options.cardView&&t.$tableFooter.scrollLeft(e),t.trigger("scroll-body",t.$tableBody)}))}},{key:"getVisibleFields",value:function(){var t,e=[],i=u(this.header.fields);try{for(i.s();!(t=i.n()).done;){var n=t.value,o=this.columns[this.fieldsColumnsIndex[n]];o&&o.visible&&(!this.options.cardView||o.cardVisible)&&e.push(n)}}catch(t){i.e(t)}finally{i.f()}return e}},{key:"initHiddenRows",value:function(){this.hiddenRows=[]}},{key:"getOptions",value:function(){var t=i.default.extend({},this.options);return delete t.data,i.default.extend(!0,{},t)}},{key:"refreshOptions",value:function(t){Gg.compareObjects(this.options,t,!0)||(this.options=i.default.extend(this.options,t),this.trigger("refresh-options",this.options),this.destroy(),this.init())}},{key:"getData",value:function(t){var e=this,i=this.options.data;if(!(this.searchText||this.options.customSearch||void 0!==this.options.sortName||this.enableCustomSort)&&Gg.isEmptyObject(this.filterColumns)&&"function"!=typeof this.options.filterOptions.filterAlgorithm&&Gg.isEmptyObject(this.filterColumnsPartial)||t&&t.unfiltered||(i=this.data),t&&t.useCurrentPage&&(i=i.slice(this.pageFrom-1,this.pageTo)),t&&!t.includeHiddenRows){var n=this.getHiddenRows();i=i.filter((function(t){return-1===Gg.findIndex(n,t)}))}return t&&t.formatted&&i.forEach((function(t){for(var i=0,n=Object.entries(t);i<n.length;i++){var o=s(n[i],2),a=o[0],r=o[1],l=e.columns[e.fieldsColumnsIndex[a]];if(!l)return;t[a]=Gg.calculateObjectValue(l,e.header.formatters[l.fieldIndex],[r,t,t.index,l.field],r)}})),i}},{key:"getSelections",value:function(){var t=this;return(this.options.maintainMetaData?this.options.data:this.data).filter((function(e){return!0===e[t.header.stateField]}))}},{key:"load",value:function(t){var e,i=t;this.options.pagination&&"server"===this.options.sidePagination&&(this.options.totalRows=i[this.options.totalField],this.options.totalNotFiltered=i[this.options.totalNotFilteredField],this.footerData=i[this.options.footerField]?[i[this.options.footerField]]:void 0),e=i.fixedScroll,i=Array.isArray(i)?i:i[this.options.dataField],this.initData(i),this.initSearch(),this.initPagination(),this.initBody(e)}},{key:"append",value:function(t){this.initData(t,"append"),this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0)}},{key:"prepend",value:function(t){this.initData(t,"prepend"),this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0)}},{key:"remove",value:function(t){for(var e=0,i=this.options.data.length-1;i>=0;i--){var n=this.options.data[i],o=Gg.getItemField(n,t.field,this.options.escape,n.escape);void 0===o&&"$index"!==t.field||(!n.hasOwnProperty(t.field)&&"$index"===t.field&&t.values.includes(i)||t.values.includes(o))&&(e++,this.options.data.splice(i,1))}e&&("server"===this.options.sidePagination&&(this.options.totalRows-=e,this.data=l(this.options.data)),this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0))}},{key:"removeAll",value:function(){this.options.data.length>0&&(this.options.data.splice(0,this.options.data.length),this.initSearch(),this.initPagination(),this.initBody(!0))}},{key:"insertRow",value:function(t){t.hasOwnProperty("index")&&t.hasOwnProperty("row")&&(this.options.data.splice(t.index,0,t.row),this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0))}},{key:"updateRow",value:function(t){var e,n=u(Array.isArray(t)?t:[t]);try{for(n.s();!(e=n.n()).done;){var o=e.value;o.hasOwnProperty("index")&&o.hasOwnProperty("row")&&(o.hasOwnProperty("replace")&&o.replace?this.options.data[o.index]=o.row:i.default.extend(this.options.data[o.index],o.row))}}catch(t){n.e(t)}finally{n.f()}this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0)}},{key:"getRowByUniqueId",value:function(t){var e,i,n=this.options.uniqueId,o=t,a=null;for(e=this.options.data.length-1;e>=0;e--){i=this.options.data[e];var r=Gg.getItemField(i,n,this.options.escape,i.escape);if(void 0!==r&&("string"==typeof r?o=o.toString():"number"==typeof r&&(Number(r)===r&&r%1==0?o=parseInt(o,10):r===Number(r)&&0!==r&&(o=parseFloat(o))),r===o)){a=i;break}}return a}},{key:"updateByUniqueId",value:function(t){var e,n=null,o=u(Array.isArray(t)?t:[t]);try{for(o.s();!(e=o.n()).done;){var a=e.value;if(a.hasOwnProperty("id")&&a.hasOwnProperty("row")){var r=this.options.data.indexOf(this.getRowByUniqueId(a.id));-1!==r&&(a.hasOwnProperty("replace")&&a.replace?this.options.data[r]=a.row:i.default.extend(this.options.data[r],a.row),n=a.id)}}}catch(t){o.e(t)}finally{o.f()}this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0,n)}},{key:"removeByUniqueId",value:function(t){var e=this.options.data.length,i=this.getRowByUniqueId(t);i&&this.options.data.splice(this.options.data.indexOf(i),1),e!==this.options.data.length&&("server"===this.options.sidePagination&&(this.options.totalRows-=1,this.data=l(this.options.data)),this.initSearch(),this.initPagination(),this.initBody(!0))}},{key:"updateCell",value:function(t){t.hasOwnProperty("index")&&t.hasOwnProperty("field")&&t.hasOwnProperty("value")&&(this.data[t.index][t.field]=t.value,!1!==t.reinit&&(this.initSort(),this.initBody(!0)))}},{key:"updateCellByUniqueId",value:function(t){var e=this;(Array.isArray(t)?t:[t]).forEach((function(t){var i=t.id,n=t.field,o=t.value,a=e.options.data.indexOf(e.getRowByUniqueId(i));-1!==a&&(e.options.data[a][n]=o)})),!1!==t.reinit&&(this.initSort(),this.initBody(!0))}},{key:"showRow",value:function(t){this._toggleRow(t,!0)}},{key:"hideRow",value:function(t){this._toggleRow(t,!1)}},{key:"_toggleRow",value:function(t,e){var i;if(t.hasOwnProperty("index")?i=this.getData()[t.index]:t.hasOwnProperty("uniqueId")&&(i=this.getRowByUniqueId(t.uniqueId)),i){var n=Gg.findIndex(this.hiddenRows,i);e||-1!==n?e&&n>-1&&this.hiddenRows.splice(n,1):this.hiddenRows.push(i),this.initBody(!0),this.initPagination()}}},{key:"getHiddenRows",value:function(t){if(t)return this.initHiddenRows(),this.initBody(!0),void this.initPagination();var e,i=[],n=u(this.getData());try{for(n.s();!(e=n.n()).done;){var o=e.value;this.hiddenRows.includes(o)&&i.push(o)}}catch(t){n.e(t)}finally{n.f()}return this.hiddenRows=i,i}},{key:"showColumn",value:function(t){var e=this;(Array.isArray(t)?t:[t]).forEach((function(t){e._toggleColumn(e.fieldsColumnsIndex[t],!0,!0)}))}},{key:"hideColumn",value:function(t){var e=this;(Array.isArray(t)?t:[t]).forEach((function(t){e._toggleColumn(e.fieldsColumnsIndex[t],!1,!0)}))}},{key:"_toggleColumn",value:function(t,e,i){if(-1!==t&&this.columns[t].visible!==e&&(this.columns[t].visible=e,this.initHeader(),this.initSearch(),this.initPagination(),this.initBody(),this.options.showColumns)){var n=this.$toolbar.find('.keep-open input:not(".toggle-all")').prop("disabled",!1);i&&n.filter(Gg.sprintf('[value="%s"]',t)).prop("checked",e),n.filter(":checked").length<=this.options.minimumCountColumns&&n.filter(":checked").prop("disabled",!0)}}},{key:"getVisibleColumns",value:function(){var t=this;return this.columns.filter((function(e){return e.visible&&!t.isSelectionColumn(e)}))}},{key:"getHiddenColumns",value:function(){return this.columns.filter((function(t){return!t.visible}))}},{key:"isSelectionColumn",value:function(t){return t.radio||t.checkbox}},{key:"showAllColumns",value:function(){this._toggleAllColumns(!0)}},{key:"hideAllColumns",value:function(){this._toggleAllColumns(!1)}},{key:"_toggleAllColumns",value:function(t){var e,n=this,o=u(this.columns.slice().reverse());try{for(o.s();!(e=o.n()).done;){var a=e.value;if(a.switchable){if(!t&&this.options.showColumns&&this.getVisibleColumns().filter((function(t){return t.switchable})).length===this.options.minimumCountColumns)continue;a.visible=t}}}catch(t){o.e(t)}finally{o.f()}if(this.initHeader(),this.initSearch(),this.initPagination(),this.initBody(),this.options.showColumns){var r=this.$toolbar.find('.keep-open input[type="checkbox"]:not(".toggle-all")').prop("disabled",!1);t?r.prop("checked",t):r.get().reverse().forEach((function(e){r.filter(":checked").length>n.options.minimumCountColumns&&i.default(e).prop("checked",t)})),r.filter(":checked").length<=this.options.minimumCountColumns&&r.filter(":checked").prop("disabled",!0)}}},{key:"mergeCells",value:function(t){var e,i,n=t.index,o=this.getVisibleFields().indexOf(t.field),a=t.rowspan||1,r=t.colspan||1,s=this.$body.find(">tr[data-index]");o+=Gg.getDetailViewIndexOffset(this.options);var l=s.eq(n).find(">td").eq(o);if(!(n<0||o<0||n>=this.data.length)){for(e=n;e<n+a;e++)for(i=o;i<o+r;i++)s.eq(e).find(">td").eq(i).hide();l.attr("rowspan",a).attr("colspan",r).show()}}},{key:"checkAll",value:function(){this._toggleCheckAll(!0)}},{key:"uncheckAll",value:function(){this._toggleCheckAll(!1)}},{key:"_toggleCheckAll",value:function(t){var e=this.getSelections();this.$selectAll.add(this.$selectAll_).prop("checked",t),this.$selectItem.filter(":enabled").prop("checked",t),this.updateRows(),this.updateSelected();var i=this.getSelections();t?this.trigger("check-all",i,e):this.trigger("uncheck-all",i,e)}},{key:"checkInvert",value:function(){var t=this.$selectItem.filter(":enabled"),e=t.filter(":checked");t.each((function(t,e){i.default(e).prop("checked",!i.default(e).prop("checked"))})),this.updateRows(),this.updateSelected(),this.trigger("uncheck-some",e),e=this.getSelections(),this.trigger("check-some",e)}},{key:"check",value:function(t){this._toggleCheck(!0,t)}},{key:"uncheck",value:function(t){this._toggleCheck(!1,t)}},{key:"_toggleCheck",value:function(t,e){var i=this.$selectItem.filter('[data-index="'.concat(e,'"]')),n=this.data[e];if(i.is(":radio")||this.options.singleSelect||this.options.multipleSelectRow&&!this.multipleSelectRowCtrlKey&&!this.multipleSelectRowShiftKey){var o,a=u(this.options.data);try{for(a.s();!(o=a.n()).done;){o.value[this.header.stateField]=!1}}catch(t){a.e(t)}finally{a.f()}this.$selectItem.filter(":checked").not(i).prop("checked",!1)}if(n[this.header.stateField]=t,this.options.multipleSelectRow){if(this.multipleSelectRowShiftKey&&this.multipleSelectRowLastSelectedIndex>=0)for(var r=s(this.multipleSelectRowLastSelectedIndex<e?[this.multipleSelectRowLastSelectedIndex,e]:[e,this.multipleSelectRowLastSelectedIndex],2),l=r[0],c=r[1],h=l+1;h<c;h++)this.data[h][this.header.stateField]=!0,this.$selectItem.filter('[data-index="'.concat(h,'"]')).prop("checked",!0);this.multipleSelectRowCtrlKey=!1,this.multipleSelectRowShiftKey=!1,this.multipleSelectRowLastSelectedIndex=t?e:-1}i.prop("checked",t),this.updateSelected(),this.trigger(t?"check":"uncheck",this.data[e],i)}},{key:"checkBy",value:function(t){this._toggleCheckBy(!0,t)}},{key:"uncheckBy",value:function(t){this._toggleCheckBy(!1,t)}},{key:"_toggleCheckBy",value:function(t,e){var i=this;if(e.hasOwnProperty("field")&&e.hasOwnProperty("values")){var n=[];this.data.forEach((function(o,a){if(!o.hasOwnProperty(e.field))return!1;if(e.values.includes(o[e.field])){var r=i.$selectItem.filter(":enabled").filter(Gg.sprintf('[data-index="%s"]',a)),s=!!e.hasOwnProperty("onlyCurrentPage")&&e.onlyCurrentPage;if(!(r=t?r.not(":checked"):r.filter(":checked")).length&&s)return;r.prop("checked",t),o[i.header.stateField]=t,n.push(o),i.trigger(t?"check":"uncheck",o,r)}})),this.updateSelected(),this.trigger(t?"check-some":"uncheck-some",n)}}},{key:"refresh",value:function(t){t&&t.url&&(this.options.url=t.url),t&&t.pageNumber&&(this.options.pageNumber=t.pageNumber),t&&t.pageSize&&(this.options.pageSize=t.pageSize),this.trigger("refresh",this.initServer(t&&t.silent,t&&t.query,t&&t.url))}},{key:"destroy",value:function(){this.$el.insertBefore(this.$container),i.default(this.options.toolbar).insertBefore(this.$el),this.$container.next().remove(),this.$container.remove(),this.$el.html(this.$el_.html()).css("margin-top","0").attr("class",this.$el_.attr("class")||"");var t=Gg.getEventName("resize.bootstrap-table",this.$el.attr("id"));i.default(window).off(t)}},{key:"resetView",value:function(t){var e=0;if(t&&t.height&&(this.options.height=t.height),this.$tableContainer.toggleClass("has-card-view",this.options.cardView),this.options.height){var i=this.$tableBody.get(0);this.hasScrollBar=i.scrollWidth>i.clientWidth}if(!this.options.cardView&&this.options.showHeader&&this.options.height?(this.$tableHeader.show(),this.resetHeader(),e+=this.$header.outerHeight(!0)+1):(this.$tableHeader.hide(),this.trigger("post-header")),!this.options.cardView&&this.options.showFooter&&(this.$tableFooter.show(),this.fitFooter(),this.options.height&&(e+=this.$tableFooter.outerHeight(!0))),this.$container.hasClass("fullscreen"))this.$tableContainer.css("height",""),this.$tableContainer.css("width","");else if(this.options.height){this.$tableBorder&&(this.$tableBorder.css("width",""),this.$tableBorder.css("height",""));var n=this.$toolbar.outerHeight(!0),o=this.$pagination.outerHeight(!0),a=this.options.height-n-o,r=this.$tableBody.find(">table"),s=r.outerHeight();if(this.$tableContainer.css("height","".concat(a,"px")),this.$tableBorder&&r.is(":visible")){var l=a-s-2;this.hasScrollBar&&(l-=Gg.getScrollBarWidth()),this.$tableBorder.css("width","".concat(r.outerWidth(),"px")),this.$tableBorder.css("height","".concat(l,"px"))}}this.options.cardView?(this.$el.css("margin-top","0"),this.$tableContainer.css("padding-bottom","0"),this.$tableFooter.hide()):(this.getCaret(),this.$tableContainer.css("padding-bottom","".concat(e,"px"))),this.trigger("reset-view")}},{key:"showLoading",value:function(){this.$tableLoading.toggleClass("open",!0);var t=this.options.loadingFontSize;"auto"===this.options.loadingFontSize&&(t=.04*this.$tableLoading.width(),t=Math.max(12,t),t=Math.min(32,t),t="".concat(t,"px")),this.$tableLoading.find(".loading-text").css("font-size",t)}},{key:"hideLoading",value:function(){this.$tableLoading.toggleClass("open",!1)}},{key:"togglePagination",value:function(){this.options.pagination=!this.options.pagination;var t=this.options.showButtonIcons?this.options.pagination?this.options.icons.paginationSwitchDown:this.options.icons.paginationSwitchUp:"",e=this.options.showButtonText?this.options.pagination?this.options.formatPaginationSwitchUp():this.options.formatPaginationSwitchDown():"";this.$toolbar.find('button[name="paginationSwitch"]').html("".concat(Gg.sprintf(this.constants.html.icon,this.options.iconsPrefix,t)," ").concat(e)),this.updatePagination(),this.trigger("toggle-pagination",this.options.pagination)}},{key:"toggleFullscreen",value:function(){this.$el.closest(".bootstrap-table").toggleClass("fullscreen"),this.resetView()}},{key:"toggleView",value:function(){this.options.cardView=!this.options.cardView,this.initHeader();var t=this.options.showButtonIcons?this.options.cardView?this.options.icons.toggleOn:this.options.icons.toggleOff:"",e=this.options.showButtonText?this.options.cardView?this.options.formatToggleOff():this.options.formatToggleOn():"";this.$toolbar.find('button[name="toggle"]').html("".concat(Gg.sprintf(this.constants.html.icon,this.options.iconsPrefix,t)," ").concat(e)).attr("aria-label",e).attr("title",e),this.initBody(),this.trigger("toggle",this.options.cardView)}},{key:"resetSearch",value:function(t){var e=Gg.getSearchInput(this),i=t||"";e.val(i),this.searchText=i,this.onSearch({currentTarget:e},!1)}},{key:"filterBy",value:function(t,e){this.filterOptions=Gg.isEmptyObject(e)?this.options.filterOptions:i.default.extend(this.options.filterOptions,e),this.filterColumns=Gg.isEmptyObject(t)?{}:t,this.options.pageNumber=1,this.initSearch(),this.updatePagination()}},{key:"scrollTo",value:function(t){var e={unit:"px",value:0};"object"===n(t)?e=Object.assign(e,t):"string"==typeof t&&"bottom"===t?e.value=this.$tableBody[0].scrollHeight:"string"!=typeof t&&"number"!=typeof t||(e.value=t);var o=e.value;"rows"===e.unit&&(o=0,this.$body.find("> tr:lt(".concat(e.value,")")).each((function(t,e){o+=i.default(e).outerHeight(!0)}))),this.$tableBody.scrollTop(o)}},{key:"getScrollPosition",value:function(){return this.$tableBody.scrollTop()}},{key:"selectPage",value:function(t){t>0&&t<=this.options.totalPages&&(this.options.pageNumber=t,this.updatePagination())}},{key:"prevPage",value:function(){this.options.pageNumber>1&&(this.options.pageNumber--,this.updatePagination())}},{key:"nextPage",value:function(){this.options.pageNumber<this.options.totalPages&&(this.options.pageNumber++,this.updatePagination())}},{key:"toggleDetailView",value:function(t,e){this.$body.find(Gg.sprintf('> tr[data-index="%s"]',t)).next().is("tr.detail-view")?this.collapseRow(t):this.expandRow(t,e),this.resetView()}},{key:"expandRow",value:function(t,e){var i=this.data[t],n=this.$body.find(Gg.sprintf('> tr[data-index="%s"][data-has-detail-view]',t));if(this.options.detailViewIcon&&n.find("a.detail-icon").html(Gg.sprintf(this.constants.html.icon,this.options.iconsPrefix,this.options.icons.detailClose)),!n.next().is("tr.detail-view")){n.after(Gg.sprintf('<tr class="detail-view"><td colspan="%s"></td></tr>',n.children("td").length));var o=n.next().find("td"),a=e||this.options.detailFormatter,r=Gg.calculateObjectValue(this.options,a,[t,i,o],"");1===o.length&&o.append(r),this.trigger("expand-row",t,i,o)}}},{key:"expandRowByUniqueId",value:function(t){var e=this.getRowByUniqueId(t);e&&this.expandRow(this.data.indexOf(e))}},{key:"collapseRow",value:function(t){var e=this.data[t],i=this.$body.find(Gg.sprintf('> tr[data-index="%s"][data-has-detail-view]',t));i.next().is("tr.detail-view")&&(this.options.detailViewIcon&&i.find("a.detail-icon").html(Gg.sprintf(this.constants.html.icon,this.options.iconsPrefix,this.options.icons.detailOpen)),this.trigger("collapse-row",t,e,i.next()),i.next().remove())}},{key:"collapseRowByUniqueId",value:function(t){var e=this.getRowByUniqueId(t);e&&this.collapseRow(this.data.indexOf(e))}},{key:"expandAllRows",value:function(){for(var t=this.$body.find("> tr[data-index][data-has-detail-view]"),e=0;e<t.length;e++)this.expandRow(i.default(t[e]).data("index"))}},{key:"collapseAllRows",value:function(){for(var t=this.$body.find("> tr[data-index][data-has-detail-view]"),e=0;e<t.length;e++)this.collapseRow(i.default(t[e]).data("index"))}},{key:"updateColumnTitle",value:function(t){t.hasOwnProperty("field")&&t.hasOwnProperty("title")&&(this.columns[this.fieldsColumnsIndex[t.field]].title=this.options.escape?Gg.escapeHTML(t.title):t.title,this.columns[this.fieldsColumnsIndex[t.field]].visible&&(this.$header.find("th[data-field]").each((function(e,n){if(i.default(n).data("field")===t.field)return i.default(i.default(n).find(".th-inner")[0]).text(t.title),!1})),this.resetView()))}},{key:"updateFormatText",value:function(t,e){/^format/.test(t)&&this.options[t]&&("string"==typeof e?this.options[t]=function(){return e}:"function"==typeof e&&(this.options[t]=e),this.initToolbar(),this.initPagination(),this.initBody())}}]),t}();return ev.VERSION=Zg.VERSION,ev.DEFAULTS=Zg.DEFAULTS,ev.LOCALES=Zg.LOCALES,ev.COLUMN_DEFAULTS=Zg.COLUMN_DEFAULTS,ev.METHODS=Zg.METHODS,ev.EVENTS=Zg.EVENTS,i.default.BootstrapTable=ev,i.default.fn.bootstrapTable=function(t){for(var e=arguments.length,o=new Array(e>1?e-1:0),a=1;a<e;a++)o[a-1]=arguments[a];var r;return this.each((function(e,a){var s=i.default(a).data("bootstrap.table"),l=i.default.extend({},ev.DEFAULTS,i.default(a).data(),"object"===n(t)&&t);if("string"==typeof t){var c;if(!Zg.METHODS.includes(t))throw new Error("Unknown method: ".concat(t));if(!s)return;r=(c=s)[t].apply(c,o),"destroy"===t&&i.default(a).removeData("bootstrap.table")}s||(s=new i.default.BootstrapTable(a,l),i.default(a).data("bootstrap.table",s),s.init())})),void 0===r?this:r},i.default.fn.bootstrapTable.Constructor=ev,i.default.fn.bootstrapTable.theme=Zg.THEME,i.default.fn.bootstrapTable.VERSION=Zg.VERSION,i.default.fn.bootstrapTable.defaults=ev.DEFAULTS,i.default.fn.bootstrapTable.columnDefaults=ev.COLUMN_DEFAULTS,i.default.fn.bootstrapTable.events=ev.EVENTS,i.default.fn.bootstrapTable.locales=ev.LOCALES,i.default.fn.bootstrapTable.methods=ev.METHODS,i.default.fn.bootstrapTable.utils=Gg,i.default((function(){i.default('[data-toggle="table"]').bootstrapTable()})),ev}));
		</script>
		<script>
			//src="https://unpkg.com/bootstrap-table@1.21.0/dist/extensions/filter-control/bootstrap-table-filter-control.min.js"
			/**
			  * bootstrap-table - An extended table to integration with some of the most widely used CSS frameworks. (Supports Bootstrap, Semantic UI, Bulma, Material Design, Foundation)
			  *
			  * @version v1.21.0
			  * @homepage https://bootstrap-table.com
			  * @author wenzhixin <wenzhixin2010@gmail.com> (http://wenzhixin.net.cn/)
			  * @license MIT
			  */
			!function(t,e){"object"==typeof exports&&"undefined"!=typeof module?e(require("jquery")):"function"==typeof define&&define.amd?define(["jquery"],e):e((t="undefined"!=typeof globalThis?globalThis:t||self).jQuery)}(this,(function(t){"use strict";function e(t){return t&&"object"==typeof t&&"default"in t?t:{default:t}}var r=e(t);function n(t){return n="function"==typeof Symbol&&"symbol"==typeof Symbol.iterator?function(t){return typeof t}:function(t){return t&&"function"==typeof Symbol&&t.constructor===Symbol&&t!==Symbol.prototype?"symbol":typeof t},n(t)}function o(t,e){if(!(t instanceof e))throw new TypeError("Cannot call a class as a function")}function i(t,e){for(var r=0;r<e.length;r++){var n=e[r];n.enumerable=n.enumerable||!1,n.configurable=!0,"value"in n&&(n.writable=!0),Object.defineProperty(t,n.key,n)}}function a(t){return a=Object.setPrototypeOf?Object.getPrototypeOf.bind():function(t){return t.__proto__||Object.getPrototypeOf(t)},a(t)}function l(t,e){return l=Object.setPrototypeOf?Object.setPrototypeOf.bind():function(t,e){return t.__proto__=e,t},l(t,e)}function c(t,e){if(e&&("object"==typeof e||"function"==typeof e))return e;if(void 0!==e)throw new TypeError("Derived constructors may only return object or undefined");return function(t){if(void 0===t)throw new ReferenceError("this hasn't been initialised - super() hasn't been called");return t}(t)}function u(t){var e=function(){if("undefined"==typeof Reflect||!Reflect.construct)return!1;if(Reflect.construct.sham)return!1;if("function"==typeof Proxy)return!0;try{return Boolean.prototype.valueOf.call(Reflect.construct(Boolean,[],(function(){}))),!0}catch(t){return!1}}();return function(){var r,n=a(t);if(e){var o=a(this).constructor;r=Reflect.construct(n,arguments,o)}else r=n.apply(this,arguments);return c(this,r)}}function f(t,e){for(;!Object.prototype.hasOwnProperty.call(t,e)&&null!==(t=a(t)););return t}function s(){return s="undefined"!=typeof Reflect&&Reflect.get?Reflect.get.bind():function(t,e,r){var n=f(t,e);if(n){var o=Object.getOwnPropertyDescriptor(n,e);return o.get?o.get.call(arguments.length<3?t:r):o.value}},s.apply(this,arguments)}function p(t){return function(t){if(Array.isArray(t))return h(t)}(t)||function(t){if("undefined"!=typeof Symbol&&null!=t[Symbol.iterator]||null!=t["@@iterator"])return Array.from(t)}(t)||function(t,e){if(!t)return;if("string"==typeof t)return h(t,e);var r=Object.prototype.toString.call(t).slice(8,-1);"Object"===r&&t.constructor&&(r=t.constructor.name);if("Map"===r||"Set"===r)return Array.from(t);if("Arguments"===r||/^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(r))return h(t,e)}(t)||function(){throw new TypeError("Invalid attempt to spread non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.")}()}function h(t,e){(null==e||e>t.length)&&(e=t.length);for(var r=0,n=new Array(e);r<e;r++)n[r]=t[r];return n}var d="undefined"!=typeof globalThis?globalThis:"undefined"!=typeof window?window:"undefined"!=typeof global?global:"undefined"!=typeof self?self:{},v=function(t){return t&&t.Math==Math&&t},g=v("object"==typeof globalThis&&globalThis)||v("object"==typeof window&&window)||v("object"==typeof self&&self)||v("object"==typeof d&&d)||function(){return this}()||Function("return this")(),y={},b=function(t){try{return!!t()}catch(t){return!0}},m=!b((function(){return 7!=Object.defineProperty({},1,{get:function(){return 7}})[1]})),C=!b((function(){var t=function(){}.bind();return"function"!=typeof t||t.hasOwnProperty("prototype")})),S=C,w=Function.prototype.call,O=S?w.bind(w):function(){return w.apply(w,arguments)},x={},T={}.propertyIsEnumerable,j=Object.getOwnPropertyDescriptor,E=j&&!T.call({1:2},1);x.f=E?function(t){var e=j(this,t);return!!e&&e.enumerable}:T;var P,k,I=function(t,e){return{enumerable:!(1&t),configurable:!(2&t),writable:!(4&t),value:e}},R=C,A=Function.prototype,_=A.bind,L=A.call,F=R&&_.bind(L,L),D=R?function(t){return t&&F(t)}:function(t){return t&&function(){return L.apply(t,arguments)}},M=D,N=M({}.toString),V=M("".slice),$=function(t){return V(N(t),8,-1)},z=b,H=$,B=Object,U=D("".split),G=z((function(){return!B("z").propertyIsEnumerable(0)}))?function(t){return"String"==H(t)?U(t,""):B(t)}:B,K=TypeError,q=function(t){if(null==t)throw K("Can't call method on "+t);return t},W=G,Y=q,J=function(t){return W(Y(t))},X=function(t){return"function"==typeof t},Q=X,Z=function(t){return"object"==typeof t?null!==t:Q(t)},tt=g,et=X,rt=function(t){return et(t)?t:void 0},nt=function(t,e){return arguments.length<2?rt(tt[t]):tt[t]&&tt[t][e]},ot=D({}.isPrototypeOf),it=nt("navigator","userAgent")||"",at=g,lt=it,ct=at.process,ut=at.Deno,ft=ct&&ct.versions||ut&&ut.version,st=ft&&ft.v8;st&&(k=(P=st.split("."))[0]>0&&P[0]<4?1:+(P[0]+P[1])),!k&&lt&&(!(P=lt.match(/Edge\/(\d+)/))||P[1]>=74)&&(P=lt.match(/Chrome\/(\d+)/))&&(k=+P[1]);var pt=k,ht=pt,dt=b,vt=!!Object.getOwnPropertySymbols&&!dt((function(){var t=Symbol();return!String(t)||!(Object(t)instanceof Symbol)||!Symbol.sham&&ht&&ht<41})),gt=vt&&!Symbol.sham&&"symbol"==typeof Symbol.iterator,yt=nt,bt=X,mt=ot,Ct=Object,St=gt?function(t){return"symbol"==typeof t}:function(t){var e=yt("Symbol");return bt(e)&&mt(e.prototype,Ct(t))},wt=String,Ot=function(t){try{return wt(t)}catch(t){return"Object"}},xt=X,Tt=Ot,jt=TypeError,Et=function(t){if(xt(t))return t;throw jt(Tt(t)+" is not a function")},Pt=Et,kt=function(t,e){var r=t[e];return null==r?void 0:Pt(r)},It=O,Rt=X,At=Z,_t=TypeError,Lt={exports:{}},Ft=g,Dt=Object.defineProperty,Mt=function(t,e){try{Dt(Ft,t,{value:e,configurable:!0,writable:!0})}catch(r){Ft[t]=e}return e},Nt=Mt,Vt="__core-js_shared__",$t=g[Vt]||Nt(Vt,{}),zt=$t;(Lt.exports=function(t,e){return zt[t]||(zt[t]=void 0!==e?e:{})})("versions",[]).push({version:"3.22.8",mode:"global",copyright:"© 2014-2022 Denis Pushkarev (zloirock.ru)",license:"https://github.com/zloirock/core-js/blob/v3.22.8/LICENSE",source:"https://github.com/zloirock/core-js"});var Ht=q,Bt=Object,Ut=function(t){return Bt(Ht(t))},Gt=Ut,Kt=D({}.hasOwnProperty),qt=Object.hasOwn||function(t,e){return Kt(Gt(t),e)},Wt=D,Yt=0,Jt=Math.random(),Xt=Wt(1..toString),Qt=function(t){return"Symbol("+(void 0===t?"":t)+")_"+Xt(++Yt+Jt,36)},Zt=g,te=Lt.exports,ee=qt,re=Qt,ne=vt,oe=gt,ie=te("wks"),ae=Zt.Symbol,le=ae&&ae.for,ce=oe?ae:ae&&ae.withoutSetter||re,ue=function(t){if(!ee(ie,t)||!ne&&"string"!=typeof ie[t]){var e="Symbol."+t;ne&&ee(ae,t)?ie[t]=ae[t]:ie[t]=oe&&le?le(e):ce(e)}return ie[t]},fe=O,se=Z,pe=St,he=kt,de=function(t,e){var r,n;if("string"===e&&Rt(r=t.toString)&&!At(n=It(r,t)))return n;if(Rt(r=t.valueOf)&&!At(n=It(r,t)))return n;if("string"!==e&&Rt(r=t.toString)&&!At(n=It(r,t)))return n;throw _t("Can't convert object to primitive value")},ve=TypeError,ge=ue("toPrimitive"),ye=function(t,e){if(!se(t)||pe(t))return t;var r,n=he(t,ge);if(n){if(void 0===e&&(e="default"),r=fe(n,t,e),!se(r)||pe(r))return r;throw ve("Can't convert object to primitive value")}return void 0===e&&(e="number"),de(t,e)},be=St,me=function(t){var e=ye(t,"string");return be(e)?e:e+""},Ce=Z,Se=g.document,we=Ce(Se)&&Ce(Se.createElement),Oe=function(t){return we?Se.createElement(t):{}},xe=Oe,Te=!m&&!b((function(){return 7!=Object.defineProperty(xe("div"),"a",{get:function(){return 7}}).a})),je=m,Ee=O,Pe=x,ke=I,Ie=J,Re=me,Ae=qt,_e=Te,Le=Object.getOwnPropertyDescriptor;y.f=je?Le:function(t,e){if(t=Ie(t),e=Re(e),_e)try{return Le(t,e)}catch(t){}if(Ae(t,e))return ke(!Ee(Pe.f,t,e),t[e])};var Fe={},De=m&&b((function(){return 42!=Object.defineProperty((function(){}),"prototype",{value:42,writable:!1}).prototype})),Me=Z,Ne=String,Ve=TypeError,$e=function(t){if(Me(t))return t;throw Ve(Ne(t)+" is not an object")},ze=m,He=Te,Be=De,Ue=$e,Ge=me,Ke=TypeError,qe=Object.defineProperty,We=Object.getOwnPropertyDescriptor,Ye="enumerable",Je="configurable",Xe="writable";Fe.f=ze?Be?function(t,e,r){if(Ue(t),e=Ge(e),Ue(r),"function"==typeof t&&"prototype"===e&&"value"in r&&Xe in r&&!r.writable){var n=We(t,e);n&&n.writable&&(t[e]=r.value,r={configurable:Je in r?r.configurable:n.configurable,enumerable:Ye in r?r.enumerable:n.enumerable,writable:!1})}return qe(t,e,r)}:qe:function(t,e,r){if(Ue(t),e=Ge(e),Ue(r),He)try{return qe(t,e,r)}catch(t){}if("get"in r||"set"in r)throw Ke("Accessors not supported");return"value"in r&&(t[e]=r.value),t};var Qe=Fe,Ze=I,tr=m?function(t,e,r){return Qe.f(t,e,Ze(1,r))}:function(t,e,r){return t[e]=r,t},er={exports:{}},rr=m,nr=qt,or=Function.prototype,ir=rr&&Object.getOwnPropertyDescriptor,ar=nr(or,"name"),lr={EXISTS:ar,PROPER:ar&&"something"===function(){}.name,CONFIGURABLE:ar&&(!rr||rr&&ir(or,"name").configurable)},cr=X,ur=$t,fr=D(Function.toString);cr(ur.inspectSource)||(ur.inspectSource=function(t){return fr(t)});var sr,pr,hr,dr=ur.inspectSource,vr=X,gr=dr,yr=g.WeakMap,br=vr(yr)&&/native code/.test(gr(yr)),mr=Lt.exports,Cr=Qt,Sr=mr("keys"),wr=function(t){return Sr[t]||(Sr[t]=Cr(t))},Or={},xr=br,Tr=g,jr=D,Er=Z,Pr=tr,kr=qt,Ir=$t,Rr=wr,Ar=Or,_r="Object already initialized",Lr=Tr.TypeError,Fr=Tr.WeakMap;if(xr||Ir.state){var Dr=Ir.state||(Ir.state=new Fr),Mr=jr(Dr.get),Nr=jr(Dr.has),Vr=jr(Dr.set);sr=function(t,e){if(Nr(Dr,t))throw new Lr(_r);return e.facade=t,Vr(Dr,t,e),e},pr=function(t){return Mr(Dr,t)||{}},hr=function(t){return Nr(Dr,t)}}else{var $r=Rr("state");Ar[$r]=!0,sr=function(t,e){if(kr(t,$r))throw new Lr(_r);return e.facade=t,Pr(t,$r,e),e},pr=function(t){return kr(t,$r)?t[$r]:{}},hr=function(t){return kr(t,$r)}}var zr={set:sr,get:pr,has:hr,enforce:function(t){return hr(t)?pr(t):sr(t,{})},getterFor:function(t){return function(e){var r;if(!Er(e)||(r=pr(e)).type!==t)throw Lr("Incompatible receiver, "+t+" required");return r}}},Hr=b,Br=X,Ur=qt,Gr=m,Kr=lr.CONFIGURABLE,qr=dr,Wr=zr.enforce,Yr=zr.get,Jr=Object.defineProperty,Xr=Gr&&!Hr((function(){return 8!==Jr((function(){}),"length",{value:8}).length})),Qr=String(String).split("String"),Zr=er.exports=function(t,e,r){"Symbol("===String(e).slice(0,7)&&(e="["+String(e).replace(/^Symbol\(([^)]*)\)/,"$1")+"]"),r&&r.getter&&(e="get "+e),r&&r.setter&&(e="set "+e),(!Ur(t,"name")||Kr&&t.name!==e)&&Jr(t,"name",{value:e,configurable:!0}),Xr&&r&&Ur(r,"arity")&&t.length!==r.arity&&Jr(t,"length",{value:r.arity});try{r&&Ur(r,"constructor")&&r.constructor?Gr&&Jr(t,"prototype",{writable:!1}):t.prototype&&(t.prototype=void 0)}catch(t){}var n=Wr(t);return Ur(n,"source")||(n.source=Qr.join("string"==typeof e?e:"")),t};Function.prototype.toString=Zr((function(){return Br(this)&&Yr(this).source||qr(this)}),"toString");var tn=X,en=tr,rn=er.exports,nn=Mt,on=function(t,e,r,n){n||(n={});var o=n.enumerable,i=void 0!==n.name?n.name:e;return tn(r)&&rn(r,i,n),n.global?o?t[e]=r:nn(e,r):(n.unsafe?t[e]&&(o=!0):delete t[e],o?t[e]=r:en(t,e,r)),t},an={},ln=Math.ceil,cn=Math.floor,un=Math.trunc||function(t){var e=+t;return(e>0?cn:ln)(e)},fn=function(t){var e=+t;return e!=e||0===e?0:un(e)},sn=fn,pn=Math.max,hn=Math.min,dn=function(t,e){var r=sn(t);return r<0?pn(r+e,0):hn(r,e)},vn=fn,gn=Math.min,yn=function(t){return t>0?gn(vn(t),9007199254740991):0},bn=yn,mn=function(t){return bn(t.length)},Cn=J,Sn=dn,wn=mn,On=function(t){return function(e,r,n){var o,i=Cn(e),a=wn(i),l=Sn(n,a);if(t&&r!=r){for(;a>l;)if((o=i[l++])!=o)return!0}else for(;a>l;l++)if((t||l in i)&&i[l]===r)return t||l||0;return!t&&-1}},xn={includes:On(!0),indexOf:On(!1)},Tn=qt,jn=J,En=xn.indexOf,Pn=Or,kn=D([].push),In=function(t,e){var r,n=jn(t),o=0,i=[];for(r in n)!Tn(Pn,r)&&Tn(n,r)&&kn(i,r);for(;e.length>o;)Tn(n,r=e[o++])&&(~En(i,r)||kn(i,r));return i},Rn=["constructor","hasOwnProperty","isPrototypeOf","propertyIsEnumerable","toLocaleString","toString","valueOf"],An=In,_n=Rn.concat("length","prototype");an.f=Object.getOwnPropertyNames||function(t){return An(t,_n)};var Ln={};Ln.f=Object.getOwnPropertySymbols;var Fn=nt,Dn=an,Mn=Ln,Nn=$e,Vn=D([].concat),$n=Fn("Reflect","ownKeys")||function(t){var e=Dn.f(Nn(t)),r=Mn.f;return r?Vn(e,r(t)):e},zn=qt,Hn=$n,Bn=y,Un=Fe,Gn=b,Kn=X,qn=/#|\.prototype\./,Wn=function(t,e){var r=Jn[Yn(t)];return r==Qn||r!=Xn&&(Kn(e)?Gn(e):!!e)},Yn=Wn.normalize=function(t){return String(t).replace(qn,".").toLowerCase()},Jn=Wn.data={},Xn=Wn.NATIVE="N",Qn=Wn.POLYFILL="P",Zn=Wn,to=g,eo=y.f,ro=tr,no=on,oo=Mt,io=function(t,e,r){for(var n=Hn(e),o=Un.f,i=Bn.f,a=0;a<n.length;a++){var l=n[a];zn(t,l)||r&&zn(r,l)||o(t,l,i(e,l))}},ao=Zn,lo=function(t,e){var r,n,o,i,a,l=t.target,c=t.global,u=t.stat;if(r=c?to:u?to[l]||oo(l,{}):(to[l]||{}).prototype)for(n in e){if(i=e[n],o=t.dontCallGetSet?(a=eo(r,n))&&a.value:r[n],!ao(c?n:l+(u?".":"#")+n,t.forced)&&void 0!==o){if(typeof i==typeof o)continue;io(i,o)}(t.sham||o&&o.sham)&&ro(i,"sham",!0),no(r,n,i,t)}},co=Et,uo=C,fo=D(D.bind),so=function(t,e){return co(t),void 0===e?t:uo?fo(t,e):function(){return t.apply(e,arguments)}},po=$,ho=Array.isArray||function(t){return"Array"==po(t)},vo={};vo[ue("toStringTag")]="z";var go="[object z]"===String(vo),yo=go,bo=X,mo=$,Co=ue("toStringTag"),So=Object,wo="Arguments"==mo(function(){return arguments}()),Oo=yo?mo:function(t){var e,r,n;return void 0===t?"Undefined":null===t?"Null":"string"==typeof(r=function(t,e){try{return t[e]}catch(t){}}(e=So(t),Co))?r:wo?mo(e):"Object"==(n=mo(e))&&bo(e.callee)?"Arguments":n},xo=D,To=b,jo=X,Eo=Oo,Po=dr,ko=function(){},Io=[],Ro=nt("Reflect","construct"),Ao=/^\s*(?:class|function)\b/,_o=xo(Ao.exec),Lo=!Ao.exec(ko),Fo=function(t){if(!jo(t))return!1;try{return Ro(ko,Io,t),!0}catch(t){return!1}},Do=function(t){if(!jo(t))return!1;switch(Eo(t)){case"AsyncFunction":case"GeneratorFunction":case"AsyncGeneratorFunction":return!1}try{return Lo||!!_o(Ao,Po(t))}catch(t){return!0}};Do.sham=!0;var Mo=!Ro||To((function(){var t;return Fo(Fo.call)||!Fo(Object)||!Fo((function(){t=!0}))||t}))?Do:Fo,No=ho,Vo=Mo,$o=Z,zo=ue("species"),Ho=Array,Bo=function(t){var e;return No(t)&&(e=t.constructor,(Vo(e)&&(e===Ho||No(e.prototype))||$o(e)&&null===(e=e[zo]))&&(e=void 0)),void 0===e?Ho:e},Uo=function(t,e){return new(Bo(t))(0===e?0:e)},Go=so,Ko=G,qo=Ut,Wo=mn,Yo=Uo,Jo=D([].push),Xo=function(t){var e=1==t,r=2==t,n=3==t,o=4==t,i=6==t,a=7==t,l=5==t||i;return function(c,u,f,s){for(var p,h,d=qo(c),v=Ko(d),g=Go(u,f),y=Wo(v),b=0,m=s||Yo,C=e?m(c,y):r||a?m(c,0):void 0;y>b;b++)if((l||b in v)&&(h=g(p=v[b],b,d),t))if(e)C[b]=h;else if(h)switch(t){case 3:return!0;case 5:return p;case 6:return b;case 2:Jo(C,p)}else switch(t){case 4:return!1;case 7:Jo(C,p)}return i?-1:n||o?o:C}},Qo={forEach:Xo(0),map:Xo(1),filter:Xo(2),some:Xo(3),every:Xo(4),find:Xo(5),findIndex:Xo(6),filterReject:Xo(7)},Zo=b,ti=pt,ei=ue("species"),ri=function(t){return ti>=51||!Zo((function(){var e=[];return(e.constructor={})[ei]=function(){return{foo:1}},1!==e[t](Boolean).foo}))},ni=Qo.filter;lo({target:"Array",proto:!0,forced:!ri("filter")},{filter:function(t){return ni(this,t,arguments.length>1?arguments[1]:void 0)}});var oi=Oo,ii=go?{}.toString:function(){return"[object "+oi(this)+"]"};go||on(Object.prototype,"toString",ii,{unsafe:!0});var ai=In,li=Rn,ci=Object.keys||function(t){return ai(t,li)},ui=Ut,fi=ci;lo({target:"Object",stat:!0,forced:b((function(){fi(1)}))},{keys:function(t){return fi(ui(t))}});var si=TypeError,pi=me,hi=Fe,di=I,vi=function(t,e,r){var n=pi(e);n in t?hi.f(t,n,di(0,r)):t[n]=r},gi=lo,yi=b,bi=ho,mi=Z,Ci=Ut,Si=mn,wi=function(t){if(t>9007199254740991)throw si("Maximum allowed index exceeded");return t},Oi=vi,xi=Uo,Ti=ri,ji=pt,Ei=ue("isConcatSpreadable"),Pi=ji>=51||!yi((function(){var t=[];return t[Ei]=!1,t.concat()[0]!==t})),ki=Ti("concat"),Ii=function(t){if(!mi(t))return!1;var e=t[Ei];return void 0!==e?!!e:bi(t)};gi({target:"Array",proto:!0,arity:1,forced:!Pi||!ki},{concat:function(t){var e,r,n,o,i,a=Ci(this),l=xi(a,0),c=0;for(e=-1,n=arguments.length;e<n;e++)if(Ii(i=-1===e?a:arguments[e]))for(o=Si(i),wi(c+o),r=0;r<o;r++,c++)r in i&&Oi(l,c,i[r]);else wi(c+1),Oi(l,c++,i);return l.length=c,l}});var Ri={},Ai=m,_i=De,Li=Fe,Fi=$e,Di=J,Mi=ci;Ri.f=Ai&&!_i?Object.defineProperties:function(t,e){Fi(t);for(var r,n=Di(e),o=Mi(e),i=o.length,a=0;i>a;)Li.f(t,r=o[a++],n[r]);return t};var Ni,Vi=nt("document","documentElement"),$i=$e,zi=Ri,Hi=Rn,Bi=Or,Ui=Vi,Gi=Oe,Ki=wr("IE_PROTO"),qi=function(){},Wi=function(t){return"<script>"+t+"</"+"script>"},Yi=function(t){t.write(Wi("")),t.close();var e=t.parentWindow.Object;return t=null,e},Ji=function(){try{Ni=new ActiveXObject("htmlfile")}catch(t){}var t,e;Ji="undefined"!=typeof document?document.domain&&Ni?Yi(Ni):((e=Gi("iframe")).style.display="none",Ui.appendChild(e),e.src=String("javascript:"),(t=e.contentWindow.document).open(),t.write(Wi("document.F=Object")),t.close(),t.F):Yi(Ni);for(var r=Hi.length;r--;)delete Ji.prototype[Hi[r]];return Ji()};Bi[Ki]=!0;var Xi=Object.create||function(t,e){var r;return null!==t?(qi.prototype=$i(t),r=new qi,qi.prototype=null,r[Ki]=t):r=Ji(),void 0===e?r:zi.f(r,e)},Qi=ue,Zi=Xi,ta=Fe.f,ea=Qi("unscopables"),ra=Array.prototype;null==ra[ea]&&ta(ra,ea,{configurable:!0,value:Zi(null)});var na=function(t){ra[ea][t]=!0},oa=xn.includes,ia=na;lo({target:"Array",proto:!0,forced:b((function(){return!Array(1).includes()}))},{includes:function(t){return oa(this,t,arguments.length>1?arguments[1]:void 0)}}),ia("includes");var aa=Z,la=$,ca=ue("match"),ua=function(t){var e;return aa(t)&&(void 0!==(e=t[ca])?!!e:"RegExp"==la(t))},fa=ua,sa=TypeError,pa=Oo,ha=String,da=function(t){if("Symbol"===pa(t))throw TypeError("Cannot convert a Symbol value to a string");return ha(t)},va=ue("match"),ga=lo,ya=function(t){if(fa(t))throw sa("The method doesn't accept regular expressions");return t},ba=q,ma=da,Ca=function(t){var e=/./;try{"/./"[t](e)}catch(r){try{return e[va]=!1,"/./"[t](e)}catch(t){}}return!1},Sa=D("".indexOf);ga({target:"String",proto:!0,forced:!Ca("includes")},{includes:function(t){return!!~Sa(ma(ba(this)),ma(ya(t)),arguments.length>1?arguments[1]:void 0)}});var wa=Oe("span").classList,Oa=wa&&wa.constructor&&wa.constructor.prototype,xa=Oa===Object.prototype?void 0:Oa,Ta=b,ja=function(t,e){var r=[][t];return!!r&&Ta((function(){r.call(null,e||function(){return 1},1)}))},Ea=Qo.forEach,Pa=ja("forEach")?[].forEach:function(t){return Ea(this,t,arguments.length>1?arguments[1]:void 0)},ka=g,Ia={CSSRuleList:0,CSSStyleDeclaration:0,CSSValueList:0,ClientRectList:0,DOMRectList:0,DOMStringList:0,DOMTokenList:1,DataTransferItemList:0,FileList:0,HTMLAllCollection:0,HTMLCollection:0,HTMLFormElement:0,HTMLSelectElement:0,MediaList:0,MimeTypeArray:0,NamedNodeMap:0,NodeList:1,PaintRequestList:0,Plugin:0,PluginArray:0,SVGLengthList:0,SVGNumberList:0,SVGPathSegList:0,SVGPointList:0,SVGStringList:0,SVGTransformList:0,SourceBufferList:0,StyleSheetList:0,TextTrackCueList:0,TextTrackList:0,TouchList:0},Ra=xa,Aa=Pa,_a=tr,La=function(t){if(t&&t.forEach!==Aa)try{_a(t,"forEach",Aa)}catch(e){t.forEach=Aa}};for(var Fa in Ia)Ia[Fa]&&La(ka[Fa]&&ka[Fa].prototype);La(Ra);var Da,Ma,Na=$e,Va=function(){var t=Na(this),e="";return t.hasIndices&&(e+="d"),t.global&&(e+="g"),t.ignoreCase&&(e+="i"),t.multiline&&(e+="m"),t.dotAll&&(e+="s"),t.unicode&&(e+="u"),t.sticky&&(e+="y"),e},$a=b,za=g.RegExp,Ha=$a((function(){var t=za("a","y");return t.lastIndex=2,null!=t.exec("abcd")})),Ba=Ha||$a((function(){return!za("a","y").sticky})),Ua={BROKEN_CARET:Ha||$a((function(){var t=za("^r","gy");return t.lastIndex=2,null!=t.exec("str")})),MISSED_STICKY:Ba,UNSUPPORTED_Y:Ha},Ga=b,Ka=g.RegExp,qa=Ga((function(){var t=Ka(".","s");return!(t.dotAll&&t.exec("\n")&&"s"===t.flags)})),Wa=b,Ya=g.RegExp,Ja=Wa((function(){var t=Ya("(?<a>b)","g");return"b"!==t.exec("b").groups.a||"bc"!=="b".replace(t,"$<a>c")})),Xa=O,Qa=D,Za=da,tl=Va,el=Ua,rl=Lt.exports,nl=Xi,ol=zr.get,il=qa,al=Ja,ll=rl("native-string-replace",String.prototype.replace),cl=RegExp.prototype.exec,ul=cl,fl=Qa("".charAt),sl=Qa("".indexOf),pl=Qa("".replace),hl=Qa("".slice),dl=(Ma=/b*/g,Xa(cl,Da=/a/,"a"),Xa(cl,Ma,"a"),0!==Da.lastIndex||0!==Ma.lastIndex),vl=el.BROKEN_CARET,gl=void 0!==/()??/.exec("")[1];(dl||gl||vl||il||al)&&(ul=function(t){var e,r,n,o,i,a,l,c=this,u=ol(c),f=Za(t),s=u.raw;if(s)return s.lastIndex=c.lastIndex,e=Xa(ul,s,f),c.lastIndex=s.lastIndex,e;var p=u.groups,h=vl&&c.sticky,d=Xa(tl,c),v=c.source,g=0,y=f;if(h&&(d=pl(d,"y",""),-1===sl(d,"g")&&(d+="g"),y=hl(f,c.lastIndex),c.lastIndex>0&&(!c.multiline||c.multiline&&"\n"!==fl(f,c.lastIndex-1))&&(v="(?: "+v+")",y=" "+y,g++),r=new RegExp("^(?:"+v+")",d)),gl&&(r=new RegExp("^"+v+"$(?!\\s)",d)),dl&&(n=c.lastIndex),o=Xa(cl,h?r:c,y),h?o?(o.input=hl(o.input,g),o[0]=hl(o[0],g),o.index=c.lastIndex,c.lastIndex+=o[0].length):c.lastIndex=0:dl&&o&&(c.lastIndex=c.global?o.index+o[0].length:n),gl&&o&&o.length>1&&Xa(ll,o[0],r,(function(){for(i=1;i<arguments.length-2;i++)void 0===arguments[i]&&(o[i]=void 0)})),o&&p)for(o.groups=a=nl(null),i=0;i<p.length;i++)a[(l=p[i])[0]]=o[l[1]];return o});var yl=ul;lo({target:"RegExp",proto:!0,forced:/./.exec!==yl},{exec:yl});var bl=C,ml=Function.prototype,Cl=ml.apply,Sl=ml.call,wl="object"==typeof Reflect&&Reflect.apply||(bl?Sl.bind(Cl):function(){return Sl.apply(Cl,arguments)}),Ol=D,xl=on,Tl=yl,jl=b,El=ue,Pl=tr,kl=El("species"),Il=RegExp.prototype,Rl=function(t,e,r,n){var o=El(t),i=!jl((function(){var e={};return e[o]=function(){return 7},7!=""[t](e)})),a=i&&!jl((function(){var e=!1,r=/a/;return"split"===t&&((r={}).constructor={},r.constructor[kl]=function(){return r},r.flags="",r[o]=/./[o]),r.exec=function(){return e=!0,null},r[o](""),!e}));if(!i||!a||r){var l=Ol(/./[o]),c=e(o,""[t],(function(t,e,r,n,o){var a=Ol(t),c=e.exec;return c===Tl||c===Il.exec?i&&!o?{done:!0,value:l(e,r,n)}:{done:!0,value:a(r,e,n)}:{done:!1}}));xl(String.prototype,t,c[0]),xl(Il,o,c[1])}n&&Pl(Il[o],"sham",!0)},Al=Mo,_l=Ot,Ll=TypeError,Fl=$e,Dl=function(t){if(Al(t))return t;throw Ll(_l(t)+" is not a constructor")},Ml=ue("species"),Nl=function(t,e){var r,n=Fl(t).constructor;return void 0===n||null==(r=Fl(n)[Ml])?e:Dl(r)},Vl=D,$l=fn,zl=da,Hl=q,Bl=Vl("".charAt),Ul=Vl("".charCodeAt),Gl=Vl("".slice),Kl=function(t){return function(e,r){var n,o,i=zl(Hl(e)),a=$l(r),l=i.length;return a<0||a>=l?t?"":void 0:(n=Ul(i,a))<55296||n>56319||a+1===l||(o=Ul(i,a+1))<56320||o>57343?t?Bl(i,a):n:t?Gl(i,a,a+2):o-56320+(n-55296<<10)+65536}},ql={codeAt:Kl(!1),charAt:Kl(!0)}.charAt,Wl=function(t,e,r){return e+(r?ql(t,e).length:1)},Yl=dn,Jl=mn,Xl=vi,Ql=Array,Zl=Math.max,tc=function(t,e,r){for(var n=Jl(t),o=Yl(e,n),i=Yl(void 0===r?n:r,n),a=Ql(Zl(i-o,0)),l=0;o<i;o++,l++)Xl(a,l,t[o]);return a.length=l,a},ec=O,rc=$e,nc=X,oc=$,ic=yl,ac=TypeError,lc=function(t,e){var r=t.exec;if(nc(r)){var n=ec(r,t,e);return null!==n&&rc(n),n}if("RegExp"===oc(t))return ec(ic,t,e);throw ac("RegExp#exec called on incompatible receiver")},cc=wl,uc=O,fc=D,sc=Rl,pc=ua,hc=$e,dc=q,vc=Nl,gc=Wl,yc=yn,bc=da,mc=kt,Cc=tc,Sc=lc,wc=yl,Oc=b,xc=Ua.UNSUPPORTED_Y,Tc=4294967295,jc=Math.min,Ec=[].push,Pc=fc(/./.exec),kc=fc(Ec),Ic=fc("".slice),Rc=!Oc((function(){var t=/(?:)/,e=t.exec;t.exec=function(){return e.apply(this,arguments)};var r="ab".split(t);return 2!==r.length||"a"!==r[0]||"b"!==r[1]}));sc("split",(function(t,e,r){var n;return n="c"=="abbc".split(/(b)*/)[1]||4!="test".split(/(?:)/,-1).length||2!="ab".split(/(?:ab)*/).length||4!=".".split(/(.?)(.?)/).length||".".split(/()()/).length>1||"".split(/.?/).length?function(t,r){var n=bc(dc(this)),o=void 0===r?Tc:r>>>0;if(0===o)return[];if(void 0===t)return[n];if(!pc(t))return uc(e,n,t,o);for(var i,a,l,c=[],u=(t.ignoreCase?"i":"")+(t.multiline?"m":"")+(t.unicode?"u":"")+(t.sticky?"y":""),f=0,s=new RegExp(t.source,u+"g");(i=uc(wc,s,n))&&!((a=s.lastIndex)>f&&(kc(c,Ic(n,f,i.index)),i.length>1&&i.index<n.length&&cc(Ec,c,Cc(i,1)),l=i[0].length,f=a,c.length>=o));)s.lastIndex===i.index&&s.lastIndex++;return f===n.length?!l&&Pc(s,"")||kc(c,""):kc(c,Ic(n,f)),c.length>o?Cc(c,0,o):c}:"0".split(void 0,0).length?function(t,r){return void 0===t&&0===r?[]:uc(e,this,t,r)}:e,[function(e,r){var o=dc(this),i=null==e?void 0:mc(e,t);return i?uc(i,e,o,r):uc(n,bc(o),e,r)},function(t,o){var i=hc(this),a=bc(t),l=r(n,i,a,o,n!==e);if(l.done)return l.value;var c=vc(i,RegExp),u=i.unicode,f=(i.ignoreCase?"i":"")+(i.multiline?"m":"")+(i.unicode?"u":"")+(xc?"g":"y"),s=new c(xc?"^(?:"+i.source+")":i,f),p=void 0===o?Tc:o>>>0;if(0===p)return[];if(0===a.length)return null===Sc(s,a)?[a]:[];for(var h=0,d=0,v=[];d<a.length;){s.lastIndex=xc?0:d;var g,y=Sc(s,xc?Ic(a,d):a);if(null===y||(g=jc(yc(s.lastIndex+(xc?d:0)),a.length))===h)d=gc(a,d,u);else{if(kc(v,Ic(a,h,d)),v.length===p)return v;for(var b=1;b<=y.length-1;b++)if(kc(v,y[b]),v.length===p)return v;d=h=g}}return kc(v,Ic(a,h)),v}]}),!Rc,xc);var Ac="\t\n\v\f\r                　\u2028\u2029\ufeff",_c=q,Lc=da,Fc=D("".replace),Dc="[\t\n\v\f\r                　\u2028\u2029\ufeff]",Mc=RegExp("^"+Dc+Dc+"*"),Nc=RegExp(Dc+Dc+"*$"),Vc=function(t){return function(e){var r=Lc(_c(e));return 1&t&&(r=Fc(r,Mc,"")),2&t&&(r=Fc(r,Nc,"")),r}},$c={start:Vc(1),end:Vc(2),trim:Vc(3)},zc=lr.PROPER,Hc=b,Bc=Ac,Uc=$c.trim;lo({target:"String",proto:!0,forced:function(t){return Hc((function(){return!!Bc[t]()||"​᠎"!=="​᠎"[t]()||zc&&Bc[t].name!==t}))}("trim")},{trim:function(){return Uc(this)}});var Gc=m,Kc=D,qc=ci,Wc=J,Yc=Kc(x.f),Jc=Kc([].push),Xc=function(t){return function(e){for(var r,n=Wc(e),o=qc(n),i=o.length,a=0,l=[];i>a;)r=o[a++],Gc&&!Yc(n,r)||Jc(l,t?[r,n[r]]:n[r]);return l}},Qc={entries:Xc(!0),values:Xc(!1)}.values;lo({target:"Object",stat:!0},{values:function(t){return Qc(t)}});var Zc=O,tu=qt,eu=ot,ru=Va,nu=RegExp.prototype,ou=lr.PROPER,iu=on,au=$e,lu=da,cu=b,uu=function(t){var e=t.flags;return void 0!==e||"flags"in nu||tu(t,"flags")||!eu(nu,t)?e:Zc(ru,t)},fu="toString",su=RegExp.prototype.toString,pu=cu((function(){return"/a/b"!=su.call({source:"a",flags:"b"})})),hu=ou&&su.name!=fu;(pu||hu)&&iu(RegExp.prototype,fu,(function(){var t=au(this);return"/"+lu(t.source)+"/"+lu(uu(t))}),{unsafe:!0});var du=lo,vu=xn.indexOf,gu=ja,yu=D([].indexOf),bu=!!yu&&1/yu([1],1,-0)<0,mu=gu("indexOf");du({target:"Array",proto:!0,forced:bu||!mu},{indexOf:function(t){var e=arguments.length>1?arguments[1]:void 0;return bu?yu(this,t,e)||0:vu(this,t,e)}});var Cu=g,Su=b,wu=D,Ou=da,xu=$c.trim,Tu=Ac,ju=Cu.parseInt,Eu=Cu.Symbol,Pu=Eu&&Eu.iterator,ku=/^[+-]?0x/i,Iu=wu(ku.exec),Ru=8!==ju(Tu+"08")||22!==ju(Tu+"0x16")||Pu&&!Su((function(){ju(Object(Pu))}))?function(t,e){var r=xu(Ou(t));return ju(r,e>>>0||(Iu(ku,r)?16:10))}:ju;lo({global:!0,forced:parseInt!=Ru},{parseInt:Ru});var Au=m,_u=D,Lu=O,Fu=b,Du=ci,Mu=Ln,Nu=x,Vu=Ut,$u=G,zu=Object.assign,Hu=Object.defineProperty,Bu=_u([].concat),Uu=!zu||Fu((function(){if(Au&&1!==zu({b:1},zu(Hu({},"a",{enumerable:!0,get:function(){Hu(this,"b",{value:3,enumerable:!1})}}),{b:2})).b)return!0;var t={},e={},r=Symbol(),n="abcdefghijklmnopqrst";return t[r]=7,n.split("").forEach((function(t){e[t]=t})),7!=zu({},t)[r]||Du(zu({},e)).join("")!=n}))?function(t,e){for(var r=Vu(t),n=arguments.length,o=1,i=Mu.f,a=Nu.f;n>o;)for(var l,c=$u(arguments[o++]),u=i?Bu(Du(c),i(c)):Du(c),f=u.length,s=0;f>s;)l=u[s++],Au&&!Lu(a,c,l)||(r[l]=c[l]);return r}:zu,Gu=Uu;lo({target:"Object",stat:!0,arity:2,forced:Object.assign!==Gu},{assign:Gu});var Ku=lo,qu=Qo.find,Wu=na,Yu="find",Ju=!0;Yu in[]&&Array(1).find((function(){Ju=!1})),Ku({target:"Array",proto:!0,forced:Ju},{find:function(t){return qu(this,t,arguments.length>1?arguments[1]:void 0)}}),Wu(Yu);var Xu,Qu,Zu,tf,ef="process"==$(g.process),rf=X,nf=String,of=TypeError,af=D,lf=$e,cf=function(t){if("object"==typeof t||rf(t))return t;throw of("Can't set "+nf(t)+" as a prototype")},uf=Object.setPrototypeOf||("__proto__"in{}?function(){var t,e=!1,r={};try{(t=af(Object.getOwnPropertyDescriptor(Object.prototype,"__proto__").set))(r,[]),e=r instanceof Array}catch(t){}return function(r,n){return lf(r),cf(n),e?t(r,n):r.__proto__=n,r}}():void 0),ff=Fe.f,sf=qt,pf=ue("toStringTag"),hf=nt,df=Fe,vf=m,gf=ue("species"),yf=ot,bf=TypeError,mf=D([].slice),Cf=TypeError,Sf=/(?:ipad|iphone|ipod).*applewebkit/i.test(it),wf=g,Of=wl,xf=so,Tf=X,jf=qt,Ef=b,Pf=Vi,kf=mf,If=Oe,Rf=function(t,e){if(t<e)throw Cf("Not enough arguments");return t},Af=Sf,_f=ef,Lf=wf.setImmediate,Ff=wf.clearImmediate,Df=wf.process,Mf=wf.Dispatch,Nf=wf.Function,Vf=wf.MessageChannel,$f=wf.String,zf=0,Hf={},Bf="onreadystatechange";try{Xu=wf.location}catch(t){}var Uf=function(t){if(jf(Hf,t)){var e=Hf[t];delete Hf[t],e()}},Gf=function(t){return function(){Uf(t)}},Kf=function(t){Uf(t.data)},qf=function(t){wf.postMessage($f(t),Xu.protocol+"//"+Xu.host)};Lf&&Ff||(Lf=function(t){Rf(arguments.length,1);var e=Tf(t)?t:Nf(t),r=kf(arguments,1);return Hf[++zf]=function(){Of(e,void 0,r)},Qu(zf),zf},Ff=function(t){delete Hf[t]},_f?Qu=function(t){Df.nextTick(Gf(t))}:Mf&&Mf.now?Qu=function(t){Mf.now(Gf(t))}:Vf&&!Af?(tf=(Zu=new Vf).port2,Zu.port1.onmessage=Kf,Qu=xf(tf.postMessage,tf)):wf.addEventListener&&Tf(wf.postMessage)&&!wf.importScripts&&Xu&&"file:"!==Xu.protocol&&!Ef(qf)?(Qu=qf,wf.addEventListener("message",Kf,!1)):Qu=Bf in If("script")?function(t){Pf.appendChild(If("script")).onreadystatechange=function(){Pf.removeChild(this),Uf(t)}}:function(t){setTimeout(Gf(t),0)});var Wf,Yf,Jf,Xf,Qf,Zf,ts,es,rs={set:Lf,clear:Ff},ns=g,os=/ipad|iphone|ipod/i.test(it)&&void 0!==ns.Pebble,is=/web0s(?!.*chrome)/i.test(it),as=g,ls=so,cs=y.f,us=rs.set,fs=Sf,ss=os,ps=is,hs=ef,ds=as.MutationObserver||as.WebKitMutationObserver,vs=as.document,gs=as.process,ys=as.Promise,bs=cs(as,"queueMicrotask"),ms=bs&&bs.value;ms||(Wf=function(){var t,e;for(hs&&(t=gs.domain)&&t.exit();Yf;){e=Yf.fn,Yf=Yf.next;try{e()}catch(t){throw Yf?Xf():Jf=void 0,t}}Jf=void 0,t&&t.enter()},fs||hs||ps||!ds||!vs?!ss&&ys&&ys.resolve?((ts=ys.resolve(void 0)).constructor=ys,es=ls(ts.then,ts),Xf=function(){es(Wf)}):hs?Xf=function(){gs.nextTick(Wf)}:(us=ls(us,as),Xf=function(){us(Wf)}):(Qf=!0,Zf=vs.createTextNode(""),new ds(Wf).observe(Zf,{characterData:!0}),Xf=function(){Zf.data=Qf=!Qf}));var Cs=ms||function(t){var e={fn:t,next:void 0};Jf&&(Jf.next=e),Yf||(Yf=e,Xf()),Jf=e},Ss=g,ws=function(t){try{return{error:!1,value:t()}}catch(t){return{error:!0,value:t}}},Os=function(){this.head=null,this.tail=null};Os.prototype={add:function(t){var e={item:t,next:null};this.head?this.tail.next=e:this.head=e,this.tail=e},get:function(){var t=this.head;if(t)return this.head=t.next,this.tail===t&&(this.tail=null),t.item}};var xs=Os,Ts=g.Promise,js="object"==typeof window&&"object"!=typeof Deno,Es=g,Ps=Ts,ks=X,Is=Zn,Rs=dr,As=ue,_s=js,Ls=pt;Ps&&Ps.prototype;var Fs=As("species"),Ds=!1,Ms=ks(Es.PromiseRejectionEvent),Ns=Is("Promise",(function(){var t=Rs(Ps),e=t!==String(Ps);if(!e&&66===Ls)return!0;if(Ls>=51&&/native code/.test(t))return!1;var r=new Ps((function(t){t(1)})),n=function(t){t((function(){}),(function(){}))};return(r.constructor={})[Fs]=n,!(Ds=r.then((function(){}))instanceof n)||!e&&_s&&!Ms})),Vs={CONSTRUCTOR:Ns,REJECTION_EVENT:Ms,SUBCLASSING:Ds},$s={},zs=Et,Hs=function(t){var e,r;this.promise=new t((function(t,n){if(void 0!==e||void 0!==r)throw TypeError("Bad Promise constructor");e=t,r=n})),this.resolve=zs(e),this.reject=zs(r)};$s.f=function(t){return new Hs(t)};var Bs,Us,Gs,Ks=lo,qs=ef,Ws=g,Ys=O,Js=on,Xs=uf,Qs=function(t,e,r){t&&!r&&(t=t.prototype),t&&!sf(t,pf)&&ff(t,pf,{configurable:!0,value:e})},Zs=function(t){var e=hf(t),r=df.f;vf&&e&&!e[gf]&&r(e,gf,{configurable:!0,get:function(){return this}})},tp=Et,ep=X,rp=Z,np=function(t,e){if(yf(e,t))return t;throw bf("Incorrect invocation")},op=Nl,ip=rs.set,ap=Cs,lp=function(t,e){var r=Ss.console;r&&r.error&&(1==arguments.length?r.error(t):r.error(t,e))},cp=ws,up=xs,fp=zr,sp=Ts,pp=$s,hp="Promise",dp=Vs.CONSTRUCTOR,vp=Vs.REJECTION_EVENT,gp=Vs.SUBCLASSING,yp=fp.getterFor(hp),bp=fp.set,mp=sp&&sp.prototype,Cp=sp,Sp=mp,wp=Ws.TypeError,Op=Ws.document,xp=Ws.process,Tp=pp.f,jp=Tp,Ep=!!(Op&&Op.createEvent&&Ws.dispatchEvent),Pp="unhandledrejection",kp=function(t){var e;return!(!rp(t)||!ep(e=t.then))&&e},Ip=function(t,e){var r,n,o,i=e.value,a=1==e.state,l=a?t.ok:t.fail,c=t.resolve,u=t.reject,f=t.domain;try{l?(a||(2===e.rejection&&Fp(e),e.rejection=1),!0===l?r=i:(f&&f.enter(),r=l(i),f&&(f.exit(),o=!0)),r===t.promise?u(wp("Promise-chain cycle")):(n=kp(r))?Ys(n,r,c,u):c(r)):u(i)}catch(t){f&&!o&&f.exit(),u(t)}},Rp=function(t,e){t.notified||(t.notified=!0,ap((function(){for(var r,n=t.reactions;r=n.get();)Ip(r,t);t.notified=!1,e&&!t.rejection&&_p(t)})))},Ap=function(t,e,r){var n,o;Ep?((n=Op.createEvent("Event")).promise=e,n.reason=r,n.initEvent(t,!1,!0),Ws.dispatchEvent(n)):n={promise:e,reason:r},!vp&&(o=Ws["on"+t])?o(n):t===Pp&&lp("Unhandled promise rejection",r)},_p=function(t){Ys(ip,Ws,(function(){var e,r=t.facade,n=t.value;if(Lp(t)&&(e=cp((function(){qs?xp.emit("unhandledRejection",n,r):Ap(Pp,r,n)})),t.rejection=qs||Lp(t)?2:1,e.error))throw e.value}))},Lp=function(t){return 1!==t.rejection&&!t.parent},Fp=function(t){Ys(ip,Ws,(function(){var e=t.facade;qs?xp.emit("rejectionHandled",e):Ap("rejectionhandled",e,t.value)}))},Dp=function(t,e,r){return function(n){t(e,n,r)}},Mp=function(t,e,r){t.done||(t.done=!0,r&&(t=r),t.value=e,t.state=2,Rp(t,!0))},Np=function(t,e,r){if(!t.done){t.done=!0,r&&(t=r);try{if(t.facade===e)throw wp("Promise can't be resolved itself");var n=kp(e);n?ap((function(){var r={done:!1};try{Ys(n,e,Dp(Np,r,t),Dp(Mp,r,t))}catch(e){Mp(r,e,t)}})):(t.value=e,t.state=1,Rp(t,!1))}catch(e){Mp({done:!1},e,t)}}};if(dp&&(Sp=(Cp=function(t){np(this,Sp),tp(t),Ys(Bs,this);var e=yp(this);try{t(Dp(Np,e),Dp(Mp,e))}catch(t){Mp(e,t)}}).prototype,(Bs=function(t){bp(this,{type:hp,done:!1,notified:!1,parent:!1,reactions:new up,rejection:!1,state:0,value:void 0})}).prototype=Js(Sp,"then",(function(t,e){var r=yp(this),n=Tp(op(this,Cp));return r.parent=!0,n.ok=!ep(t)||t,n.fail=ep(e)&&e,n.domain=qs?xp.domain:void 0,0==r.state?r.reactions.add(n):ap((function(){Ip(n,r)})),n.promise})),Us=function(){var t=new Bs,e=yp(t);this.promise=t,this.resolve=Dp(Np,e),this.reject=Dp(Mp,e)},pp.f=Tp=function(t){return t===Cp||undefined===t?new Us(t):jp(t)},ep(sp)&&mp!==Object.prototype)){Gs=mp.then,gp||Js(mp,"then",(function(t,e){var r=this;return new Cp((function(t,e){Ys(Gs,r,t,e)})).then(t,e)}),{unsafe:!0});try{delete mp.constructor}catch(t){}Xs&&Xs(mp,Sp)}Ks({global:!0,constructor:!0,wrap:!0,forced:dp},{Promise:Cp}),Qs(Cp,hp,!1),Zs(hp);var Vp={},$p=Vp,zp=ue("iterator"),Hp=Array.prototype,Bp=Oo,Up=kt,Gp=Vp,Kp=ue("iterator"),qp=function(t){if(null!=t)return Up(t,Kp)||Up(t,"@@iterator")||Gp[Bp(t)]},Wp=O,Yp=Et,Jp=$e,Xp=Ot,Qp=qp,Zp=TypeError,th=O,eh=$e,rh=kt,nh=so,oh=O,ih=$e,ah=Ot,lh=function(t){return void 0!==t&&($p.Array===t||Hp[zp]===t)},ch=mn,uh=ot,fh=function(t,e){var r=arguments.length<2?Qp(t):e;if(Yp(r))return Jp(Wp(r,t));throw Zp(Xp(t)+" is not iterable")},sh=qp,ph=function(t,e,r){var n,o;eh(t);try{if(!(n=rh(t,"return"))){if("throw"===e)throw r;return r}n=th(n,t)}catch(t){o=!0,n=t}if("throw"===e)throw r;if(o)throw n;return eh(n),r},hh=TypeError,dh=function(t,e){this.stopped=t,this.result=e},vh=dh.prototype,gh=function(t,e,r){var n,o,i,a,l,c,u,f=r&&r.that,s=!(!r||!r.AS_ENTRIES),p=!(!r||!r.IS_ITERATOR),h=!(!r||!r.INTERRUPTED),d=nh(e,f),v=function(t){return n&&ph(n,"normal",t),new dh(!0,t)},g=function(t){return s?(ih(t),h?d(t[0],t[1],v):d(t[0],t[1])):h?d(t,v):d(t)};if(p)n=t;else{if(!(o=sh(t)))throw hh(ah(t)+" is not iterable");if(lh(o)){for(i=0,a=ch(t);a>i;i++)if((l=g(t[i]))&&uh(vh,l))return l;return new dh(!1)}n=fh(t,o)}for(c=n.next;!(u=oh(c,n)).done;){try{l=g(u.value)}catch(t){ph(n,"throw",t)}if("object"==typeof l&&l&&uh(vh,l))return l}return new dh(!1)},yh=ue("iterator"),bh=!1;try{var mh=0,Ch={next:function(){return{done:!!mh++}},return:function(){bh=!0}};Ch[yh]=function(){return this},Array.from(Ch,(function(){throw 2}))}catch(t){}var Sh=Ts,wh=function(t,e){if(!e&&!bh)return!1;var r=!1;try{var n={};n[yh]=function(){return{next:function(){return{done:r=!0}}}},t(n)}catch(t){}return r},Oh=Vs.CONSTRUCTOR||!wh((function(t){Sh.all(t).then(void 0,(function(){}))})),xh=O,Th=Et,jh=$s,Eh=ws,Ph=gh;lo({target:"Promise",stat:!0,forced:Oh},{all:function(t){var e=this,r=jh.f(e),n=r.resolve,o=r.reject,i=Eh((function(){var r=Th(e.resolve),i=[],a=0,l=1;Ph(t,(function(t){var c=a++,u=!1;l++,xh(r,e,t).then((function(t){u||(u=!0,i[c]=t,--l||n(i))}),o)})),--l||n(i)}));return i.error&&o(i.value),r.promise}});var kh=lo,Ih=Vs.CONSTRUCTOR,Rh=Ts,Ah=nt,_h=X,Lh=on,Fh=Rh&&Rh.prototype;if(kh({target:"Promise",proto:!0,forced:Ih,real:!0},{catch:function(t){return this.then(void 0,t)}}),_h(Rh)){var Dh=Ah("Promise").prototype.catch;Fh.catch!==Dh&&Lh(Fh,"catch",Dh,{unsafe:!0})}var Mh=O,Nh=Et,Vh=$s,$h=ws,zh=gh;lo({target:"Promise",stat:!0,forced:Oh},{race:function(t){var e=this,r=Vh.f(e),n=r.reject,o=$h((function(){var o=Nh(e.resolve);zh(t,(function(t){Mh(o,e,t).then(r.resolve,n)}))}));return o.error&&n(o.value),r.promise}});var Hh=O,Bh=$s;lo({target:"Promise",stat:!0,forced:Vs.CONSTRUCTOR},{reject:function(t){var e=Bh.f(this);return Hh(e.reject,void 0,t),e.promise}});var Uh=$e,Gh=Z,Kh=$s,qh=lo,Wh=Vs.CONSTRUCTOR,Yh=function(t,e){if(Uh(t),Gh(e)&&e.constructor===t)return e;var r=Kh.f(t);return(0,r.resolve)(e),r.promise};nt("Promise"),qh({target:"Promise",stat:!0,forced:Wh},{resolve:function(t){return Yh(this,t)}});var Jh=Ot,Xh=TypeError,Qh=tc,Zh=Math.floor,td=function(t,e){var r=t.length,n=Zh(r/2);return r<8?ed(t,e):rd(t,td(Qh(t,0,n),e),td(Qh(t,n),e),e)},ed=function(t,e){for(var r,n,o=t.length,i=1;i<o;){for(n=i,r=t[i];n&&e(t[n-1],r)>0;)t[n]=t[--n];n!==i++&&(t[n]=r)}return t},rd=function(t,e,r,n){for(var o=e.length,i=r.length,a=0,l=0;a<o||l<i;)t[a+l]=a<o&&l<i?n(e[a],r[l])<=0?e[a++]:r[l++]:a<o?e[a++]:r[l++];return t},nd=td,od=it.match(/firefox\/(\d+)/i),id=!!od&&+od[1],ad=/MSIE|Trident/.test(it),ld=it.match(/AppleWebKit\/(\d+)\./),cd=!!ld&&+ld[1],ud=lo,fd=D,sd=Et,pd=Ut,hd=mn,dd=function(t,e){if(!delete t[e])throw Xh("Cannot delete property "+Jh(e)+" of "+Jh(t))},vd=da,gd=b,yd=nd,bd=ja,md=id,Cd=ad,Sd=pt,wd=cd,Od=[],xd=fd(Od.sort),Td=fd(Od.push),jd=gd((function(){Od.sort(void 0)})),Ed=gd((function(){Od.sort(null)})),Pd=bd("sort"),kd=!gd((function(){if(Sd)return Sd<70;if(!(md&&md>3)){if(Cd)return!0;if(wd)return wd<603;var t,e,r,n,o="";for(t=65;t<76;t++){switch(e=String.fromCharCode(t),t){case 66:case 69:case 70:case 72:r=3;break;case 68:case 71:r=4;break;default:r=2}for(n=0;n<47;n++)Od.push({k:e+n,v:r})}for(Od.sort((function(t,e){return e.v-t.v})),n=0;n<Od.length;n++)e=Od[n].k.charAt(0),o.charAt(o.length-1)!==e&&(o+=e);return"DGBEFHACIJK"!==o}}));ud({target:"Array",proto:!0,forced:jd||!Ed||!Pd||!kd},{sort:function(t){void 0!==t&&sd(t);var e=pd(this);if(kd)return void 0===t?xd(e):xd(e,t);var r,n,o=[],i=hd(e);for(n=0;n<i;n++)n in e&&Td(o,e[n]);for(yd(o,function(t){return function(e,r){return void 0===r?-1:void 0===e?1:void 0!==t?+t(e,r)||0:vd(e)>vd(r)?1:-1}}(t)),r=o.length,n=0;n<r;)e[n]=o[n++];for(;n<i;)dd(e,n++);return e}});var Id=D,Rd=Ut,Ad=Math.floor,_d=Id("".charAt),Ld=Id("".replace),Fd=Id("".slice),Dd=/\$([$&'`]|\d{1,2}|<[^>]*>)/g,Md=/\$([$&'`]|\d{1,2})/g,Nd=wl,Vd=O,$d=D,zd=Rl,Hd=b,Bd=$e,Ud=X,Gd=fn,Kd=yn,qd=da,Wd=q,Yd=Wl,Jd=kt,Xd=function(t,e,r,n,o,i){var a=r+t.length,l=n.length,c=Md;return void 0!==o&&(o=Rd(o),c=Dd),Ld(i,c,(function(i,c){var u;switch(_d(c,0)){case"$":return"$";case"&":return t;case"`":return Fd(e,0,r);case"'":return Fd(e,a);case"<":u=o[Fd(c,1,-1)];break;default:var f=+c;if(0===f)return i;if(f>l){var s=Ad(f/10);return 0===s?i:s<=l?void 0===n[s-1]?_d(c,1):n[s-1]+_d(c,1):i}u=n[f-1]}return void 0===u?"":u}))},Qd=lc,Zd=ue("replace"),tv=Math.max,ev=Math.min,rv=$d([].concat),nv=$d([].push),ov=$d("".indexOf),iv=$d("".slice),av="$0"==="a".replace(/./,"$0"),lv=!!/./[Zd]&&""===/./[Zd]("a","$0");zd("replace",(function(t,e,r){var n=lv?"$":"$0";return[function(t,r){var n=Wd(this),o=null==t?void 0:Jd(t,Zd);return o?Vd(o,t,n,r):Vd(e,qd(n),t,r)},function(t,o){var i=Bd(this),a=qd(t);if("string"==typeof o&&-1===ov(o,n)&&-1===ov(o,"$<")){var l=r(e,i,a,o);if(l.done)return l.value}var c=Ud(o);c||(o=qd(o));var u=i.global;if(u){var f=i.unicode;i.lastIndex=0}for(var s=[];;){var p=Qd(i,a);if(null===p)break;if(nv(s,p),!u)break;""===qd(p[0])&&(i.lastIndex=Yd(a,Kd(i.lastIndex),f))}for(var h,d="",v=0,g=0;g<s.length;g++){for(var y=qd((p=s[g])[0]),b=tv(ev(Gd(p.index),a.length),0),m=[],C=1;C<p.length;C++)nv(m,void 0===(h=p[C])?h:String(h));var S=p.groups;if(c){var w=rv([y],m,b,a);void 0!==S&&nv(w,S);var O=qd(Nd(o,void 0,w))}else O=Xd(y,a,b,m,S,o);b>=v&&(d+=iv(a,v,b)+O,v=b+y.length)}return d+iv(a,v)}]}),!!Hd((function(){var t=/./;return t.exec=function(){var t=[];return t.groups={a:"7"},t},"7"!=="".replace(t,"$<a>")}))||!av||lv);var cv=O,uv=$e,fv=yn,sv=da,pv=q,hv=kt,dv=Wl,vv=lc;Rl("match",(function(t,e,r){return[function(e){var r=pv(this),n=null==e?void 0:hv(e,t);return n?cv(n,e,r):new RegExp(e)[t](sv(r))},function(t){var n=uv(this),o=sv(t),i=r(e,n,o);if(i.done)return i.value;if(!n.global)return vv(n,o);var a=n.unicode;n.lastIndex=0;for(var l,c=[],u=0;null!==(l=vv(n,o));){var f=sv(l[0]);c[u]=f,""===f&&(n.lastIndex=dv(o,fv(n.lastIndex),a)),u++}return 0===u?null:c}]}));var gv=lo,yv=G,bv=J,mv=ja,Cv=D([].join),Sv=yv!=Object,wv=mv("join",",");gv({target:"Array",proto:!0,forced:Sv||!wv},{join:function(t){return Cv(bv(this),void 0===t?",":t)}});var Ov=r.default.fn.bootstrapTable.utils;function xv(t){var e=arguments.length>1&&void 0!==arguments[1]&&arguments[1],r=e?t.constants.classes.select:t.constants.classes.input;return t.options.iconSize?Ov.sprintf("%s-%s",r,t.options.iconSize):r}function Tv(t){return t.options.filterControlContainer?r.default("".concat(t.options.filterControlContainer)):t.options.height&&t._initialized?r.default(".fixed-table-header table thead"):t.$header}function jv(t){return r.default.inArray(t,[37,38,39,40])>-1}function Ev(t){return Tv(t).find('select, input:not([type="checkbox"]):not([type="radio"])')}function Pv(t,e,r,n,o){var i=null==e?"":e.toString().trim();if(i=Ov.removeHTML(Ov.unescapeHTML(i)),r=Ov.removeHTML(Ov.unescapeHTML(r)),!function(t,e){for(var r=function(t){return t[0].options}(t),n=0;n<r.length;n++)if(r[n].value===Ov.unescapeHTML(e))return!0;return!1}(t,i)){var a=new Option(r,i,!1,o?i===n||r===n:i===n);t.get(0).add(a)}}function kv(t,e,r){var n=t.get(0);if("server"!==e){for(var o=new Array,i=0;i<n.options.length;i++)o[i]=new Array,o[i][0]=n.options[i].text,o[i][1]=n.options[i].value,o[i][2]=n.options[i].selected;for(o.sort((function(t,n){return Ov.sort(t[0],n[0],"desc"===e?-1:1,r)}));n.options.length>0;)n.options[0]=null;for(var a=0;a<o.length;a++){var l=new Option(o[a][0],o[a][1],!1,o[a][2]);n.add(l)}}}function Iv(t){var e=t.$tableHeader;e.css("height",e.find("table").outerHeight(!0))}function Rv(t){if(r.default(t).is("input[type=search]")){var e=0;if("selectionStart"in t)e=t.selectionStart;else if("selection"in document){t.focus();var n=document.selection.createRange(),o=document.selection.createRange().text.length;n.moveStart("character",-t.value.length),e=n.text.length-o}return e}return-1}function Av(t){var e=Ev(t);t._valuesFilterControl=[],e.each((function(){var e=r.default(this),n=e.attr("class").replace("form-control","").replace("form-select","").replace("focus-temp","").replace("search-input","").trim();e=t.options.height&&!t.options.filterControlContainer?t.$el.find(".fixed-table-header .".concat(n)):t.options.filterControlContainer?r.default("".concat(t.options.filterControlContainer," .").concat(n)):t.$el.find(".".concat(n)),t._valuesFilterControl.push({field:e.closest("[data-field]").data("field"),value:e.val(),position:Rv(e.get(0)),hasFocus:e.is(":focus")})}))}function _v(t){var e=null,n=[],o=Ev(t);if(t._valuesFilterControl.length>0){var i=[];o.each((function(o,a){var l,c,u=r.default(a);if(e=u.closest("[data-field]").data("field"),(n=t._valuesFilterControl.filter((function(t){return t.field===e}))).length>0&&(n[0].hasFocus||n[0].value)){var f=(l=u.get(0),c=n[0],function(){if(c.hasFocus&&l.focus(),Array.isArray(c.value)){var t=r.default(l);r.default.each(c.value,(function(e,r){t.find(Ov.sprintf("option[value='%s']",r)).prop("selected",!0)}))}else l.value=c.value;!function(t,e){try{if(t)if(t.createTextRange){var r=t.createTextRange();r.move("character",e),r.select()}else t.setSelectionRange(e,e)}catch(t){}}(l,c.position)});i.push(f)}})),i.length>0&&i.forEach((function(t){return t()}))}}function Lv(t){return String(t).replace(/([:.\[\],])/g,"\\$1")}function Fv(t){var e=t.options.data;r.default.each(t.header.fields,(function(r,o){var i,a,l,c,u=t.columns[t.fieldsColumnsIndex[o]],f=Tv(t).find("select.bootstrap-table-filter-control-".concat(Lv(u.field)));if(l=(a=u).filterControl,c=a.searchable,l&&"select"===l.toLowerCase()&&c&&(void 0===(i=u.filterData)||"column"===i.toLowerCase())&&function(t){return t&&t.length>0}(f)){f[0].multiple||0!==f.get(f.length-1).options.length||Pv(f,"",u.filterControlPlaceholder||" ",u.filterDefault);for(var s={},p=0;p<e.length;p++){var h=Ov.getItemField(e[p],o,!1),d=t.options.editable&&u.editable?u._formatter:t.header.formatters[r],v=Ov.calculateObjectValue(t.header,d,[h,e[p],p],h);h||(h=v,u._forceFormatter=!0),u.filterDataCollector&&(v=Ov.calculateObjectValue(t.header,u.filterDataCollector,[h,e[p],v],v)),u.searchFormatter&&(h=v),s[v]=h,"object"!==n(v)||null===v||v.forEach((function(t){Pv(f,t,t,u.filterDefault)}))}for(var g in s)Pv(f,s[g],g,u.filterDefault);t.options.sortSelectOptions&&kv(f,"asc",t.options)}}))}function Dv(t,e){var n,o=!1;r.default.each(t.columns,(function(i,a){if(n=[],a.visible||t.options.filterControlContainer&&r.default(".bootstrap-table-filter-control-".concat(a.field)).length>=1){if(a.filterControl||t.options.filterControlContainer)if(t.options.filterControlContainer){var l=r.default(".bootstrap-table-filter-control-".concat(a.field));r.default.each(l,(function(t,e){var n=r.default(e);if(!n.is("[type=radio]")){var o=a.filterControlPlaceholder||"";n.attr("placeholder",o).val(a.filterDefault)}n.attr("data-field",a.field)})),o=!0}else{var c=a.filterControl.toLowerCase();n.push('<div class="filter-control">'),o=!0,a.searchable&&t.options.filterTemplate[c]&&n.push(t.options.filterTemplate[c](t,a,a.filterControlPlaceholder?a.filterControlPlaceholder:"",a.filterDefault))}else n.push('<div class="no-filter-control"></div>');if(a.filterControl&&""!==a.filterDefault&&void 0!==a.filterDefault&&(r.default.isEmptyObject(t.filterColumnsPartial)&&(t.filterColumnsPartial={}),a.field in t.filterColumnsPartial||(t.filterColumnsPartial[a.field]=a.filterDefault)),r.default.each(e.find("th"),(function(t,e){var o=r.default(e);if(o.data("field")===a.field)return o.find(".filter-control").remove(),o.find(".fht-cell").html(n.join("")),!1})),a.filterData&&"column"!==a.filterData.toLowerCase()){var u,f,s=function(t,e){for(var r=Object.keys(t),n=0;n<r.length;n++)if(r[n]===e)return t[e];return null}(Nv,a.filterData.substring(0,a.filterData.indexOf(":")));if(!s)throw new SyntaxError('Error. You should use any of these allowed filter data methods: var, obj, json, url, func. Use like this: var: {key: "value"}');u=a.filterData.substring(a.filterData.indexOf(":")+1,a.filterData.length),Pv(f=e.find(".bootstrap-table-filter-control-".concat(Lv(a.field))),"",a.filterControlPlaceholder,a.filterDefault,!0),s(t,u,f,t.options.filterOrderBy,a.filterDefault)}}})),o?(e.off("keyup","input").on("keyup","input",(function(e,n){var o=e.currentTarget,i=e.keyCode;if(i=n?n.keyCode:i,!(t.options.searchOnEnterKey&&13!==i||jv(i))){var a=r.default(o);a.is(":checkbox")||a.is(":radio")||(clearTimeout(o.timeoutId||0),o.timeoutId=setTimeout((function(){t.onColumnSearch({currentTarget:o,keyCode:i})}),t.options.searchTimeOut))}})),e.off("change","select",".fc-multipleselect").on("change","select",".fc-multipleselect",(function(e){var n=e.currentTarget,o=e.keyCode,i=r.default(n),a=i.val();if(Array.isArray(a))for(var l=0;l<a.length;l++)a[l]&&a[l].length>0&&a[l].trim()&&i.find('option[value="'.concat(a[l],'"]')).attr("selected",!0);else a&&a.length>0&&a.trim()?(i.find("option[selected]").removeAttr("selected"),i.find('option[value="'.concat(a,'"]')).attr("selected",!0)):i.find("option[selected]").removeAttr("selected");clearTimeout(n.timeoutId||0),n.timeoutId=setTimeout((function(){t.onColumnSearch({currentTarget:n,keyCode:o})}),t.options.searchTimeOut)})),e.off("mouseup","input:not([type=radio])").on("mouseup","input:not([type=radio])",(function(e){var n=e.currentTarget,o=e.keyCode,i=r.default(n);""!==i.val()&&setTimeout((function(){""===i.val()&&(clearTimeout(n.timeoutId||0),n.timeoutId=setTimeout((function(){t.onColumnSearch({currentTarget:n,keyCode:o})}),t.options.searchTimeOut))}),1)})),e.off("change","input[type=radio]").on("change","input[type=radio]",(function(e){var r=e.currentTarget,n=e.keyCode;clearTimeout(r.timeoutId||0),r.timeoutId=setTimeout((function(){t.onColumnSearch({currentTarget:r,keyCode:n})}),t.options.searchTimeOut)})),e.find(".date-filter-control").length>0&&r.default.each(t.columns,(function(r,n){var o=n.filterDefault,i=n.filterControl,a=n.field,l=n.filterDatepickerOptions;if(void 0!==i&&"datepicker"===i.toLowerCase()){var c=e.find(".date-filter-control.bootstrap-table-filter-control-".concat(a));o&&c.value(o),l.min&&c.attr("min",l.min),l.max&&c.attr("max",l.max),l.step&&c.attr("step",l.step),l.pattern&&c.attr("pattern",l.pattern),c.on("change",(function(e){var r=e.currentTarget;clearTimeout(r.timeoutId||0),r.timeoutId=setTimeout((function(){t.onColumnSearch({currentTarget:r})}),t.options.searchTimeOut)}))}})),"server"!==t.options.sidePagination&&t.triggerSearch(),t.options.filterControlVisible||e.find(".filter-control, .no-filter-control").hide()):e.find(".filter-control, .no-filter-control").hide(),t.trigger("created-controls")}function Mv(t){t.options.height&&(0!==r.default(".fixed-table-header table thead").length&&t.$header.children().find("th[data-field]").each((function(t,e){if("bs-checkbox"!==e.classList[0]){var n=r.default(e),o=n.data("field"),i=r.default("th[data-field='".concat(o,"']")).not(n),a=n.find("input"),l=i.find("input");a.length>0&&l.length>0&&a.val()!==l.val()&&a.val(l.val())}})))}var Nv={func:function(t,e,r,n,o){var i=window[e].apply();for(var a in i)Pv(r,a,i[a],o);t.options.sortSelectOptions&&kv(r,n,t.options),_v(t)},obj:function(t,e,r,n,o){var i=e.split("."),a=i.shift(),l=window[a];for(var c in i.length>0&&i.forEach((function(t){l=l[t]})),l)Pv(r,c,l[c],o);t.options.sortSelectOptions&&kv(r,n,t.options),_v(t)},var:function(t,e,r,n,o){var i=window[e],a=Array.isArray(i);for(var l in i)Pv(r,a?i[l]:l,i[l],o,!0);t.options.sortSelectOptions&&kv(r,n,t.options),_v(t)},url:function(t,e,n,o,i){r.default.ajax({url:e,dataType:"json",success:function(e){for(var r in e)Pv(n,r,e[r],i);t.options.sortSelectOptions&&kv(n,o,t.options),_v(t)}})},json:function(t,e,r,n,o){var i=JSON.parse(e);for(var a in i)Pv(r,a,i[a],o);t.options.sortSelectOptions&&kv(r,n,t.options),_v(t)}},Vv=r.default.fn.bootstrapTable.utils;r.default.extend(r.default.fn.bootstrapTable.defaults,{filterControl:!1,filterControlVisible:!0,filterControlMultipleSearch:!1,filterControlMultipleSearchDelimiter:",",onColumnSearch:function(t,e){return!1},onCreatedControls:function(){return!1},alignmentSelectControlOptions:void 0,filterTemplate:{input:function(t,e,r,n){return Vv.sprintf('<input type="search" class="%s bootstrap-table-filter-control-%s search-input" style="width: 100%;" placeholder="%s" value="%s">',xv(t),e.field,void 0===r?"":r,void 0===n?"":n)},select:function(t,e){return Vv.sprintf('<select class="%s bootstrap-table-filter-control-%s %s" %s style="width: 100%;" dir="%s"></select>',xv(t,!0),e.field,"","",function(t){switch(void 0===t?"left":t.toLowerCase()){case"left":default:return"ltr";case"right":return"rtl";case"auto":return"auto"}}(t.options.alignmentSelectControlOptions))},datepicker:function(t,e,r){return Vv.sprintf('<input type="date" class="%s date-filter-control bootstrap-table-filter-control-%s" style="width: 100%;" value="%s">',xv(t),e.field,void 0===r?"":r)}},searchOnEnterKey:!1,showFilterControlSwitch:!1,sortSelectOptions:!1,_valuesFilterControl:[],_initialized:!1,_isRendering:!1,_usingMultipleSelect:!1}),r.default.extend(r.default.fn.bootstrapTable.columnDefaults,{filterControl:void 0,filterControlMultipleSelect:!1,filterControlMultipleSelectOptions:{},filterDataCollector:void 0,filterData:void 0,filterDatepickerOptions:{},filterStrictSearch:!1,filterStartsWithSearch:!1,filterControlPlaceholder:"",filterDefault:"",filterOrderBy:"asc",filterCustomSearch:void 0}),r.default.extend(r.default.fn.bootstrapTable.Constructor.EVENTS,{"column-search.bs.table":"onColumnSearch","created-controls.bs.table":"onCreatedControls"}),r.default.extend(r.default.fn.bootstrapTable.defaults.icons,{filterControlSwitchHide:{bootstrap3:"glyphicon-zoom-out icon-zoom-out",bootstrap5:"bi-zoom-out",materialize:"zoom_out"}[r.default.fn.bootstrapTable.theme]||"fa-search-minus",filterControlSwitchShow:{bootstrap3:"glyphicon-zoom-in icon-zoom-in",bootstrap5:"bi-zoom-in",materialize:"zoom_in"}[r.default.fn.bootstrapTable.theme]||"fa-search-plus"}),r.default.extend(r.default.fn.bootstrapTable.locales,{formatFilterControlSwitch:function(){return"Hide/Show controls"},formatFilterControlSwitchHide:function(){return"Hide controls"},formatFilterControlSwitchShow:function(){return"Show controls"}}),r.default.extend(r.default.fn.bootstrapTable.defaults,r.default.fn.bootstrapTable.locales),r.default.extend(r.default.fn.bootstrapTable.defaults,{formatClearSearch:function(){return"Clear filters"}}),r.default.fn.bootstrapTable.methods.push("triggerSearch"),r.default.fn.bootstrapTable.methods.push("clearFilterControl"),r.default.fn.bootstrapTable.methods.push("toggleFilterControl"),r.default.BootstrapTable=function(t){!function(t,e){if("function"!=typeof e&&null!==e)throw new TypeError("Super expression must either be null or a function");t.prototype=Object.create(e&&e.prototype,{constructor:{value:t,writable:!0,configurable:!0}}),Object.defineProperty(t,"prototype",{writable:!1}),e&&l(t,e)}(d,t);var e,c,f,h=u(d);function d(){return o(this,d),h.apply(this,arguments)}return e=d,c=[{key:"init",value:function(){var t=this;this.options.filterControl&&(this._valuesFilterControl=[],this._initialized=!1,this._usingMultipleSelect=!1,this._isRendering=!1,this.$el.on("reset-view.bs.table",Vv.debounce((function(){Fv(t),_v(t)}),3)).on("toggle.bs.table",Vv.debounce((function(e,r){t._initialized=!1,r||(Fv(t),_v(t),t._initialized=!0)}),1)).on("post-header.bs.table",Vv.debounce((function(){Fv(t),_v(t)}),3)).on("column-switch.bs.table",Vv.debounce((function(){_v(t),t.options.height&&t.fitHeader()}),1)).on("post-body.bs.table",Vv.debounce((function(){t.options.height&&!t.options.filterControlContainer&&t.options.filterControlVisible&&Iv(t),t.$tableLoading.css("top",t.$header.outerHeight()+1)}),1)).on("all.bs.table",(function(){Mv(t)}))),s(a(d.prototype),"init",this).call(this)}},{key:"initBody",value:function(){var t=this;s(a(d.prototype),"initBody",this).call(this),this.options.filterControl&&setTimeout((function(){Fv(t),_v(t)}),3)}},{key:"load",value:function(t){s(a(d.prototype),"load",this).call(this,t),this.options.filterControl&&(Dv(this,Tv(this)),_v(this))}},{key:"initHeader",value:function(){s(a(d.prototype),"initHeader",this).call(this),this.options.filterControl&&(Dv(this,Tv(this)),this._initialized=!0)}},{key:"initSearch",value:function(){var t=this,e=this,o=r.default.isEmptyObject(e.filterColumnsPartial)?null:e.filterColumnsPartial;s(a(d.prototype),"initSearch",this).call(this),"server"!==this.options.sidePagination&&null!==o&&(e.data=o?e.data.filter((function(i,a){var l=[],c=Object.keys(i),u=Object.keys(o),f=c.concat(u.filter((function(t){return!c.includes(t)})));return f.forEach((function(c){var u,f=e.columns[e.fieldsColumnsIndex[c]],s=o[c]||"",p=s.toLowerCase(),h=Vv.unescapeHTML(Vv.getItemField(i,c,!1));t.options.searchAccentNeutralise&&(p=Vv.normalizeAccent(p));var d=[p];t.options.filterControlMultipleSearch&&(d=p.split(t.options.filterControlMultipleSearchDelimiter)),d.forEach((function(t){!0!==u&&(""===(t=t.trim())?u=!0:(f&&(f.searchFormatter||f._forceFormatter)&&(h=r.default.fn.bootstrapTable.utils.calculateObjectValue(e.header,e.header.formatters[r.default.inArray(c,e.header.fields)],[h,i,a],h)),-1!==r.default.inArray(c,e.header.fields)&&(null==h?u=!1:"object"===n(h)&&f.filterCustomSearch?l.push(e.isValueExpected(s,h,f,c)):"object"===n(h)&&Array.isArray(h)?h.forEach((function(r){u||(u=e.isValueExpected(t,r,f,c))})):"object"!==n(h)||Array.isArray(h)?"string"!=typeof h&&"number"!=typeof h&&"boolean"!=typeof h||(u=e.isValueExpected(t,h,f,c)):Object.values(h).forEach((function(r){u||(u=e.isValueExpected(t,r,f,c))})))))})),l.push(u)})),!l.includes(!1)})):e.data,e.unsortedData=p(e.data))}},{key:"isValueExpected",value:function(t,e,r,n){var o=!1;o=r.filterStrictSearch||"select"===r.filterControl&&!1!==r.passed.filterStrictSearch?e.toString().toLowerCase()===t.toString().toLowerCase():r.filterStartsWithSearch?0==="".concat(e).toLowerCase().indexOf(t):"datepicker"===r.filterControl?new Date(e).getTime()===new Date(t).getTime():this.options.regexSearch?Vv.regexCompare(e,t):"".concat(e).toLowerCase().includes(t);var i=/(?:(<=|=>|=<|>=|>|<)(?:\s+)?(\d+)?|(\d+)?(\s+)?(<=|=>|=<|>=|>|<))/gm.exec(t);if(i){var a=i[1]||"".concat(i[5],"l"),l=i[2]||i[3],c=parseInt(e,10),u=parseInt(l,10);switch(a){case">":case"<l":o=c>u;break;case"<":case">l":o=c<u;break;case"<=":case"=<":case">=l":case"=>l":o=c<=u;break;case">=":case"=>":case"<=l":case"=<l":o=c>=u}}if(r.filterCustomSearch){var f=Vv.calculateObjectValue(this,r.filterCustomSearch,[t,e,n,this.options.data],!0);null!==f&&(o=f)}return o}},{key:"initColumnSearch",value:function(t){if(Av(this),t)for(var e in this.filterColumnsPartial=t,this.updatePagination(),t)this.trigger("column-search",e,t[e])}},{key:"initToolbar",value:function(){this.showToolbar=this.showToolbar||this.options.showFilterControlSwitch,this.showSearchClearButton=this.options.filterControl&&this.options.showSearchClearButton,this.options.showFilterControlSwitch&&(this.buttons=Object.assign(this.buttons,{filterControlSwitch:{text:this.options.filterControlVisible?this.options.formatFilterControlSwitchHide():this.options.formatFilterControlSwitchShow(),icon:this.options.filterControlVisible?this.options.icons.filterControlSwitchHide:this.options.icons.filterControlSwitchShow,event:this.toggleFilterControl,attributes:{"aria-label":this.options.formatFilterControlSwitch(),title:this.options.formatFilterControlSwitch()}}})),s(a(d.prototype),"initToolbar",this).call(this)}},{key:"resetSearch",value:function(t){this.options.filterControl&&this.options.showSearchClearButton&&this.clearFilterControl(),s(a(d.prototype),"resetSearch",this).call(this,t)}},{key:"clearFilterControl",value:function(){if(this.options.filterControl){var t=this,e=this.$el.closest("table"),n=function(){var t=[],e=document.cookie.match(/bs\.table\.(filterControl|searchText)/g),n=localStorage;if(e&&r.default.each(e,(function(e,n){var o=n;/./.test(o)&&(o=o.split(".").pop()),-1===r.default.inArray(o,t)&&t.push(o)})),n)for(var o=0;o<n.length;o++){var i=n.key(o);/./.test(i)&&(i=i.split(".").pop()),t.includes(i)||t.push(i)}return t}(),o=Ev(t),i=!1,a=0;if(r.default.each(t._valuesFilterControl,(function(t,e){i=!!i||""!==e.value,e.value=""})),r.default.each(o,(function(t,e){e.value=""})),_v(t),clearTimeout(a),a=setTimeout((function(){n&&n.length>0&&r.default.each(n,(function(e,r){void 0!==t.deleteCookie&&t.deleteCookie(r)}))}),t.options.searchTimeOut),i&&o.length>0&&(this.filterColumnsPartial={},o.eq(0).trigger("INPUT"===this.tagName?"keyup":"change",{keyCode:13}),t.options.sortName!==e.data("sortName")||t.options.sortOrder!==e.data("sortOrder"))){var l=this.$header.find(Vv.sprintf('[data-field="%s"]',r.default(o[0]).closest("table").data("sortName")));l.length>0&&(t.onSort({type:"keypress",currentTarget:l}),r.default(l).find(".sortable").trigger("click"))}}}},{key:"onColumnSearch",value:function(t){var e=this,n=t.currentTarget;jv(t.keyCode)||(Av(this),this.options.cookie?this._filterControlValuesLoaded=!0:this.options.pageNumber=1,r.default.isEmptyObject(this.filterColumnsPartial)&&(this.filterColumnsPartial={}),(this.options.searchOnEnterKey?Ev(this).toArray():[n]).forEach((function(t){var n=r.default(t),o=n.val(),i=o?o.trim():"",a=n.closest("[data-field]").data("field");e.trigger("column-search",a,i),i?e.filterColumnsPartial[a]=i:delete e.filterColumnsPartial[a]})),this.onSearch({currentTarget:n},!1))}},{key:"toggleFilterControl",value:function(){this.options.filterControlVisible=!this.options.filterControlVisible;var t=Tv(this).find(".filter-control, .no-filter-control");this.options.filterControlVisible?t.show():(t.hide(),this.clearFilterControl()),this.options.height&&(r.default(".fixed-table-header table thead").find(".filter-control, .no-filter-control").toggle(this.options.filterControlVisible),Iv(this));var e=this.options.showButtonIcons?this.options.filterControlVisible?this.options.icons.filterControlSwitchHide:this.options.icons.filterControlSwitchShow:"",n=this.options.showButtonText?this.options.filterControlVisible?this.options.formatFilterControlSwitchHide():this.options.formatFilterControlSwitchShow():"";this.$toolbar.find(">.columns").find(".filter-control-switch").html("".concat(Vv.sprintf(this.constants.html.icon,this.options.iconsPrefix,e)," ").concat(n))}},{key:"triggerSearch",value:function(){Ev(this).each((function(){var t=r.default(this);t.is("select")?t.trigger("change"):t.trigger("keyup")}))}},{key:"_toggleColumn",value:function(t,e,r){this._initialized=!1,s(a(d.prototype),"_toggleColumn",this).call(this,t,e,r),Mv(this)}}],c&&i(e.prototype,c),f&&i(e,f),Object.defineProperty(e,"prototype",{writable:!1}),d}(r.default.BootstrapTable)}));
		</script>
		<script>
			function headerStyle(column) {
				return {
				  css: {
				    'padding-left': '15px',
				    'padding-right': '15px',
				    'padding-top': '10px',
				    'padding-bottom': '10px'
				  },
				}
			}
		</script>
'@
}
function New-BootstrapAlert {
    <#
        .SYNOPSIS
            Creates a new HTML div that uses the Bootstrap alert class
        .DESCRIPTION
            Creates a new HTML div that uses the Bootstrap alert class
        .OUTPUTS
            A string wih the HTML code for the div
        .EXAMPLE
            New-BootstrapAlert -Text 'blah'

            This example returns the following string:
            '<div class="alert alert-info"><strong>Info!</strong> blah</div>'
    #>
    [CmdletBinding()]
    param(
        #The HTML element to apply the Bootstrap column to
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [string[]]$Text,

        [Parameter(
            Position = 1
        )]
        [string]$Class = 'Info'
    )
    begin {}
    process {
        ForEach ($String in $Text) {
            #"<div class=`"alert alert-$($Class.ToLower())`"><strong>$Class!</strong> $String</div>"
            "<div class=`"alert alert-$($Class.ToLower())`">$String</div>"
        }
    }
    end {}

}
function New-BootstrapColumn {
    <#
        .SYNOPSIS
            Wraps HTML elements in a Bootstrap column of the specified width
        .DESCRIPTION
            Creates a Bootstrap container which contains a row which contains a column of the specified width
        .OUTPUTS
            A string wih the code for the Bootstrap container
        .EXAMPLE
            New-BootstrapColumn -Html '<h1>Heading</h1>'

            This example returns the following string:
            '<div class="container"><div class="row justify-content-md-center"><div class="col col-lg-12"><h1>Heading</h1></div></div></div>'
    #>
    [OutputType([System.String])]
    [CmdletBinding()]
    param(
        #The HTML element to apply the Bootstrap column to
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$Html,

        [Parameter(
            Position = 1
        )]
        [Int]$Width = 12
    )
    begin {
        $NewHtml = "<div class=`"container`"><div class=`"row justify-content-md-center`">"
    }
    process {
        ForEach ($OldHtml in $Html) {
            $NewHtml = "$NewHtml<div class=`"col col-lg-$Width`">$OldHtml</div>"
        }
    }
    end {
        $NewHtml = "$NewHtml</div></div>"
        return $NewHtml
    }
}
function New-BootstrapDiv {
    <#
        .SYNOPSIS
            Creates a new HTML div that uses the Bootstrap alert class
        .DESCRIPTION
            Creates a new HTML div that uses the Bootstrap alert class
        .OUTPUTS
            A string wih the HTML code for the div
        .EXAMPLE
            New-BootstrapAlert -Text 'blah'

            This example returns the following string:
            '<div class="alert alert-info"><strong>Info!</strong> blah</div>'
    #>
    [CmdletBinding()]
    param(
        #The HTML element to apply the Bootstrap column to
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [string[]]$Text,

        [Parameter(
            Position = 1
        )]
        [string]$Class = 'h-100 p-1 bg-light border rounded-3'
    )
    begin {}
    process {
        ForEach ($String in $Text) {
            #"<div class=`"alert alert-$($Class.ToLower())`"><strong>$Class!</strong> $String</div>"
            "<div class=`"alert alert-$($Class.ToLower())`">$String</div>"
        }
    }
    end {}

}
function New-BootstrapDivWithHeading {
    param (
        [string]$HeadingText,
        [uint16]$HeadingLevel = 5,
        [string]$Content,
        [hashtable]$HeadingsAndContent
    )

    if ($PSBoundParameters.ContainsKey('HeadingsAndContent')) {
        [string]$Text = ForEach ($Key in $HeadingsAndContent.Keys) {
            (New-HtmlHeading $Key -Level $HeadingLevel) +
            $HeadingsAndContent[$Key]
        }
    } else {
        $Text = (New-HtmlHeading $HeadingText -Level $HeadingLevel) +
        $Content
    }

    New-BootstrapDiv -Text $Text
}
function New-BootstrapGrid {
    <#
        .SYNOPSIS
            Wraps HTML elements in a Bootstrap column of the specified width
        .DESCRIPTION
            Creates a Bootstrap container which contains a row which contains a column of the specified width
        .OUTPUTS
            A string wih the code for the Bootstrap container
        .EXAMPLE
            New-BootstrapColumn -Html '<h1>Heading</h1>'

            This example returns the following string:
            '<div class="container"><div class="row justify-content-md-center"><div class="col col-lg-12"><h1>Heading</h1></div></div></div>'
    #>
    [CmdletBinding()]
    param(
        #The HTML element to apply the Bootstrap column to
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$Html,

        [string]$Justify = 'Center'
    )
    begin {
        $String = @()
        [decimal]$ExactWidth = 12 / ($Html | Measure-Object).Count
        [int]$Width = [Math]::Floor($ExactWidth)
        $String += "<div class=`"container`"><div class=`"row justify-content-md-$($Justify.ToLower())`">"
    }
    process {
        ForEach ($OldHtml in $Html) {
            $String += "<div class=`"col col-lg-$Width`">$OldHtml</div>"
        }
    }
    end {
        $String += "</div></div>"
        $String -join ''
    }

}
Function New-BootstrapList {
    <#
        .SYNOPSIS
            Upgrade a boring HTML unordered list to a fancy Bootstrap list group
        .DESCRIPTION
            Applies the Bootstrap 'table table-striped' class to an HTML table
        .OUTPUTS
            A string wih the code for the Bootstrap table
        .EXAMPLE
            New-BootstrapTable -HtmlTable '<table><tr><th>Name</th><th>Id</th></tr><tr><td>ALMon</td><td>5540</td></tr></table>'

            This example returns the following string:
            '<table class="table table-striped"><tr><th>Name</th><th>Id</th></tr><tr><td>ALMon</td><td>5540</td></tr></table>'
        .NOTES
            Author: Jeremy La Camera
            Last Updated: 11/6/2016
    #>
    [CmdletBinding()]
    param(
        #The HTML table to apply the Bootstrap striped table CSS class to
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$HtmlTable
    )
    begin {}
    process {
        ForEach ($Table in $HtmlTable) {
            [String]$NewTable = $Table -replace '<table>', '<table class="table table-striped">'
            Write-Output $NewTable
        }
    }
    end {}
}
function New-BootstrapPanel {
    <#
        .SYNOPSIS
            Wraps HTML elements in a Bootstrap column of the specified width
        .DESCRIPTION
            Creates a Bootstrap container which contains a row which contains a column of the specified width
        .OUTPUTS
            A string wih the code for the Bootstrap container
        .EXAMPLE
            New-BootstrapColumn -Html '<h1>Heading</h1>'

            This example returns the following string:
            '<div class="container"><div class="row justify-content-md-center"><div class="col col-lg-12"><h1>Heading</h1></div></div></div>'
    #>
    [CmdletBinding()]
    param(
        #The HTML element to apply the Bootstrap column to
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$Html,

        [string]$Class = 'default',

        [string]$Heading,

        [string]$Footer
    )
    begin {
        $String = @()
        $String += "<div class=`"panel panel-$($Class.ToLower())`">"
        if ($Heading) {
            $String += "<div class=`"panel-heading`">$Heading</div>"
        }
    }
    process {
        ForEach ($OldHtml in $Html) {
            $String += "<div class=`"panel-body`">$OldHtml</div>"
        }
    }
    end {
        if ($Footer) {
            $String += "<div class=`"panel-footer`">$Footer</div>"
        }
        $String += "</div>"
        $String -join ''
    }

}
function New-BootstrapReport {
    <#
        .SYNOPSIS
            Build a new Bootstrap report based on an HTML template
        .DESCRIPTION
            Inserts the specified title, description, and body into the HTML report template
        .OUTPUTS
            Outputs a complete HTML report as a string
        .EXAMPLE
            New-BootstrapReport -Title 'ReportTitle' -Description 'This is the report description' -Body 'This is the body of the report'
    #>
    [CmdletBinding()]
    param(

        #Title of the report (displayed at the top)
        [String]$Title,

        #Description of the report (displayed below the Title)
        [String]$Description,

        #Body of the report (tables, list groups, etc.)
        [String[]]$Body,

        #The path to the HTML report template that includes the Boostrap CSS
        [String]$TemplatePath,

        [switch]$JavaScript,

        #The path to the JavaScript (inside of <script> tags)
        [String]$ScriptPath,

        [String]$AdditionalScriptHtml

    )

    if ($PSBoundParameters.ContainsKey('TemplatePath')) {
        [String]$Report = Get-Content $TemplatePath -Raw
        if ($null -eq $Report) { Write-Warning "$TemplatePath not loaded.  Failure." }
    } else {
        [String]$Report = Get-BootstrapTemplate
    }

    if ($JavaScript) {
        [string]$ReportScript = Get-JavaScript
        $ReportScript = "$ReportScript$AdditionalScriptHtml"
    } else {
        $ReportScript = $AdditionalScriptHtml
    }

    # Turn URLs into hyperlinks
    $URLs = ($Body | Select-String -Pattern 'http[s]?:\/\/[^\s\"\<\>\#\%\{\}\|\\\^\~\[\]\`]*' -AllMatches).Matches.Value | Sort-Object -Unique
    foreach ($URL in $URLs) {
        if ($URL.Length -gt 50) {
            $Body = $Body.Replace($URL, "<a href=$URL>$($URL[0..46] -join '')...</a>")
        } else {
            $Body = $Body.Replace($URL, "<a href=$URL>$URL</a>")
        }
    }

    $Report = $Report.Replace('_ReportTitle_', $Title)
    $Report = $Report.Replace('_ReportDescription_', $Description)
    $Report = $Report.Replace('_ReportBody_', $Body)
    $Report = $Report.Replace('_ReportScript_', $ReportScript)

    return $Report
}
Function New-BootstrapTable {
    <#
        .SYNOPSIS
            Upgrade a boring HTML table to a fancy Bootstrap table
        .DESCRIPTION
            Applies the Bootstrap 'table table-striped' class to an HTML table
        .OUTPUTS
            A string wih the code for the Bootstrap table
        .EXAMPLE
            New-BootstrapTable -HtmlTable '<table><tr><th>Name</th><th>Id</th></tr><tr><td>ALMon</td><td>5540</td></tr></table>'

            This example returns the following string:
            '<table class="table table-striped"><tr><th>Name</th><th>Id</th></tr><tr><td>ALMon</td><td>5540</td></tr></table>'
        .NOTES
            Author: Jeremy La Camera
            Last Updated: 11/6/2016
    #>
    [CmdletBinding()]
    param(
        #The HTML table to apply the Bootstrap striped table CSS class to
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$HtmlTable
    )
    begin {}
    process {
        ForEach ($Table in $HtmlTable) {
            [String]$NewTable = $Table -replace '<table>', '<table class="table table-striped">'
            Write-Output $NewTable
        }
    }
    end {}
}
function New-HtmlAnchor {
    <#
        .SYNOPSIS
            Build a new HTML anchor
        .DESCRIPTION
            Inserts the specified HTML element into an HTML anchor with the specified name
        .OUTPUTS
            Outputs the heading as a string
        .EXAMPLE
            New-HtmlAnchor -Element "<h1>SampleHeader</h1>" -Name "AnchorToSampleHeader"
    #>
    [CmdletBinding()]
    param(

        #The text of the heading
        [Parameter(
            Position = 0,
            ValueFromPipeline = $true,
            Mandatory = $true
        )]
        [String[]]$Element,

        #The heading level to generate (New-HtmlHeading can create h1, h2, h3, h4, h5, or h6 tags)
        [Parameter(Mandatory)]
        [String]$Name

    )
    begin {}
    process {
        Write-Output "<h$Level>$Text</h$Level>"
    }
    end {}
}
function New-HtmlHeading {
    <#
        .SYNOPSIS
            Build a new HTML heading
        .DESCRIPTION
            Inserts the specified text into an HTML heading of the specified level
        .OUTPUTS
            Outputs the heading as a string
        .EXAMPLE
            New-HtmlHeading -Text 'Example Heading'
    #>
    [CmdletBinding()]
    param(

        #The text of the heading
        [Parameter(
            Position = 0,
            ValueFromPipeline = $True
        )]
        [String[]]$Text,

        #The heading level to generate (New-HtmlHeading can create h1, h2, h3, h4, h5, or h6 tags)
        [ValidateRange(1, 6)]
        [Int16]$Level = 1

    )
    begin {}
    process {
        Write-Output "<h$Level>$Text</h$Level>"
    }
    end {}
}
function New-HtmlParagraph {
    <#
        .SYNOPSIS
            Build a new HTML heading
        .DESCRIPTION
            Inserts the specified text into an HTML heading of the specified level
        .OUTPUTS
            Outputs the heading as a string
        .EXAMPLE
            New-HtmlHeading -Text 'Example Heading'
    #>
    [CmdletBinding()]
    param(

        #The text of the heading
        [Parameter(
            Position = 0,
            ValueFromPipeline = $True
        )]
        [String[]]$Text,

        #The heading level to generate (New-HtmlHeading can create h1, h2, h3, h4, h5, or h6 tags)
        [ValidateRange(1, 6)]
        [Int16]$Level = 1

    )
    begin {}
    process {
        Write-Output "<h$Level>$Text</h$Level>"
    }
    end {}
}
<#
# Add any custom C# classes as usable (exported) types
$CSharpFiles = Get-ChildItem -Path "$PSScriptRoot\*.cs"
ForEach ($ThisFile in $CSharpFiles) {
    Add-Type -Path $ThisFile.FullName -ErrorAction Stop
}
#>

# Definition of Module 'Permission' Version '0.0.73' is below

function Expand-Folder {

    # Expand a folder path into the paths of its subfolders

    param (

        # Path to return along, with the paths to its subfolders
        $Folder,

        <#
        How many levels of subfolder to enumerate

            Set to 0 to ignore all subfolders

            Set to -1 (default) to recurse infinitely

            Set to any whole number to enumerate that many levels
        #>
        $LevelsOfSubfolders,

        # Number of asynchronous threads to use
        [uint16]$ThreadCount = ((Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum),

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Hashtable of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages

    )

    $LogParams = @{
        LogMsgCache  = $LogMsgCache
        ThisHostname = $TodaysHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }

    if ($ThreadCount -eq 1 -or @($Folder).Count -eq 1) {

        $i = 0
        ForEach ($ThisFolder in $Folder) {
            $PercentComplete = $i / $Folder.Count
            Write-Progress -Activity "Get-Subfolder" -CurrentOperation $ThisFolder -PercentComplete $PercentComplete
            $i++
            $Subfolders = $null
            $Subfolders = Get-Subfolder -TargetPath $ThisFolder -FolderRecursionDepth $LevelsOfSubfolders -ErrorAction Continue
            Write-LogMsg @LogParams -Text "# Folders (including parent): $($Subfolders.Count + 1) for '$ThisFolder'"
            $Subfolders
        }
        Write-Progress -Activity "Get-Subfolder" -Completed

    } else {

        $GetSubfolder = @{
            Command           = 'Get-Subfolder'
            InputObject       = $Folder
            InputParameter    = 'TargetPath'
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogMsgCache       = $LogMsgCache
            Threads           = $ThreadCount
        }
        Split-Thread @GetSubfolder

    }
}
function Export-FolderPermissionHtml {

    param (

        # Regular expressions matching names of security principals to exclude from the HTML report
        $ExcludeAccount,

        # Accounts whose objectClass property is in this list are excluded from the HTML report
        [string[]]$ExcludeClass = @('group', 'computer'),

        <#
        Domain(s) to ignore (they will be removed from the username)

        Intended when a user has matching SamAccountNames in multiple domains but you only want them to appear once on the report.

        Can also be used to remove all domains simply for brevity in the report.
        #>
        $IgnoreDomain,

        # Path to the NTFS folder whose permissions are being exported
        [string[]]$TargetPath,

        # Group members are not being exported (only the groups themselves)
        $NoGroupMembers,

        # Path to the folder to save the logs and reports generated by this script
        $OutputDir,

        # NTAccount caption of the user running the script
        $WhoAmI,

        # FQDN of the computer running the script
        $ThisFqdn,

        # Timer to measure progress and performance
        $StopWatch,

        # Title at the top of the HTML report
        $Title,

        # Generate a report with only HTML and CSS but no JavaScript
        [switch]$NoJavaScript,

        $FolderPermissions,
        $LogParams,
        $ReportDescription,
        $FolderTableHeader,
        $ReportFileList,
        $ReportFile,
        $LogFileList,
        $ReportInstanceId,
        $Subfolders,
        $ResolvedFolderTargets
    )

    # Convert the target path(s) to a Bootstrap alert
    $TargetPathString = $TargetPath -join '<br />'
    Write-LogMsg @LogParams -Text "New-BootstrapAlert -Class Dark -Text '$TargetPathString'"
    $ReportDescription = "$(New-BootstrapAlert -Class Dark -Text $TargetPathString) $ReportDescription"

    # Convert the folder list to an HTML table
    $FormattedFolders = Get-FolderBlock -FolderPermissions $FolderPermissions

    # Convert the folder permissions to an HTML table
    $GetFolderPermissionsBlock = @{
        FolderPermissions = $FolderPermissions
        ExcludeAccount    = $ExcludeAccount
        ExcludeClass      = $ExcludeClass
        IgnoreDomain      = $IgnoreDomain
    }
    Write-LogMsg @LogParams -Text "Get-FolderPermissionsBlock @GetFolderPermissionsBlock"
    $FormattedFolderPermissions = Get-FolderPermissionsBlock @GetFolderPermissionsBlock

    ##Commented the three lines below because actually keeping semicolons means it copy/pastes better into Excel
    ### Convert-ToHtml will not expand in-line HTML
    ### So replace the placeholders (semicolons) with HTML line breaks now, after Convert-ToHtml has already run
    ##$FormattedFolderPermissions.HtmlDiv = $FormattedFolderPermissions.HtmlDiv -replace ' ; ','<br>'

    # Combine the header and table inside a Bootstrap div
    Write-LogMsg @LogParams -Text "New-BootstrapDivWithHeading -HeadingText '$FolderTableHeader' -Content `$FormattedFolders.HtmlDiv"
    $HtmlFolderList = New-BootstrapDivWithHeading -HeadingText $FolderTableHeader -Content $FormattedFolders.HtmlDiv
    $JsonFolderList = New-BootstrapDivWithHeading -HeadingText $FolderTableHeader -Content $FormattedFolders.JsonDiv

    $HeadingText = 'Accounts Excluded by Regular Expression'
    if ($ExcludeAccount) {
        $ListGroup = $ExcludeAccount |
        ConvertTo-HtmlList |
        ConvertTo-BootstrapListGroup

        $Description = 'Accounts matching these regular expressions were excluded from the report.'
        Write-LogMsg @LogParams -Text "New-BootstrapDivWithHeading -HeadingText '$HeadingText' -Content `"`$Description`$ListGroup`""
        $HtmlRegExExclusions = New-BootstrapDivWithHeading -HeadingText $HeadingText -Content "$Description$ListGroup"
    } else {
        $Description = 'No accounts were excluded based on regular expressions.'
        $HtmlRegExExclusions = New-BootstrapDivWithHeading -HeadingText $HeadingText -Content $Description
    }

    $HeadingText = 'Accounts Excluded by Class'
    if ($ExcludeClass) {
        $ListGroup = $ExcludeClass |
        ConvertTo-HtmlList |
        ConvertTo-BootstrapListGroup

        $Description = 'Accounts whose objectClass property is in this list were excluded from the report.'
        $HtmlClassExclusions = New-BootstrapDivWithHeading -HeadingText $HeadingText -Content "$Description$ListGroup"
    } else {
        $Description = 'No accounts were excluded based on objectClass.'
        $HtmlClassExclusions = New-BootstrapDivWithHeading -HeadingText $HeadingText -Content $Description
    }

    $HeadingText = 'Domains Ignored'
    if ($IgnoreDomain) {
        $ListGroup = $IgnoreDomain |
        ConvertTo-HtmlList |
        ConvertTo-BootstrapListGroup

        $Description = 'Accounts from these domains are listed in the report without their domain.'
        $HtmlIgnoredDomains = New-BootstrapDivWithHeading -HeadingText $HeadingText -Content "$Description$ListGroup"
    } else {
        $Description = 'No domains were ignored.  All accounts have their domain listed.'
        $HtmlIgnoredDomains = New-BootstrapDivWithHeading -HeadingText $HeadingText -Content $Description
    }

    $HeadingText = 'Group Members'
    if ($NoGroupMembers) {
        $Description = 'Group members were excluded from the report.<br />Only accounts directly from the ACLs are included in the report.'
    } else {
        $Description = 'No accounts were excluded based on group membership.<br />Members of groups from the ACLs are included in the report.'
    }
    $HtmlExcludedGroupMembers = New-BootstrapDivWithHeading -HeadingText $HeadingText -Content $Description

    # Arrange the exclusions in two Bootstrap columns
    Write-LogMsg @LogParams -Text "New-BootstrapColumn -Html '`$HtmlExcludedGroupMembers`$HtmlClassExclusions',`$HtmlIgnoredDomains`$HtmlRegExExclusions"
    $ExclusionsDiv = New-BootstrapColumn -Html "$HtmlExcludedGroupMembers$HtmlClassExclusions", "$HtmlIgnoredDomains$HtmlRegExExclusions" -Width 6

    if ($NoJavaScript) {
        $NoJavaScriptReportFile = $ReportFile -replace 'PermissionsReport', 'PermissionsReport_NoJavaScript'
        $ReportFileList += $NoJavaScriptReportFile
    }

    # Convert the list of generated report files to a Bootstrap list group
    $HtmlListOfReports = $ReportFileList + $ReportFile |
    Split-Path -Leaf |
    ConvertTo-HtmlList |
    ConvertTo-BootstrapListGroup

    # Convert the list of generated log files to a Bootstrap list group
    $HtmlListOfLogs = $LogFileList |
    Split-Path -Leaf |
    ConvertTo-HtmlList |
    ConvertTo-BootstrapListGroup

    # Arrange the lists of generated files in two Bootstrap columns
    $HtmlReportsHeading = New-HtmlHeading -Text 'Reports' -Level 6
    $HtmlLogsHeading = New-HtmlHeading -Text 'Logs' -Level 6
    Write-LogMsg @LogParams -Text "New-BootstrapColumn -Html '`$HtmlReportsHeading`$HtmlListOfReports',`$HtmlLogsHeading`$HtmlListOfLogs"
    $FileListColumns = New-BootstrapColumn -Html "$HtmlReportsHeading$HtmlListOfReports", "$HtmlLogsHeading$HtmlListOfLogs" -Width 6

    # Convert the output directory path to a Boostrap alert
    #$HtmlOutputDir = New-HtmlHeading -Text $OutputDir -Level 6
    $HtmlOutputDir = New-BootstrapAlert -Text $OutputDir -Class 'secondary'

    # Combine the alert and the columns of generated files inside a Bootstrap div
    Write-LogMsg @LogParams -Text "New-BootstrapDivWithHeading -HeadingText 'Output Folder:' -Content '`$HtmlOutputDir`$FileListColumns'"
    $FileList = New-BootstrapDivWithHeading -HeadingText "Output Folder:" -Content "$HtmlOutputDir$FileListColumns"

    # Generate a footer to include at the bottom of the report
    Write-LogMsg @LogParams -Text "Get-ReportFooter -StopWatch `$StopWatch -ReportInstanceId '$ReportInstanceId' -WhoAmI '$WhoAmI' -ThisFqdn '$ThisFqdn'"
    $FooterParams = @{
        StopWatch        = $StopWatch
        ReportInstanceId = $ReportInstanceId
        WhoAmI           = $WhoAmI
        ThisFqdn         = $ThisFqdn
        ItemCount        = ($Subfolders.Count + $ResolvedFolderTargets.Count)
    }
    $ReportFooter = Get-HtmlReportFooter @FooterParams

    # Combine all the elements into a single string which will be the innerHtml of the <body> element of the report
    Write-LogMsg @LogParams -Text "Get-HtmlBody -FolderList `$HtmlFolderList -HtmlFolderPermissions `$FormattedFolderPermissions.HtmlDiv"
    $BodyParams = @{
        FolderList            = $HtmlFolderList
        HtmlFolderPermissions = $FormattedFolderPermissions.HtmlDiv
        HtmlExclusions        = $ExclusionsDiv
        HtmlFileList          = $FileList
        ReportFooter          = $ReportFooter
    }
    [string]$Body = Get-HtmlBody @BodyParams

    # Apply the report template to the generated HTML report body and description
    $ReportParameters = @{
        Title       = $Title
        Description = $ReportDescription
        Body        = $Body
    }
    Write-LogMsg @LogParams -Text "New-BootstrapReport @ReportParameters"
    $Report = New-BootstrapReport @ReportParameters

    if ($NoJavaScript) {
        # Save the Html report
        $null = Set-Content -LiteralPath $NoJavaScriptReportFile -Value $Report

        # Output the name of the report file to the Information stream
        Write-Information $NoJavaScriptReportFile
    }


    Write-LogMsg @LogParams -Text "Get-HtmlBody -FolderList `$JsonFolderList -HtmlFolderPermissions `$FormattedFolderPermissions.JsonDiv"
    $BodyParams = @{
        FolderList            = $JsonFolderList
        HtmlFolderPermissions = $FormattedFolderPermissions.JsonDiv
        HtmlExclusions        = $ExclusionsDiv
        HtmlFileList          = $FileList
        ReportFooter          = $ReportFooter
    }
    [string]$Body = Get-HtmlBody @BodyParams

    $ScriptHtmlBuilder = [System.Text.StringBuilder]::new()

    $FormattedFolderPermissions |
    ForEach-Object {
        $null = $ScriptHtmlBuilder.AppendLine((ConvertTo-BootstrapTableScript -TableId "#Perms_$($_.Path -replace '[^A-Za-z0-9\-_:.]', '-')" -ColumnJson $_.JsonColumns -DataJson $_.JsonData))
    }

    $null = $ScriptHtmlBuilder.AppendLine((ConvertTo-BootstrapTableScript -TableId '#Folders' -ColumnJson $FormattedFolders.JsonColumns -DataJson $FormattedFolders.JsonData))
    $ScriptHtml = $ScriptHtmlBuilder.ToString()

    # Apply the report template to the generated HTML report body and description
    $ReportParameters = @{
        Title                = $Title
        Description          = $ReportDescription
        Body                 = $Body
        JavaScript           = $true
        AdditionalScriptHtml = $ScriptHtml
    }
    Write-LogMsg @LogParams -Text "New-BootstrapReport @ReportParameters"
    $Report = New-BootstrapReport @ReportParameters

    # Save the Html report
    $null = Set-Content -LiteralPath $ReportFile -Value $Report

    # Output the name of the report file to the Information stream
    Write-Information $ReportFile

}
function Format-TimeSpan {
    param (
        [timespan]$TimeSpan,
        [string[]]$UnitsToResolve = @('day', 'hour', 'minute', 'second', 'millisecond')
    )
    $StringBuilder = [System.Text.StringBuilder]::new()
    $aUnitWithAValueHasBeenFound = $false
    foreach ($Unit in $UnitsToResolve) {
        if ($TimeSpan."$Unit`s") {
            if ($aUnitWithAValueHasBeenFound) {
                $null = $StringBuilder.Append(", ")
            }
            $aUnitWithAValueHasBeenFound = $true

            if ($TimeSpan."$Unit`s" -eq 1) {
                $null = $StringBuilder.Append("$($TimeSpan."$Unit`s") $Unit")
            } else {
                $null = $StringBuilder.Append("$($TimeSpan."$Unit`s") $Unit`s")
            }
        }
    }
    $StringBuilder.ToString()
}
function Get-FolderAccessList {
    param (

        # Path to the item whose permissions to export (inherited ACEs will be included)
        $Folder,

        # Path to the subfolders whose permissions to report (inherited ACEs will be skipped)
        $Subfolder,

        # Number of asynchronous threads to use
        [uint16]$ThreadCount = ((Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum),

        # Will be sent to the Type parameter of Write-LogMsg in the PsLogMessage module
        [string]$DebugOutputStream = 'Silent',

        # Hostname to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$TodaysHostname = (HOSTNAME.EXE),

        # Username to record in log messages (can be passed to Write-LogMsg as a parameter to avoid calling an external process)
        [string]$WhoAmI = (whoami.EXE),

        # Hashtable of log messages for Write-LogMsg (can be thread-safe if a synchronized hashtable is provided)
        [hashtable]$LogMsgCache = $Global:LogMessages,

        # Thread-safe cache of items and their owners
        [System.Collections.Concurrent.ConcurrentDictionary[String, PSCustomObject]]$OwnerCache = [System.Collections.Concurrent.ConcurrentDictionary[String, PSCustomObject]]::new()

    )

    $LogParams = @{
        LogMsgCache  = $LogMsgCache
        ThisHostname = $TodaysHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }

    # We expect a small number of folders and a large number of subfolders
    # We will multithread the subfolders but not the folders
    # Multithreading overhead actually hurts performance for such a fast operation (Get-FolderAce) on a small number of items
    $i = 0
    ForEach ($ThisFolder in $Folder) {
        $PercentComplete = $i / $Folder.Count
        Write-Progress -Activity "Get-FolderAce -IncludeInherited" -CurrentOperation $ThisFolder -PercentComplete $PercentComplete
        $i++
        Get-FolderAce -LiteralPath $ThisFolder -OwnerCache $OwnerCache -IncludeInherited
    }
    Write-Progress -Activity "Get-FolderAce -IncludeInherited" -Completed

    if ($ThreadCount -eq 1) {

        $i = 0
        ForEach ($ThisFolder in $Subfolder) {
            $PercentComplete = $i / $Subfolder.Count
            Write-Progress -Activity "Get-FolderAce" -CurrentOperation $ThisFolder -PercentComplete $PercentComplete
            $i++
            Get-FolderAce -LiteralPath $ThisFolder -OwnerCache $OwnerCache
        }
        Write-Progress -Activity "Get-FolderAce" -Completed

    } else {

        $GetFolderAce = @{
            Command           = 'Get-FolderAce'
            InputObject       = $Subfolder
            InputParameter    = 'LiteralPath'
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogMsgCache       = $LogMsgCache
            Threads           = $ThreadCount
            AddParam          = @{
                OwnerCache = $OwnerCache
            }
        }
        Split-Thread @GetFolderAce

    }

    # Return ACEs for the item owners (if they do not match the owner of the item's parent folder)
    # First return the owner of the parent item
    Get-OwnerAce -Item $Folder -OwnerCache $OwnerCache
    # Then return the owners of any items that differ from their parents' owners
    if ($ThreadCount -eq 1) {

        $i = 0
        ForEach ($Child in $Subfolder) {
            $PercentComplete = $i / $Subfolder.Count
            Write-Progress -Activity "Get-OwnerAce" -CurrentOperation $Child -PercentComplete $PercentComplete
            $i++

            Get-OwnerAce -Item $Child -OwnerCache $OwnerCache

        }
        Write-Progress -Activity "Get-OwnerAce" -Completed

    } else {

        $GetOwnerAce = @{
            Command           = 'Get-OwnerAce'
            InputObject       = $Subfolder
            InputParameter    = 'Item'
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogMsgCache       = $LogMsgCache
            Threads           = $ThreadCount
            AddParam          = @{
                OwnerCache = $OwnerCache
            }
        }
        Split-Thread @GetOwnerAce

    }

}
function Get-FolderBlock {
    param (

        $FolderPermissions

    )

    Write-LogMsg @LogParams -Text "Select-FolderTableProperty -InputObject `$FolderPermissions | ConvertTo-Html -Fragment | New-BootstrapTable"
    $FolderObjectsForTable = Select-FolderTableProperty -InputObject $FolderPermissions |
    Sort-Object -Property Folder

    $HtmlTable = $FolderObjectsForTable |
    ConvertTo-Html -Fragment |
    New-BootstrapTable

    $JsonData = $FolderObjectsForTable |
    ConvertTo-Json

    $JsonColumns = Get-FolderColumnJson -InputObject $FolderObjectsForTable
    $JsonTable = ConvertTo-BootstrapJavaScriptTable -Id 'Folders' -InputObject $FolderObjectsForTable -DataFilterControl -SearchableColumn 'Folder' -DropdownColumn 'Inheritance'

    return [pscustomobject]@{
        HtmlDiv     = $HtmlTable
        JsonDiv     = $JsonTable
        JsonData    = $JsonData
        JsonColumns = $JsonColumns
    }

}
function Get-FolderColumnJson {
    # For the JSON that will be used by JavaScript to generate the table
    param (
        $InputObject,
        [string[]]$PropNames
    )

    if (-not $PSBoundParameters.ContainsKey('PropNames')) {
        $PropNames = ($InputObject | Get-Member -MemberType noteproperty).Name
    }

    $Columns = ForEach ($Prop in $PropNames) {
        $Props = @{
            'field' = $Prop -replace '\s', ''
            'title' = $Prop
        }
        if ($Prop -eq 'Inheritance') {
            $Props['width'] = '1'
        }
        [PSCustomObject]$Props
    }

    $Columns |
    ConvertTo-Json
}
function Get-FolderPermissionsBlock {
    param (

        # Output from Format-FolderPermission in the PsNtfsModule which has already been piped to Group-Object using the Folder property
        $FolderPermissions,

        # Regular expressions matching names of Users or Groups to exclude from the Html report
        [string[]]$ExcludeAccount,

        # Accounts whose objectClass property is in this list are excluded from the HTML report
        [string[]]$ExcludeClass = @('group', 'computer'),

        <#
        Domain(s) to ignore (they will be removed from the username)

        Intended when a user has matching SamAccountNames in multiple domains but you only want them to appear once on the report.

        Can also be used to remove all domains simply for brevity in the report.
        #>
        [string[]]$IgnoreDomain

    )

    # Convert the $ExcludeClass array into a dictionary for fast lookups
    $ClassExclusions = @{}
    ForEach ($ThisClass in $ExcludeClass) {
        $ClassExclusions[$ThisClass] = $true
    }

    $ShortestFolderPath = @($FolderPermissions.Name |
        Sort-Object)[0]

    ForEach ($ThisFolder in $FolderPermissions) {

        $ThisHeading = New-HtmlHeading "Accounts with access to $($ThisFolder.Name)" -Level 5

        $ThisSubHeading = Get-FolderPermissionTableHeader -ThisFolder $ThisFolder -ShortestFolderPath $ShortestFolderPath

        $FilterContents = @{}

        $FilteredAccounts = $ThisFolder.Group |
        Group-Object -Property Account |
        Where-Object -FilterScript {

            # On built-in groups like 'Authenticated Users' or 'Administrators' the SchemaClassName is null but we have an ObjectType instead.
            # TODO: Research where this difference came from, should these be normalized earlier in the process?
            # A user who was found by being a member of a local group not have an ObjectType (because they are not directly part of the AccessControlEntry)
            # They should have their parent group's AccessControlEntry there...do they?  Doesn't it have a Group ObjectType there?

            if ($_.Group.AccessControlEntry.ObjectType) {
                $Schema = @($_.Group.AccessControlEntry.ObjectType)[0]
            } else {
                $Schema = @($_.Group.SchemaClassName)[0]
                # ToDo: SchemaClassName is a real property but may not exist on all objects.  ObjectType is my own property.  Need to verify+test all usage of both for accuracy.
                # ToDo: Why is $_.Group.SchemaClassName 'user' for the local Administrators group and Authenticated Users group, and it is 'Group' for the TestPC\Owner user?
            }

            # Exclude the object whose classes were specified in the parameters
            $SchemaExclusionResult = if ($ExcludeClass.Count -gt 0) {
                $ClassExclusions[$Schema]
            }
            -not $SchemaExclusionResult -and

            # Exclude the objects whose names match the regular expressions specified in the parameters
            ![bool]$(
                ForEach ($RegEx in $ExcludeAccount) {
                    if ($_.Name -match $RegEx) {
                        $FilterContents[$_.Name] = $_
                        $true
                    }
                }
            )

        }

        # Bugfix #48 https://github.com/IMJLA/Export-Permission/issues/48
        # Sending a dummy object down the line to avoid errors
        # TODO: More elegant solution needed. Downstream code should be able to handle null input.
        # TODO: Why does this suppress errors, but the object never appears in the tables? NOTE: Suspect this is now resolved by using -AsArray on ConvertTo-Json (lack of this was causing single objects to not be an array therefore not be displayed)
        if ($null -eq $FilteredAccounts) {
            $FilteredAccounts = [pscustomobject]@{
                'Name'  = 'NoAccountsMatchingCriteria'
                'Group' = [pscustomobject]@{
                    'IdentityReference' = '.'
                    'Access'            = '.'

                    'Name'              = '.'
                    'Department'        = '.'
                    'Title'             = '.'
                }
            }
        }

        $ObjectsForFolderPermissionTable = Select-FolderPermissionTableProperty -InputObject $FilteredAccounts -IgnoreDomain $IgnoreDomain |
        Sort-Object -Property Name

        $ThisTable = $ObjectsForFolderPermissionTable |
        ConvertTo-Html -Fragment |
        New-BootstrapTable

        $TableId = $ThisFolder.Name -replace '[^A-Za-z0-9\-_:.]', '-'

        $ThisJsonTable = ConvertTo-BootstrapJavaScriptTable -Id "Perms_$TableId" -InputObject $ObjectsForFolderPermissionTable -DataFilterControl -AllColumnsSearchable

        # Remove spaces from property titles
        $ObjectsForJsonData = $ObjectsForFolderPermissionTable |
        Select-Object -Property Account,
        Access,
        @{
            Label      = 'DuetoMembershipIn'
            Expression = { $_.'Due to Membership In' }
        },
        @{
            Label      = 'SourceofAccess'
            Expression = { $_.'Source of Access' }
        },
        Name,
        Department,
        Title

        [pscustomobject]@{
            HtmlDiv     = New-BootstrapDiv -Text ($ThisHeading + $ThisSubHeading + $ThisTable)
            JsonDiv     = New-BootstrapDiv -Text ($ThisHeading + $ThisSubHeading + $ThisJsonTable)
            JsonData    = $ObjectsForJsonData | ConvertTo-Json -AsArray
            JsonColumns = Get-FolderColumnJson -InputObject $ObjectsForFolderPermissionTable -PropNames Account, Access,
            'Due to Membership In', 'Source of Access', Name, Department, Title
            Path        = $ThisFolder.Name
        }
    }
}
function Get-FolderPermissionTableHeader {
    [OutputType([System.String])]
    param (
        $ThisFolder,
        [string]$ShortestFolderPath
    )
    $Leaf = $ThisFolder.Name | Split-Path -Parent | Split-Path -Leaf -ErrorAction SilentlyContinue
    if ($Leaf) {
        $ParentLeaf = $Leaf
    } else {
        $ParentLeaf = $ThisFolder.Name | Split-Path -Parent
    }
    if ('' -ne $ParentLeaf) {
        if (@($ThisFolder.Group.FolderInheritanceEnabled)[0] -eq $true) {
            if ($ThisFolder.Name -eq $ShortestFolderPath) {
                return "Inherited permissions from the parent folder ($ParentLeaf) are included. This folder can only be accessed by the accounts listed below:"
            } else {
                return "Inheritance is enabled on this folder. Accounts with access to the parent folder and subfolders ($ParentLeaf) can access this folder. So can any accounts listed below:"
            }
        } else {
            return "Inheritance is disabled on this folder. Accounts with access to the parent folder and subfolders ($ParentLeaf) cannot access this folder unless they are listed below:"
        }
    } else {
        return "This is the top-level folder. It can only be accessed by the accounts listed below:"
    }
}
function Get-FolderTableHeader {
    param ($LevelsOfSubfolders)

    switch ($LevelsOfSubfolders ) {
        0 {
            'Includes the target folder only (option to report on subfolders was declined)'
        }
        -1 {
            'Includes the target folder and all subfolders with unique permissions'
        }
        default {
            "Includes the target folder and $LevelsOfSubfolders levels of subfolders with unique permissions"
        }
    }
}
function Get-HtmlBody {
    param (
        $FolderList,
        $HtmlFolderPermissions,
        $ReportFooter,
        $HtmlFileList,
        $LogDir,
        $HtmlExclusions
    )
    $StringBuilder = [System.Text.StringBuilder]::new()
    $null = $StringBuilder.Append((New-HtmlHeading "Folders with Permissions in This Report" -Level 3))
    $null = $StringBuilder.Append($FolderList)
    $null = $StringBuilder.Append((New-HtmlHeading "Accounts Included in Those Permissions" -Level 3))
    $HtmlFolderPermissions |
    ForEach-Object {
        $null = $StringBuilder.Append($_)
    }
    if ($HtmlExclusions) {
        $null = $StringBuilder.Append((New-HtmlHeading "Exclusions from This Report" -Level 3))
        $null = $StringBuilder.Append($HtmlExclusions)
    }
    $null = $StringBuilder.Append((New-HtmlHeading "Files Generated" -Level 3))
    $null = $StringBuilder.Append($HtmlFileList)
    $null = $StringBuilder.Append($ReportFooter)
    $StringBuilder.ToString()
}
function Get-HtmlReportFooter {
    param (
        # Stopwatch that was started when report generation began
        [System.Diagnostics.Stopwatch]$StopWatch,

        # NT Account caption (CONTOSO\User) of the account running this function
        [string]$WhoAmI = (whoami.EXE),

        <#
        FQDN of the computer running this function

        Can be provided as a string to avoid calls to HOSTNAME.EXE and [System.Net.Dns]::GetHostByName()
        #>
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),

        [uint64]$ItemCount,

        [uint64]$TotalBytes,

        [string]$ReportInstanceId

    )
    $null = $StopWatch.Stop()
    $FinishTime = Get-Date
    $StartTime = $FinishTime.AddTicks(-$StopWatch.ElapsedTicks)
    $TimeZoneName = Get-TimeZoneName -Time $FinishTime
    $Duration = Format-TimeSpan -TimeSpan $StopWatch.Elapsed
    if ($TotalBytes) {
        $Size = " ($($TotalBytes / 1TB) TiB"
    }
    $Text = @"
Report generated by $WhoAmI on $ThisFQDN starting at $StartTime and ending at $FinishTime $TimeZoneName<br />
Processed permissions for $ItemCount items$Size in $Duration<br />
Report instance: $ReportInstanceId
"@
    New-BootstrapAlert -Class Light -Text $Text
}
function Get-PrtgXmlSensorOutput {
    param (
        $NtfsIssues
    )

    $Channels = [System.Collections.Generic.List[string]]::new()


    # Build our XML output formatted for PRTG.
    $ChannelParams = @{
        MaxError   = 0.5
        Channel    = 'Folders with inheritance disabled'
        Value      = ($NtfsIssues.FoldersWithBrokenInheritance | Measure-Object).Count
        CustomUnit = 'folders'
    }
    Format-PrtgXmlResult @ChannelParams |
    ForEach-Object { $null = $Channels.Add($_) }

    $ChannelParams = @{
        MaxError   = 0.5
        Channel    = 'ACEs for groups breaking naming convention'
        Value      = ($NtfsIssues.NonCompliantGroups | Measure-Object).Count
        CustomUnit = 'ACEs'
    }
    Format-PrtgXmlResult @ChannelParams |
    ForEach-Object { $null = $Channels.Add($_) }

    $ChannelParams = @{
        MaxError   = 0.5
        Channel    = 'ACEs for users instead of groups'
        Value      = ($NtfsIssues.UserACEs | Measure-Object).Count
        CustomUnit = 'ACEs'
    }
    Format-PrtgXmlResult @ChannelParams |
    ForEach-Object { $null = $Channels.Add($_) }


    $ChannelParams = @{
        MaxError   = 0.5
        Channel    = 'ACEs for unresolvable SIDs'
        Value      = ($NtfsIssues.SIDsToCleanup | Measure-Object).Count
        CustomUnit = 'ACEs'
    }
    Format-PrtgXmlResult @ChannelParams |
    ForEach-Object { $null = $Channels.Add($_) }


    $ChannelParams = @{
        MaxError   = 0.5
        Channel    = "Folders with 'CREATOR OWNER' access"
        Value      = ($NtfsIssues.FoldersWithCreatorOwner | Measure-Object).Count
        CustomUnit = 'folders'
    }
    Format-PrtgXmlResult @ChannelParams |
    ForEach-Object { $null = $Channels.Add($_) }

    Format-PrtgXmlSensorOutput -PrtgXmlResult $Channels -IssueDetected:$($NtfsIssues.IssueDetected)

}
function Get-ReportDescription {
    param ($LevelsOfSubfolders)

    switch ($LevelsOfSubfolders ) {
        0 {
            'Does not include permissions on subfolders (option was declined)'
        }
        -1 {
            'Includes all subfolders with unique permissions (including ∞ levels of subfolders)'
        }
        default {
            "Includes all subfolders with unique permissions (down to $LevelsOfSubfolders levels of subfolders)"
        }
    }
}
function Get-TimeZoneName {
    param (
        [datetime]$Time,
        [Microsoft.Management.Infrastructure.CimInstance]$TimeZone = (Get-CimInstance -ClassName Win32_TimeZone)
    )
    if ($Time.IsDaylightSavingTime()) {
        return $TimeZone.DaylightName
    } else {
        return $TimeZone.StandardName
    }
}
function Select-FolderPermissionTableProperty {
    # For the HTML table
    param (
        $InputObject,
        $IgnoreDomain
    )
    ForEach ($Object in $InputObject) {
        $GroupString = ($Object.Group.IdentityReference | Sort-Object -Unique) -join ' ; '
        # ToDo: param to allow setting [self] instead of the objects own name for this property
        #if ($GroupString -eq $Object.Name) {
        #    $GroupString = '[self]'
        #} else {
        ForEach ($IgnoreThisDomain in $IgnoreDomain) {
            $GroupString = $GroupString -replace "$IgnoreThisDomain\\", ''
        }
        #}
        [pscustomobject]@{
            'Account'              = $Object.Name
            'Access'               = ($Object.Group | Sort-Object -Property IdentityReference -Unique).Access -join ' ; '
            'Due to Membership In' = $GroupString
            'Source of Access'     = ($Object.Group.AccessControlEntry.ACESource | Sort-Object -Unique) -join ' ; '
            'Name'                 = @($Object.Group.Name)[0]
            'Department'           = @($Object.Group.Department)[0]
            'Title'                = @($Object.Group.Title)[0]
        }
    }

}
function Select-FolderTableProperty {
    # For the HTML table
    param (
        $InputObject
    )
    $Culture = Get-Culture
    $InputObject | Select-Object -Property @{
        Label      = 'Folder'
        Expression = { $_.Name }
    },
    @{
        Label      = 'Inheritance'
        Expression = {
            $Culture.TextInfo.ToTitleCase(@($_.Group.FolderInheritanceEnabled)[0])
        }
    }
}
function Select-UniqueAccountPermission {

    param (

        # Objects output from Format-SecurityPrincipal ... | Group-Object -Property User
        [Parameter(ValueFromPipeline)]
        $AccountPermission,

        <#
        Domain(s) to ignore (they will be removed from the username)

        Intended when a user has matching SamAccountNames in multiple domains but you only want them to appear once on the report.

        Can also be used to remove all domains simply for brevity in the report.
        #>
        [string[]]$IgnoreDomain,

        # Hashtable will be used to deduplicate
        $KnownUsers = [hashtable]::Synchronized(@{})

    )
    process {

        ForEach ($ThisUser in $AccountPermission) {

            $ShortName = $ThisUser.Name
            ForEach ($IgnoreThisDomain in $IgnoreDomain) {
                $ShortName = $ShortName -replace "^$IgnoreThisDomain\\", ''
            }

            $ThisKnownUser = $null
            $ThisKnownUser = $KnownUsers[$ShortName]
            if ($null -eq $ThisKnownUser) {
                $KnownUsers[$ShortName] = [pscustomobject]@{
                    'Count' = $ThisUser.Group.Count
                    'Name'  = $ShortName
                    'Group' = $ThisUser.Group
                }
            } else {
                $KnownUsers[$ShortName] = [pscustomobject]@{
                    'Count' = $ThisKnownUser.Group.Count + $ThisUser.Group.Count
                    'Name'  = $ShortName
                    'Group' = $ThisKnownUser.Group + $ThisUser.Group
                }
            }
        }

    }
    end {
        $KnownUsers.Values
    }

}
function Update-CaptionCapitalization {
    # As of 2022-08-31 this function is still not implemented...need to rethink
    param (
        [string]$ThisHostName,
        [hashtable]$Win32AccountsByCaption
    )
    $NewDictionary = [hashtable]::Synchronized(@{})
    $Win32AccountsByCaption.Keys |
    ForEach-Object {
        $Object = $Win32AccountsByCaption[$_]
        $NewKey = $_ -replace "^$ThisHostname\\$ThisHostname\\", "$ThisHostname\$ThisHostname\"
        $NewKey = $NewKey -replace "^$ThisHostname\\", "$ThisHostname\"
        $NewDictionary[$NewKey] = $Object
    }
    return $NewDictionary
}

# Add any custom C# classes as usable (exported) types
$CSharpFiles = Get-ChildItem -Path "$PSScriptRoot\*.cs"
ForEach ($ThisFile in $CSharpFiles) {
    Add-Type -Path $ThisFile.FullName -ErrorAction Stop
}

#----------------[ Logging ]----------------

    # Start a timer to measure progress and performance
    $StopWatch = [System.Diagnostics.Stopwatch]::new()
    $null = $StopWatch.Start()

    # Generate a unique ID for this run of the script
    $ReportInstanceId = [guid]::NewGuid().ToString()

    # Create a folder to store logs
    $OutputDir = New-DatedSubfolder -Root $OutputDir -Suffix "_$ReportInstanceId"

    # Start the PowerShell transcript
    # PowerShell cannot redirect the Success stream of Start-Transcript to the Information stream
    # But it can redirect it to $null, and then send the Transcript file path to Write-Information
    $TranscriptFile = "$OutputDir\PowerShellTranscript.log"
    Start-Transcript $TranscriptFile *>$null
    Write-Information $TranscriptFile

    #----------------[ Declarations ]----------------

    $CsvFilePath1 = "$OutputDir\1-AccessControlList.csv"
    $CsvFilePath2 = "$OutputDir\2-AccessControlListWithResolvedIdentityReferences.csv"
    $CsvFilePath3 = "$OutputDir\3-AccessControlListWithResolvedAndExpandedIdentityReferences.csv"
    $XmlFile = "$OutputDir\4-PrtgResult.xml"
    $ReportFile = "$OutputDir\PermissionsReport.htm"
    $LogFile = "$OutputDir\Export-Permission.log"
    $DirectoryEntryCache = [hashtable]::Synchronized(@{})
    $IdentityReferenceCache = [hashtable]::Synchronized(@{})
    $Win32AccountsBySID = [hashtable]::Synchronized(@{})
    $Win32AccountsByCaption = [hashtable]::Synchronized(@{})
    $DomainsBySID = [hashtable]::Synchronized(@{})
    $DomainsByNetbios = [hashtable]::Synchronized(@{})
    $DomainsByFqdn = [hashtable]::Synchronized(@{})
    $LogMsgCache = [hashtable]::Synchronized(@{})
    $ResolvedFolderTargets = [System.Collections.Generic.List[string]]::new()
    $UniqueServerNames = [System.Collections.Generic.List[string]]::new()
    $Permissions = $null
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

    # Get the FQDN of the computer running the script
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

        # Resolve each target path to all of its associated paths (including all DFS folder targets)
        Write-LogMsg @LogParams -Text "Resolve-Folder -FolderPath '$ThisTargetPath'"
        $null = $ResolvedFolderTargets.AddRange([string[]](Resolve-Folder -FolderPath $ThisTargetPath))

    }

}

end {

    # Expand each resolved folder path into the paths of its subfolders
    Write-LogMsg @LogParams -Text "Expand-Folder -Folder @('$($ResolvedFolderTargets -join "',")') -LevelsOfSubfolders $SubfolderLevels"
    $Subfolders = Expand-Folder -Folder $ResolvedFolderTargets -LevelsOfSubfolders $SubfolderLevels -ThreadCount $ThreadCount @LoggingParams

    # Get the relevant Access Control Entries for each folder and subfolder
    Write-LogMsg @LogParams -Text "Get-FolderAccessList -FolderTargets @('$($Subfolders -join "','")')"
    $Permissions = Get-FolderAccessList -Folder $ResolvedFolderTargets -Subfolder $Subfolders -ThreadCount $ThreadCount @LoggingParams

    # Save a CSV of the raw NTFS ACEs, showing non-inherited ACEs only except for the root folder $TargetPath
    $Permissions |
    Select-Object -Property @{
        Label      = 'Path'
        Expression = { $_.SourceAccessList.Path }
    }, IdentityReference, AccessControlType, FileSystemRights, IsInherited, PropagationFlags, InheritanceFlags, Source |
    Export-Csv -NoTypeInformation -LiteralPath $CsvFilePath1

    Write-Information $CsvFilePath1

    # This prevents threads that start near the same time from finding the cache empty and attempting costly operations to populate it
    # This prevents repetitive queries to the same directory servers

    # Identify server names from the item paths
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
            Threads        = $ThreadCount
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
            Threads              = $ThreadCount
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
    $PermissionsWithResolvedIdentityReferences |
    Select-Object -Property @{
        Label      = 'Path'
        Expression = { $_.SourceAccessList.Path }
    }, * |
    Export-Csv -NoTypeInformation -LiteralPath $CsvFilePath2

    Write-Information $CsvFilePath2

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
            Threads              = $ThreadCount
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
            Threads              = $ThreadCount
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
            Threads              = $ThreadCount
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
    Write-LogMsg @LogParams -Text "`$ExpandedAccountPermissions |"
    Write-LogMsg @LogParams -Text "`Select-Object -Property @{ Label = 'SourceAclPath'; Expression = { `$_.ACESourceAccessList.Path } }, * |"
    Write-LogMsg @LogParams -Text "Export-Csv -NoTypeInformation -LiteralPath '$CsvFilePath3'"

    $ExpandedAccountPermissions |
    Export-Csv -NoTypeInformation -LiteralPath $CsvFilePath3

    Write-Information $CsvFilePath3

    $Accounts = $ExpandedAccountPermissions |
    Group-Object -Property User

    # Filter out domain names we do not want on the report
    # This can be done when the domain is always the same and doesn't need to be displayed
    # This can also be done to ensure accounts only appear once on the report if they exist in multiple domains
    $IgnoreDomainString = "@('$($IgnoreDomain -join "',")')"
    Write-LogMsg @LogParams -Text "`$UniqueAccountPermissions = Select-UniqueAccountPermission -AccountPermission `$Accounts -IgnoreDomain $IgnoreDomainString"
    $UniqueAccountPermissions = Select-UniqueAccountPermission -AccountPermission $Accounts -IgnoreDomain $IgnoreDomain

    # Group the account permissions back into folder permissions for the report
    Write-LogMsg @LogParams -Text "Format-FolderPermission -UserPermission `$UniqueAccountPermissions | Group Folder | Sort Name"

    $FolderPermissions = Format-FolderPermission -UserPermission $UniqueAccountPermissions @LogParams |
    Group-Object -Property Folder |
    Sort-Object -Property Name

    # Export two versions of the HTML report
    # The first version uses no JavaScript so it can be rendered by e-mail clients
    # The second version is JavaScript-dependent and will not work in e-mail clients
    $ExportFolderPermissionHtml = @{ FolderPermissions = $FolderPermissions ; ExcludeAccount = $ExcludeAccount ; ExcludeClass = $ExcludeClass ;
        IgnoreDomain = $IgnoreDomain ; TargetPath = $TargetPath ; LogParams = $LogParams ; ReportDescription = $ReportDescription ; FolderTableHeader = $FolderTableHeader ;
        NoGroupMembers = $NoGroupMembers ; ReportFileList = $CsvFilePath1, $CsvFilePath2, $CsvFilePath3, $XmlFile; ReportFile = $ReportFile ;
        LogFileList = $TranscriptFile, $LogFile ; OutputDir = $OutputDir ; ReportInstanceId = $ReportInstanceId ; WhoAmI = $WhoAmI ; ThisFqdn = $ThisFqdn ;
        StopWatch = $StopWatch ; Subfolders = $Subfolders ; ResolvedFolderTargets = $ResolvedFolderTargets ; Title = $Title; NoJavaScript = $NoJavaScript
    }
    Export-FolderPermissionHtml @ExportFolderPermissionHtml

    # Identify common issues with permissions
    # ToDo: Users with ownership
    $NtfsIssueParams = @{
        FolderPermissions = $FolderPermissions
        UserPermissions   = $Accounts
        GroupNameRule     = $GroupNameRule
        TodaysHostname    = $ThisHostname
        WhoAmI            = $WhoAmI
        LogMsgCache       = $LogMsgCache
    }
    Write-LogMsg @LogParams -Text "New-NtfsAclIssueReport @NtfsIssueParams"
    $NtfsIssues = New-NtfsAclIssueReport @NtfsIssueParams

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
    $LogMsgCache.Values |
    Sort-Object -Property Timestamp |
    Export-Csv -Delimiter "`t" -NoTypeInformation -LiteralPath $LogFile

    Stop-Transcript  *>$null

    # Output the XML so the script can be directly used as a PRTG sensor
    # Caution: This use may be a problem for a PRTG probe because of how long the script can run on large folders/domains
    # Recommendation: Specify the appropriate parameters to run this as a PRTG push sensor instead
    return $XMLOutput

}

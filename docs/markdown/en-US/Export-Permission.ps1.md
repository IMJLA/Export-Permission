---
external help file: -help.xml
help version: 0.0.370
locale: en-US
script name: 
online version:
schema: 2.0.0
script guid: fd2d03cf-4d29-4843-bb1c-0fba86b0220a
---

# Export-Permission.ps1

## SYNOPSIS
Create CSV, HTML, and XML reports of permissions

## SYNTAX

```
Export-Permission.ps1 [[-TargetPath] <DirectoryInfo[]>] [[-ExcludeAccount] <String[]>]
 [[-IncludeAccount] <String[]>] [[-ExcludeClass] <String[]>] [[-IgnoreDomain] <String[]>]
 [[-OutputDir] <String>] [-NoMembers] [[-RecurseDepth] <Int32>] [[-Title] <String>]
 [[-AccountConvention] <ScriptBlock>] [[-ThreadCount] <UInt16>] [-Interactive] [[-PrtgProbe] <String>]
 [[-PrtgProtocol] <String>] [[-PrtgPort] <UInt16>] [[-PrtgToken] <String>] [[-SplitBy] <String[]>]
 [[-GroupBy] <String>] [[-FileFormat] <String[]>] [[-OutputFormat] <String>] [[-Detail] <Int32[]>]
 [[-InheritanceFlagResolved] <String[]>] [-NoProgress] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
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

## EXAMPLES

### EXAMPLE 1
```
Export-Permission.ps1 -TargetPath C:\Test
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

### EXAMPLE 2
```
Export-Permission.ps1 -TargetPath C:\Test -ExcludeAccount 'BUILTIN\\Administrator'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Exclude the built-in Administrator account from the HTML report

The ExcludeAccount parameter uses RegEx, so the \ in BUILTIN\Administrator needed to be escaped.

The RegEx escape character is \ so the regular expression needed for the parameter is 'BUILTIN\\\\Administrator'

### EXAMPLE 3
```
Export-Permission.ps1 -TargetPath C:\Test -ExcludeAccount @(
    'BUILTIN\\Administrators',
    'BUILTIN\\Administrator',
    'CREATOR OWNER',
    'NT AUTHORITY\\SYSTEM'
)
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Exclude from the HTML report:
- The built-in Administrator account
- The built-in Administrators group and its members (unless they appear elsewhere in the permissions)
- The CREATOR OWNER security principal
- The computer account (NT AUTHORITY\SYSTEM)

Note: CREATOR OWNER will still be reported as an alarm in the PRTG XML output

### EXAMPLE 4
```
Export-Permission.ps1 -TargetPath C:\Test -ExcludeClass @('computer')
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Include empty groups on the HTML report (rather than the default setting which would exclude computers and groups)

### EXAMPLE 5
```
Export-Permission.ps1 -TargetPath C:\Test -NoGroupMembers -ExcludeClass @('computer')
```

Generate reports on the NTFS permissions for the folder C:\Test

Do not spend time retrieving group members

Include groups on the report, but exclude computers (rather than the default setting which would exclude computers and groups)

### EXAMPLE 6
```
Export-Permission.ps1 -TargetPath C:\Test -IgnoreDomain 'CONTOSO'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Remove the CONTOSO domain prefix from associated accounts and groups

### EXAMPLE 7
```
Export-Permission.ps1 -TargetPath C:\Test -IgnoreDomain 'CONTOSO1','CONTOSO2'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Remove the CONTOSO1\ and CONTOSO2\ domain prefixes from associated accounts and groups

Across the two domains, accounts with the same samAccountNames will be considered equivalent

Across the two domains, groups with the same Names will be considered equivalent

### EXAMPLE 8
```
Export-Permission.ps1 -TargetPath C:\Test -LogDir C:\Logs
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Redirect logs and output files to C:\Logs instead of the default location in AppData

### EXAMPLE 9
```
Export-Permission.ps1 -TargetPath C:\Test -RecurseDepth 0
```

Generate reports on the NTFS permissions for the folder C:\Test only (no subfolders)

### EXAMPLE 10
```
Export-Permission.ps1 -TargetPath C:\Test -RecurseDepth 2
```

Generate reports on the NTFS permissions for the folder C:\Test

Only include subfolders to a maximum of 2 levels deep (C:\Test\Level1\Level2)

### EXAMPLE 11
```
Export-Permission.ps1 -TargetPath C:\Test -Title 'New Custom Report Title'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Change the title of the HTML report to 'New Custom Report Title'

### EXAMPLE 12
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithTarget'
```

The target path is a DFS folder with folder targets

Generate reports on the NTFS permissions for the DFS folder targets associated with this path

### EXAMPLE 13
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget\DfsSubfolderWithTarget'
```

The target path is a DFS subfolder with folder targets

Generate reports on the NTFS permissions for the DFS folder targets associated with this path

### EXAMPLE 14
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget\DfsSubfolderWithTarget\Subfolder'
```

The target path is a subfolder of a DFS subfolder with folder targets

Generate reports on the NTFS permissions for the DFS folder targets associated with this path

### EXAMPLE 15
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\'
```

This is an edge case that is not currently supported

The target path is the root of an AD domain

Generate reports on the NTFS permissions for ?
Invalid/fail param validation?

### EXAMPLE 16
```
Export-Permission.ps1 -TargetPath '\\computer.ad.contoso.com\'
```

This is an edge case that is not currently supported

The target path is the root of a server

Generate reports on the NTFS permissions for ?
Invalid/fail param validation?

### EXAMPLE 17
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace'
```

This is an edge case that is not currently supported

The target path is a DFS namespace

Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

Add a warning that they are permissions from the DFS namespace server and could be confusing

### EXAMPLE 18
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget'
```

This is an edge case that is not currently supported.

The target path is a DFS folder without a folder target

Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

Add a warning that they are permissions from the DFS namespace server and could be confusing

### EXAMPLE 19
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget'
```

This is an edge case that is not currently supported.

The target path is a DFS subfolder without a folder target.

Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

Add a warning that they are permissions from the DFS namespace server and could be confusing

## PARAMETERS

### -AccountConvention
Valid accounts that are allowed to appear in ACEs

Specify as a ScriptBlock meant for the FilterScript parameter of Where-Object

By default, this is a ScriptBlock that always evaluates to $true so it doesn't evaluate any account convention compliance

In the ScriptBlock, any account properties are available for evaluation:

e.g.
{$_.DomainNetbios -eq 'CONTOSO'} # Accounts used in ACEs should be in the CONTOSO domain
e.g.
{$_.Name -eq 'Group23'} # Accounts used in ACEs should be named Group23
e.g.
{$_.ResolvedAccountName -like 'CONTOSO\Group1*' -or $_.ResolvedAccountName -eq 'CONTOSO\Group23'}

The format of the ResolvedAccountName property is CONTOSO\Group1
  where
    CONTOSO is the NetBIOS name of the domain (the computer name for local accounts)
    and
    Group1 is the samAccountName of the account

```yaml
Type: System.Management.Automation.ScriptBlock
Parameter Sets: (All)
Aliases:

Required: False
Position: 9
Default value: { $true }
Accept pipeline input: False
Accept wildcard characters: False
```

### -Detail
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

```yaml
Type: System.Int32[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 19
Default value: 10
Accept pipeline input: False
Accept wildcard characters: False
```

### -ExcludeAccount
Regular expressions matching names of security principals to exclude from the HTML report

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: SYSTEM
Accept pipeline input: False
Accept wildcard characters: False
```

### -ExcludeClass
Accounts whose objectClass property is in this list are excluded from the HTML report

Note on the 'group' class:
  By default, a group with members is replaced in the report by its members unless the -NoGroupMembers switch is used.
  Any remaining groups are empty and not useful to see in the middle of a list of users/job titles/departments/etc).
  So the 'group' class is excluded here by default.

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: @('group', 'computer')
Accept pipeline input: False
Accept wildcard characters: False
```

### -FileFormat
File format(s) to export

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 17
Default value: Js
Accept pipeline input: False
Accept wildcard characters: False
```

### -GroupBy
How to group the permissions in the output stream and within each exported file

    SplitBy	GroupBy
    none	none	$FlatPermissions all in 1 file
    none	account	$AccountPermissions all in 1 file
    none	item	$ItemPermissions all in 1 file

    account	none	1 file per item in $AccountPermissions. 
In each file, $_.Access | sort path
    account	account	(same as -SplitBy account -GroupBy none)
    account	item	1 file per item in $AccountPermissions. 
In each file, $_.Access | group item | sort name

    item	none	1 file per item in $ItemPermissions. 
In each file, $_.Access | sort account
    item	account	1 file per item in $ItemPermissions. 
In each file, $_.Access | group account | sort name
    item	item	(same as -SplitBy item -GroupBy none)

    target	none	1 file per $TargetPath. 
In each file, sort ACEs by item path then account name
    target	account	1 file per $TargetPath. 
In each file, group ACEs by account and sort by account name
    target	item	1 file per $TargetPath. 
In each file, group ACEs by item and sort by item path
    target  target  (same as -SplitBy target -GroupBy none)

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 16
Default value: Item
Accept pipeline input: False
Accept wildcard characters: False
```

### -IgnoreDomain
Domain(s) to ignore (they will be removed from the username)

Can be used:
  to ensure accounts only appear once on the report when they have matching SamAccountNames in multiple domains.
  when the domain is often the same and doesn't need to be displayed

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -IncludeAccount
Regular expressions matching names of security principals to include in the HTML report

Only security principals with names matching these regular expressions will be returned

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -InheritanceFlagResolved
String translations indexed by value in the \[System.Security.AccessControl.InheritanceFlags\] enum
Parameter default value is on a single line as a workaround to a PlatyPS bug
TODO: Move to i18n

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 20
Default value: @('this folder but not subfolders', 'this folder and subfolders', 'this folder and files, but not subfolders', 'this folder, subfolders, and files')
Accept pipeline input: False
Accept wildcard characters: False
```

### -Interactive
Open the HTML report after the script is finished using Invoke-Item (only useful interactively)

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -NoMembers
Do not get group members (only report the groups themselves)

Note: By default, the -ExcludeClass parameter will exclude groups from the report.
  If using -NoGroupMembers, you most likely want to modify the value of -ExcludeClass.
  Remove the 'group' class from ExcludeClass in order to see groups on the report.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -NoProgress
Workaround for https://github.com/PowerShell/PowerShell/issues/20657

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -OutputDir
Path to the folder to save the logs and reports generated by this script

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: "$env:AppData\Export-Permission"
Accept pipeline input: False
Accept wildcard characters: False
```

### -OutputFormat
Type of output returned to the output stream

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 18
Default value: Passthru
Accept pipeline input: False
Accept wildcard characters: False
```

### -PrtgPort
If all four of the PRTG parameters are specified,

the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor

```yaml
Type: System.UInt16
Parameter Sets: (All)
Aliases:

Required: False
Position: 13
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -PrtgProbe
If all four of the PRTG parameters are specified,

the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 11
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -PrtgProtocol
If all four of the PRTG parameters are specified,

the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 12
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -PrtgToken
If all four of the PRTG parameters are specified,

the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 14
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -RecurseDepth
How many levels of children to enumerate

  Set to 0 to ignore all children
  Set to -1 (default) to recurse through all children
  Set to any whole number to enumerate that many levels of children

```yaml
Type: System.Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 7
Default value: -1
Accept pipeline input: False
Accept wildcard characters: False
```

### -SplitBy
How to split up the exported files:
    none    generate 1 report file with all permissions
    target  generate 1 report file per target (default)
    item    generate 1 report file per item
    account generate 1 report file per account
    all     generate 1 report file per target and 1 file per item and 1 file per account and 1 file with all permissions.

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 15
Default value: Target
Accept pipeline input: False
Accept wildcard characters: False
```

### -TargetPath
Path to the NTFS folder whose permissions to export

Currently supports NTFS folders
TODO: support same targets as Get-Acl (AD, Registry, StorageSubSystem)

```yaml
Type: System.IO.DirectoryInfo[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

### -ThreadCount
Number of asynchronous threads to use
Recommended starting with the # of logical CPUs (Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum

```yaml
Type: System.UInt16
Parameter Sets: (All)
Aliases:

Required: False
Position: 10
Default value: 1
Accept pipeline input: False
Accept wildcard characters: False
```

### -Title
Title at the top of the HTML report

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 8
Default value: Permissions Report
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### [System.IO.DirectoryInfo[]] TargetPath parameter
### Strings can be passed to this parameter and will be re-cast as DirectoryInfo objects.
## OUTPUTS

### [System.String] XML output formatted for a Custom XML Sensor in Paessler PRTG Network Monitor
## NOTES
This code has not been reviewed or audited by a third party

This code has limited or no tests

It was designed for presenting reports to non-technical management or administrative staff

It is convenient for that purpose but it is not recommended for compliance reporting or similar formal uses

ToDo bugs/enhancements: https://github.com/IMJLA/Export-Permission/issues

## RELATED LINKS


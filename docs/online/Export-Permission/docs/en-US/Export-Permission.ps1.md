---
download help link: https://imjla.github.io/Export-PermissionHelp
external help file: Export-Permission-help.xml
help version: 0.0.566
locale: en-US
online version: https://imjla.github.io/Export-Permission
schema: 2.0.0
script guid: fd2d03cf-4d29-4843-bb1c-0fba86b0220a
script name: Export-Permission.ps1
---

# Export-Permission.ps1

## SYNOPSIS
Create CSV, HTML, JSON, and XML exports of permissions

## SYNTAX

```powershell
Export-Permission.ps1 [-SourcePath] <DirectoryInfo[]> [[-RecurseDepth] <Int32>] [[-IncludeAccount] <String[]>]
 [[-ExcludeAccount] <String[]>] [[-ExcludeClass] <String[]>] [[-AccountProperty] <String[]>] [-NoMembers]
 [[-IgnoreDomain] <String[]>] [[-OutputDir] <String>] [[-Title] <String>] [[-SplitBy] <String[]>]
 [[-GroupBy] <String>] [[-FileFormat] <String[]>] [[-OutputFormat] <String>] [[-Detail] <Int32[]>]
 [[-AccountConvention] <ScriptBlock>] [[-PrtgProbe] <String>] [[-PrtgProtocol] <String>] [[-PrtgPort] <UInt16>]
 [[-PrtgToken] <String>] [[-ThreadCount] <UInt16>] [-Interactive] [-NoProgress]
 [<CommonParameters>]
```

## DESCRIPTION
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

## EXAMPLES

### EXAMPLE 1
```powershell
Export-Permission.ps1 -SourcePath C:\Test
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

### EXAMPLE 2
```powershell
Export-Permission.ps1 -SourcePath C:\Test -ExcludeAccount 'BUILTIN\\Administrator'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Exclude the built-in Administrator account from the HTML report

The ExcludeAccount parameter uses RegEx, so the \ in BUILTIN\Administrator needed to be escaped.

The RegEx escape character is \ so the regular expression needed for the parameter is 'BUILTIN\\\\Administrator'

### EXAMPLE 3
```powershell
Export-Permission.ps1 -SourcePath C:\Test -ExcludeAccount @(
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
```powershell
Export-Permission.ps1 -SourcePath C:\Test -ExcludeClass @('computer')
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Include empty groups on the HTML report (rather than the default setting which would exclude computers and groups)

### EXAMPLE 5
```powershell
Export-Permission.ps1 -SourcePath C:\Test -NoGroupMembers -ExcludeClass @('computer')
```

Generate reports on the NTFS permissions for the folder C:\Test

Do not spend time retrieving group members

Include groups on the report, but exclude computers (rather than the default setting which would exclude computers and groups)

### EXAMPLE 6
```powershell
Export-Permission.ps1 -SourcePath C:\Test -IgnoreDomain 'CONTOSO'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Remove the CONTOSO domain prefix from associated accounts and groups

### EXAMPLE 7
```powershell
Export-Permission.ps1 -SourcePath C:\Test -IgnoreDomain 'CONTOSO1','CONTOSO2'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Remove the CONTOSO1\ and CONTOSO2\ domain prefixes from associated accounts and groups

Across the two domains, accounts with the same samAccountNames will be considered equivalent

Across the two domains, groups with the same Names will be considered equivalent

### EXAMPLE 8
```powershell
Export-Permission.ps1 -SourcePath C:\Test -LogDir C:\Logs
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Redirect logs and output files to C:\Logs instead of the default location in AppData

### EXAMPLE 9
```powershell
Export-Permission.ps1 -SourcePath C:\Test -RecurseDepth 0
```

Generate reports on the NTFS permissions for the folder C:\Test only (no subfolders)

### EXAMPLE 10
```powershell
Export-Permission.ps1 -SourcePath C:\Test -RecurseDepth 2
```

Generate reports on the NTFS permissions for the folder C:\Test

Only include subfolders to a maximum of 2 levels deep (C:\Test\Level1\Level2)

### EXAMPLE 11
```powershell
Export-Permission.ps1 -SourcePath C:\Test -Title 'New Custom Report Title'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Change the title of the HTML report to 'New Custom Report Title'

### EXAMPLE 12
```powershell
Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace\DfsFolderWithTarget'
```

The source path is a DFS folder with folder targets

Generate reports on the NTFS permissions for the DFS folder targets associated with this path

### EXAMPLE 13
```powershell
Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget\DfsSubfolderWithTarget'
```

The source path is a DFS subfolder with folder targets

Generate reports on the NTFS permissions for the DFS folder targets associated with this path

### EXAMPLE 14
```powershell
Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget\DfsSubfolderWithTarget\Subfolder'
```

The source path is a subfolder of a DFS subfolder with folder targets

Generate reports on the NTFS permissions for the DFS folder targets associated with this path

### EXAMPLE 15
```powershell
Export-Permission.ps1 -SourcePath '\\ad.contoso.com\'
```

This is an edge case that is not currently supported

The source path is the root of an AD domain

Generate reports on the NTFS permissions for the root of an AD domain. 
TODO: param validation?
or otherwise handle error.

### EXAMPLE 16
```powershell
Export-Permission.ps1 -SourcePath '\\computer.ad.contoso.com\'
```

This is an edge case that is not currently supported

The source path is the root of a SMB server

Generate reports on the NTFS permissions for the root of a SMB server. 
TODO: param validation?
or otherwise handle error.

### EXAMPLE 17
```powershell
Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace'
```

This is an edge case that is not currently supported

The source path is a DFS namespace

Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

Add a warning that they are permissions from the DFS namespace server and could be confusing

### EXAMPLE 18
```powershell
Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget'
```

This is an edge case that is not currently supported.

The source path is a DFS folder without a folder target

Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

Add a warning that they are permissions from the DFS namespace server and could be confusing

### EXAMPLE 19
```powershell
Export-Permission.ps1 -SourcePath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget'
```

This is an edge case that is not currently supported.

The source path is a DFS subfolder without a folder target.

Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

Add a warning that they are permissions from the DFS namespace server and could be confusing

## PARAMETERS

### -AccountConvention
Valid accounts that are allowed to appear in ACEs

Specify as a ScriptBlock meant for the FilterScript parameter of Where-Object

By default, this is a ScriptBlock that always evaluates to $true so it doesn't evaluate any account convention compliance

In the ScriptBlock, any account properties are available for evaluation:
- ` $_.DomainNetbios -eq 'CONTOSO' )`
 Accounts used in ACEs should be in the CONTOSO domain
- ` $_.Name -eq 'Group23' )`
Accounts used in ACEs should be named Group23
- ` $_.ResolvedAccountName -like 'CONTOSO\Group1*' -or $_.ResolvedAccountName -eq 'CONTOSO\Group23' )`
Accounts used in ACEs should be in the CONTOSO domain and named Group1something or Group23

The format of the ResolvedAccountName property is CONTOSO\Group1 where:
- CONTOSO is the NetBIOS name of the domain (the computer name for local accounts)
- Group1 is the samAccountName of the account

```yaml
Type: System.Management.Automation.ScriptBlock
Parameter Sets: (All)
Aliases:

Required: False
Position: 15
Default value: { $true }
Accept pipeline input: False
Accept wildcard characters: False
```

### -AccountProperty
Properties of each account to display on the report (left out: managedBy, operatingSystem)

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: @('DisplayName', 'Company', 'Department', 'Title', 'Description')
Accept pipeline input: False
Accept wildcard characters: False
```

### -Detail
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

```yaml
Type: System.Int32[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 14
Default value: 10
Accept pipeline input: False
Accept wildcard characters: False
```

### -ExcludeAccount
Regular expressions matching names of accounts to exclude from the HTML report

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: \\SYSTEM$
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
Position: 5
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
Position: 12
Default value: Js
Accept pipeline input: False
Accept wildcard characters: False
```

### -GroupBy
How to group the permissions in the output stream and within each exported file.
Interacts with the SplitBy parameter:

| SplitBy | GroupBy | Behavior |
|---------|---------|----------|
| none    | none    | 1 file with all permissions in a flat list |
| none    | account | 1 file with all permissions grouped by account |
| none    | item    | 1 file with all permissions grouped by item |
| account | none    | 1 file per account; in each file, sort ACEs by item path |
| account | account | (same as -SplitBy account -GroupBy none) |
| account | item    | 1 file per account; in each file, group ACEs by item and sort by item path |
| item    | none    | 1 file per item; in each file, sort ACEs by account name |
| item    | account | 1 file per item; in each file, group ACEs by account and sort by account name |
| item    | item    | (same as -SplitBy item -GroupBy none) |
| source  | none    | 1 file per source path; in each file, sort ACEs by source path |
| source  | account | 1 file per source path; in each file, group ACEs by account and sort by account name |
| source  | item    | 1 file per source path; in each file, group ACEs by item and sort by item path |
| source  | source  | (same as -SplitBy source -GroupBy none) |

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 11
Default value: Item
Accept pipeline input: False
Accept wildcard characters: False
```

### -IgnoreDomain
Domain(s) to ignore (they will be removed from the username)

Can be used:
- to ensure accounts only appear once on the report when they have matching SamAccountNames in multiple domains.
- when the domain is often the same and doesn't need to be displayed

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 7
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -IncludeAccount
Regular expressions matching names of accounts to include in the HTML report

If this parameter is specified, only accounts whose names match these regular expressions will be included

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
Position: 8
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
Position: 13
Default value: Passthru
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction- `{ Fill ProgressAction Description )`}

```yaml
Type: System.Management.Automation.ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
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
Position: 18
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
Position: 16
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
Position: 17
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
Position: 19
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -RecurseDepth
How many levels of child items to enumerate
- Set to 0 to ignore all children
- Set to -1 (default) to recurse through all children
- Set to any whole number to enumerate that many levels of children

```yaml
Type: System.Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: -1
Accept pipeline input: False
Accept wildcard characters: False
```

### -SourcePath
Path to the item whose permissions to export

Supports:
- NTFS Folder paths
    - Local folder paths
    - UNC folder paths
    - DFS folder paths
    - Mapped network drives

Does Not Support (ToDo):
- same sources as Get-Acl (AD, Registry, StorageSubSystem)
- M365 sources (SP sites, Teams, etc)

```yaml
Type: System.IO.DirectoryInfo[]
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

### -SplitBy
How to split up the exported files:

| Value   | Behavior |
|---------|----------|
| none    | generate 1 report file with all permissions |
| account | generate 1 report file per account |
| item    | generate 1 report file per item |
| source  | generate 1 report file per source path (default) |

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 10
Default value: Source
Accept pipeline input: False
Accept wildcard characters: False
```

### -ThreadCount
Number of asynchronous threads to use

Recommended starting with the # of logical CPUs:
- ` (Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum )`

```yaml
Type: System.UInt16
Parameter Sets: (All)
Aliases:

Required: False
Position: 20
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
Position: 9
Default value: Permissions Report
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### [System.IO.DirectoryInfo[]] SourcePath parameter
### Strings can be passed to this parameter and will be re-cast as DirectoryInfo objects.
## OUTPUTS

### [PSCustomObject] Items, permissions, and accounts formatted according to specified parameters.
## NOTES
This code has not been reviewed or audited by a third party

This code has limited or no tests

It was designed for presenting reports to non-technical management or administrative staff

It is convenient for that purpose but it is not recommended for compliance reporting or similar formal uses

## RELATED LINKS

[https://imjla.github.io/Export-Permission](https://imjla.github.io/Export-Permission)

[https://github.com/IMJLA/Export-Permission](https://github.com/IMJLA/Export-Permission)



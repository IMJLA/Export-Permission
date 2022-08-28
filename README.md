---
external help file: -help.xml
help version: 0.0.149
locale: en-US
Module Name:
online version:
schema: 2.0.0
script guid: fd2d03cf-4d29-4843-bb1c-0fba86b0220a
---

# Export-Permission.ps1

## SYNOPSIS
Create CSV, HTML, and XML reports of permissions

## SYNTAX

```
Export-Permission.ps1 [[-TargetPath] <DirectoryInfo[]>] [[-ExcludeAccount] <String[]>] [-ExcludeEmptyGroups]
 [[-IgnoreDomain] <String[]>] [[-LogDir] <String>] [-NoGroupMembers] [[-SubfolderLevels] <Int32>]
 [[-Title] <String>] [[-GroupNamingConvention] <ScriptBlock>] [[-ThreadCount] <UInt16>] [-OpenReportAtEnd]
 [[-PrtgProbe] <String>] [[-PrtgSensorProtocol] <String>] [[-PrtgSensorPort] <UInt16>]
 [[-PrtgSensorToken] <String>] [<CommonParameters>]
```

## DESCRIPTION
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

The RegEx escape character is \ so that is why the regular expression needed for the parameter is 'BUILTIN\\\\Administrator'

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
Export-Permission.ps1 -TargetPath C:\Test -ExcludeEmptyGroups
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Exclude empty groups from the HTML report (leaving accounts only)

### EXAMPLE 5
```
Export-Permission.ps1 -TargetPath C:\Test -IgnoreDomain 'CONTOSO'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Remove the CONTOSO domain prefix from associated accounts and groups

### EXAMPLE 6
```
Export-Permission.ps1 -TargetPath C:\Test -IgnoreDomain 'CONTOSO1','CONTOSO2'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Remove the CONTOSO1\ and CONTOSO2\ domain prefixes from associated accounts and groups

Across the two domains, accounts with the same samAccountNames will be considered equivalent

Across the two domains, groups with the same Names will be considered equivalent

### EXAMPLE 7
```
Export-Permission.ps1 -TargetPath C:\Test -LogDir C:\Logs
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Redirect logs and output files to C:\Logs instead of the default location in AppData

### EXAMPLE 8
```
Export-Permission.ps1 -TargetPath C:\Test -LevelsOfSubfolders 0
```

Generate reports on the NTFS permissions for the folder C:\Test only (no subfolders)

### EXAMPLE 9
```
Export-Permission.ps1 -TargetPath C:\Test -LevelsOfSubfolders 2
```

Generate reports on the NTFS permissions for the folder C:\Test

Only include subfolders to a maximum of 2 levels deep (C:\Test\Level1\Level2)

### EXAMPLE 10
```
Export-Permission.ps1 -TargetPath C:\Test -Title 'New Custom Report Title'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Change the title of the HTML report to 'New Custom Report Title'

### EXAMPLE 11
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithTarget'
```

The target path is a DFS folder with folder targets

Generate reports on the NTFS permissions for the DFS folder targets associated with this path

### EXAMPLE 12
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget\DfsSubfolderWithTarget'
```

The target path is a DFS subfolder with folder targets

Generate reports on the NTFS permissions for the DFS folder targets associated with this path

### EXAMPLE 13
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget\DfsSubfolderWithTarget\Subfolder'
```

The target path is a subfolder of a DFS subfolder with folder targets

Generate reports on the NTFS permissions for the DFS folder targets associated with this path

### EXAMPLE 14
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\'
```

This is an edge case that is not currently supported

The target path is the root of an AD domain

Generate reports on the NTFS permissions for ?
Invalid/fail param validation?

### EXAMPLE 15
```
Export-Permission.ps1 -TargetPath '\\computer.ad.contoso.com\'
```

This is an edge case that is not currently supported

The target path is the root of a server

Generate reports on the NTFS permissions for ?
Invalid/fail param validation?

### EXAMPLE 16
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace'
```

This is an edge case that is not currently supported

The target path is a DFS namespace

Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

Add a warning that they are permissions from the DFS namespace server and could be confusing

### EXAMPLE 17
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget'
```

This is an edge case that is not currently supported.

The target path is a DFS folder without a folder target

Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

Add a warning that they are permissions from the DFS namespace server and could be confusing

### EXAMPLE 18
```
Export-Permission.ps1 -TargetPath '\\ad.contoso.com\DfsNamespace\DfsFolderWithoutTarget\DfsSubfolderWithoutTarget'
```

This is an edge case that is not currently supported.

The target path is a DFS subfolder without a folder target.

Generate reports on the NTFS permissions for the folder on the DFS namespace server associated with this path

Add a warning that they are permissions from the DFS namespace server and could be confusing

## PARAMETERS

### -ExcludeAccount
Regular expressions matching names of security principals to exclude from the HTML report

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ExcludeEmptyGroups
Exclude empty groups from the HTML report

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

### -GroupNamingConvention
Valid group names that are allowed to appear in ACEs

Specify as a ScriptBlock meant for the FilterScript parameter of Where-Object

In the scriptblock, use string comparisons on the Name property

e.g.
{$_.Name -like 'CONTOSO\Group1*' -or $_.Name -eq 'CONTOSO\Group23'}

The naming format that will be used for the groups is CONTOSO\Group1

where CONTOSO is the NetBIOS name of the domain, and Group1 is the samAccountName of the group

By default, this is a scriptblock that always evaluates to $true so it doesn't evaluate any naming convention compliance

```yaml
Type: System.Management.Automation.ScriptBlock
Parameter Sets: (All)
Aliases:

Required: False
Position: 7
Default value: { $true }
Accept pipeline input: False
Accept wildcard characters: False
```

### -IgnoreDomain
Domain(s) to ignore (they will be removed from the username)

Intended when a user has matching SamAccountNames in multiple domains but you only want them to appear once on the report.

Can also be used to remove all domains simply for brevity in the report.

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

### -LogDir
Path to the folder to save the logs and reports generated by this script

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: "$env:AppData\Export-Permission\Logs"
Accept pipeline input: False
Accept wildcard characters: False
```

### -NoGroupMembers
Do not get group members (only report the groups themselves)

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

### -OpenReportAtEnd
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

### -PrtgProbe
If all four of the PRTG parameters are specified,

the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 9
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -PrtgSensorPort
If all four of the PRTG parameters are specified,

the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor

```yaml
Type: System.UInt16
Parameter Sets: (All)
Aliases:

Required: False
Position: 11
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -PrtgSensorProtocol
If all four of the PRTG parameters are specified,

the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 10
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -PrtgSensorToken
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

### -SubfolderLevels
How many levels of subfolder to enumerate

    Set to 0 to ignore all subfolders

    Set to -1 (default) to recurse infinitely

    Set to any whole number to enumerate that many levels

```yaml
Type: System.Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: -1
Accept pipeline input: False
Accept wildcard characters: False
```

### -TargetPath
Path to the NTFS folder whose permissions to export

```yaml
Type: System.IO.DirectoryInfo[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: C:\Test
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

### -ThreadCount
Number of asynchronous threads to use

```yaml
Type: System.UInt16
Parameter Sets: (All)
Aliases:

Required: False
Position: 8
Default value: 4
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
Position: 6
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

### [System.String] XML PRTG sensor output
## NOTES
This code has not been reviewed or audited by a third party

This code has limited or no tests

It was designed for presenting reports to non-technical management or administrative staff

It is convenient for that purpose but it is not recommended for compliance reporting or similar formal uses

ToDo bugs/enhancements: https://github.com/IMJLA/Export-Permission/issues

## RELATED LINKS


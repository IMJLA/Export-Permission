---
external help file: -help.xml
help version: 0.0.110
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
Export-Permission.ps1 [[-TargetPath] <String>] [[-ExcludeAccount] <String[]>] [-ExcludeEmptyGroups]
 [[-IgnoreDomain] <String[]>] [[-LogDir] <String>] [-NoGroupMembers] [[-SubfolderLevels] <Int32>]
 [[-Title] <String>] [[-GroupNamingConvention] <ScriptBlock>] [-OpenReportAtEnd] [[-PrtgProbe] <String>]
 [[-PrtgSensorProtocol] <String>] [[-PrtgSensorPort] <Int32>] [[-PrtgSensorToken] <String>]
 [<CommonParameters>]
```

## DESCRIPTION
Gets all permissions for the target folder

Gets non-inherited permissions for subfolders (if specified)

Exports the permissions to a .csv file

Uses ADSI to get information about the accounts and groups listed in the permissions

Exports information about the accounts and groups to a .csv file

Uses ADSI to recursively retrieve the members of nested groups

Exports information about all accounts with access to a .csv file

Exports information about all accounts with access to a report generated as a .html file

Outputs an XML-formatted list of common misconfigurations for use in Paessler PRTG Network Monitor as a custom XML sensor

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
Export-Permission.ps1 -TargetPath C:\Test -ExcludeEmptyGroups
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Exclude empty groups from the HTML report (leaving accounts only)

### EXAMPLE 4
```
Export-Permission.ps1 -TargetPath C:\Test -IgnoreDomain 'CONTOSO'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Remove the CONTOSO domain prefix from associated accounts and groups

### EXAMPLE 5
```
Export-Permission.ps1 -TargetPath C:\Test -LogDir C:\Logs
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Redirect logs and output files to C:\Logs instead of the default location in AppData

### EXAMPLE 6
```
Export-Permission.ps1 -TargetPath C:\Test -LevelsOfSubfolders 0
```

Generate reports on the NTFS permissions for the folder C:\Test only (no subfolders)

### EXAMPLE 7
```
Export-Permission.ps1 -TargetPath C:\Test -LevelsOfSubfolders 2
```

Generate reports on the NTFS permissions for the folder C:\Test

Only include subfolders to a maximum of 2 levels deep (C:\Test\Level1\Level2)

### EXAMPLE 8
```
Export-Permission.ps1 -TargetPath C:\Test -Title 'New Custom Report Title'
```

Generate reports on the NTFS permissions for the folder C:\Test and all subfolders

Change the title of the HTML report to 'New Custom Report Title'

## PARAMETERS

### -ExcludeAccount
Regular expressions matching names of Users or Groups to exclude from the HTML report

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
Domains to ignore (they will be removed from the username)

Intended when a user has matching SamAccountNames in multiple domains but you only want them to appear once on the report.

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
Path to save the logs and reports generated by this script

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
Position: 8
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -PrtgSensorPort
If all four of the PRTG parameters are specified,

the results will be XML-formatted and pushed to the specified PRTG probe for a push sensor

```yaml
Type: System.Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 10
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
Position: 9
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
Position: 11
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
Path to the folder whose permissions to export (only tested with local paths, UNC may work, unknown)

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: C:\Test
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
Default value: Folder Permissions Report
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None. Pipeline input is not accepted.
## OUTPUTS

### [System.String] XML PRTG sensor output
## NOTES
TODO: Investigate - Looks like I am filtering out ignored domains in 2 separate places? 
redundant?

TODO: Bug - Logic Flaw for Owner.
            Currently we search folders for non-inherited access rules, then we manually add a FullControl access rule for the Owner.
            This misses folders with only inherited access rules but a different owner.

TODO: Bug - Doesn't work for AD users' default group/primary group (which is typically Domain Users).
            The user's default group is not listed in their memberOf attribute so I need to fix the LDAP search filter to include the primary group attribute.

TODO: Bug - For a fake group created by New-FakeDirectoryEntry in the Adsi module, in the report its name will end up as an NT Account (CONTOSO\User123).
            If it is a fake user, its name will correctly appear without the domain prefix (User123)

TODO: Bug - Fix bug in PlatyPS New-MarkdownHelp with multi-line param descriptions (?and example help maybe affected also?).
            When provided the same comment-based help as input, Get-Help respects the line breaks but New-MarkdownHelp does not.
            New-MarkdownHelp generates an inaccurate markdown representation by converting multiple lines to a single line.
            Declared as wontfix https://github.com/PowerShell/platyPS/issues/314
            Need to fix it myself because that makes no sense
            workaround is to include markdown syntax in PowerShell comment-based help
            That is why there are so many extra blank lines in the commented metadata in this script

TODO: Feature - List any excluded accounts at the end

TODO: Feature - Remove all usage of Add-Member to improve performance (create new pscustomobjects instead, nest original object inside)

TODO: Feature - Parameter to specify properties to include in report

TODO: Feature - This script does NOT account for individual file permissions. 
Only folder permissions are considered.

TODO: Feature - This script does NOT account for file share permissions.
Only NTFS permissions are considered.

TODO: Feature - Support ACLs from Registry or AD objects

## RELATED LINKS


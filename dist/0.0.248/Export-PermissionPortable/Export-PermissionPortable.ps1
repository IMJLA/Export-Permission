
<#PSScriptInfo

.VERSION 0.0.248

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
fix test staging

.PRIVATEDATA

#>

<# 

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

#> 
Param()


